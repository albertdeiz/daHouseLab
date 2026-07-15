# ADR-0009: Caddy as Reverse Proxy

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | ADR-0004, ADR-0007, ADR-0008, ADR-0010, [docs/standards/docker-compose-conventions.md](../standards/docker-compose-conventions.md) |

## Context

The platform runs multiple web applications as containers on one host
([ADR-0003](0003-docker-first.md), [ADR-0004](0004-docker-compose.md)). Without a reverse
proxy, each service would publish its own host port: URLs become `host:8096`-style, TLS is
per-service or absent, and every published port is an independent piece of host attack surface.

The platform's conventions already assume a single ingress: applications join an external
`proxy` Docker network and must not use `ports:`; databases sit on per-stack internal networks
only ([docker-compose-conventions](../standards/docker-compose-conventions.md)). Remote access
arrives via Tailscale ([ADR-0010](0010-tailscale-remote-access.md)), so the proxy serves LAN
and tailnet clients — nothing is internet-facing.

Requirements: automatic TLS with near-zero certificate operations, ARM64 support, a
configuration format that can be reviewed in Git ([ADR-0007](0007-git-as-source-of-truth.md)),
and operational simplicity befitting a single operator.

## Problem

Which reverse proxy provides the single ingress point for all web services, and where does its
routing configuration live?

## Alternatives considered

### Option A — Caddy with a version-controlled Caddyfile

- Summary: Caddy 2 as the only container publishing 80/443; routing declared in one Caddyfile
  in `infrastructure/configs/`, mounted `:ro`; TLS handled automatically by Caddy.
- Pros: automatic HTTPS is Caddy's core feature, not an add-on; the Caddyfile is short, human
  readable, and diffs cleanly in review; single static binary, first-class ARM64; sane secure
  defaults (modern TLS, HTTP/2/3).
- Cons: smaller ecosystem than Nginx; fewer battle-tested examples for exotic apps; advanced
  scenarios need the JSON config or plugins requiring a custom build (`xcaddy`).
- Why chosen: it needs the least configuration to be correct, and its configuration is exactly
  the kind of small reviewed text file this platform is built around.

### Option B — Traefik (label-driven)

- Summary: Traefik discovers routes from Docker labels on each application container.
- Pros: routes deploy with the service; popular in homelab setups; good dashboard.
- Cons: routing is scattered across every compose file instead of one reviewable document;
  Traefik needs the Docker socket (or a socket proxy) — handing the ingress container
  effectively root on the host; label syntax is notoriously fiddly; configuration model
  (static vs dynamic) is heavier to learn.
- Why not chosen: label-driven discovery is a scale feature this platform doesn't need, paid
  for with Docker-socket exposure and routing that can't be read in one place. This is also
  why routing-in-labels is explicitly banned in
  [docker-compose-conventions](../standards/docker-compose-conventions.md).

### Option C — Nginx / Nginx Proxy Manager

- Summary: plain Nginx with hand-written vhosts, or NPM adding a web UI and certbot automation.
- Pros: Nginx is the most battle-tested proxy alive; unlimited documentation; NPM is beginner
  friendly.
- Cons: plain Nginx means manual certificate plumbing (certbot timers, renewal hooks) — the
  exact toil Caddy eliminates; NPM moves routing into a clicked-through database, which is
  invisible to Git and violates [ADR-0007](0007-git-as-source-of-truth.md); NPM has had a weak
  security track record.
- Why not chosen: plain Nginx costs recurring TLS toil; NPM costs the source-of-truth principle.
  Both lose to Caddy on this platform's actual requirements.

### Option D — HAProxy

- Summary: HAProxy as TCP/HTTP load balancer and TLS terminator.
- Pros: exceptional performance and reliability at scale; fine-grained traffic control.
- Cons: no built-in ACME automation comparable to Caddy's; configuration is expert-oriented;
  its strengths (load balancing across backends) are irrelevant with one replica of everything.
- Why not chosen: a load balancer without anything to balance; wrong tool shape.

