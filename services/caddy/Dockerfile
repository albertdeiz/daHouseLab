# Stock Caddy + caddy-dns/cloudflare for DNS-01 (ADR-0011).
# Update procedure: bump BOTH tags in lockstep, then rebuild (update-containers runbook).
FROM caddy:2.10.2-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2.10.2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
