# ADR-0011: TLS Certificates via DNS-01 with Cloudflare DNS

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | [ADR-0009](0009-caddy-reverse-proxy.md), [ADR-0010](0010-tailscale-remote-access.md), [docs/runbooks/deploy-caddy.md](../runbooks/deploy-caddy.md) |

## Context

Every web service is reached at `https://<name>.${DOMAIN}` through Caddy
([ADR-0009](0009-caddy-reverse-proxy.md)), and browsers require a trusted TLS certificate for
each hostname. Caddy obtains certificates automatically from Let's Encrypt, but Let's Encrypt
must first verify domain control through an ACME challenge:

- **HTTP-01** — Let's Encrypt connects to port 80 of the host **from the internet**.
- **DNS-01** — the ACME client proves control by creating a temporary DNS TXT record; no inbound
  connectivity is required.

The platform is deliberately unreachable from the internet: zero router port-forwarding, remote
access only via Tailscale ([ADR-0010](0010-tailscale-remote-access.md)). HTTP-01 is therefore
structurally impossible — not a configuration problem, a consequence of the security posture.

The platform owns the domain `dahub.casa`, registered at **Namecheap**. Relevant facts:

- Namecheap's DNS API has eligibility requirements (account-level thresholds such as domain count
  or spend) and requires **whitelisting the caller's fixed IP** — hostile to a homelab behind a
  residential connection.
- The corresponding Caddy plugin (`caddy-dns/namecheap`) is community-maintained with low activity.
- A domain's registrar and its DNS host are independent: nameservers can be delegated to any DNS
  provider while registration stays at Namecheap.
- Platform policy is HTTPS everywhere ([security model](../security/README.md)) — plain HTTP or
  long-lived certificate warnings are not a workable fallback.

Requirement: certificates that every device trusts with zero per-device setup, automatic renewal,
and no public exposure of the host.

## Problem

How does Caddy obtain publicly-trusted TLS certificates for `*.dahub.casa` on a host that is
intentionally unreachable from the internet?

## Alternatives considered

### Option A — DNS-01 with the zone delegated to Cloudflare (chosen)

- Summary: keep registration at Namecheap; point the domain's nameservers at Cloudflare (free
  plan); build Caddy with the `caddy-dns/cloudflare` plugin; enable DNS-01 globally with
  `acme_dns cloudflare` and a zone-scoped API token.
- Pros: the most mature and widely-used Caddy DNS plugin; API tokens scoped to a single zone's
  DNS with no account-level access; no IP whitelisting; free; renewal is fully automatic.
- Cons: one-time nameserver delegation; a third party (Cloudflare) is added to the trust chain;
  Caddy becomes a custom-built image instead of the stock one.
- Why chosen: only option that combines publicly-trusted certs, zero exposure, zero per-device
  setup and a well-maintained integration.

### Option B — DNS-01 directly against the Namecheap API

- Summary: same mechanism, using Namecheap's own DNS API and plugin.
- Pros: no nameserver change; one vendor fewer.
- Cons: API eligibility thresholds this account does not meet; mandatory source-IP whitelisting
  breaks on residential IP rotation; weakly-maintained plugin; API key is account-wide (poor
  blast radius).
- Why not chosen: operationally fragile at exactly the moment it must work unattended (renewal).

### Option C — Tailscale certificates (`ts.net`)

- Summary: use Tailscale's built-in `tailscale cert` for names under the tailnet's `ts.net` domain.
- Pros: zero cost, zero DNS management, valid public certs.
- Cons: hostnames are machine-scoped (`host.tailnet.ts.net`), fitting one-service-per-host, not
  eight services behind one proxy; abandons the owned domain; couples naming to Tailscale
  (deepens the ADR-0010 dependency).
- Why not chosen: does not fit the single-host, many-subdomains architecture.

### Option D — Caddy internal CA (`local_certs`)

- Summary: Caddy signs certificates with its own private CA.
- Pros: works with no domain, no internet, no third parties.
- Cons: every device (phones included) must manually install and trust the root CA; every new
  device repeats the ritual; guests can never be served cleanly; `.dev` HSTS makes any trust gap
  a hard failure.
- Why not chosen: per-device manual trust violates the maintainability principle; this is
  the fallback of last resort, not the design.

