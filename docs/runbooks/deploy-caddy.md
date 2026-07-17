# Runbook: Deploy Caddy

| Field           | Value            |
| --------------- | ---------------- |
| Last reviewed   | 2026-07-14       |
| Estimated time  | 45 minutes       |
| Risk level      | Medium           |
| Automation      | Manual           |

## Purpose

Deploy Caddy as the platform's single ingress ([ADR-0009](../decisions/0009-caddy-reverse-proxy.md)).
When this runbook completes, Caddy is the **only** container publishing host ports (80/443), it
terminates TLS for `https://<name>.${DOMAIN}`, routes to application containers over the external
`proxy` network, and its routing table (the Caddyfile) is version-controlled in this repository.

## Scope

Covers: creating the `proxy` network, the `services/caddy/` stack, the version-controlled
Caddyfile, first start, the reload procedure, and the procedure for adding a site block for a new
service.

Does not cover: the one-time vendor-side setup (Namecheap nameserver delegation, Cloudflare zone
and token creation — listed as prerequisites here, rationale in
[ADR-0011](../decisions/0011-dns-01-tls-certificates.md)), tailnet configuration
([deploy-tailscale](deploy-tailscale.md)), or per-application deployment (each service's own
runbook adds its site block via the procedure defined here).

## Prerequisites

- [ ] [deploy-with-compose](deploy-with-compose.md) read — this runbook assumes that generic procedure
- [ ] [deploy-tailscale](deploy-tailscale.md) completed (so this can be finished remotely if the session drops)
- [ ] Repo present at `/opt/dahouselab` and root `.env` filled in:

  ```bash
  test -f /opt/dahouselab/.env && grep -c ROOT /opt/dahouselab/.env
  ```

  Expected: file exists; `CONFIG_ROOT`, `DATA_ROOT`, `BACKUP_ROOT` defined.

- [ ] DNS for `${DOMAIN}` is hosted on Cloudflare ([ADR-0011](../decisions/0011-dns-01-tls-certificates.md)):
      nameservers delegated at the registrar (Namecheap), zone shows **Active** in the Cloudflare
      dashboard, and a wildcard record `*.${DOMAIN}` (type A, DNS-only/grey cloud — **not** proxied)
      points at the host's Tailscale address (`tailscale ip -4`). Verified from a client:

  ```bash
  dig +short test.${DOMAIN}
  ```

  Expected: the host's tailnet address (`100.x.y.z`).

- [ ] A Cloudflare API token exists, scoped to **Zone → DNS → Edit** on the `${DOMAIN}` zone only
      (created at Cloudflare dashboard → My Profile → API Tokens), and is at hand for step 4.

- [ ] Ports 80/443 free on the host: `sudo ss -tlnp | grep -E ':80|:443'` — Expected: no output.

## Risks

- Caddy is a single point of failure by design: if this deployment breaks, **every** web UI on
  the platform is unreachable (host and containers keep running; only ingress is lost).
- A syntactically valid but wrong Caddyfile can route a hostname to the wrong backend.
- Worst case: TLS issuance misconfiguration causes browsers to distrust every service URL until fixed.

## Safety checks

- [ ] No other service defines `ports:` (Caddy must be the only one):

  ```bash
  grep -rl "ports:" /opt/dahouselab/services/*/compose.yaml | grep -v caddy
  ```

  Expected: no output.

- [ ] The Caddyfile validates before any container is started (step 5 below repeats this in-container).

## Procedure

1. **Create the external proxy network** (platform-owned, per
   [`infrastructure/networks/`](../../infrastructure/networks/README.md)):

   ```bash
   docker network create proxy
   docker network inspect proxy --format '{{.Name}}'
   ```

   Expected: `proxy`. (If it already exists, `docker network create` errors — that is fine.)

2. **Create the service directory and state directories**

   Caddy's certificates and internal state are runtime-generated — they live in
   `${CONFIG_ROOT}/caddy`, **never** in Git.

   ```bash
   sudo mkdir -p /srv/dahouselab/config/caddy/{data,config}
   sudo chown -R "$(grep ^PUID /opt/dahouselab/.env | cut -d= -f2):$(grep ^PGID /opt/dahouselab/.env | cut -d= -f2)" /srv/dahouselab/config/caddy
   mkdir -p /opt/dahouselab/services/caddy
   ```

   Expected: directories exist, owned by `PUID:PGID`.

