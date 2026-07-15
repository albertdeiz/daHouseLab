# caddy

Reverse proxy and TLS termination — the platform's **single ingress**
([ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md)). Every web service is reached
through Caddy at `https://<name>.dahub.casa`; no other container may publish ports. Certificates
come from Let's Encrypt via DNS-01 against Cloudflare
([ADR-0011](../../docs/decisions/0011-dns-01-tls-certificates.md)), which is why the image is a
custom build (see [`Dockerfile`](Dockerfile)).

## Quick reference

| Field         | Value                                                        |
| ------------- | ------------------------------------------------------------ |
| Image         | `dahouselab/caddy:2.10.2` (local build: `caddy:2.10.2` + `caddy-dns/cloudflare`) |
| URL           | n/a (infrastructure — serves all `*.dahub.casa` vhosts)      |
| Ports         | `80`, `443`, `443/udp` — the only published ports on the host |
| Networks      | `proxy` (external)                                            |
| Config path   | Routing: `${DAHOUSELAB_ROOT}/infrastructure/configs/Caddyfile` (`:ro`, in Git) · runtime state: `${CONFIG_ROOT}/caddy/{data,config}` |
| Data path     | none                                                          |
| Backup        | yes — `${CONFIG_ROOT}/caddy` (certificates; cheap to lose, re-issued automatically) |
| Category      | infrastructure                                                |

## Dependencies

- `proxy` Docker network exists ([infrastructure/networks](../../infrastructure/networks/README.md))
- Cloudflare-hosted DNS for `dahub.casa` with `*.dahub.casa` → host's Tailscale IP, and a
  zone-scoped API token ([ADR-0011](../../docs/decisions/0011-dns-01-tls-certificates.md))

## Deployment

Follow the runbook: [deploy-caddy](../../docs/runbooks/deploy-caddy.md).

## Configuration

- Environment: see [`.env.example`](.env.example) — the only secret is `CLOUDFLARE_API_TOKEN`.
- Routing lives in the version-controlled
  [Caddyfile](../../infrastructure/configs/Caddyfile); changes are committed to Git and applied
  with a zero-downtime reload (runbook, step 7). Never edit routing on the host.

## Data

None. `${CONFIG_ROOT}/caddy` holds only re-creatable runtime state (issued certificates, OCSP).

## Backup & restore

`${CONFIG_ROOT}/caddy` is included in platform backups to avoid re-issuance rate limits after a
restore, but losing it is harmless: certificates re-issue automatically on next start.

## Operations

- Health: `docker compose ps` shows `healthy`; `curl -sk https://localhost` answers.
- Logs: `docker compose logs -f caddy`
- Reload after Caddyfile change:
  `docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile && docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`
- Known failure modes: see the runbook's troubleshooting table.

## References

- Upstream: <https://caddyserver.com/docs/>
- Plugin: <https://github.com/caddy-dns/cloudflare>
- ADRs: [0009](../../docs/decisions/0009-caddy-reverse-proxy.md), [0011](../../docs/decisions/0011-dns-01-tls-certificates.md)
