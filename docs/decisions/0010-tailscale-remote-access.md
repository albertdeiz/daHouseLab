# ADR-0010: Tailscale for Remote Access

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | ADR-0005, ADR-0009, [docs/security/](../security/README.md), [docs/network/](../network/README.md) |

## Context

The platform hosts personal, sensitive services — passwords (Vaultwarden), documents
(Paperless-ngx), photos (Immich) — on a Raspberry Pi 4 behind a residential router
([ADR-0005](0005-raspberry-pi-platform.md)). These must be reachable from outside the LAN:
phones syncing photos, laptops reaching the dashboard from anywhere.

The home network constraints are typical: a consumer router, a dynamic public IP, possibly
CGNAT (which breaks inbound connections entirely), and a single operator with no appetite for
24/7 incident response. Any internet-exposed service on a residential IP is scanned within
minutes of appearing; exposure demands patching urgency this platform cannot promise.

Ingress inside the network is already settled: Caddy terminates TLS and routes everything
([ADR-0009](0009-caddy-reverse-proxy.md)). The remote-access question is purely how packets
from outside reach Caddy, and browsers still require valid HTTPS certificates for names that
never resolve publicly.

## Problem

How do trusted devices reach the platform's services from outside the LAN without exposing any
service to the public internet?

## Alternatives considered

### Option A — Tailscale mesh VPN

- Summary: Tailscale (WireGuard-based) on the host and every client device; the tailnet is a
  private overlay network; MagicDNS names the host; Tailscale-provisioned certificates give
  valid HTTPS for internal names. Zero router changes.
- Pros: no open inbound ports — zero public attack surface; works through CGNAT and dynamic
  IPs via NAT traversal (DERP relays as fallback); key distribution, device management and DNS
  are handled; WireGuard underneath is modern and fast; clients for every OS.
- Cons: dependency on Tailscale Inc.'s coordination servers for control plane (data plane is
  peer-to-peer); free tier is a commercial decision that could change; identity is delegated to
  an OAuth provider (login account compromise ≈ tailnet compromise).
- Why chosen: strongest security posture (no listening ports at all) with the least operational
  burden, and the control-plane dependency has a documented exit (headscale, Option E).

### Option B — Router port-forwarding + dynamic DNS

- Summary: forward 443 to Caddy, use DDNS for the changing IP, expose services publicly with
  authentication at each app.
- Pros: no client software; works from any device including untrusted ones; no third-party in
  the data path.
- Cons: every exposed service becomes internet attack surface on a residential IP; security
  now depends on the weakest login form and same-day patching; useless behind CGNAT; DDNS is
  another moving part.
- Why not chosen: converts a homelab into a 24/7 security operation. The blast radius (password
  vault, personal documents) is disproportionate to the convenience gained.

### Option C — Self-hosted WireGuard or OpenVPN

- Summary: run a VPN server on the host or router; clients connect back to home.
- Pros: no third-party control plane; WireGuard itself is excellent; full sovereignty.
- Cons: still requires one forwarded UDP port and a stable address (fails under CGNAT); manual
  key generation and distribution per device; hub-and-spoke, not mesh; DNS for internal names
  is self-assembled; OpenVPN adds legacy complexity for no benefit over WireGuard.
- Why not chosen: it is Tailscale minus NAT traversal, key management and DNS — precisely the
  parts that consume operator time — while re-adding an open port.

### Option D — Cloudflare Tunnel

- Summary: outbound tunnel from the host to Cloudflare's edge; services published on public
  hostnames behind Cloudflare Access policies.
- Pros: no open ports; survives CGNAT; can safely publish to untrusted devices; DDoS-shielded.
- Cons: Cloudflare terminates TLS and sees all traffic in plaintext at the edge — unacceptable
  for a password vault and personal documents; services get *public* hostnames by design,
  the opposite of this platform's posture; deeper vendor coupling than Tailscale (data plane,
  not just control plane).
- Why not chosen: it solves "publish safely", but the requirement is "don't publish at all".

### Option E — Headscale (self-hosted Tailscale control plane)

- Summary: the open-source reimplementation of Tailscale's coordination server, self-hosted;
  official Tailscale clients connect to it.
