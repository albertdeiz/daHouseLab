# Runbook: Deploy Tailscale

| Field           | Value            |
| --------------- | ---------------- |
| Last reviewed   | 2026-07-14       |
| Estimated time  | 30 minutes       |
| Risk level      | Medium           |
| Automation      | Manual           |

## Purpose

Join the host to the tailnet so that every subsequent runbook can be executed remotely and
securely. When this runbook completes, the Raspberry Pi is reachable over Tailscale (including
SSH over the tailnet), MagicDNS resolves its name, and no service port needs to be exposed to
the LAN or the internet. Remote access via Tailscale only is a platform rule
([ADR-0010](../decisions/0010-tailscale-remote-access.md)).

This is deliberately the **first** service deployment: everything after it can be done from
anywhere.

## Scope

Covers: installing Tailscale **on the host** from the official apt repository, joining the
tailnet, enabling Tailscale SSH, enabling MagicDNS, and verifying connectivity.

Does not cover: exit nodes, subnet routers, ACL/tailnet policy design, or serving HTTPS via
`tailscale serve` (ingress is Caddy's job — [deploy-caddy](deploy-caddy.md)).

**Deliberate exception to Docker First:** Tailscale is installed at host level, not as a
container. It needs kernel WireGuard and control over host networking and DNS
(`/etc/resolv.conf`), and remote access must survive a Docker daemon outage — losing the VPN
because Docker is down would strand every other recovery procedure. This deviation from
[ADR-0003 (Docker First)](../decisions/0003-docker-first.md) is documented in
[ADR-0010](../decisions/0010-tailscale-remote-access.md).

## Prerequisites

- [ ] [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md) and [configure-ssh](configure-ssh.md) completed
- [ ] You have local or LAN SSH access to the host (you are **not** yet depending on the tailnet)
- [ ] A Tailscale account exists and you can log in to <https://login.tailscale.com> from a browser on another device
- [ ] System clock is correct (TLS to the control plane fails otherwise):

  ```bash
  timedatectl | grep "System clock synchronized"
  ```

  Expected: `System clock synchronized: yes`

## Risks

- Worst case: a botched network/DNS change cuts off your current SSH session. Blast radius is
  remote access only — running containers are unaffected. Mitigation: perform this runbook from
  the LAN (or console), never over the tailnet itself.
- `tailscale up --ssh` adds a second SSH authentication path (tailnet identity). If your tailnet
  ACLs are permissive, more devices can SSH in than before. Review ACLs after enabling.
- MagicDNS rewrites the host resolver; a misconfigured tailnet DNS setting can break local name
  resolution.

## Safety checks

- [ ] Confirm you are connected via LAN, not a VPN that this procedure could tear down:

  ```bash
  echo $SSH_CONNECTION
  ```

  Expected: client IP is on your LAN subnet (e.g. `192.168.x.x`).

- [ ] apt is healthy and there is disk space:

  ```bash
  sudo apt-get update && df -h /
  ```

  Expected: update succeeds; `/` has > 1 GB free.

## Procedure

1. **Add the official Tailscale apt repository**

   Raspberry Pi OS Lite 64-bit is Debian bookworm based, so the Debian repo is correct:

   ```bash
   curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
     | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
   curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
     | sudo tee /etc/apt/sources.list.d/tailscale.list > /dev/null
   ```

   Expected: both files created, no output on stderr.

2. **Install Tailscale**

   ```bash
   sudo apt-get update
   sudo apt-get install -y tailscale
   tailscale version
   ```

   Expected: install succeeds; version prints (1.86.x pinned by the repo at time of writing).

3. **Enable and start the daemon**

   ```bash
   sudo systemctl enable --now tailscaled
   systemctl is-active tailscaled
   ```

   Expected: `active`.

4. **Join the tailnet with Tailscale SSH enabled**

   `--ssh` makes the host accept SSH over the tailnet, authenticated by tailnet identity and
   governed by tailnet ACLs. This is the recommended mode here: it gives an SSH path that works
   even if `sshd` keys are lost, and access is revocable centrally from the admin console. If
   you prefer to keep OpenSSH as the only SSH server, omit `--ssh` — plain `tailscale up` still
   gives you network reachability to port 22.

   ```bash
   sudo tailscale up --ssh --hostname dahouselab
   ```

   Expected: the command prints an authentication URL. Open it in a browser on another device,
   log in, and approve the machine. The command then returns `Success.`

5. **Enable MagicDNS**

   In the admin console (<https://login.tailscale.com/admin/dns>): ensure a global nameserver is
   set and **MagicDNS** is enabled. Then confirm the host picked it up:

   ```bash
   tailscale status
   tailscale dns status | head -n 5
   ```

   Expected: `tailscale status` lists this machine as `dahouselab` plus your other devices;
   DNS status shows MagicDNS enabled with the tailnet domain (e.g. `tailxxxx.ts.net`).

6. **Disable key expiry for this machine (recommended for servers)**

   In the admin console, Machines → `dahouselab` → **Disable key expiry**. Otherwise the node
   silently drops off the tailnet when its key expires.

   Expected: machine shows "Expiry disabled" in the console.

7. **Verify SSH over the tailnet from another device**

   From a laptop/phone on the tailnet (not on the LAN, if you can — e.g. mobile hotspot):

   ```bash
   ssh <user>@dahouselab
   ```

   Expected: shell prompt on the Pi. With `--ssh`, authentication is via tailnet identity (a
   browser check-URL may appear on first use, depending on ACLs).

8. **Update the services inventory**

   Record Tailscale (host-level, version, join date) in the services inventory in
   [`services/README.md`](../../services/README.md) and the network documentation in
   [`docs/network/`](../network/README.md).

   Expected: inventory committed to Git.

## Verification

- [ ] `tailscale status` shows the node online with a `100.x.y.z` address
- [ ] `tailscale ip -4` prints the tailnet IPv4 address
- [ ] From another tailnet device: `ping dahouselab` resolves via MagicDNS and replies
- [ ] SSH over the tailnet works (step 7)
- [ ] Existing LAN SSH still works (`ssh <user>@<HOST_IP>`) — Tailscale must add a path, not replace one
- [ ] `docker ps` unaffected — host services untouched

## Rollback

Rollback is possible at any point; no application data is involved.

```bash
sudo tailscale down                      # leave the tailnet (reversible with `tailscale up`)
sudo apt-get remove -y tailscale         # full removal, if needed
sudo rm /etc/apt/sources.list.d/tailscale.list
```

Also delete the machine from the admin console so its node key cannot be reused. LAN SSH access
is unaffected throughout.

## Troubleshooting

| Symptom                                   | Likely cause                              | Action                                                        |
| ----------------------------------------- | ----------------------------------------- | ------------------------------------------------------------- |
| `tailscale up` hangs before printing URL  | Clock skew or no route to control plane   | Fix NTP (`timedatectl`); check outbound 443                   |
| Node online but name does not resolve     | MagicDNS disabled or client DNS override  | Enable MagicDNS in admin console; `tailscale dns status`      |
| SSH over tailnet refused                  | ACLs missing an `ssh` rule for `--ssh`    | Add/adjust the SSH section of the tailnet policy file         |
| Node vanished from tailnet after months   | Key expiry was left enabled               | Re-auth locally; disable key expiry (step 6)                  |
| Local DNS broken after joining            | Tailnet global nameserver misconfigured   | Fix DNS settings in admin console or `tailscale up --accept-dns=false` |

## Automation opportunities

- Steps 1–4 are scriptable today with a pre-generated auth key
  (`tailscale up --ssh --auth-key=...`), suitable for `scripts/bootstrap/`. Blocked only by
  deciding where the auth key is stored securely (roadmap: SOPS + age).
- Steps 5–6 are API-automatable via the Tailscale admin API.

## Future improvements

- Manage the tailnet ACL policy file as code in this repository.
- Pin the Tailscale package version explicitly (apt hold) and fold updates into
  [update-containers](update-containers.md)-style controlled maintenance.
- Document a break-glass procedure for regaining access if both LAN and tailnet paths fail.
