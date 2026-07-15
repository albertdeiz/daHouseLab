# Runbook: Configure static IP

| Field           | Value           |
| --------------- | --------------- |
| Last reviewed   | 2026-07-14      |
| Estimated time  | 20 minutes      |
| Risk level      | Medium          |
| Automation      | Manual          |

## Purpose

Give the host a fixed LAN address so that `HOST_IP` in `.env`, Caddy, DNS entries and every
client can rely on it never changing. When this runbook completes, the Pi answers on the same
IP across reboots and router restarts, and the address is documented in
[`docs/network/`](../network/README.md).

## Scope

Covers the two ways to pin the address — a DHCP reservation on the router (**recommended**) or
a static configuration on the host via NetworkManager (`nmcli`, the Bookworm default; `dhcpcd`
from older Raspberry Pi OS releases is gone). Does not cover VLANs, IPv6, Wi-Fi setup, or
Tailscale addressing ([deploy-tailscale](deploy-tailscale.md)).

## Prerequisites

- [ ] [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md) completed — verify: `ssh <deploy-user>@dahouselab.local hostname`
- [ ] The target IP chosen, inside the LAN subnet but **outside** the router's DHCP pool (or reserved in it) — e.g. `192.168.1.50`
- [ ] Router admin access (for option A) — verify: you can log in to the router's web UI
- [ ] The Pi's MAC address noted — verify on the Pi: `ip -br link show eth0`

## Risks

- Mistyping the address, gateway or subnet on the host severs SSH connectivity the moment the
  connection re-activates — worst case: the Pi is unreachable over the network until fixed from
  the physical console.
- An address inside the DHCP pool but not reserved can later be handed to another device,
  causing an IP conflict that intermittently breaks both machines.
- Blast radius: network reachability of this host only; no data loss possible.

## Safety checks

- [ ] Current addressing recorded (rollback reference): `nmcli -g ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns connection show "$(nmcli -g NAME connection show --active | head -1)"` — expected: current method (`auto`) and values printed; save them
- [ ] The target IP is currently free: `ping -c 3 192.168.1.50` from the Mac — expected: 100% packet loss (nobody answers)
- [ ] You know where keyboard/HDMI access to the Pi is, in case connectivity is lost
- [ ] mDNS works as a fallback name: `ping -c 3 dahouselab.local` — expected: replies (lets you find the Pi even if the IP change misfires)

## Procedure

### Option A — DHCP reservation on the router (recommended)

Preferred because the host stays a standard DHCP client (zero host-side config to migrate,
nothing to break) and the router remains the single source of truth for the LAN.

1. **Create the reservation**

   In the router's admin UI, find *DHCP* → *Address reservation* (naming varies) and bind the
   Pi's MAC address (from Prerequisites) to the chosen IP.

   Expected: the reservation is listed as active in the router UI.

2. **Renew the lease on the Pi**

   ```bash
   sudo nmcli connection up "$(nmcli -g NAME connection show --active | head -1)"
   ```

   Expected: the command returns successfully; the SSH session may drop if the IP changed —
   reconnect to the new IP.

3. **Confirm the address**

   ```bash
   ip -br addr show eth0
   ```

   Expected: the reserved IP with the correct prefix, e.g. `192.168.1.50/24`.

### Option B — static configuration on the host (nmcli)

Use only when the router cannot do reservations. All four `nmcli ... modify` settings are
staged first; nothing applies until step 6.

4. **Identify the wired connection profile**

   ```bash
   nmcli connection show
   ```

   Expected: one active ethernet profile — on Imager-flashed Bookworm usually named
   `preconfigured` or `Wired connection 1`. Use its exact name below (quoted).

5. **Stage the static configuration**

   ```bash
   sudo nmcli connection modify "Wired connection 1" \
     ipv4.method manual \
     ipv4.addresses 192.168.1.50/24 \
     ipv4.gateway 192.168.1.1 \
     ipv4.dns "192.168.1.1 1.1.1.1"
   ```

   Expected: no output. Nothing has changed on the wire yet.

   > **Warning:** the next step re-activates the connection and **will drop your SSH session**
   > if the address changes. Have the console fallback ready.

6. **Apply by re-activating the connection**

   ```bash
   sudo nmcli connection up "Wired connection 1"
   ```

   Expected: session freezes/drops; reconnect from the Mac with `ssh <deploy-user>@192.168.1.50`.

### Both options

7. **Update `.env` and document the address**

   On the Pi, set `HOST_IP` in `/opt/dahouselab/.env` to the new address. Then, in the repo,
   record the assignment (IP, MAC, method chosen, router pool range) in
   [`docs/network/`](../network/README.md) and commit.

   Expected: `grep HOST_IP /opt/dahouselab/.env` shows the new IP; docs updated.

## Verification

- [ ] `ssh <deploy-user>@192.168.1.50 hostname` returns `dahouselab`
- [ ] `ip -br addr show eth0` on the Pi shows exactly the chosen IP
- [ ] Default route is sane: `ip route show default` shows `via 192.168.1.1 dev eth0`
- [ ] DNS resolves: `getent hosts deb.debian.org` returns addresses
- [ ] `sudo reboot`, then all of the above still hold
- [ ] `docs/network/` documents the address; `.env` `HOST_IP` matches reality

## Rollback

Option A: delete the reservation in the router UI and renew the lease (step 2) — fully
reversible at any time. Option B: revert the profile to DHCP from any session (or the physical
console if locked out):

```bash
sudo nmcli connection modify "Wired connection 1" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns ""
sudo nmcli connection up "Wired connection 1"
```

Then reconnect via `dahouselab.local`. There is no point past which rollback is impossible.

## Troubleshooting

| Symptom                                    | Likely cause                              | Action                                                          |
| ------------------------------------------ | ----------------------------------------- | --------------------------------------------------------------- |
| SSH unreachable after step 6               | Wrong address/gateway/prefix staged       | Physical console → run the Rollback commands                     |
| Pi reachable by IP but no internet         | Wrong `ipv4.gateway` or empty DNS         | Fix with `nmcli connection modify`, re-run `connection up`       |
| Intermittent connectivity, ARP flapping    | IP conflict — address inside DHCP pool    | Move to an IP outside the pool, or make it a router reservation  |
| `nmcli` profile name not found             | Name has spaces / differs                 | Copy the exact name from `nmcli connection show`, keep quotes    |
| Reservation ignored by router              | Lease for old IP still active             | Reboot the Pi or force-renew; some routers need a DHCP restart   |

## Automation opportunities

Option B is scriptable as `scripts/set-static-ip.sh <ip> <gw> <dns>` with a built-in dead-man
switch: schedule a revert-to-auto via `systemd-run --on-active=3m`, apply, and cancel the timer
only after a fresh SSH login succeeds. Option A is router-side and stays manual — which is an
argument *for* option A, not against automating B.

## Future improvements

- Add `HOST_IP` consistency (does `.env` match `ip addr`?) to [run-health-checks](run-health-checks.md).
- Consider local DNS (router or Pi-hole class) so services use names, shrinking the blast
  radius of any future renumbering.
