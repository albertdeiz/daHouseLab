# Runbook: Configure SSH

| Field           | Value           |
| --------------- | --------------- |
| Last reviewed   | 2026-07-14      |
| Estimated time  | 20 minutes      |
| Risk level      | Medium          |
| Automation      | Manual          |

## Purpose

Harden the SSH daemon on the Pi so that only public-key authentication is accepted and root
login is impossible. When this runbook completes, `sshd` rejects passwords entirely, and the
configuration lives in a clean drop-in file that survives OS package upgrades.

## Scope

Covers `sshd` daemon hardening only: key-only auth, no root login, validated drop-in config.
Does **not** cover fail2ban or port changes — the host has no public exposure (remote access is
Tailscale-only, see [architecture overview](../architecture/overview.md)), so those add
complexity without threat-model benefit. Does not cover key generation or distribution
(done in [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md)).

## Prerequisites

- [ ] [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md) completed — verify: `ssh <deploy-user>@dahouselab.local hostname` returns `dahouselab`
- [ ] Your public key is installed on the Pi — verify: `ssh <deploy-user>@dahouselab.local cat ~/.ssh/authorized_keys` shows your key
- [ ] Physical access to the Pi (keyboard + HDMI) is possible if everything goes wrong — know where the hardware is

## Risks

- The classic failure: disabling password auth before key auth is proven, then closing the last
  session — worst case: complete SSH lockout, requiring physical console access or reflashing.
- A syntactically broken `sshd_config` drop-in that is restarted without validation leaves
  `sshd` down; existing sessions survive, new ones fail.
- Blast radius is this host's remote manageability only; no service data is at risk.

## Safety checks

- [ ] Key-only auth works **before** any change: `ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no <deploy-user>@dahouselab.local echo OK` — expected: `OK` with no password prompt. **Do not proceed if this fails.**
- [ ] You have a second, already-open SSH session to the Pi that you will keep open until Verification passes — expected: two terminal windows, both live
- [ ] Disk is not full (a full disk can corrupt config writes): `df -h /` — expected: usage well below 100%

## Procedure

1. **Open the safety session**

   In a separate terminal, open a session and leave it untouched for the whole procedure:

   ```bash
   ssh <deploy-user>@dahouselab.local
   ```

   Expected: a live shell that you do not close until the end.

2. **Check current effective settings**

   In your working session on the Pi:

   ```bash
   sudo sshd -T | grep -E '^(passwordauthentication|permitrootlogin|pubkeyauthentication)'
   ```

   Expected output:

   ```text
   passwordauthentication yes   # or no, if Imager already disabled it
   permitrootlogin without-password
   pubkeyauthentication yes
   ```

   Note the current values — they are your rollback reference.

3. **Write the hardening drop-in**

   Bookworm's `/etc/ssh/sshd_config` includes `/etc/ssh/sshd_config.d/*.conf`; drop-ins are
   read first and the first-seen value wins, so this overrides the defaults:

   ```bash
   sudo tee /etc/ssh/sshd_config.d/10-dahouselab-hardening.conf > /dev/null <<'EOF'
   # daHouseLab SSH hardening — docs/runbooks/configure-ssh.md
   PasswordAuthentication no
   PermitRootLogin no
   PubkeyAuthentication yes
   KbdInteractiveAuthentication no
   EOF
   ```

   Expected: file exists with the four directives.

4. **Validate the configuration before touching the daemon**

   ```bash
   sudo sshd -t
   ```

   Expected: no output, exit code 0. Any output means a syntax error — fix the drop-in before
   proceeding. **Never restart sshd on a failed `sshd -t`.**

   > **Warning:** the next step applies the lockout-capable change. Your safety session from
   > step 1 must still be open.

5. **Reload the SSH daemon**

   ```bash
   sudo systemctl reload ssh
   ```

   Expected: `systemctl status ssh` shows `active (running)`; your existing sessions stay alive.

6. **Prove the new policy from the Mac (new session)**

   Without closing anything on the Pi:

   ```bash
   ssh <deploy-user>@dahouselab.local sudo sshd -T | grep -E '^(passwordauthentication|permitrootlogin)'
   ```

   Expected output:

   ```text
   passwordauthentication no
   permitrootlogin no
   ```

7. **Prove passwords are rejected**

   ```bash
   ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password <deploy-user>@dahouselab.local
   ```

   Expected: immediate `Permission denied (publickey)` — no password prompt appears.

## Verification

- [ ] A brand-new `ssh <deploy-user>@dahouselab.local` session opens with key auth only
- [ ] `ssh -o PubkeyAuthentication=no ... ` fails with `Permission denied (publickey)`
- [ ] `sudo sshd -T | grep permitrootlogin` returns `permitrootlogin no`
- [ ] `systemctl is-active ssh` returns `active`
- [ ] Only after all of the above: close the safety session from step 1

## Rollback

Possible at any point, from any surviving session (this is why the safety session stays open):

```bash
sudo rm /etc/ssh/sshd_config.d/10-dahouselab-hardening.conf
sudo sshd -t && sudo systemctl reload ssh
```

This restores the pre-procedure defaults recorded in step 2. If all sessions were lost *and*
key auth is broken: attach keyboard and monitor to the Pi, log in locally, and run the same
two commands. Last resort: mount the boot medium on another machine and delete the drop-in.

## Troubleshooting

| Symptom                                     | Likely cause                                  | Action                                                       |
| ------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------ |
| New sessions refused, old one alive         | Broken directive applied                      | From the old session: run the Rollback commands               |
| `sshd -t` reports "Directive ... twice"     | Conflicting drop-in in `sshd_config.d/`       | `grep -r PasswordAuthentication /etc/ssh/` and deduplicate    |
| Password prompt still appears               | Drop-in not read (wrong extension/path)       | File must end in `.conf` and live in `/etc/ssh/sshd_config.d/` |
| `Permission denied (publickey)` for you too | Wrong key offered by the Mac                  | `ssh -i ~/.ssh/id_ed25519 -v ...` and check `authorized_keys` |
| Locked out completely                       | Keys broken + passwords off                   | Physical console; or edit config from the mounted boot medium |

## Automation opportunities

Steps 3–5 are a natural `scripts/harden-ssh.sh`: write drop-in, `sshd -t`, reload, and verify
via a fresh non-interactive connection — aborting (and self-reverting) if the fresh connection
fails. Nothing blocks this today except writing the self-revert logic carefully; the safety
pattern (never apply without a proven fallback path) must survive into the script.

## Future improvements

- Manage the drop-in from the repo (`infrastructure/configs/ssh/`) so it is version-controlled
  and diffable, deployed by script rather than typed.
- Add an SSH check to [run-health-checks](run-health-checks.md): assert `passwordauthentication no`
  so config drift is caught on schedule.
