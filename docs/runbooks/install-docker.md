# Runbook: Install Docker

| Field           | Value           |
| --------------- | --------------- |
| Last reviewed   | 2026-07-14      |
| Estimated time  | 30 minutes      |
| Risk level      | Low             |
| Automation      | Manual          |

## Purpose

Install Docker Engine and the Compose plugin from Docker's official apt repository, configure
log rotation to protect the SSD, and create the shared `proxy` network. When this runbook
completes, the host can run every service in [`/services`](../../services/) via
[deploy-with-compose](deploy-with-compose.md).

## Scope

Covers engine + Compose plugin installation, docker group membership, daemon log configuration
and the external `proxy` network. Does **not** cover deploying any service, rootless Docker, or
alternative runtimes. Installation is via Docker's apt repository — not `get.docker.com` (an
unpinned curl-pipe-to-shell, unreviewable and unreproducible) and not Debian's `docker.io`
(lags upstream, no Compose v2 plugin): the official repo gives signed, pinned, upgradeable
packages, matching [ADR-0003](../decisions/0003-docker-first.md) /
[ADR-0004](../decisions/0004-docker-compose.md).

## Prerequisites

- [ ] [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md) completed — verify: `git -C /opt/dahouselab status` works and `findmnt /srv/dahouselab` shows the SSD mount
- [ ] Running Raspberry Pi OS Lite 64-bit (arm64) — verify: `dpkg --print-architecture` returns `arm64` (the Debian repo below has no armhf Pi packages; 32-bit OS would need the Raspbian repo instead)
- [ ] Internet access from the Pi — verify: `curl -fsSI https://download.docker.com > /dev/null && echo OK`
- [ ] No conflicting container packages installed — verify: `dpkg -l docker.io docker-compose podman-docker containerd runc 2>/dev/null | grep '^ii' || echo clean` returns `clean`

## Risks

- Adding the deploy user to the `docker` group is effectively granting root: anyone with that
  group can mount `/` into a container. Accepted here because the deploy user is the sole admin
  of a single-user host — but it must be a conscious acceptance, not an accident.
- Unbounded container logs can fill the SSD and take every service down — this is why log
  rotation is part of installation, not an afterthought.
- Worst case of a botched install: no containers run yet, so blast radius is redoing this runbook.

## Safety checks

- [ ] Disk space available for images: `df -h /var/lib/docker /` — expected: several GB free on the filesystem backing `/var/lib/docker`
- [ ] APT is healthy: `sudo apt update` — expected: completes without errors
- [ ] Time is sane (TLS to the repo fails otherwise): `timedatectl` — expected: correct date, `System clock synchronized: yes`

## Procedure

1. **Install the Docker apt repository GPG key**

   ```bash
   sudo apt install -y ca-certificates curl
   sudo install -m 0755 -d /etc/apt/keyrings
   sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
   sudo chmod a+r /etc/apt/keyrings/docker.asc
   ```

   Expected: `/etc/apt/keyrings/docker.asc` exists, world-readable.

2. **Add the repository (arm64, Bookworm)**

   ```bash
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
   https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
   sudo apt update
   ```

   Expected: `apt update` lists `download.docker.com/linux/debian bookworm InRelease` without errors.

3. **Install engine, CLI and plugins**

   ```bash
   sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
   ```

   Expected: packages install; `docker --version` and `docker compose version` print versions.

4. **Enable and start the service**

   ```bash
   sudo systemctl enable --now docker
   ```

   Expected: `systemctl is-active docker` returns `active`; `is-enabled` returns `enabled`.

5. **Configure log rotation before any container runs**

   Cap per-container logs so a chatty service can never fill the SSD:

   ```bash
   sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
   {
     "log-driver": "json-file",
     "log-opts": {
       "max-size": "10m",
       "max-file": "3"
     }
   }
   EOF
   sudo systemctl restart docker
   ```

   Expected: `docker info --format '{{.LoggingDriver}}'` returns `json-file`; daemon restarts cleanly.

6. **Add the deploy user to the docker group**

   > **Warning:** membership in the `docker` group is root-equivalent on this host. Only the
   > deploy user gets it, and only because it is the sole admin account.

   ```bash
   sudo usermod -aG docker "$USER"
   ```

   Log out and back in (or `newgrp docker` for the current shell).

   Expected: `id` in a fresh session lists `docker` among the groups.

7. **Verify the engine end to end**

   ```bash
   docker run --rm hello-world
   ```

   Expected output includes:

   ```text
   Hello from Docker!
   This message shows that your installation appears to be working correctly.
   ```

8. **Create the external `proxy` network**

   The shared network every application joins and through which Caddy reaches them
   ([architecture overview](../architecture/overview.md)):

   ```bash
   docker network create proxy
   ```

   Expected: a network ID is printed; `docker network ls` lists `proxy` with driver `bridge`.

## Verification

- [ ] `docker --version` and `docker compose version` print current stable versions
- [ ] `docker run --rm hello-world` succeeds **without sudo** in a fresh login session
- [ ] `docker info --format '{{.LoggingDriver}}'` returns `json-file`
- [ ] `docker network inspect proxy --format '{{.Driver}}'` returns `bridge`
- [ ] `apt-cache policy docker-ce` shows the install candidate coming from `download.docker.com`
- [ ] `sudo reboot`, then `systemctl is-active docker` returns `active` and `docker network ls` still shows `proxy`

## Rollback

Fully reversible at any step while no services depend on Docker yet:

```bash
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker
sudo rm /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc
sudo gpasswd -d "$USER" docker
```

Note `rm -rf /var/lib/docker` deletes all images and containers — harmless now, destructive
once services are deployed; after that point, rollback of Docker itself is a
[disaster-recovery](disaster-recovery.md) scenario, not this section.

## Troubleshooting

| Symptom                                        | Likely cause                                | Action                                                       |
| ---------------------------------------------- | ------------------------------------------- | ------------------------------------------------------------ |
| `apt update` GPG error on docker.list          | Key file missing/unreadable                 | Re-run step 1; check `ls -l /etc/apt/keyrings/docker.asc`     |
| `permission denied ... docker.sock`            | Group change not picked up                  | Log out/in fully; verify with `id`                            |
| `hello-world` fails to pull                    | DNS/clock issue on the host                 | `getent hosts registry-1.docker.io`; check `timedatectl`      |
| Daemon fails after daemon.json edit            | Invalid JSON                                | `sudo dockerd --validate`; fix syntax; `journalctl -u docker` |
| `network proxy declared as external, but ...`  | Step 8 skipped                              | `docker network create proxy`                                 |
| Repo has no packages for the architecture      | 32-bit OS installed                         | Reflash 64-bit ([bootstrap-raspberry-pi](bootstrap-raspberry-pi.md)) |

## Automation opportunities

The entire runbook is deterministic and idempotency-friendly: `scripts/install-docker.sh`
(repo setup → install → daemon.json → group → network, each step check-before-change).
Nothing blocks it today; it is the best first candidate for graduating a runbook into
[`/scripts`](../../scripts/).

## Future improvements

- Pin an exact `docker-ce` version (`apt-mark hold` + documented upgrade via
  [update-containers](update-containers.md)-style runbook) instead of tracking latest stable.
- Consider `local` log driver (better compression) once nothing depends on parsing json-file logs.
- Evaluate rootless Docker to remove the docker-group-is-root tradeoff; requires re-testing all
  bind-mount ownership assumptions in [storage-and-bind-mounts](../standards/storage-and-bind-mounts.md).
