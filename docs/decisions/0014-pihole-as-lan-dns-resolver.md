# ADR-0014: Pi-hole as the LAN DNS Resolver

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-08-12                               |
| Deciders | albertdeiz                               |
| Related  | [ADR-0009](0009-caddy-reverse-proxy.md), [ADR-0010](0010-tailscale-remote-access.md), [ADR-0011](0011-dns-01-tls-certificates.md), [ADR-0013](0013-host-networking-for-lan-scanning.md) (evaluated Pi-hole for a different problem), [deploy-pihole](../runbooks/deploy-pihole.md) |

## Context

The platform runs no resolver of its own. Every device in the house resolves against whatever the
router hands out over DHCP — the ISP's upstream — which means:

- No filtering of advertising or telemetry at the network layer. Blocking is per-device, per-app,
  or absent (smart TVs and IoT devices have no ad blocker at all).
- No visibility into what any device queries. The platform monitors uptime
  ([Uptime Kuma](../../services/uptime-kuma/README.md)) and LAN presence
  ([NetAlertX](../../services/netalertx/README.md)) but is blind to DNS.
- No authority over name resolution. `*.dahub.casa` is an A record at Cloudflare pointing at the
  **tailnet** address ([ADR-0011](0011-dns-01-tls-certificates.md)), so a laptop sitting two metres
  from the Pi reaches `home.dahub.casa` by routing through the Tailscale mesh — and cannot reach it
  at all when the tailnet is down, even though both machines are on the same switch.

The last point is the one with teeth: the platform's own services are, on the LAN, reachable only
through an overlay network that has nothing to do with the LAN.

