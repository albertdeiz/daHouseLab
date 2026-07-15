# Network Documentation

How traffic reaches services: topology, addressing, DNS, reverse proxy routing and remote access.

## Scope

| Concern        | Content to document here                                        |
| -------------- | ---------------------------------------------------------------- |
| Topology       | Router → host → Docker networks; physical and logical diagrams   |
| IP plan        | Static LAN IP of the host, DHCP ranges, reserved addresses       |
| DNS            | Local DNS / MagicDNS names, per-service hostnames                |
| Reverse proxy  | Hostname → container routing table (Caddy)                       |
| Ports          | The single authoritative table of every published host port      |
| Remote access  | Tailscale mesh: nodes, ACLs, exit-node policy                    |
| Firewall       | Host firewall rules and router port-forwarding policy (none, by default) |

## Ground rules

- **Only the reverse proxy publishes HTTP/HTTPS ports on the host.** Applications attach to the
  internal `proxy` Docker network ([ADR-0009](../decisions/0009-caddy-reverse-proxy.md)).
- **Nothing is exposed to the public internet by default.** Remote access goes through Tailscale
  ([ADR-0010](../decisions/0010-tailscale-remote-access.md)).
- Every published port must appear in the port table here — an undocumented open port is an incident.

Related runbooks: [configure-static-ip](../runbooks/configure-static-ip.md),
[deploy-caddy](../runbooks/deploy-caddy.md), [deploy-tailscale](../runbooks/deploy-tailscale.md).
