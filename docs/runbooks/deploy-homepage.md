# Runbook: Deploy Homepage

| Field           | Value            |
| --------------- | ---------------- |
| Last reviewed   | 2026-07-14       |
| Estimated time  | 30 minutes       |
| Risk level      | Low              |
| Automation      | Manual           |

## Purpose

Deploy [gethomepage/homepage](https://gethomepage.dev) as the platform dashboard at
`https://home.${DOMAIN}`. When complete, Homepage runs behind Caddy on the `proxy` network, its
YAML configuration lives in `${CONFIG_ROOT}/homepage`, and it lists every deployed service.

## Scope

Covers: the `services/homepage/` stack, config directory, Caddy site block, and the initial
services/widgets configuration. Covers the docker.sock integration question (recommendation:
don't). Does not cover per-widget API keys for future services — added as those services deploy.

## Prerequisites

- [ ] [deploy-with-compose](deploy-with-compose.md) read — this runbook assumes that generic procedure
- [ ] `proxy` network exists: `docker network inspect proxy --format '{{.Name}}'` → `proxy`
- [ ] Caddy deployed and healthy ([deploy-caddy](deploy-caddy.md)):

  ```bash
  docker ps --filter name=caddy --format '{{.Status}}'
  ```

  Expected: `Up ... (healthy)`.

- [ ] Root `.env` at `/opt/dahouselab/.env` defines the global set (`TZ`, `PUID`, `PGID`, `DOMAIN`, `*_ROOT`).

## Risks

- Low blast radius: Homepage is read-only glue; failure loses the dashboard, nothing else.
- The real risk is the Docker socket: mounting `/var/run/docker.sock` into any web-facing
  container is effectively root on the host if that container is compromised. Worst case with
  the socket mounted: full host takeover from a Homepage vulnerability.

## Safety checks

- [ ] `home.${DOMAIN}` is not already routed: `grep -n "home\." /opt/dahouselab/infrastructure/configs/Caddyfile` → no output
- [ ] Disk space sane: `df -h /srv` → ample free space (config is a few KB)

## Procedure

1. **Create the service directory from the template**

   ```bash
   cp -r /opt/dahouselab/templates/service /opt/dahouselab/services/homepage
   ```

   Expected: `services/homepage/` exists with `compose.yaml` scaffold and docs.

2. **Create host directories with correct ownership**

   ```bash
   source /opt/dahouselab/.env
   sudo mkdir -p ${CONFIG_ROOT}/homepage
   sudo chown -R ${PUID}:${PGID} ${CONFIG_ROOT}/homepage
   ```

   Expected: `/srv/dahouselab/config/homepage` owned by `PUID:PGID`. (Homepage is stateless
   beyond config — no `${DATA_ROOT}` directory needed; deviation noted in the compose file.)

3. **Write `services/homepage/compose.yaml`**

   ```yaml
   name: homepage

   services:
     homepage:
       image: ghcr.io/gethomepage/homepage:v1.3.2 # pinned at time of writing (2026-07)
       container_name: homepage
       restart: unless-stopped
       env_file: .env
       environment:
         TZ: ${TZ}
         PUID: ${PUID}
         PGID: ${PGID}
         HOMEPAGE_ALLOWED_HOSTS: home.${DOMAIN} # mandatory since v1.x; 400s otherwise
       volumes:
         # Config only — Homepage keeps no data; single mount is a documented
         # deviation from the two-mount rule (storage standard, rule 3).
         - ${CONFIG_ROOT}/homepage:/app/config
       networks:
         - proxy
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD", "wget", "-qO-", "http://127.0.0.1:3000/api/healthcheck"]
         interval: 30s
         timeout: 5s
         retries: 3
         start_period: 30s
       labels:
         dahouselab.service: "homepage"
         dahouselab.category: "infrastructure"
         dahouselab.description: "Platform dashboard"
         dahouselab.url: "https://home.${DOMAIN}"
         dahouselab.backup: "true"

   networks:
     proxy:
       external: true
   ```

   Expected: file saved; no `ports:` (Caddy is the only ingress).

4. **Create `.env`** (no secrets yet — widget API keys arrive later):

   ```bash
   cd /opt/dahouselab/services/homepage
   cp /opt/dahouselab/.env .env && chmod 600 .env
   ```

   Expected: `.env` present, mode `600`. Keep `services/homepage/.env.example` updated with
   every variable the service consumes (currently the global set + `HOMEPAGE_ALLOWED_HOSTS`).

5. **Docker integration decision — recommended: do NOT mount docker.sock.**
   Homepage can show container status via the Docker socket, but this platform's dashboard data
   is not worth socket-level host access from a web-exposed container. The recommended pattern
   is static service entries in `services.yaml` (below), with Uptime Kuma providing live status.

   If you accept the risk anyway: mount it read-only and record the decision —

   ```yaml
       # RISK ACCEPTED <date>: docker.sock grants Docker-API (effectively root) access
       # to this container. Read-only mount limits nothing meaningful — the API is
       # still fully usable. Prefer a socket proxy (e.g. docker-socket-proxy) that
       # whitelists GET /containers only.
       # - /var/run/docker.sock:/var/run/docker.sock:ro
   ```

   Expected: this runbook proceeds without the socket.

6. **Validate and start**

   ```bash
   cd /opt/dahouselab/services/homepage
   docker compose config --quiet && echo OK
   docker compose up -d && docker compose ps
   ```

   Expected: `OK`; `homepage` reaches `Up ... (healthy)`. First start seeds skeleton YAML files
   into `${CONFIG_ROOT}/homepage/`.

7. **Configure the dashboard** — edit `${CONFIG_ROOT}/homepage/services.yaml`:

   ```yaml
   - Infrastructure:
       - Caddy:
           href: https://home.{{HOMEPAGE_VAR_DOMAIN}} # or hardcode your domain
           description: Reverse proxy
   - Apps: []
   ```

   Add `settings.yaml` title/theme to taste. Homepage hot-reloads config on save.

   Expected: entries appear on refresh.

8. **Add the Caddy site block** to `/opt/dahouselab/infrastructure/configs/Caddyfile`:

   ```text
   home.{$DOMAIN} {
   	reverse_proxy homepage:3000
   }
   ```

   Then validate + reload (procedure in [deploy-caddy](deploy-caddy.md), step 7):

   ```bash
   cd /opt/dahouselab/services/caddy
   docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
   docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
   ```

   Expected: reload exits 0. Commit the Caddyfile change.

9. **Verify the URL** from a tailnet client: open `https://home.${DOMAIN}` — dashboard renders
   over HTTPS.

10. **Add an Uptime Kuma monitor** for `https://home.${DOMAIN}` once Uptime Kuma is deployed
    ([deploy-uptime-kuma](deploy-uptime-kuma.md) backfills monitors for everything before it).

11. **Update the services inventory** in [`services/README.md`](../../services/README.md) and
    commit `services/homepage/` to Git.

## Verification

- [ ] `docker compose ps` → `homepage` `healthy`
- [ ] `curl -sk -o /dev/null -w '%{http_code}\n' https://home.${DOMAIN}` → `200`
- [ ] Config landed on the host: `ls ${CONFIG_ROOT}/homepage/*.yaml` lists `services.yaml`, `settings.yaml`, etc.
- [ ] No Docker socket mounted: `docker inspect homepage --format '{{range .Mounts}}{{.Source}} {{end}}'` contains no `docker.sock`
- [ ] Platform still healthy: `docker ps` shows caddy + homepage running

## Rollback

```bash
cd /opt/dahouselab/services/homepage
docker compose down
```

Remove the `home.{$DOMAIN}` site block and reload Caddy. `${CONFIG_ROOT}/homepage` persists; if
config was mutated during troubleshooting, restore it from the latest backup under
`${BACKUP_ROOT}`. Rollback is possible at every step.

## Troubleshooting

| Symptom                              | Likely cause                           | Action                                                    |
| ------------------------------------ | -------------------------------------- | --------------------------------------------------------- |
| HTTP 400 "Host not allowed"          | `HOMEPAGE_ALLOWED_HOSTS` missing/wrong | Set it to `home.${DOMAIN}`; `docker compose up -d`        |
| 502 from Caddy                       | Homepage not on `proxy` network        | `docker network inspect proxy`; fix compose; re-up        |
| Dashboard empty after edits          | YAML syntax error                      | `docker compose logs homepage`; fix indentation           |
| Widgets show no data                 | Missing API key/URL in widget config   | Add per-service keys to `.env`, reference in `services.yaml` |
| Permission denied writing config     | Directory owned by root                | Re-run step 2 `chown`                                     |

## Automation opportunities

- Steps 1–6 are the generic deploy flow — prime candidate for `scripts/deploy-service.sh`.
- `services.yaml` could be generated from the `dahouselab.*` labels of running containers
  (labels exist for exactly this), replacing hand-maintained entries; blocked on writing the
  generator script — which would also remove any temptation to mount docker.sock.

## Future improvements

- Adopt a docker-socket-proxy pattern if live container status becomes a hard requirement.
- Template `services.yaml` from the inventory so the dashboard can never drift from reality.
