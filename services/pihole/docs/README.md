# pihole — Documentation

Deep documentation for the LAN resolver. Front page: [`../README.md`](../README.md).
The decision and its costs: [ADR-0014](../../../docs/decisions/0014-pihole-as-lan-dns-resolver.md).

## Why the UI holds state that Git does not

Everything below — blocklists, local records, allowlist entries — is configured in the web UI and
written to `${DATA_ROOT}/pihole/pihole.toml`. That is a deliberate departure from the platform's
usual "config lives in Git" habit, and it is upstream's model, not a choice: Pi-hole owns its
config file and rewrites it. The consequence is that **this service's configuration is only as
durable as the backups**, so the settings that matter are recorded here in prose as well.

## Local DNS records (split-horizon)

| Record          | Type | Value            | Why                                            |
| --------------- | ---- | ---------------- | ---------------------------------------------- |
| `dahub.casa`    | A    | `192.168.100.17` | Apex, so the bare domain resolves on the LAN   |
| `*.dahub.casa`  | A    | `192.168.100.17` | Every service hostname resolves directly over the LAN |

Cloudflare still answers `*.dahub.casa` with the tailnet address `100.68.72.70` for everyone else
([ADR-0011](../../../docs/decisions/0011-dns-01-tls-certificates.md)). TLS is unaffected —
certificates are issued over DNS-01 against the Cloudflare zone and are valid regardless of which
address the client connects to.

**The trap:** a resolver cannot answer differently depending on who is asking. These records apply
to *every* Pi-hole client. If a tailnet device were pointed at Pi-hole, it would receive
`192.168.100.17` for `home.dahub.casa` and fail to connect from outside the house. This is why
Pi-hole is **not** configured as the tailnet's Global nameserver, and why the `${TAILNET_IP}`
binding exists for deliberate opt-in only. Making it safe fleet-wide requires advertising the LAN
subnet over Tailscale (`tailscale up --advertise-routes=192.168.100.0/24`) — a separate decision.

## Blocklists

Start with the default list Pi-hole ships (StevenBlack's unified hosts list) and add deliberately.
The failure mode of aggressive blocking is not a broken site — it is a household member who stops
trusting the platform, so every list added should be recorded here with a date and a reason.

| List | Added | Why | Removed |
| ---- | ----- | --- | ------- |
| StevenBlack unified hosts (default) | 2026-08-12 | Ships with Pi-hole; broad ads + malware, low false-positive rate | — |

When a site breaks: find the domain in *Query Log*, allowlist that single domain, and note it
below. Disabling filtering wholesale to "fix" one site hides the actual cause.

| Allowlisted domain | Date | Why |
| ------------------ | ---- | --- |
|                    |      |     |

## Upstream resolvers

Cloudflare (`1.1.1.1`, `1.0.0.1`), set in `compose.yaml` and overridable from the UI. Chosen for
consistency with the rest of the stack, which already depends on Cloudflare for the DNS zone and
DNS-01 issuance — it adds no new third party. Note that this does mean one company sees both the
authoritative zone and the recursive queries; DNS-over-HTTPS or a different upstream would change
that, and is listed as a future review condition in the ADR.

## Client attribution

Pi-hole is bridge-networked, so client IPs reach it through Docker's DNAT. LAN clients keep their
real source address and are attributed correctly. Two known exceptions:

- Queries originating **on the host itself** appear as the Docker gateway address.
- Pi-hole's *Network* tab (its ARP-derived device table) sees only the container's own namespace,
  so it shows no LAN MAC addresses. **That table is not a device inventory here** — device identity
  is [NetAlertX](../../netalertx/README.md)'s job, which is exactly why both services exist
  ([ADR-0013](../../../docs/decisions/0013-host-networking-for-lan-scanning.md) rejected Pi-hole
  for discovery).

## Configuration reference

Settings changed from upstream defaults, and why:

| Setting | Value | Why |
| ------- | ----- | --- |
| `FTLCONF_dns_listeningMode` | `ALL` | Required on a bridge network: FTL otherwise ignores queries arriving from outside its own subnet |
| `FTLCONF_webserver_port` | `80` | Plain HTTP inside the container only. TLS terminates at Caddy ([ADR-0009](../../../docs/decisions/0009-caddy-reverse-proxy.md)); it also avoids FTL's IPv6 bind quirks on the default port string |
| `FTLCONF_dns_upstreams` | `1.1.1.1;1.0.0.1` | See above |
| DHCP server | **off** | The router keeps DHCP. Enabling it would require `NET_ADMIN` and host networking — the exception ADR-0014 exists to avoid |

## Troubleshooting

Incidents and their resolutions, dated, most recent first.

| Date | Symptom | Cause | Resolution |
| ---- | ------- | ----- | ---------- |
|      |         |       |            |
