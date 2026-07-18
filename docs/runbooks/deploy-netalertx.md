# Runbook: Deploy NetAlertX

| Field           | Value            |
| --------------- | ---------------- |
| Last reviewed   | 2026-07-17       |
| Estimated time  | 60 minutes       |
| Risk level      | Medium           |
| Automation      | Manual           |

## Purpose

Deploy [NetAlertX](https://github.com/netalertx/NetAlertX) (LAN device discovery + presence
alerting) at `https://net.${DOMAIN}`. When complete: NetAlertX runs in the **host network
namespace** (required for ARP scanning — [ADR-0013](../decisions/0013-host-networking-for-lan-scanning.md)),
its data lives in `${DATA_ROOT}/netalertx`, the web UI is reachable **only through Caddy+TLS**,
and its raw port (20211) is fenced to Caddy by a host nftables rule.

## Scope

Covers: the `services/netalertx/` stack, the host-networking deviation and its mitigations, the
nftables rule, the Caddy `extra_hosts` change + site block, first-run setup, monitor. Does not
cover: per-device naming, notification-gateway tuning beyond enabling Telegram, or Homepage tiles
(host bind-mount config, not in Git).

## Prerequisites

- [ ] [deploy-with-compose](deploy-with-compose.md) read; [ADR-0013](../decisions/0013-host-networking-for-lan-scanning.md) read — this service is a deliberate networking exception
- [ ] `proxy` network exists; Caddy deployed and healthy; Uptime Kuma deployed (deploy is watched)
- [ ] Root `.env` at `/opt/dahouselab/.env` defines the global set
- [ ] `nftables` available on the host: `command -v nft` → a path
- [ ] The host's LAN interface name is known: `ip -o -4 route show to default` → e.g. `eth0`

## Risks

- **Elevated blast radius:** this container shares the host network stack and holds
  `NET_RAW`/`NET_ADMIN` — a compromise reaches further than any bridge-isolated service. The
  nftables rule and pinned image are load-bearing, not optional.
- A wrong nftables rule either exposes port 20211 on the LAN (too permissive) or blocks Caddy from
  reaching the UI (too strict — it must allow the docker-bridge source). Worst case is only an
  unreachable UI or an exposed admin port; no data loss.
- Editing Caddy's compose (`extra_hosts`) recreates the Caddy container — a brief ingress blip for
  all services. Do it in a maintenance window.

## Safety checks

- [ ] `net.${DOMAIN}` not already routed: `grep -n "net\." /opt/dahouselab/infrastructure/configs/Caddyfile` → no output
- [ ] Port 20211 free on the host: `sudo ss -ltnp | grep -w 20211` → no output
- [ ] Uptime Kuma green across the board

## Procedure

1. **Create the host data directory** (the service dir is already in Git — do **not** copy the
   template over it):

   ```bash
   cd /opt/dahouselab && git pull
   source /opt/dahouselab/.env
   sudo mkdir -p ${DATA_ROOT}/netalertx
   sudo chown -R 20211:20211 ${DATA_ROOT}/netalertx   # NetAlertX runs as uid 20211
   ```

   Expected: `${DATA_ROOT}/netalertx` exists, owned by `20211:20211`.

2. **Create the environment files** ([ADR-0012](../decisions/0012-layered-environment-files.md)):

   ```bash
   cd /opt/dahouselab/services/netalertx
   ln -sf ../../.env .env
   cp .env.service.example .env.service && chmod 600 .env.service
   ```

   `.env.service` needs no secret (NetAlertX uses a local sqlite; the admin login is set in the UI
   at first run). Leave `PORT=20211` unless it collides with something. Expected: `ls -l` shows
   `.env -> ../../.env` and `.env.service` as `-rw-------`.

3. **Validate and start**

   ```bash
   docker compose config --quiet && echo OK
   docker compose up -d && watch docker compose ps
   ```

   Expected: `OK`; `netalertx` becomes `healthy` (first boot initializes `/data`). At this point
   the UI answers on the host at `http://localhost:20211` but is **not yet fenced** — step 4.

4. **Fence port 20211 to Caddy with nftables.** Host networking binds 20211 on every interface;
   this rule permits it only from loopback and the docker-bridge range (where Caddy connects
   from) and drops it everywhere else. Add this table to `/etc/nftables.conf`:

   ```
   # NetAlertX (ADR-0013): expose the UI port only to Caddy (docker bridge) + loopback.
   table inet netalertx {
   	chain input {
   		type filter hook input priority -10; policy accept;
   		iif "lo" tcp dport 20211 accept
   		tcp dport 20211 ip saddr 172.16.0.0/12 accept
   		tcp dport 20211 drop
   	}
   }
   ```

   Then load and persist:

   ```bash
   sudo nft -f /etc/nftables.conf
   sudo systemctl enable --now nftables
   sudo nft list table inet netalertx        # verify the rules are live
   ```

   Expected: the table lists the three rules. From another LAN host,
   `curl -m3 http://192.168.100.17:20211` now **fails/times out**; from the host,
   `curl -fsS http://localhost:20211/` still succeeds.