### Option E — No proxy (direct published ports)

- Summary: each service publishes its own host port; clients use `host:port` URLs.
- Pros: zero extra components; nothing between client and app.
- Cons: no uniform TLS (browsers scream, some apps require HTTPS for features); N published
  ports of host attack surface; unmemorable URLs; per-service TLS if attempted at all;
  contradicts the single-ingress property in [overview](../architecture/overview.md).
- Why not chosen: do-nothing baseline; fails TLS and attack-surface requirements immediately.

## Decision

We will run Caddy as the platform's single ingress. Caddy is the only container that publishes
ports 80/443 on the host; every web application attaches to the external `proxy` network and is
reachable only through Caddy. TLS is automatic via Caddy. All routing lives in one Caddyfile in
`infrastructure/configs/`, version-controlled and mounted read-only
([ADR-0008](0008-configuration-data-separation.md)) — never in Docker labels. Applications
that need `ports:` for non-proxyable protocols require a documented exception per
[docker-compose-conventions](../standards/docker-compose-conventions.md).

## Pros

- One place to see, review and diff every route on the platform; adding a service's route is a
  commit, with history and rollback.
- Certificate management drops to zero recurring work.
- Host attack surface is exactly two ports regardless of how many services run.
- Consistent `https://<service>.${DOMAIN}` URLs across LAN and tailnet.
- No Docker socket access needed by the ingress — Caddy knows nothing about Docker.

## Cons

- Single point of failure by design: Caddy down means every web UI is down (accepted — the
  whole node is already a SPOF, [ADR-0005](0005-raspberry-pi-platform.md)).
- Adding a service is a two-place change (compose file + Caddyfile); forgetting the Caddyfile
  is a predictable failure mode, mitigated by the deploy runbook, not by tooling.
- Less community mindshare than Nginx/Traefik when debugging an odd application behind a proxy.
- Plugins (if ever needed) mean maintaining a custom `xcaddy` image build.

## Consequences

- The `proxy` external network and the "no `ports:` on applications" rule become enforceable
  review checks with a clear owner (this ADR).
- The Caddyfile becomes a load-bearing reviewed artifact; its syntax and reload procedure need
  runbook coverage.
- WebSocket-, gRPC- or streaming-dependent services must be verified through Caddy at
  deployment time, not assumed.
- Replacing Caddy later is contained: one service directory plus one config file, as recorded
  in the [overview](../architecture/overview.md) layer table.

## Operational impact

- New-service deployment gains a standard step: add the site block, `git commit`, reload Caddy
  (graceful — no dropped connections).
- Ingress observability centralizes: Caddy's access logs are the single traffic record for the
  platform, feeding monitoring (Uptime Kuma checks go through the proxy, exercising the real
  path).
- Caddy image updates follow the normal pinned-version
  [update runbook](../runbooks/update-containers.md); as the ingress, it gets updated first and
  verified before applications.

## Security considerations

- Attack surface concentrates in one well-audited component: memory-safe (Go), TLS 1.2+
  defaults, automatic HSTS-capable HTTPS.
- Applications are unreachable except through Caddy; databases are not even on the `proxy`
  network — two network hops of containment between ingress and data.
- The read-only Caddyfile mount means a compromised Caddy container cannot persist routing
  changes across a redeploy ([ADR-0008](0008-configuration-data-separation.md)).
- Caddy terminates TLS, so traffic to backends crosses the `proxy` Docker network in plaintext
  — acceptable on a single host, but a constraint to revisit if backends ever leave the node.

## Future review

- If any service must become internet-facing (this also triggers a new ADR per
  [ADR-0010](0010-tailscale-remote-access.md)) — hardening, rate limiting and WAF-type
  requirements change the ingress calculus.
- If more than one node exists, plaintext backend traffic and single-ingress topology must be
  re-decided.
- If a required capability forces custom Caddy plugin builds as routine work, re-evaluate
  against Traefik/Nginx.
- If Caddy's release cadence or maintenance falters.
