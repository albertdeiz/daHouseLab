# Runbook: Deploy with Compose

| Field           | Value               |
| --------------- | ------------------- |
| Last reviewed   | 2026-07-14          |
| Estimated time  | 30 minutes          |
| Risk level      | Low                 |
| Automation      | Partially scripted  |

## Purpose

The generic procedure for deploying any service from [`/services`](../../services/) onto the
host. Every `deploy-<service>` runbook is this procedure plus service-specific values and
caveats; when this runbook completes, the service is running, healthy, routed through Caddy,
monitored by Uptime Kuma and recorded in the service inventory.

## Scope

Covers first deployment of a single service with `docker compose`. Does **not** cover updates
to a running service ([update-containers](update-containers.md)), removal, or
service-specific setup (databases, admin accounts) — those live in each `deploy-<service>`
runbook, which references this one. Replace `<service>` throughout with the service name.

## Prerequisites

- [ ] [install-docker](install-docker.md) completed — verify: `docker compose version` works without sudo
- [ ] [deploy-caddy](deploy-caddy.md) completed (unless deploying Caddy or Tailscale themselves) — verify: `docker ps --format '{{.Names}}' | grep caddy`
- [ ] Root `.env` exists and is current — verify: `test -f /opt/dahouselab/.env && echo OK` (see [environment-variables](../standards/environment-variables.md))
- [ ] The service directory exists in the repo — verify: `ls /opt/dahouselab/services/<service>/compose.yaml`
- [ ] Repo checkout is up to date — verify: `git -C /opt/dahouselab pull --ff-only`

## Risks

- Starting a container before its bind-mount directories exist lets Docker create them as
  `root:root` — the app then fails with permission errors, or worse, half-writes data with wrong
  ownership that pollutes backups. This is why directory creation is a pre-start step, never
  left to Docker ([storage standard, rule 6](../standards/storage-and-bind-mounts.md)).
- A malformed `.env` interpolates empty strings into the compose file — paths like
  `/<service>` mounted at filesystem root. `docker compose config` before `up` catches this.
- Worst case on a *first* deployment: a broken container and wrongly-owned empty directories —
  no existing data is at risk. Deploying over an existing service is out of scope here.

## Safety checks

- [ ] The `proxy` network exists: `docker network inspect proxy --format '{{.Name}}'` — expected: `proxy`
- [ ] Disk space for image + data: `df -h /srv/dahouselab /var/lib/docker` — expected: comfortable headroom on both
- [ ] No name collision: `docker ps -a --format '{{.Names}}' | grep -w <service> || echo free` — expected: `free`
- [ ] The rendered config is valid **before** anything starts (step 4 below is mandatory, not optional)

## Procedure

All commands run on the Pi from the service directory:

```bash
cd /opt/dahouselab/services/<service>
```

1. **Create the config and data directories with correct ownership**

   Must happen before first start so Docker never creates them as root. `PUID`/`PGID` come
   from the root `.env` (both `1000`):

   ```bash
   install -d -o 1000 -g 1000 /srv/dahouselab/config/<service> /srv/dahouselab/data/<service>
   ```

   Expected: `ls -ldn /srv/dahouselab/{config,data}/<service>` shows both owned by `1000:1000`.

2. **Create the layered environment files** ([ADR-0012](../decisions/0012-layered-environment-files.md))

   `.env` is a symlink to the root globals file — never a copy; service-specific variables and
   secrets live in `.env.service`, created from its committed template:

   ```bash
   ln -sf ../../.env .env
   cp .env.service.example .env.service
   chmod 600 .env.service
   nano .env.service
   ```

   Fill every variable; generate secrets as the template's comments instruct
   (e.g. `openssl rand -base64 32`). An empty secret must fail loudly at step 4, not default silently.

   Expected: `ls -l .env .env.service` shows `.env -> ../../.env` and `.env.service` as
   `-rw-------`; no variable left empty unless the template says so.

3. **Review the compose file against the standards**

   Read `compose.yaml` and confirm: bind mounts only, via `${CONFIG_ROOT}`/`${DATA_ROOT}`; no
   published ports (only Caddy publishes); joins the external `proxy` network; no secrets in
   `environment:` blocks; declares the layered `env_file:` list:

   ```yaml
   env_file:
     - .env          # platform globals (via symlink)
     - .env.service  # service-specific — overrides globals on collision
   ```

   Expected: any deviation is fixed in the repo (and reviewed) before deploying — not patched live.

4. **Validate the interpolated configuration**

   ```bash
   docker compose config
   ```

   Expected: the fully-rendered YAML prints with real paths and values everywhere — no
   `variable is not set` warnings, no empty-string paths in `volumes:`. **Do not proceed on warnings.**

5. **Start the service**

   ```bash
   docker compose up -d
   ```

   Expected: images pull, containers create and start without error.

