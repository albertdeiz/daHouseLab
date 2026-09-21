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
| `dahub.casa`         | A    | `192.168.100.17`| Pi-hole local record — **LAN clients only** ([ADR-0014](../decisions/0014-pihole-as-lan-dns-resolver.md)) |
| `*.dahub.casa`       | A    | `192.168.100.17`| Pi-hole local record — **LAN clients only** |

Service hostnames resolve publicly but point at the tailnet address — reachable only from
devices on the Tailscale mesh ([ADR-0010](../decisions/0010-tailscale-remote-access.md)).

**Split-horizon:** since [ADR-0014](../decisions/0014-pihole-as-lan-dns-resolver.md), clients that
resolve through Pi-hole (i.e. everything on the LAN, via the router's DHCP DNS option) get the
**LAN** address instead, reaching the services directly rather than through the tailnet. TLS is
unaffected — certificates come from DNS-01 against the Cloudflare zone and are valid at either
address. Tailnet devices are deliberately **not** pointed at Pi-hole: they would receive the LAN
address and fail to connect from outside the house.

Resolver for the LAN: `192.168.100.17` (Pi-hole), handed out by the router's DHCP as the **only**
DNS server — no secondary, so filtering is deterministic. Fallback if the host is down: set a
client's DNS to `1.1.1.1` manually, or revert the router's DHCP option.

## Published ports (authoritative table)

| Host port | Protocol   | Service | Why                                             |
| --------- | ---------- | ------- | ------------------------------------------------ |
| 80        | TCP        | caddy   | HTTP→HTTPS redirect (single ingress, [ADR-0009](../decisions/0009-caddy-reverse-proxy.md)) |
| 443       | TCP + UDP  | caddy   | HTTPS + HTTP/3                                   |
| 22        | TCP        | sshd (host) | Key-only ([configure-ssh](../runbooks/configure-ssh.md)) |
| 20211     | TCP        | netalertx (host net) | LAN scanner UI ([ADR-0013](../decisions/0013-host-networking-for-lan-scanning.md)). **Firewalled**: reachable only from loopback + docker bridge (`172.16.0.0/12`) — i.e. Caddy — never the LAN/tailnet directly ([deploy-netalertx](../runbooks/deploy-netalertx.md)) |
| 53        | UDP + TCP  | pihole   | LAN DNS resolution ([ADR-0014](../decisions/0014-pihole-as-lan-dns-resolver.md)). **Bound to `192.168.100.17` and `100.68.72.70` only** — never `0.0.0.0`; the bind address is the boundary, so no firewall rule exists. Not reachable from the internet (no port-forwarding) |

Router port-forwarding: **none** — and it stays that way without a new ADR.
An open port not in this table is an incident.