3. **Write the Caddyfile in the repository** at
   `/opt/dahouselab/infrastructure/configs/Caddyfile`. This is the documented exception that
   allows a container to see the repo: version-controlled config mounted read-only
   ([storage standard, rule 5](../standards/storage-and-bind-mounts.md)). Initial content:

   ```text
   {
   	email admin@{$DOMAIN}
   	# Ports 80/443 are not internet-reachable (Tailscale-only platform), so the default
   	# HTTP-01 challenge cannot work. Certificates come from Let's Encrypt via DNS-01
   	# against Cloudflare (ADR-0011); requires the caddy-dns/cloudflare plugin baked into
   	# the image (see the Dockerfile in step 4).
   	acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
   }

   # Site blocks are appended here by each service's deploy runbook, e.g.:
   # vault.{$DOMAIN} {
   # 	reverse_proxy vaultwarden:80
   # }
   ```

   Expected: file committed to Git.

4. **Create the custom image and `services/caddy/compose.yaml`**

   Stock Caddy cannot do DNS-01 against Cloudflare — the plugin must be compiled in
   ([ADR-0011](../decisions/0011-dns-01-tls-certificates.md)). Create
   `/opt/dahouselab/services/caddy/Dockerfile`:

   ```dockerfile
   # Stock Caddy + caddy-dns/cloudflare for DNS-01 (ADR-0011).
   # Update procedure: bump BOTH tags in lockstep, then rebuild (update-containers runbook).
   FROM caddy:2.10.2-builder AS builder
   RUN xcaddy build --with github.com/caddy-dns/cloudflare

   FROM caddy:2.10.2
   COPY --from=builder /usr/bin/caddy /usr/bin/caddy
   ```

   Then create `compose.yaml` — the only compose file allowed `ports:`:

   ```yaml
   name: caddy

   services:
     caddy:
       build: . # custom image: stock caddy + caddy-dns/cloudflare (ADR-0011)
       image: dahouselab/caddy:2.10.2 # local tag; mirrors the pinned base version
       container_name: caddy
       restart: unless-stopped
       env_file: .env
       environment:
         TZ: ${TZ}
         DOMAIN: ${DOMAIN} # consumed by {$DOMAIN} placeholders in the Caddyfile
       ports: # deviation from rule 6: Caddy is the single ingress (ADR-0009)
         - "80:80"
         - "443:443"
         - "443:443/udp" # HTTP/3
       volumes:
         # Directory mount, NOT a single-file mount: git pull replaces files by inode,
         # and a file bind mount would keep serving a stale Caddyfile silently.
         - ${DAHOUSELAB_ROOT}/infrastructure/configs:/etc/caddy:ro
         - ${CONFIG_ROOT}/caddy/data:/data # certs, OCSP — runtime state, NOT in git
         - ${CONFIG_ROOT}/caddy/config:/config
       networks:
         - proxy
       security_opt:
         - no-new-privileges:true
       healthcheck: # image ships no HTTP client; validate proves config + process liveness
         test: ["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"]
         interval: 30s
         timeout: 5s
         retries: 3
         start_period: 15s
       labels:
         dahouselab.service: "caddy"
         dahouselab.category: "infrastructure"
         dahouselab.description: "Reverse proxy — single ingress for all web services"
         dahouselab.backup: "true"

   networks:
     proxy:
       external: true
   ```

   Create `.env` from the globals, then append the Cloudflare token **with an editor, never
   `echo`** (secrets must not enter shell history — [rotate-secrets](rotate-secrets.md)):

   ```bash
   cd /opt/dahouselab/services/caddy
   cp /opt/dahouselab/.env .env && chmod 600 .env
   nano .env   # append: CLOUDFLARE_API_TOKEN=<token from Prerequisites>
   ```

   Note: the variable keeps the plugin's canonical name `CLOUDFLARE_API_TOKEN` (it is what
   `{env.CLOUDFLARE_API_TOKEN}` in the Caddyfile resolves) — a documented deviation from the
   service-prefix rule in the [environment standard](../standards/environment-variables.md).

   Expected: `.env` present, mode `600`, token set.

5. **Validate and start**

   ```bash
   cd /opt/dahouselab/services/caddy
   docker compose config --quiet && echo OK
   docker compose up -d --build
   docker compose ps
   ```

   Expected: `OK`; first run compiles the plugin image (several minutes on a Pi 4), then
   container `caddy` shows `Up ... (healthy)`.

