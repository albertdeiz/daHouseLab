# Runbook: Deploy Uptime Kuma

| Field           | Value            |
| --------------- | ---------------- |
| Last reviewed   | 2026-07-14       |
| Estimated time  | 45 minutes       |
| Risk level      | Low              |
| Automation      | Manual           |

## Purpose

Deploy [louislam/uptime-kuma](https://github.com/louislam/uptime-kuma) as the platform monitor at
`https://status.${DOMAIN}`. Deployed **early and deliberately** in the service order: every
deployment after this one is watched from minute zero. When complete, Uptime Kuma runs behind
Caddy, stores its SQLite database in `${DATA_ROOT}/uptime-kuma`, monitors every already-deployed
service, and pushes alerts through at least one notification channel.

## Scope

Covers: the `services/uptime-kuma/` stack, first-run admin setup, monitors for everything
deployed so far (host, Tailscale, Caddy, Homepage, itself), and one notification channel.
Does not cover: status-page publishing to the internet, or monitors for future services — each
later runbook adds its own monitor as a standard step.

## Prerequisites

- [ ] [deploy-with-compose](deploy-with-compose.md) read — this runbook assumes that generic procedure
- [ ] `proxy` network exists: `docker network inspect proxy --format '{{.Name}}'` → `proxy`
- [ ] Caddy deployed and healthy: `docker ps --filter name=caddy --format '{{.Status}}'` → `Up ... (healthy)`
- [ ] Root `.env` at `/opt/dahouselab/.env` defines the global set
- [ ] Credentials for a notification channel at hand (e.g. Telegram bot token or SMTP account)

## Risks

- Low blast radius: losing Uptime Kuma loses alerting, not services — but note the second-order
  risk: an unnoticed monitoring outage means later failures go unseen. The "monitor the monitor"
  check in Verification exists for this.
- Worst case: SQLite database corruption on unclean shutdown loses monitor history and config —
  recreated from this runbook in minutes; history is not precious.

## Safety checks

- [ ] `status.${DOMAIN}` not already routed: `grep -n "status\." /opt/dahouselab/infrastructure/configs/Caddyfile` → no output
- [ ] Disk space: `df -h /srv` → ample (database grows slowly, MBs/year at this scale)

## Procedure

1. **Create the service directory from the template**

   ```bash
   cp -r /opt/dahouselab/templates/service /opt/dahouselab/services/uptime-kuma
   ```

   Expected: `services/uptime-kuma/` scaffold exists.

2. **Create the data directory with correct ownership**

   ```bash
   source /opt/dahouselab/.env
   sudo mkdir -p ${DATA_ROOT}/uptime-kuma
   sudo chown -R ${PUID}:${PGID} ${DATA_ROOT}/uptime-kuma
   ```

   Expected: `/srv/dahouselab/data/uptime-kuma` owned by `PUID:PGID`. (Uptime Kuma keeps config
   and data in one SQLite app dir — single data mount, deviation noted in the compose file.)

3. **Write `services/uptime-kuma/compose.yaml`**

   ```yaml
   name: uptime-kuma

   services:
     uptime-kuma:
       image: louislam/uptime-kuma:2.0.1 # pinned at time of writing (2026-07)
       container_name: uptime-kuma
       restart: unless-stopped
       env_file:
         - .env          # platform globals (via symlink)
         - .env.service  # service-specific — overrides globals on collision
       environment:
         TZ: ${TZ}
       volumes:
         # Config and data are one SQLite-backed app dir — single mount is a
         # documented deviation from the two-mount rule (storage standard, rule 3).
         - ${DATA_ROOT}/uptime-kuma:/app/data
       networks:
         - proxy
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD", "extra/healthcheck"] # ships in the image for exactly this
         interval: 30s
         timeout: 5s
         retries: 3
         start_period: 60s
       labels:
         dahouselab.service: "uptime-kuma"
         dahouselab.category: "monitoring"
         dahouselab.description: "Uptime monitoring and alerting"
         dahouselab.url: "https://status.${DOMAIN}"
         dahouselab.backup: "true"

   networks:
     proxy:
       external: true
   ```

   Expected: file saved; no `ports:`.

4. **Create the environment files** ([ADR-0012](../decisions/0012-layered-environment-files.md))

   ```bash
   cd /opt/dahouselab/services/uptime-kuma
   ln -sf ../../.env .env
   cp .env.service.example .env.service && chmod 600 .env.service
   ```

   No service-specific variables to fill today — the template ships empty. Expected: `ls -l`
   shows `.env -> ../../.env` and `.env.service` mode `600`; keep `.env.service.example` in the
   service dir current.

5. **Validate and start**

   ```bash
   docker compose config --quiet && echo OK
   docker compose up -d && docker compose ps
   ```

   Expected: `OK`; `uptime-kuma` reaches `Up ... (healthy)` (start_period is 60 s — first boot
   runs DB migrations).

6. **Add the Caddy site block** to `/opt/dahouselab/infrastructure/configs/Caddyfile`:

   ```text
   status.{$DOMAIN} {
   	reverse_proxy uptime-kuma:3001
   }
   ```

   Validate + reload per [deploy-caddy](deploy-caddy.md) step 7:

   ```bash
   cd /opt/dahouselab/services/caddy
   docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
   docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
   ```

   Expected: reload exits 0. Commit the Caddyfile change.

7. **First-run setup** — open `https://status.${DOMAIN}`. Create the admin account immediately
   (setup is open to anyone who reaches the page first). Use a strong unique password; store it
   where you store platform credentials (Vaultwarden, once deployed — until then, your existing
   password manager).

   Expected: logged in to an empty dashboard.

8. **Configure a notification channel** — Settings → Notifications → Setup Notification. Example
   (Telegram): paste bot token + chat ID, **Test** → message arrives, enable "Default enabled"
   so future monitors inherit it.

   Expected: test notification received on your device.

9. **Add monitors for every already-deployed service** — with "Default enabled" notification:

   | Monitor          | Type        | Target                                   | Interval |
   | ---------------- | ----------- | ---------------------------------------- | -------- |
   | host             | Ping        | `${HOST_IP}` (from inside = gateway works) | 60 s   |
   | tailscale        | Ping        | the Pi's tailnet IP (`tailscale ip -4`)  | 60 s     |
   | caddy            | HTTP(s)     | `https://home.${DOMAIN}` (proves ingress) | 60 s    |
   | homepage         | HTTP(s)     | `https://home.${DOMAIN}` keyword check   | 60 s     |
   | uptime-kuma self | HTTP(s)     | `https://status.${DOMAIN}`               | 60 s     |

   For container-to-container checks, `http://homepage:3000` over the `proxy` network also works
   and removes the DNS dependency — use both styles where useful.

   Expected: all monitors green within one interval.

10. **Update the services inventory** in [`services/README.md`](../../services/README.md),
    commit `services/uptime-kuma/` to Git, and add Uptime Kuma to the Homepage dashboard
    (`${CONFIG_ROOT}/homepage/services.yaml`).

## Verification

- [ ] `docker compose ps` → `uptime-kuma` `healthy`
- [ ] `curl -sk -o /dev/null -w '%{http_code}\n' https://status.${DOMAIN}` → `200`
- [ ] Login works; all step-9 monitors are green
- [ ] Test notification delivered (step 8)
- [ ] Data landed correctly: `ls ${DATA_ROOT}/uptime-kuma/` shows `kuma.db*`
- [ ] Monitor-the-monitor: stop Homepage briefly (`docker stop homepage && sleep 90 && docker start homepage`) — an alert must arrive

## Rollback

```bash
cd /opt/dahouselab/services/uptime-kuma
docker compose down
```

Remove the `status.{$DOMAIN}` site block and reload Caddy. `${DATA_ROOT}/uptime-kuma` (monitors,
history, notification config) persists and is picked up by a later `up -d`. If the database was
corrupted during troubleshooting, restore `${DATA_ROOT}/uptime-kuma` from `${BACKUP_ROOT}` or
delete it and repeat steps 7–9. Rollback possible at every step.

## Troubleshooting

| Symptom                            | Likely cause                                  | Action                                                  |
| ---------------------------------- | --------------------------------------------- | -------------------------------------------------------- |
| 502 from Caddy                     | Wrong upstream port (must be 3001)            | Fix site block; reload Caddy                             |
| WebSocket/live updates broken      | Proxy not passing upgrade headers             | Caddy `reverse_proxy` handles this natively — check for a custom handler interfering |
| Monitors flap on ping targets      | ICMP restrictions in container                | Prefer HTTP(s) monitors; or accept TCP-ping type         |
| First boot very slow / unhealthy   | DB migration on Pi-class SD/SSD I/O           | Wait out `start_period`; check `docker compose logs`     |
| Notification test fails            | Bad token/chat ID or egress blocked           | Re-check credentials; `curl` the provider API from host  |

## Automation opportunities

- Steps 1–6 are the generic deploy flow — `scripts/deploy-service.sh` candidate.
- Monitors and notifications can be provisioned via Uptime Kuma's API/socket (community client
  libraries) from the `dahouselab.url` labels — would make "add a monitor" in every later
  runbook a one-liner. Blocked on picking/pinning a client library.

## Future improvements

- Export metrics (Uptime Kuma exposes Prometheus metrics) once a metrics stack exists.
- A second, external check (e.g. a free ping service watching `https://status.${DOMAIN}`)
  to catch whole-platform outages that Uptime Kuma cannot report on itself.