[ADR-0013](0013-host-networking-for-lan-scanning.md) already evaluated Pi-hole as **Option C** and
rejected it — but for device discovery, not on its merits as a resolver ("solves a different
problem (DNS visibility), not device discovery"). That ADR also named the price this one now pays:
adopting a LAN resolver "requires taking over DHCP's DNS option (a network-wide change)".

## Problem

Should the Pi become the authoritative DNS resolver for the home LAN — accepting that it becomes a
single point of failure for household internet — in exchange for network-wide filtering, per-client
query visibility, and local name resolution?

## Alternatives considered

### Option A — Pi-hole on the `proxy` bridge, port 53 bound to specific addresses (chosen)

- Pi-hole v6 runs as an ordinary bridged service on the `proxy` network. Its web UI (container port
  80) is served only through Caddy. Port 53/udp+tcp is published, but **bound explicitly to the LAN
  address and the tailnet address** rather than `0.0.0.0`.
- Pros: no deviation beyond the one compose-convention rule 6 already anticipates ("unless a
  protocol cannot traverse the proxy" — DNS/UDP cannot); no host networking; no added
  capabilities; no host firewall rule, because the bind address itself is the boundary; binding to
  a specific address also sidesteps `systemd-resolved`'s stub listener on `127.0.0.53:53` without
  reconfiguring the host.
- Cons: DNS becomes a household-wide dependency on one container; the published port is a second
  service publishing ports, weakening the "only Caddy publishes ports" shorthand (though not the
  rule, which always allowed this case).
- Why chosen: it buys the full feature set at the smallest structural cost — it is the only option
  that adds no new architectural exception to the platform.

### Option B — Pi-hole with `network_mode: host`

- Run Pi-hole in the host network namespace, as NetAlertX does.
- Pros: simplest possible networking; client IPs are unambiguous; would also populate Pi-hole's
  own ARP-derived network table with real MAC addresses.
- Cons: needs its own ADR by the explicit terms of
  [ADR-0013](0013-host-networking-for-lan-scanning.md) ("future host-networked services do **not**
  inherit this exception automatically"); binds 53 on **every** interface, which then has to be
  fenced back with an nftables table; collides head-on with the `systemd-resolved` stub listener.
- Why not chosen: it pays an architectural price for a capability we do not need. Pi-hole requires
  no layer-2 access — a published port is sufficient — so the exception would buy nothing that
  Option A does not already provide.

### Option C — AdGuard Home instead of Pi-hole

- Functionally equivalent: filtering resolver with a web UI, DNS-over-HTTPS upstreams built in.
- Pros: DoH/DoT upstreams without extra components; arguably a nicer UI.
- Cons: no advantage that matters at this scale; smaller ecosystem of documented homelab practice;
  [`services/netalertx/docs/README.md`](../../services/netalertx/docs/README.md) already anticipates
  a **Pi-hole/AdGuard client import** for the device inventory, and Pi-hole's API is the
  better-documented of the two for that.
- Why not chosen: a coin flip resolved by maturity and by the volume of existing operational
  knowledge; not a technical rejection.

### Option D — Do nothing

- Keep resolving through the router's ISP upstream.
- Pros: zero new failure modes; zero maintenance; the router stays the only thing that must be up
  for the house to work.
- Cons: leaves every stated problem unsolved, including the LAN-traffic-through-the-tailnet detour,
  which is a real availability defect rather than a missing luxury.
- Why not chosen: the detour alone justifies acting.

## Decision

We will run **Pi-hole v6 as the authoritative DNS resolver for the LAN**, deployed as an ordinary
bridged service. Concretely:

1. **Bridge networking.** Pi-hole joins `proxy` like every other service. Its UI is reached **only**
   through Caddy + TLS at `dns.dahub.casa`; container ports 80/443 are never published.
2. **Port 53 is published, bound to explicit addresses.** `${HOST_IP}` (LAN) and `${TAILNET_IP}`
   (Tailscale), never `0.0.0.0`. This is the `ports:` exception that compose-convention rule 6
   already provides for; it is annotated in the compose file and recorded in
   [`docs/network/ip-plan.md`](../network/ip-plan.md). **No host firewall rule is created** — the
   bind address is the boundary.
3. **DHCP stays at the router.** Pi-hole's DHCP server is not used, so the container needs neither
   `NET_ADMIN` nor host networking. The router's DHCP **DNS option** points at the Pi and at
   nothing else — a single resolver, no secondary.
4. **Split-horizon local records.** Pi-hole answers `dahub.casa` and `*.dahub.casa` with
   `192.168.100.17`, so LAN clients reach the platform's services directly over the LAN instead of
   through the tailnet.
5. **`TAILNET_IP` becomes a reserved platform global**, alongside `HOST_IP`, because compose can
   interpolate globals only and the port bindings need both.

This ADR introduces **no exception to [ADR-0009](0009-caddy-reverse-proxy.md)**: all web ingress
still passes through Caddy alone. It qualifies [ADR-0011](0011-dns-01-tls-certificates.md) — public
resolution of `*.dahub.casa` is unchanged; only the answer given to LAN clients differs.

## Pros

- Network-wide ad and telemetry filtering, including for devices that can never run a blocker.
- Per-client DNS visibility — the first insight the platform has into what the household actually
  talks to, and a useful complement to NetAlertX's presence data.
- LAN traffic to platform services stops detouring through Tailscale: lower latency, and the
  services stay reachable at home even when the tailnet is down.
- The platform gains authority over its own namespace without touching the Cloudflare zone.

## Cons

- **DNS becomes a single point of failure for the whole house.** If the Pi is down, name resolution
  is down — for everyone, for everything. This is the deliberate cost of choosing a single resolver
  over a secondary; a secondary would make blocking non-deterministic, which is worse.
- The split-horizon record applies to **every** Pi-hole client, because a resolver cannot answer
  differently by source. Pointing tailnet devices at Pi-hole would hand them the LAN address and
  break remote access (see Consequences).
- A second service now publishes host ports. The invariant is intact but the shorthand ("only Caddy
  publishes ports") is no longer literally true, and a reader must know why.
- Changing the router's DHCP DNS option is a household-visible change with a brief outage window
  while leases renew.

## Consequences

- **Tailnet devices must not be pointed at Pi-hole** until the LAN subnet is advertised
  (`tailscale up --advertise-routes=192.168.100.0/24`). Pi-hole is therefore **not** configured as
  a Global nameserver in the Tailscale admin console; remote devices keep resolving
  `*.dahub.casa` via Cloudflare to the tailnet address. The `${TAILNET_IP}` binding is provisioned
  for deliberate opt-in, not for fleet-wide use. Advertising that route is a separate decision.
- `HOST_IP` — declared but empty since the platform was built — must now be populated, and
  `TAILNET_IP` added, in the root `.env`. An empty value silently degrades the binding to
  `0.0.0.0`, so `docker compose config` is a mandatory pre-flight check in the runbook.
- Ports 53/udp and 53/tcp join the authoritative port table. An open port absent from that table
  remains an incident.
- Host/board replacement must re-verify both addresses:
  [replace-raspberry-pi](../runbooks/replace-raspberry-pi.md) and
  [migrate-to-mini-pc](../runbooks/migrate-to-mini-pc.md) now have a DNS dependency, and the LAN
  address is load-bearing for both the bindings and the local records.
- Disaster recovery gains a hard ordering constraint: until Pi-hole is back, LAN clients cannot
  resolve anything. [disaster-recovery](../runbooks/disaster-recovery.md) must state the manual
  fallback (set a client's DNS to `1.1.1.1`) before any other step depends on name resolution.
- Uptime Kuma monitors this service twice: an HTTP check on the UI **and** a DNS check against
  `192.168.100.17`. The UI can be healthy while resolution is broken; only the second check speaks
  to what the household actually depends on.

## Operational impact

- Deployment and lifecycle follow [deploy-pihole](../runbooks/deploy-pihole.md).
- Blocklists and local DNS records are configured in the web UI and persist under
  `${DATA_ROOT}/pihole` — they are **not** in Git, and are therefore backup-dependent state.
- Rollback is fast and does not involve the container: set the router's DNS option back to
  `1.1.1.1` and renew leases. This is the first line of defence for any DNS-shaped outage and
  belongs in the household's "the internet is broken" reflex.
- Upstream resolvers default to Cloudflare (`1.1.1.1`, `1.0.0.1`) and are changeable from the UI
  without redeployment.

## Security considerations

- **Not an open resolver.** Router port-forwarding remains `none`
  ([ADR-0010](0010-tailscale-remote-access.md)) and 53 is bound to the LAN and tailnet addresses
  only — never `0.0.0.0`, and never reachable from the internet. This bounds the classic DNS
  amplification risk without needing a firewall rule.
- **Blast radius is ordinary.** Unlike [ADR-0013](0013-host-networking-for-lan-scanning.md)'s
  exception, this container is bridge-isolated, holds no added capabilities, and runs with
  `no-new-privileges:true` and a pinned image tag.
- **New sensitive data.** The query log is a per-client record of household browsing — the most
  privacy-sensitive dataset on the platform. It lives only in `${DATA_ROOT}/pihole` and is covered
  by the same backup and disk-disposal handling as everything else under `DATA_ROOT`.
- **One secret**, the admin/API password, lives in `services/pihole/.env.service` (`chmod 600`)
  like every other service secret ([ADR-0012](0012-layered-environment-files.md)).
- **A compromised resolver can redirect any name.** This is inherent to running a resolver; it is
  mitigated by the UI being reachable only through Caddy over the tailnet, and by the admin
  password.

## Future review

- **When a second node exists**, revisit for a redundant resolver — that is the only real fix for
  the single-point-of-failure cost accepted here.
- **At the Mini PC migration**, re-verify the bind addresses and local records against the new
  host's addressing.
- **If the LAN subnet is advertised over Tailscale**, revisit whether tailnet devices should use
  Pi-hole, which would make the split-horizon record safe fleet-wide.
- **If DNS-over-HTTPS upstreams become a requirement**, re-evaluate Option C (AdGuard Home) or add
  a `cloudflared` sidecar — either is a change to this decision.
