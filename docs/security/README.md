# Security Documentation

The security model of the platform: what is protected, from what, and how.

## Threat model (summary)

This is a personal homelab, not a bank. The realistic threats, in priority order:

1. **Accidental exposure** — a service reachable from the internet that shouldn't be.
2. **Credential leakage** — secrets committed to Git or reused across services.
3. **Data loss** — covered by [`../backup/`](../backup/README.md), but ransomware makes it a security concern too.
4. **Opportunistic attackers** — scanners hitting anything publicly reachable.

Targeted attacks by sophisticated adversaries are explicitly out of scope.

## Defense posture

| Layer          | Control                                                                      |
| -------------- | ---------------------------------------------------------------------------- |
| Network        | No router port-forwarding; remote access only via Tailscale ([ADR-0010](../decisions/0010-tailscale-remote-access.md)) |
| Host           | SSH key-only auth, no root login, unattended security updates ([runbook](../runbooks/configure-ssh.md)) |
| Transport      | TLS everywhere via Caddy ([ADR-0009](../decisions/0009-caddy-reverse-proxy.md)) |
| Secrets        | Never in Git; `.env` files on host with `600` permissions; rotation runbook ([rotate-secrets](../runbooks/rotate-secrets.md)) |
| Containers     | Pinned image versions, no unnecessary privileges, isolated internal networks |
| Data           | Offline/external backups as ransomware mitigation                            |

## Scope

- Secrets management: where secrets live, how they are created, rotated and revoked
- Host hardening checklist and its verification
- Container security conventions (users, capabilities, read-only mounts)
- Exposure policy: the process required before any service becomes publicly reachable

## Ground rules

- Secrets, keys and certificates never enter Git — enforced by [`.gitignore`](../../.gitignore),
  verified by review.
- Every account on every service uses a unique generated password stored in Vaultwarden.
- Any deviation from secure defaults requires an ADR.
