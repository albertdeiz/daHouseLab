# ADR-0013: Host Networking for LAN Device Discovery

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-17                               |
| Deciders | albertdeiz                               |
| Related  | [ADR-0009](0009-caddy-reverse-proxy.md) (scoped exception), [ADR-0003](0003-docker-first.md), [ADR-0010](0010-tailscale-remote-access.md), [deploy-netalertx](../runbooks/deploy-netalertx.md) |

## Context

The platform has no visibility into which devices are on the home LAN. We want a service that
**discovers and lists connected devices and alerts on unknown ones** — a network presence monitor
([NetAlertX](https://github.com/netalertx/NetAlertX) is the chosen tool).

Device discovery worth the name is done with **ARP at layer 2**: the scanner broadcasts ARP
requests on the LAN segment and reads the MAC/IP pairs that answer. This is the only method that
yields a stable device **identity** (the MAC) and finds hosts that never initiate traffic.

The platform's networking model ([ADR-0009](0009-caddy-reverse-proxy.md)) is deliberately narrow:
applications attach **only** to the internal `proxy` Docker bridge network, and **only Caddy
publishes ports** on the host. On a Docker bridge network the container sits behind NAT in its own
L3 subnet — it cannot see LAN MAC addresses at all. ARP discovery is therefore **impossible** from
a bridge-networked container; it requires the container to share the host's network stack
(`network_mode: host`). That directly contradicts ADR-0009 and compose-convention rule 6.

## Problem

How do we give the platform layer-2 LAN device discovery without abandoning the single-ingress,
bridge-only networking model that ADR-0009 exists to protect?

## Alternatives considered

### Option A — `network_mode: host` for the scanner (chosen)

- Run NetAlertX in the host network namespace so arp-scan sees the LAN directly.
- Pros: the only option with true ARP presence + MAC identity + silent-host discovery; it is
  upstream's documented, supported deployment.
- Cons: breaks ADR-0009 for this one container; binds its web port (20211) on all host interfaces;
  needs raw-socket capabilities — a larger blast radius than any other service.
- Why chosen: it is the only alternative that actually solves the stated problem. The cost is
  contained to one container and mitigated (see Security), and the UI is kept behind Caddy+TLS.

### Option B — Poll the router (SNMP / vendor API)

- A bridge-networked container makes outbound queries to the router for its ARP/DHCP-lease table.
- Pros: zero deviation from ADR-0009; no raw sockets; no published port.
- Cons: depends entirely on router capabilities (the household router exposes no usable SNMP/API);
  it reports the router's *lease* view, not independent presence, and misses static-IP or
  short-lease devices. A ready-made UI for this (LibreNMS, Home Assistant) is far heavier.
- Why not chosen: not viable on the current router, and a weaker signal even where it is.

### Option C — DNS-based visibility (Pi-hole / AdGuard Home)

- Make the Pi the LAN DNS server and read connected clients from DNS query logs.
- Pros: no raw sockets; doubles as ad-blocking; only a normal published port (53).
- Cons: shows only devices that *resolve DNS through it* — not presence, no MAC identity, misses
  anything with hardcoded DNS; requires taking over DHCP's DNS option (a network-wide change).
- Why not chosen: solves a different problem (DNS visibility), not device discovery.

### Option D — `macvlan` network

- Give the container its own MAC/IP directly on the LAN.
- Pros: L2 visibility without full host networking.
- Cons: equally architectural (a new network type outside the `proxy` model), classic
  host↔macvlan isolation headaches, extra IP/DHCP management, and it still sidesteps ADR-0009.
- Why not chosen: as invasive as Option A with more operational sharp edges and no offsetting gain.

### Option E — Bridge network + `NET_RAW` ping/TCP sweep

- Keep the container on `proxy`, grant `NET_RAW`, sweep the subnet with ICMP/TCP.
- Pros: no host networking.
- Cons: NAT strips L2, so **no MAC addresses** (no stable identity) and **silent hosts are
  invisible**. This is a fundamentally weaker scan masquerading as discovery.
- Why not chosen: fails the core requirement (identity + completeness) while still needing a cap.

## Decision

We will run **NetAlertX — and only NetAlertX — with `network_mode: host`**, as a narrow,
documented exception to [ADR-0009](0009-caddy-reverse-proxy.md). ADR-0009 remains in force for
every other service; this ADR does not supersede it.

The exception is bounded by four conditions, all mandatory:

1. The deviation is annotated **in the compose file** (comment citing this ADR) as the deviation
   policy requires.
2. The web UI is **still reached through Caddy + TLS** at `net.dahub.casa` — no new plaintext
   ingress is normalized.
3. The raw UI port (20211) is **firewalled to Caddy only**: a host nftables rule permits tcp/20211
   from loopback and the docker-bridge range (`172.16.0.0/12`) and drops it from every other
   source, so LAN/tailnet clients cannot reach it directly.
4. The container runs least-privilege otherwise: pinned image tag, `no-new-privileges`, and only
   the `NET_RAW`/`NET_ADMIN` capabilities arp-scan actually needs.

## Pros

- The platform gains real LAN device discovery and unknown-device alerting.
- The blast radius of the deviation is one container, explicitly reasoned about and fenced in.
- The single-ingress UX (`*.dahub.casa` via Caddy/TLS) is preserved even for this service.

## Cons

- One container now shares the host network stack and holds raw-socket capabilities — a genuinely
  larger attack surface than the rest of the fleet.
- The "only Caddy publishes ports" invariant now has an exception a reader must know about (hence
  this ADR and the port-table entry).
- The firewall rule is the first host-firewall rule on the platform; it must be persisted and
  maintained, and it is load-bearing for the security argument above.

## Consequences

- A new host firewall posture: `docs/network/README.md` changes from "firewall: none by default"
  to "one targeted rule". The rule lives in the [deploy-netalertx](../runbooks/deploy-netalertx.md)
  runbook as a **standalone nftables table** (`/etc/nftables.d/netalertx.conf`) applied by a
  **oneshot unit ordered after `docker.service`**. It must **never** go in a flushing
  `/etc/nftables.conf` / `nftables.service`: that flushes Docker's own chains
  (`DOCKER`, `DOCKER-USER`) and breaks all container networking (incident 2026-07-17).
- Port 20211 is added to the authoritative port table (`docs/network/ip-plan.md`) with its
  firewall qualifier — an open port absent from that table is still an incident.
- Caddy's compose gains `extra_hosts: host.docker.internal:host-gateway` so it can reach the
  host-networked UI; this is a benign, documented cross-service coupling.
- Future host-networked services do **not** inherit this exception automatically — each needs its
  own ADR. This ADR is the precedent's *reasoning*, not a blanket grant.

## Operational impact

- Deployment and lifecycle follow [deploy-netalertx](../runbooks/deploy-netalertx.md); the firewall
  rule is part of that runbook and of disaster recovery (it must be re-applied on rebuild).
- Uptime Kuma monitors `net.dahub.casa` like any other service.
- On host/board replacement, re-verify the firewall rule and interface names
  ([replace-raspberry-pi](../runbooks/replace-raspberry-pi.md)).

## Security considerations

- **Elevated blast radius:** a compromise of this container has host network visibility and
  raw-socket capability — unlike bridge-isolated services. This is the central cost of the ADR.
- **Mitigations:** pinned image (no `:latest`), `no-new-privileges:true`, capabilities limited to
  `NET_RAW`/`NET_ADMIN`, the nftables rule fencing 20211 to Caddy, DNS pointing only at the tailnet
  (no LAN/WAN exposure of `net.dahub.casa`), and NetAlertX's own login enabled at first run.
- **No public exposure:** router port-forwarding stays `none` ([ADR-0010](0010-tailscale-remote-access.md));
  the service is reachable only over the Tailscale mesh through Caddy.
- **Precedent:** Tailscale already runs at host level as a networking exception; this ADR extends
  the same "narrow, documented, mitigated" pattern to a containerized scanner.

## Future review

- Re-examine at the **Mini PC migration** — a multi-NIC/VLAN host may allow a cleaner isolation.
- If a non-host discovery path becomes viable (router gains SNMP/API, or a maintained tool offers
  equivalent presence without host networking), migrate and retire this exception.
- If NetAlertX becomes unmaintained or the container is found to need broader privileges than
  `NET_RAW`/`NET_ADMIN`, reassess whether the feature is worth the deviation.
