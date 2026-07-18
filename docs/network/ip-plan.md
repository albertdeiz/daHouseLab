# IP Plan

## Why

Services and clients need the host at a stable address. The chosen mechanism is a **DHCP
reservation at the router** (option A of [configure-static-ip](../runbooks/configure-static-ip.md)):
the host stays a plain DHCP client — zero host-side configuration to migrate — and the router
pins the lease to the MAC.

## Host addressing

| Field                | Value                                | Notes                                   |
| -------------------- | ------------------------------------ | ---------------------------------------- |
| Hostname             | `daHouse`                            | Raspberry Pi 4                           |
| MAC (Ethernet)       | `dc:a6:32:f8:e9:c9`                  | The reservation key — re-check after board replacement ([replace-raspberry-pi](../runbooks/replace-raspberry-pi.md)) |
| LAN IP               | `192.168.100.17`                     | DHCP reservation, configured 2026-07-17  |
| Tailnet IP           | `100.68.72.70`                       | `tailscale ip -4`                        |
| LAN subnet           | `192.168.100.0/24`                   | Router at `192.168.100.1`                |

## DNS

| Record               | Type | Value           | Where                        |
| -------------------- | ---- | --------------- | ---------------------------- |
| `*.dahub.casa`       | A    | `100.68.72.70`  | Cloudflare (DNS-only / grey cloud) — [ADR-0011](../decisions/0011-dns-01-tls-certificates.md) |

Service hostnames resolve publicly but point at the tailnet address — reachable only from
devices on the Tailscale mesh ([ADR-0010](../decisions/0010-tailscale-remote-access.md)).

## Published ports (authoritative table)

| Host port | Protocol   | Service | Why                                             |
| --------- | ---------- | ------- | ------------------------------------------------ |
| 80        | TCP        | caddy   | HTTP→HTTPS redirect (single ingress, [ADR-0009](../decisions/0009-caddy-reverse-proxy.md)) |
| 443       | TCP + UDP  | caddy   | HTTPS + HTTP/3                                   |
| 22        | TCP        | sshd (host) | Key-only ([configure-ssh](../runbooks/configure-ssh.md)) |
| 20211     | TCP        | netalertx (host net) | LAN scanner UI ([ADR-0013](../decisions/0013-host-networking-for-lan-scanning.md)). **Firewalled**: reachable only from loopback + docker bridge (`172.16.0.0/12`) — i.e. Caddy — never the LAN/tailnet directly ([deploy-netalertx](../runbooks/deploy-netalertx.md)) |

Router port-forwarding: **none** — and it stays that way without a new ADR.
An open port not in this table is an incident.