- Pros: removes the vendor control-plane dependency; same WireGuard mesh and clients.
- Cons: the coordination server must itself be hosted somewhere reachable (a VPS — new cost,
  new attack surface, new thing to patch); no MagicDNS certificates without extra work;
  community-maintained with no compatibility guarantee against client changes; bootstrapping
  problem if it runs on the very infrastructure it provides access to.
- Why not chosen (now): operating a control plane is real work that Tailscale currently does
  better for free. Kept explicitly as the exit path if Option A's dependency sours.

## Decision

We will provide remote access exclusively through a Tailscale mesh. The host runs Tailscale;
every trusted device joins the tailnet; remote traffic reaches Caddy
([ADR-0009](0009-caddy-reverse-proxy.md)) only over the tailnet. Zero ports are forwarded on
the home router — the router's inbound posture is identical to having no homelab at all.
MagicDNS plus Tailscale-provisioned certificates give valid HTTPS for internal names without
public DNS records. Publicly exposing **any** service, by any mechanism, is out of scope of
this ADR and requires a new ADR before implementation.

## Pros

- No inbound attack surface: nothing on the public internet ever gets a SYN-ACK from this
  network; scanning, credential stuffing and zero-day exposure classes vanish.
- Application authentication becomes defense-in-depth rather than the first line of defense —
  device identity gates access before any login form is reachable.
- Works from anywhere regardless of CGNAT, dynamic IP or hotel Wi-Fi; no DDNS.
- Near-zero maintenance: no keys to rotate by hand, no VPN server to patch, no certs to renew.
- Peer-to-peer WireGuard data plane: Tailscale's servers relay only when NAT traversal fails,
  and even relayed traffic stays end-to-end encrypted.

## Cons

- Control-plane dependency on Tailscale Inc.: coordination outage blocks *new* connections
  (established ones persist); pricing or free-tier changes are outside our control.
  Mitigation: headscale (Option E) is a tested-in-community exit path using the same clients.
- Identity root shifts to the OAuth login backing the tailnet; that account becomes a critical
  secret with 2FA mandatory.
- Every accessing device needs the client installed and enrolled — no ad-hoc access from a
  friend's browser, and no access for devices that can't run Tailscale.
- Sharing a service with family means onboarding their devices onto the tailnet (or a future
  ADR for selective exposure).

## Consequences

- The router configuration stays factory-simple and is no longer part of the platform's
  security boundary; [docs/network/](../network/README.md) documents the tailnet as the only
  remote path.
- Internal DNS naming and certificates are coupled to MagicDNS; service URLs must work for both
  LAN and tailnet clients (documented in [docs/network/](../network/README.md)).
- Any future "expose service X publicly" idea has a mandatory checkpoint: a new ADR weighing
  Option B/D-style mechanisms for that one service.
- The Mini PC migration must include tailnet enrollment of the new host before cutover so
  remote access never depends on being physically home.

## Operational impact

- Onboarding a device is: install client, authenticate, done — documented in
  [docs/runbooks/](../runbooks/README.md).
- The tailnet admin console becomes a periodic review item: prune stale devices, verify the
  device list matches reality.
- Monitoring must distinguish "Tailscale control plane unreachable" from "platform down";
  Uptime Kuma checks run on-net and can't see the remote path — a known observability gap.
- Tailscale client updates on the host ride the normal update runbook.

## Security considerations

- Blast-radius model: an attacker must first compromise an enrolled device or the tailnet
  identity account before any service login page is even reachable. Both are outside the
  platform's perimeter, so 2FA on the identity provider and device hygiene are load-bearing.
- Any enrolled device can reach every service on the host by default; Tailscale ACLs can narrow
  this if lower-trust devices (family members') ever join.
- Traffic is end-to-end WireGuard-encrypted; Tailscale's coordination servers see metadata
  (device names, endpoints, connection times) but not payloads.
- Node keys on the host and clients are secrets; a stolen enrolled laptop must be removed from
  the tailnet immediately (covered in [docs/security/](../security/README.md)).

## Future review

- If Tailscale changes free-tier terms, has a serious security incident, or its control-plane
  reliability degrades: execute the headscale evaluation (Option E).
- If any service must be shared with people who cannot join the tailnet: new ADR for selective
  public exposure.
- If lower-trust devices join the tailnet: introduce Tailscale ACLs and revisit the
  flat-network assumption.
- At the Mini PC migration: re-verify NAT traversal and MagicDNS behavior on the new host.
