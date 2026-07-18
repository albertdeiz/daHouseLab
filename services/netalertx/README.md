# netalertx

[NetAlertX](https://github.com/netalertx/NetAlertX) — LAN device discovery and presence
monitoring at `https://net.dahub.casa`. It scans the local network (ARP), maintains an inventory
of every device seen, and **alerts when an unknown device joins** — turning the manual
[IP plan](../../docs/network/ip-plan.md) into a live, self-updating view of what is on the WiFi.

## Quick reference

| Field         | Value                                          |
| ------------- | ---------------------------------------------- |
| Image         | `ghcr.io/netalertx/netalertx:26.7.1`           |
| URL           | `https://net.${DOMAIN}` (via Caddy; port 20211 on the host, fenced to Caddy) |
| Networks      | **host** (deviation, [ADR-0013](../../docs/decisions/0013-host-networking-for-lan-scanning.md)) — not on `proxy` |
| Config path   | — (single app dir; see Data)                   |
| Data path     | `${DATA_ROOT}/netalertx` (config + sqlite db, single mount — documented deviation) |
| Backup        | yes — device history + config (sqlite: dump/stop-copy, never live file copy) |
| Category      | monitoring                                     |

## Deviations from the standards

- **Architectural — host networking ([ADR-0013](../../docs/decisions/0013-host-networking-for-lan-scanning.md)):**
  ARP discovery needs layer-2 LAN access, impossible from the NAT'd `proxy` bridge. This service
  runs `network_mode: host`, a scoped exception to [ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md).
  It is **not** on the `proxy` network and binds port 20211 on the host. Mitigations: UI still via
  Caddy+TLS, raw port firewalled to Caddy only, `NET_RAW`/`NET_ADMIN` caps only, pinned image,
  `no-new-privileges`.
- **Non-architectural — single mount:** config and the sqlite db both live under `/data`
  (upstream layout), collapsing the two-mount rule into one — documented as a comment in
  `compose.yaml`, no ADR (as with vaultwarden).

## Dependencies

- `proxy` network + Caddy with TLS, **plus** `extra_hosts: host.docker.internal:host-gateway` on
  Caddy so it can reach the host-networked UI
- Uptime Kuma deployed, so this service is monitored from day one
- Host firewall (nftables) — the deploy adds a rule fencing port 20211 to Caddy

## Deployment

Follow the runbook: [deploy-netalertx](../../docs/runbooks/deploy-netalertx.md).

## Configuration

- Environment: globals via the `.env` symlink ([ADR-0012](../../docs/decisions/0012-layered-environment-files.md));
  service layer in [`.env.service.example`](.env.service.example) — copy to `.env.service`.
  No DB secret (local sqlite); the admin login is set in the web UI at first run.
- Scan targets, notification gateways (Telegram) and thresholds are configured in the web UI and
  persisted under `${DATA_ROOT}/netalertx/config`.

Details: [`docs/`](docs/README.md).

## Data

`${DATA_ROOT}/netalertx`: `config/` (app settings) and `db/` (the sqlite device history). Small
(MBs) but the device history is worth keeping. Runs as uid 20211.

## Backup & restore

- sqlite via dump or stop-copy-start — never a live copy
  ([execute-backup](../../docs/runbooks/execute-backup.md)); config rides the file backup.
- Restore: [restore-from-backup](../../docs/runbooks/restore-from-backup.md).

## Operations

- Health: `docker compose ps` → `healthy`; `curl -sk https://net.${DOMAIN}/` (over Tailscale) → 200
- Logs: `docker compose logs -f netalertx`
- Known failure modes:
  - UI unreachable via `net.dahub.casa` but container healthy → Caddy `extra_hosts`/site block, or
    the nftables rule is dropping the docker-bridge source
  - No devices discovered → arp-scan needs `NET_RAW`/`NET_ADMIN` and host networking; confirm both
  - Port 20211 reachable from a LAN host → firewall rule missing/incorrect (should be Caddy-only)

## References

- Upstream documentation: <https://github.com/netalertx/NetAlertX>
- Related: [ADR-0013](../../docs/decisions/0013-host-networking-for-lan-scanning.md),
  [ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md),
  [network/ip-plan](../../docs/network/ip-plan.md)