5. **Let Caddy reach the host-networked UI, then route it.** Add `extra_hosts` to Caddy's compose
   (`services/caddy/compose.yaml`) — already present if this repo is current:

   ```yaml
       extra_hosts:
         - "host.docker.internal:host-gateway" # reach host-networked services (ADR-0013)
   ```

   Add the site block to `/opt/dahouselab/infrastructure/configs/Caddyfile`:

   ```text
   net.{$DOMAIN} {
   	reverse_proxy host.docker.internal:20211
   }
   ```

   Apply (the `extra_hosts` change requires recreating Caddy, not just a reload):

   ```bash
   cd /opt/dahouselab/services/caddy
   docker compose up -d                       # recreates caddy with extra_hosts
   docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
   docker compose exec caddy caddy reload  --config /etc/caddy/Caddyfile
   ```

   Commit the Caddyfile + compose change to Git. Expected: reload exits 0;
   `curl -sk https://net.${DOMAIN}/` (over Tailscale) returns the NetAlertX UI.

6. **First-run setup** — open `https://net.${DOMAIN}`:
   - **Enable authentication** (Settings → set a login password) — mandatory, the port is admin-grade.
   - Set the **scan interface/subnet** to the LAN (`192.168.100.0/24`) and enable the arp-scan plugin.
   - Configure the **Telegram** notification gateway (reuse the platform bot) and enable
     new-device alerts.

   Expected: a first scan lists the known devices from the LAN.

7. **Monitor and inventory** — add an Uptime Kuma HTTP(s) monitor for `https://net.${DOMAIN}/`
   (keyword: `NetAlertX`), 60s, cert-expiry on, Telegram; update
   [`services/README.md`](../../services/README.md), the
   [monitor inventory](../../services/uptime-kuma/docs/README.md), the
   [port table](../network/ip-plan.md), and Homepage; commit.

## Verification

- [ ] `docker compose ps` → `netalertx` `healthy`
- [ ] `curl -sk https://net.${DOMAIN}/` (over Tailscale) → NetAlertX UI (HTTP 200)
- [ ] `curl -m3 http://192.168.100.17:20211` **from a LAN host** → refused/timeout (firewall proves Caddy-only)
- [ ] Devices from `192.168.100.0/24` appear in the device list; a test new device raises an alert
- [ ] `sudo nft list table inet netalertx` shows the three rules; rule survives `sudo systemctl restart nftables`
- [ ] Port 20211 appears in [`docs/network/ip-plan.md`](../network/ip-plan.md) with its firewall note

## Rollback

```bash
cd /opt/dahouselab/services/netalertx
docker compose down
sudo nft delete table inet netalertx        # remove the firewall rule
```

Remove the `net.` site block from the Caddyfile and reload Caddy; the `extra_hosts` line on Caddy
is harmless to leave. `${DATA_ROOT}/netalertx` persists; a later `up -d` resumes. Reverting the
firewall/network changes fully restores the pre-deploy state — nothing here is irreversible.

## Troubleshooting

| Symptom                                   | Likely cause                                  | Action                                                          |
| ----------------------------------------- | --------------------------------------------- | --------------------------------------------------------------- |
| UI 502 via `net.dahub.casa`               | Caddy can't reach the host                    | Confirm `extra_hosts: host-gateway` on Caddy and that it was **recreated** (not just reloaded) |
| UI 502 but container healthy              | nftables dropping the docker-bridge source    | The `172.16.0.0/12 accept` rule must precede the `drop`; check `nft list table inet netalertx` |
| Port 20211 reachable from the LAN         | Firewall rule missing or ordered wrong        | Re-apply step 4; `iif lo` + bridge accept **before** drop       |
| No devices discovered                     | Missing caps or not host-networked            | Confirm `network_mode: host` and `NET_RAW`/`NET_ADMIN` in `docker inspect` |
| `healthcheck` failing, UI works           | Image lacks `curl`                            | Swap the healthcheck to `wget -q --spider` or a python one-liner |
| nftables rule gone after reboot           | `nftables.service` not enabled / not in conf  | `systemctl enable --now nftables`; ensure the table is in `/etc/nftables.conf` |

## Automation opportunities

- Steps 1–3 are the generic deploy flow — `scripts/deploy-service.sh` candidate.
- The nftables rule is a fixed artifact — it could be templated and applied by a host-config script
  rather than hand-edited into `/etc/nftables.conf`.

## Future improvements

- Revisit the host-networking exception at the Mini PC migration (multi-NIC/VLAN may allow cleaner
  isolation) — see [ADR-0013](../decisions/0013-host-networking-for-lan-scanning.md).
- Enrich device metadata by importing DHCP leases from the router if it ever exposes them.
