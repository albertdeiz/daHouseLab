# Runbook: Deploy Vaultwarden

| Field           | Value            |
| --------------- | ---------------- |
| Last reviewed   | 2026-07-14       |
| Estimated time  | 45 minutes       |
| Risk level      | High             |
| Automation      | Manual           |

## Purpose

Deploy [vaultwarden/server](https://github.com/dani-garcia/vaultwarden) (Bitwarden-compatible
password manager) at `https://vault.${DOMAIN}`. When complete: Vaultwarden runs behind Caddy over
HTTPS only, signups are disabled after your own account exists, the admin panel is protected by
an argon2-hashed token, and the SQLite vault lives in `${DATA_ROOT}/vaultwarden`.

**This is the highest-value target on the platform.** It holds every credential you own. Treat
every security step below as mandatory, and treat its backups as the most critical on the host.

## Scope

Covers: the `services/vaultwarden/` stack, admin token generation, signup lockdown, Caddy site
block, first account creation, and monitor. Does not cover: client device enrollment, emergency
access/organizations setup, or SMTP configuration (recommended follow-up, see Future improvements).

## Prerequisites

- [ ] [deploy-with-compose](deploy-with-compose.md) read — this runbook assumes that generic procedure
- [ ] `proxy` network exists: `docker network inspect proxy --format '{{.Name}}'` → `proxy`
- [ ] Caddy deployed and healthy — **HTTPS is strictly required**: Bitwarden clients refuse to
  talk to plain HTTP, and the web vault's crypto requires a secure context. Verify:

  ```bash
  curl -sk -o /dev/null -w '%{http_code}\n' https://home.${DOMAIN}
  ```

  Expected: `200` (ingress + TLS proven working).

- [ ] Uptime Kuma deployed ([deploy-uptime-kuma](deploy-uptime-kuma.md)) so this deploy is watched
- [ ] Root `.env` at `/opt/dahouselab/.env` defines the global set

## Risks

- Worst case: loss or corruption of `${DATA_ROOT}/vaultwarden/db.sqlite3` with no valid backup =
  loss of **all** credentials. Backups of this path are the single most critical backup on the
  platform ([execute-backup](execute-backup.md) must include it; [validate-backup](validate-backup.md)
  must restore-test it).
- A window exists between first start and step 8 where signups are open — anyone who can reach
  the URL can register. On this Tailscale-only platform the window is tailnet-internal, but
  close it in the same sitting.
- A leaked plain admin token grants the admin panel (user management, config). The argon2 hash
  below means the `.env.service` never stores the plain token.

## Safety checks

- [ ] `vault.${DOMAIN}` not already routed: `grep -n "vault\." /opt/dahouselab/infrastructure/configs/Caddyfile` → no output
- [ ] Backup target reachable: `df -h /mnt/backups` → external disk mounted (you will back up immediately after first data)
- [ ] Disk space: `df -h /srv` → ample (vault DB is MBs)

## Procedure

1. **Create the service directory and host directories**

   ```bash
   cp -r /opt/dahouselab/templates/service /opt/dahouselab/services/vaultwarden
   source /opt/dahouselab/.env
   sudo mkdir -p ${DATA_ROOT}/vaultwarden
   sudo chown -R ${PUID}:${PGID} ${DATA_ROOT}/vaultwarden
   sudo chmod 700 ${DATA_ROOT}/vaultwarden
   ```

   Expected: `/srv/dahouselab/data/vaultwarden` exists, `PUID:PGID`, mode `700`. (Vaultwarden
   keeps everything under one `/data` dir — single mount, deviation noted in compose.)

2. **Generate the admin token (argon2 hash — preferred over plaintext)**

   Generate a strong secret, hash it with the built-in `vaultwarden hash`, and keep only the
   hash in `.env.service`. The plain value goes straight into your current password manager.

   ```bash
   openssl rand -base64 48
   # Copy the output into your password manager as "vaultwarden admin token", then:
   docker run --rm -it vaultwarden/server:1.34.3 /vaultwarden hash
   ```

   Expected: `hash` prompts for the password twice and prints
   `ADMIN_TOKEN='$argon2id$v=19$...'`. Keep that line for step 4.

3. **Write `services/vaultwarden/compose.yaml`**

   ```yaml
   name: vaultwarden

   services:
     vaultwarden:
       image: vaultwarden/server:1.34.3 # pinned at time of writing (2026-07)
       container_name: vaultwarden
       restart: unless-stopped
       env_file:
         - .env          # platform globals (via symlink)
         - .env.service  # service-specific — overrides globals on collision
       environment:
         TZ: ${TZ}
       volumes:
         # SQLite DB, attachments, sends, RSA keys — all under /data.
         # Single mount is a documented deviation from the two-mount rule.
         - ${DATA_ROOT}/vaultwarden:/data
       networks:
         - proxy
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD", "curl", "-fsS", "http://localhost:80/alive"]
         interval: 30s
         timeout: 5s
         retries: 3
         start_period: 30s
       labels:
         dahouselab.service: "vaultwarden"
         dahouselab.category: "security"
         dahouselab.description: "Password manager (Bitwarden-compatible)"
         dahouselab.url: "https://vault.${DOMAIN}"
         dahouselab.backup: "true"

   networks:
     proxy:
       external: true
   ```