6. **Verify ingress end-to-end** — until a service exists, expect Caddy's empty-config behavior:

   ```bash
   curl -sk -o /dev/null -w '%{http_code}\n' https://localhost
   docker compose logs caddy 2>&1 | grep -i "certificate obtained" || true
   ```

   Expected: an HTTP status from Caddy (e.g. `200`/`308`/`404`) — proof it is listening on 443.
   Once the first site block exists, the log shows `certificate obtained successfully` for its
   hostname (DNS-01 issuance takes up to ~2 minutes including DNS propagation).

7. **Learn the reload procedure** (used by every later runbook; zero-downtime):

   ```bash
   cd /opt/dahouselab/services/caddy
   docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
   docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
   ```

   Expected: `Valid configuration`, then reload returns silently (exit 0).

8. **Adding a new site block (the standard procedure referenced by service runbooks)**
   1. Edit `/opt/dahouselab/infrastructure/configs/Caddyfile`, append:

      ```text
      <name>.{$DOMAIN} {
      	reverse_proxy <container>:<port>
      }
      ```

   2. Validate + reload (step 7). The mount is `:ro` and live — no restart needed.
   3. Commit the Caddyfile change to Git in the same sitting.

   Expected: `https://<name>.${DOMAIN}` routes to the new container.

9. **Update the services inventory** in [`services/README.md`](../../services/README.md).

## Verification

- [ ] `docker compose ps` → `caddy` is `healthy`; only Caddy publishes 80/443 (`sudo ss -tlnp | grep -E ':80|:443'` shows only docker-proxy/caddy)
- [ ] `curl -sk https://localhost` answers (step 6)
- [ ] Cert state appears on the host: `ls /srv/dahouselab/config/caddy/data/caddy/` is non-empty after first TLS issuance
- [ ] `docker network inspect proxy` lists `caddy` as an attached container
- [ ] Nothing under `infrastructure/configs/` is writable by the container (mount is `:ro`)

## Rollback

```bash
cd /opt/dahouselab/services/caddy
docker compose down
```

The `proxy` network, the Caddyfile in Git, and `${CONFIG_ROOT}/caddy` state all persist — a later
`up -d` resumes with the same certificates. If the Caddyfile was mutated during the procedure,
restore it with `git -C /opt/dahouselab checkout -- infrastructure/configs/Caddyfile` and reload.
Rollback is possible at every step; nothing here is destructive.

## Troubleshooting

| Symptom                                | Likely cause                                | Action                                                          |
| -------------------------------------- | ------------------------------------------- | --------------------------------------------------------------- |
| `up -d` fails: port already allocated  | Another process bound 80/443                | `sudo ss -tlnp` to find it; only Caddy may publish these ports  |
| Browser shows untrusted certificate    | DNS-01 issuance failed; Caddy fell back to its internal CA | `docker compose logs caddy`; fix token/zone; certs re-issue automatically |
| TLS issuance loops/fails               | Token lacks `Zone → DNS → Edit`, or zone not Active on Cloudflare | Re-check token scope in the Cloudflare dashboard; `dig NS ${DOMAIN}` must return Cloudflare nameservers |
| Issuance fails with propagation errors | TXT record not visible yet to Let's Encrypt | Wait and retry (Caddy retries automatically); check the zone for stale `_acme-challenge` records |
| `502 Bad Gateway` for a service        | Backend not on `proxy` network or wrong port| `docker network inspect proxy`; fix site block; reload          |
| Reload succeeds but old routing served | Edited a copy, not the mounted Caddyfile    | Confirm path `infrastructure/configs/Caddyfile`; reload again   |
| Caddyfile changes ignored after `git pull` | Single-file bind mount pinned to the pre-pull inode | Mount the configs *directory* (current compose does); `docker compose up -d` to rebind |
| Container `unhealthy`                  | Caddyfile syntax error after an edit        | `docker compose logs caddy`; `caddy validate`; fix and reload   |

## Automation opportunities

- Steps 2, 4–5 are the generic deploy flow — scriptable as `scripts/deploy-service.sh caddy`.
- Site-block addition + validate + reload (step 8) is fully mechanical and the highest-value
  script candidate (`scripts/caddy-add-site.sh <name> <container:port>`), blocked only by
  deciding a marker format for machine-managed Caddyfile sections.
- A CI check that no non-Caddy compose file contains `ports:` would enforce the safety check.

## Future improvements

- Switch per-host certificates to a single wildcard `*.{$DOMAIN}` certificate so service names
  stay out of public Certificate Transparency logs
  ([ADR-0011 security considerations](../decisions/0011-dns-01-tls-certificates.md)).
- Add access logging + fail2ban-style rate limiting for sensitive vhosts (Vaultwarden admin).
- Serve an explicit maintenance page for unknown hosts instead of the default response.