6. **Watch until healthy**

   ```bash
   docker compose ps
   ```

   Re-run until `STATUS` shows `Up` (and `(healthy)` if the image defines a healthcheck).
   First start can take minutes (migrations, key generation).

   Expected: all containers `Up`, none `Restarting`.

7. **Inspect the logs for silent failures**

   ```bash
   docker compose logs --tail=100 -f
   ```

   Expected: startup completes in the logs (listening/ready message); no error loops. `Ctrl-C` to detach.

8. **Add the Caddy route and reload**

   Add the service's site block to the Caddyfile in
   `${DAHOUSELAB_ROOT}/infrastructure/configs/` (per [deploy-caddy](deploy-caddy.md)), commit
   it, then reload Caddy without downtime:

   ```bash
   docker compose -f /opt/dahouselab/services/caddy/compose.yaml exec caddy \
     caddy reload --config /etc/caddy/Caddyfile
   ```

   Expected: reload returns cleanly; `curl -kI https://<service>.${DOMAIN}` from the LAN returns an HTTP response from the service.

9. **Register the service in monitoring and inventory**

   - In Uptime Kuma ([deploy-uptime-kuma](deploy-uptime-kuma.md)): add an HTTP(S) monitor for
     `https://<service>.${DOMAIN}` with the standard interval and notification.
   - In the repo: add the service to the [`docs/services`](../services/README.md) inventory
     (name, URL, ports, data paths, dependencies) and commit.

   Expected: the monitor shows green; the inventory row exists in Git.

## Verification

- [ ] `docker compose ps` — all containers `Up`/`healthy`, zero restarts: `docker inspect --format '{{.RestartCount}}' <service>` returns `0`
- [ ] The app answers through Caddy: `curl -kI https://<service>.${DOMAIN}` returns 2xx/3xx (or its login page in a browser)
- [ ] No ports published by the service itself: `docker ps --format '{{.Names}} {{.Ports}}' | grep <service>` shows no `0.0.0.0` bindings
- [ ] Data lands in the right place: `ls /srv/dahouselab/data/<service>` shows app-created files owned by `1000:1000`
- [ ] Uptime Kuma monitor green; inventory updated; the rest of the platform unaffected: `docker ps` shows all other services still `Up`

## Rollback

```bash
cd /opt/dahouselab/services/<service>
docker compose down
```

This stops and removes containers and their networks — **data and config persist** in the bind
mounts under `/srv/dahouselab/{config,data}/<service>` (the entire point of
[the storage standard](../standards/storage-and-bind-mounts.md)). Also remove the Caddyfile
block (revert the commit) and reload Caddy, and pause the Uptime Kuma monitor. To erase the
service entirely, additionally delete its two directories — destructive, take a backup first.
Rollback is possible at any step; before step 5 nothing has started, so it is just `rm .env .env.service`.

## Troubleshooting

| Symptom                                    | Likely cause                                  | Action                                                        |
| ------------------------------------------ | --------------------------------------------- | ------------------------------------------------------------- |
| `variable is not set` at `compose config`  | Missing value in root `.env` or `.env.service` | Fill the variable; re-run step 4                               |
| Container restarts in a loop               | Bad config value or missing secret            | `docker compose logs`; fix `.env.service`; `docker compose up -d` |
| `ls -la .env` shows a dangling symlink     | Root `.env` moved, or link created with a wrong target | Interpolation resolves empty — `compose config` fails or mounts wrong paths; fix with `ln -sf ../../.env .env` |
| `permission denied` in app logs            | Dirs created as root before this runbook      | `sudo chown -R 1000:1000 /srv/dahouselab/{config,data}/<service>`; restart |
| `network proxy ... not found`              | External network missing                      | `docker network create proxy` ([install-docker](install-docker.md) step 8) |
| 502 from Caddy                             | Wrong upstream name/port in Caddyfile         | Upstream must be the container name + internal port on `proxy` |
| Healthy container, unreachable URL         | DNS for `<service>.${DOMAIN}` not pointing at `HOST_IP` | Fix LAN DNS / hosts entry; see [configure-static-ip](configure-static-ip.md) |

## Automation opportunities

Steps 1–7 are `scripts/deploy-service.sh <service>`: create dirs, create the `.env` symlink,
check `.env.service` completeness against `.env.service.example`, `compose config` gate,
`up -d`, poll `ps` until healthy, tail logs on failure. Caddy route and Kuma registration block full automation today (hand-edited Caddyfile,
manual Kuma UI); Caddyfile generation from service metadata would unblock the former.

## Future improvements

- A per-service `metadata.yaml` (domain, port, health path) as the single source for Caddyfile,
  Kuma monitor and inventory row — write once, generate three.
- Standardize compose `healthcheck:` blocks across all services so "watch until healthy" is
  never a guess based on logs.
