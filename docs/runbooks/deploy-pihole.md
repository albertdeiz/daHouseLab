# Runbook: Deploy Pi-hole

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-08-12                                   |
| Estimated time  | 60 minutes                                   |
| Risk level      | High — step 9 takes over DNS for the whole house |
| Automation      | Manual                                       |

## Purpose

Deploy [Pi-hole](https://pi-hole.net/) as the LAN's DNS resolver at `https://dns.${DOMAIN}`. When
complete: Pi-hole runs bridge-networked on `proxy`, its UI is reachable **only** through Caddy+TLS,
port 53 is bound to the LAN and tailnet addresses (never `0.0.0.0`), every device in the house
resolves through it, and `*.dahub.casa` answers with the LAN address for LAN clients
([ADR-0014](../decisions/0014-pihole-as-lan-dns-resolver.md)).

## Scope

Covers: the `services/pihole/` stack, the two new platform globals, the Caddy route, the local DNS
records, and the router's DHCP DNS change.

Does not cover: Pi-hole's DHCP server (deliberately unused — the router keeps DHCP); pointing
tailnet devices at Pi-hole (**must not be done** — see step 8's warning); DNS-over-HTTPS upstreams.

## Prerequisites

- [ ] [deploy-caddy](deploy-caddy.md) complete and Caddy healthy
- [ ] [ADR-0014](../decisions/0014-pihole-as-lan-dns-resolver.md) read — in particular the
      single-point-of-failure cost accepted in step 9
- [ ] Admin access to the router's DHCP settings, and physical/SSH access that does **not** depend
      on name resolution (use `192.168.100.17` directly, not `daHouse.local`)
- [ ] Uptime Kuma green across the board: `https://status.${DOMAIN}`

## Risks

- **Worst case: the entire household loses DNS.** After step 9 every device resolves through this
  container. If it is down, misconfigured, or its data directory is unwritable, nothing on the
  network resolves anything — including the operator's own laptop while trying to fix it. This is
  why step 9 is last, and why its rollback is a router change, not a container change.
- An empty `HOST_IP`/`TAILNET_IP` silently degrades the port binding to `0.0.0.0`, exposing 53 on
  every interface. Caught in step 5, not in production.
- A wrong local DNS record (step 8) makes `*.dahub.casa` unreachable from the LAN, or — if tailnet
  devices are pointed here — from outside the house.
- Port 53 collides with `systemd-resolved`'s stub listener if that listener is not confined to
  `127.0.0.53`. Caught in the safety checks.

## Safety checks

- [ ] Port 53 free on the addresses we will bind:
      `sudo ss -lunp | grep -w :53` → shows **only** `127.0.0.53` (systemd-resolved's stub).
      Anything bound to `0.0.0.0:53`, `192.168.100.17:53` or `100.68.72.70:53` → stop.
- [ ] `dns.${DOMAIN}` not already routed:
      `grep -n "dns\." /opt/dahouselab/infrastructure/configs/Caddyfile` → no output
- [ ] Tailnet address unchanged: `tailscale ip -4` → `100.68.72.70`
- [ ] LAN address unchanged: `ip -4 addr show | grep 192.168.100` → `192.168.100.17`
- [ ] A known-good fallback resolver is reachable: `dig +short cloudflare.com @1.1.1.1` → answers.
      This is the rollback target for step 9.
- [ ] Uptime Kuma green across the board

## Procedure

1. **Pull the repo and populate the new globals.**

   `HOST_IP` has been declared-but-empty since the platform was built; `TAILNET_IP` is new
   ([ADR-0014](../decisions/0014-pihole-as-lan-dns-resolver.md)). Both are consumed by the port
   bindings, and compose interpolates **globals only** — so they must be in the root `.env`.

   ```bash
   cd /opt/dahouselab && git pull
   ```

   Edit `/opt/dahouselab/.env` (with an editor, not `echo`) so it contains:

   ```bash
   HOST_IP=192.168.100.17
   TAILNET_IP=100.68.72.70
   ```

   Expected: `grep -E '^(HOST_IP|TAILNET_IP)=' /opt/dahouselab/.env` prints both, non-empty.

2. **Create the data directory.**

   ```bash
   source /opt/dahouselab/.env
   sudo install -d -o 1000 -g 1000 "${DATA_ROOT}/pihole"
   ```

   Expected: `${DATA_ROOT}/pihole` exists, owned by `1000:1000`.

3. **Wire the environment layers.**

   ```bash
   cd /opt/dahouselab/services/pihole
   ln -sf ../../.env .env
   cp .env.service.example .env.service && chmod 600 .env.service
   openssl rand -base64 24        # copy this, do not pipe it anywhere
   ```

   Paste the generated value into `FTLCONF_webserver_api_password=` in `.env.service` **with an
   editor**, and store it in Vaultwarden. Expected: `ls -l` shows `.env -> ../../.env` and
   `-rw------- .env.service`.

4. **Validate the composition before starting anything.**

   ```bash
   docker compose config | grep -A6 'published'
   ```

   Expected: **four** published entries, each with a literal `host_ip` of `192.168.100.17` or
   `100.68.72.70`. If any shows `0.0.0.0`, a global is empty — return to step 1. Do not proceed.

5. **Start the container.**

   ```bash
   docker compose up -d && watch docker compose ps
   ```

   Expected: `pihole` reaches `healthy` within ~1 minute (first boot initialises `/etc/pihole` and
   downloads gravity).

   > If the container restarts in a loop, check `docker compose logs pihole` for a failure to bind
   > port 53. `pihole-FTL` relies on `CAP_NET_BIND_SERVICE`, which `no-new-privileges:true` can
   > block from being gained via file capabilities. Mitigate **in this order**, stopping at the
   > first that works: (a) add `cap_add: [NET_BIND_SERVICE]` to `compose.yaml`; (b) only if that
   > is insufficient, remove `security_opt: no-new-privileges` with an inline comment explaining
   > why. Either change is committed to Git with the reason — never left only on the host.

   At this point Pi-hole resolves on `192.168.100.17:53` but **nothing uses it yet**.

6. **Verify resolution before exposing any UI.**

   ```bash
   dig +short cloudflare.com @192.168.100.17     # → an A record: upstream works
   dig +short doubleclick.net @192.168.100.17    # → 0.0.0.0: filtering works
   ```

   Expected: both as annotated. If the first fails, the container cannot reach the internet; if the
   second returns a real address, gravity has not finished building — wait and retry.

7. **Add the Caddy route.**

   Append to `/opt/dahouselab/infrastructure/configs/Caddyfile`:

   ```caddyfile
   dns.{$DOMAIN} {
   	reverse_proxy pihole:80
   }
   ```

   ```bash
   docker compose -f /opt/dahouselab/services/caddy/compose.yaml exec caddy \
     caddy validate --config /etc/caddy/Caddyfile
   docker compose -f /opt/dahouselab/services/caddy/compose.yaml exec caddy \
     caddy reload --config /etc/caddy/Caddyfile
   ```

   Expected: `Valid configuration`, then a clean reload. `curl -sk https://dns.${DOMAIN}/` (over
   Tailscale) returns the Pi-hole UI; log in with the password from step 3.

8. **Add the local DNS records (split-horizon).**

   In the UI: *Settings → Local DNS Records*. Add both:

   | Domain         | IP               |
   | -------------- | ---------------- |
   | `dahub.casa`   | `192.168.100.17` |
   | `*.dahub.casa` | `192.168.100.17` |

   ```bash
   dig +short home.dahub.casa @192.168.100.17    # → 192.168.100.17
   ```

   > **Warning — do not point tailnet devices at Pi-hole.** These records apply to *every* client;
   > a resolver cannot answer differently by source. A remote device using Pi-hole would receive
   > the LAN address for `home.dahub.casa` and be unable to connect. Leave Tailscale's *Global
   > nameservers* setting untouched — remote devices must keep resolving via Cloudflare
   > ([ADR-0014](../decisions/0014-pihole-as-lan-dns-resolver.md)).

9. **Point the router's DHCP at Pi-hole.**

   > **Warning: step 9 is the destructive step.** From here the household depends on this
   > container for name resolution. Rollback point: the router's previous DNS value — note it down
   > before changing anything.

   On the router (`http://192.168.100.1`), in the DHCP/LAN settings:

   - Primary DNS: `192.168.100.17`
   - Secondary DNS: **empty**

   A secondary resolver is deliberately omitted: clients query either server at will, so a fallback
   would make filtering intermittent and unpredictable. Availability is handled by rollback, not by
   a second resolver.

   Then, on one client, renew the lease (disconnect/reconnect the network, or
   `sudo dhclient -r && sudo dhclient`) and confirm:

   ```bash
   # from the client
   dig +short doubleclick.net      # → 0.0.0.0
   dig +short home.dahub.casa      # → 192.168.100.17
   ```

   Expected: the client's queries appear in Pi-hole's *Query Log*, attributed to the client's real
   IP address — not to a Docker gateway address.

10. **Register the service.**

    - Uptime Kuma — **two** monitors, because the UI can be healthy while resolution is broken:
      - HTTP(s) `https://dns.dahub.casa/` (keyword `Pi-hole`), 60 s, cert-expiry on, Telegram
      - DNS, resolver `192.168.100.17`, hostname `cloudflare.com`, 60 s, Telegram
    - Homepage tile in `infrastructure/configs/homepage/services.yaml`
    - Confirm the port table ([ip-plan](../network/ip-plan.md)), the portfolio
      ([services/README](../../services/README.md)) and the monitor inventory
      ([uptime-kuma/docs](../../services/uptime-kuma/docs/README.md)) list this service

    Commit any host-side corrections back to Git — never leave a fix only on the host.

## Verification

- [ ] `docker compose ps` → `pihole` `healthy`
- [ ] `sudo ss -lunp | grep -w :53` → bound on `192.168.100.17` and `100.68.72.70`, **never**
      `0.0.0.0`
- [ ] `dig +short cloudflare.com @192.168.100.17` → resolves
- [ ] `dig +short doubleclick.net @192.168.100.17` → `0.0.0.0`
- [ ] `dig +short home.dahub.casa @192.168.100.17` → `192.168.100.17`
- [ ] `curl -sk https://dns.${DOMAIN}/` (over Tailscale) → Pi-hole UI, HTTP 200
- [ ] **No remote-access regression** — from a tailnet device **outside the house**, DNS untouched:
      `dig +short home.dahub.casa` → `100.68.72.70` (not the LAN address), and
      `curl -I https://home.dahub.casa` → 200
- [ ] From a LAN client with **Tailscale switched off**: `https://home.dahub.casa` loads
- [ ] A LAN client appears in *Query Log* by its real IP
- [ ] Persistence: `docker compose restart pihole`; the admin password and both local DNS records
      survive (`grep -c dahub.casa ${DATA_ROOT}/pihole/pihole.toml` → non-zero)
- [ ] Ports 53/udp and 53/tcp appear in [ip-plan](../network/ip-plan.md)
- [ ] Both Uptime Kuma monitors green; other services still green

## Rollback

Rollback is possible at every step. The fastest and most important one does not involve the
container at all:

```bash
# 1. Give the house its DNS back (router UI): primary DNS -> 1.1.1.1, secondary empty.
#    Renew leases on affected clients. The household is working again from here.

# 2. Then, at leisure:
cd /opt/dahouselab/services/pihole
docker compose down
```

Remove the `dns.{$DOMAIN}` block from the Caddyfile and reload Caddy. `${DATA_ROOT}/pihole`
persists, so a later `up -d` resumes with settings and history intact. No nftables rules or systemd
units were created, so there is nothing else on the host to clean up.

## Troubleshooting

| Symptom                                        | Likely cause                                  | Action                                                                 |
| ---------------------------------------------- | --------------------------------------------- | ---------------------------------------------------------------------- |
| `bind: address already in use` on :53          | systemd-resolved's stub listener is global     | `resolvectl status` → confirm the stub is on `127.0.0.53`; if not, set `DNSStubListener=no` in `/etc/systemd/resolved.conf.d/` and restart it |
| `docker compose config` shows `0.0.0.0`        | `HOST_IP`/`TAILNET_IP` empty in the root `.env`| Step 1. Do not start the container until this is fixed                  |
| Container restart-loops, log shows a bind failure | `no-new-privileges` blocking `CAP_NET_BIND_SERVICE` | Escalate the mitigation in step 5's note, and commit the change     |
| Container fails to start only after a reboot   | `tailscale0` has no address yet when Docker starts | `restart: unless-stopped` retries; if it persists, order the container start after `tailscaled` |
| Everything resolves but nothing is blocked     | Clients kept an old lease, or use hardcoded DNS | Renew the lease; check *Query Log* for the client. Devices with hardcoded DNS bypass Pi-hole entirely |
| All queries attributed to one Docker address   | Docker's userland proxy is rewriting the source | Confirm the query really comes from the host; otherwise set `"userland-proxy": false` in `/etc/docker/daemon.json` |
| Pi-hole *Network* tab shows no MAC addresses   | Expected — bridge networking, not a fault      | Device identity is [NetAlertX](../../services/netalertx/README.md)'s job ([ADR-0013](../decisions/0013-host-networking-for-lan-scanning.md)) |
| Remote `*.dahub.casa` resolves to the LAN IP   | A tailnet device is using Pi-hole              | Step 8's warning — remove Pi-hole from Tailscale's global nameservers   |
| UI 502 via `dns.dahub.casa`                    | Pi-hole not on `proxy`, or listening elsewhere | `docker network inspect proxy`; confirm `FTLCONF_webserver_port: "80"`  |

## Automation opportunities

- Steps 2–5 are the generic [deploy-with-compose](deploy-with-compose.md) flow and would be covered
  by the planned `scripts/deploy-service.sh`.
- The pre-flight assertion in step 4 (no binding may resolve to `0.0.0.0`) is a good candidate for
  a repo-wide compose lint — it generalises to any service that interpolates an address.
- Blocklists and local DNS records could be declared in Git and pushed via Pi-hole's API at deploy
  time, which would remove this service's dependence on backups for its configuration.

## Future improvements

- **The single point of failure is unaddressed.** A second resolver (on a second node, or
  `keepalived` with a floating address) is the only real fix; a secondary DNS entry at the router is
  not, because it makes filtering non-deterministic. Revisit when a second node exists.
- Advertising the LAN subnet over Tailscale would let tailnet devices use Pi-hole safely and make
  the `${TAILNET_IP}` binding useful rather than merely provisioned.
- Query-log retention is at upstream's default; if the privacy exposure of a per-client browsing
  record is unwanted, shorten it or disable logging in the UI.