4. **Create the environment files** ([ADR-0012](../decisions/0012-layered-environment-files.md)) —
   globals via the `.env` symlink, Vaultwarden's own variables in `.env.service`:

   ```bash
   cd /opt/dahouselab/services/vaultwarden
   ln -sf ../../.env .env
   cp .env.service.example .env.service && chmod 600 .env.service
   ```

   Then fill `.env.service` with an editor (never echo secrets into shell history):

   ```bash
   # --- vaultwarden ---
   DOMAIN=https://vault.<your-domain>          # full URL, required for WebAuthn/attachments
   SIGNUPS_ALLOWED=true                        # flipped to false in step 8
   ADMIN_TOKEN='$argon2id$v=19$...'            # hash from step 2 — single quotes matter
   ```

   Expected: `ls -l` shows `.env -> ../../.env` and `.env.service` mode `600`; mirror variable
   names (values redacted/empty) into `services/vaultwarden/.env.service.example`.

5. **Validate and start**

   ```bash
   docker compose config --quiet && echo OK
   docker compose up -d && docker compose ps
   ```

   Expected: `OK`; `vaultwarden` reaches `Up ... (healthy)`.

6. **Add the Caddy site block** to `/opt/dahouselab/infrastructure/configs/Caddyfile`
   (WebSocket notifications ride the same port since Vaultwarden 1.29 — no extra route needed):

   ```text
   vault.{$DOMAIN} {
   	reverse_proxy vaultwarden:80
   }
   ```

   Validate + reload per [deploy-caddy](deploy-caddy.md) step 7. Expected: reload exits 0;
   commit the Caddyfile change.

7. **Create YOUR account** — open `https://vault.${DOMAIN}`, Create account. Use a long,
   memorable master password. **The master password is unrecoverable by design** — losing it
   loses the vault regardless of backups.

   Expected: you can log in and create a test item.

8. **Disable signups immediately**

   > **Warning:** do not leave this step for later — until it is done, anyone who can reach the
   > URL can register an account on your server.

   Edit `.env.service`: `SIGNUPS_ALLOWED=false`, then:

   ```bash
   cd /opt/dahouselab/services/vaultwarden
   docker compose up -d
   ```

   Expected: container recreated; the registration form now refuses new signups.

9. **Verify the admin panel** — open `https://vault.${DOMAIN}/admin`, authenticate with the
   **plain** token from step 2 (from your password manager). Confirm settings, then close.

   Expected: admin panel loads; "Invalid admin token" means the hash was mangled (check quoting).

10. **Back up now, then monitor and inventory**
    - Run [execute-backup](execute-backup.md) so a vault backup exists from day one.
    - Add an Uptime Kuma HTTP(s) monitor for `https://vault.${DOMAIN}/alive` (expects `200`).
    - Update [`services/README.md`](../../services/README.md) inventory and the Homepage dashboard; commit.

    Expected: backup set contains `vaultwarden/`; monitor green.

## Verification

- [ ] `docker compose ps` → `vaultwarden` `healthy`
- [ ] `curl -sk https://vault.${DOMAIN}/alive` → `200`, and the web vault loads over HTTPS
- [ ] Login with your account works from the web vault and a Bitwarden client app
- [ ] Signups closed: registration attempt is refused
- [ ] Data landed correctly: `sudo ls ${DATA_ROOT}/vaultwarden/` shows `db.sqlite3`, `rsa_key*`
- [ ] Uptime Kuma monitor green; rest of platform still healthy (`docker ps`)

## Rollback

```bash
cd /opt/dahouselab/services/vaultwarden
docker compose down
```

Remove the `vault.{$DOMAIN}` site block and reload Caddy. `${DATA_ROOT}/vaultwarden` persists —
**never delete it as part of a rollback**; if it was mutated during troubleshooting, restore from
`${BACKUP_ROOT}` per [restore-from-backup](restore-from-backup.md). Restore `.env.service` from
backup if edited. Rollback possible at every step; only master-password loss (step 7 note) is unrecoverable.

## Troubleshooting

| Symptom                                  | Likely cause                              | Action                                                   |
| ---------------------------------------- | ----------------------------------------- | --------------------------------------------------------- |
| Client apps refuse to connect            | Plain HTTP or bad cert                    | HTTPS only; fix Caddy TLS (deploy-caddy troubleshooting)  |
| "Invalid admin token" at `/admin`        | argon2 hash mangled by shell interpolation| Re-paste hash in single quotes in `.env.service`; `up -d` |
| Registration still possible after step 8 | Container not recreated                   | `docker compose up -d` (not just `restart`); verify env inside: `docker exec vaultwarden env \| grep SIGNUPS` |
| Attachments/icons fail                   | `DOMAIN` env not the full https URL       | Set `DOMAIN=https://vault.<domain>`; recreate             |
| DB "database is locked" errors           | Backup tooling copying SQLite live        | Back up via sqlite `.backup` or stop-copy-start window    |

## Automation opportunities

- Steps 1, 3–5 are the generic deploy flow — `scripts/deploy-service.sh` candidate.
- A nightly `sqlite3 db.sqlite3 ".backup ..."` pre-backup hook belongs in the backup tooling.
- A scripted post-deploy check ("signups disabled? admin reachable? /alive 200?") would encode
  the security checklist; nothing blocks writing it today.

## Future improvements

- Configure SMTP so invitations, verification, and (critically) master-password-hint mail work.
- Restrict `/admin` at the Caddy layer (extra basic-auth or tailnet-IP allowlist).
- Enable and test WebAuthn/passkey login once clients are enrolled.