### Option E — Temporary public exposure for HTTP-01

- Summary: open port 80 during issuance windows.
- Cons: directly violates [ADR-0010](0010-tailscale-remote-access.md)'s zero-exposure posture for
  a recurring (60–90 day) operation.
- Why not chosen: rejected outright; renewals would institutionalize the exposure.

## Decision

We will obtain TLS certificates from Let's Encrypt using the **DNS-01 challenge against
Cloudflare-hosted DNS**:

1. `dahub.casa` stays registered at Namecheap; its **nameservers are delegated to Cloudflare**
   (free plan), which becomes the authoritative DNS host.
2. DNS records for services (`*.dahub.casa`) point at the host's **Tailscale address**, so
   names resolve publicly but are reachable only inside the tailnet.
3. Caddy runs as a **custom image** built from the pinned official image plus
   `caddy-dns/cloudflare` (Dockerfile version-controlled in `services/caddy/`).
4. DNS-01 is enabled platform-wide via `acme_dns cloudflare` in the Caddyfile global block, so
   service site blocks need no per-site TLS configuration.
5. The Cloudflare API token is scoped to `Zone → DNS → Edit` on this single zone and lives only
   in `services/caddy/.env` on the host ([environment standard](../standards/environment-variables.md)).

## Pros

- Publicly-trusted certificates on every device with zero per-device setup — including guests.
- Fully automatic issuance and renewal; no recurring manual operation.
- No inbound exposure, preserving ADR-0010 intact.
- Token blast radius limited to DNS records of one zone.
- Per-site Caddyfile blocks stay minimal — TLS is a platform concern, configured once.

## Cons

- Caddy is no longer the stock image: updates now mean rebuilding the custom image, not just
  bumping a tag.
- Cloudflare joins the critical-vendor list (DNS availability, API compatibility).
- Individual subdomain certificates appear in public Certificate Transparency logs, revealing
  service names (`vault.dahub.casa` is now guessable knowledge).
- The public A record exposes the host's tailnet IP (100.64.0.0/100 range) — unreachable to
  outsiders, but visible.

## Consequences

- A new secret class exists (DNS provider API token) — added to the
  [rotate-secrets](../runbooks/rotate-secrets.md) inventory.
- `services/caddy/` gains a Dockerfile; the [update-containers](../runbooks/update-containers.md)
  flow for Caddy is: bump base-image tags in the Dockerfile → rebuild → up.
- One-time manual actions at vendors: nameserver change at Namecheap, zone + token creation at
  Cloudflare — recorded as prerequisites in [deploy-caddy](../runbooks/deploy-caddy.md).
- Any future service is HTTPS-ready by creating a DNS record; nothing else changes.

## Operational impact

- Renewals are unattended; failure surfaces as certificate-expiry alerts — Uptime Kuma should
  monitor certificate expiry on at least one canonical URL.
- DNS record changes move from Namecheap's panel to Cloudflare's (documented in
  [`docs/network/`](../network/README.md)).
- Restoring the platform (disaster recovery) now also requires the Cloudflare account credential —
  it belongs in the off-platform credential set listed in
  [disaster-recovery](../runbooks/disaster-recovery.md).

## Security considerations

- The API token can alter DNS for the zone if exfiltrated (enabling domain takeover for this
  zone) — mitigations: minimal scope, `600` permissions on `.env`, rotation on suspicion,
  never in Git ([ADR-0007](0007-git-as-source-of-truth.md)).
- CT-log service-name disclosure is accepted for now; the documented hardening is switching to a
  single wildcard certificate (`*.dahub.casa`), which publishes only the wildcard.
- Publishing tailnet IPs in public DNS is accepted: the addresses are unroutable from outside the
  tailnet; secrecy of internal addressing is not a security control we rely on.

## Future review

Re-examine this decision if:

- Cloudflare's free DNS tier or API terms change materially.
- `caddy-dns/cloudflare` becomes unmaintained.
- The platform adopts a second ingress or public exposure for any service (new ADR required by
  [ADR-0010](0010-tailscale-remote-access.md)) — HTTP-01 may then become viable and simpler.
- CT-log disclosure becomes a concern in practice → adopt the wildcard certificate.
