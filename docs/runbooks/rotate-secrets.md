# Runbook: Rotate secrets

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-07-14                                   |
| Estimated time  | 15–30 minutes per secret class               |
| Risk level      | Medium                                       |
| Automation      | Manual — target home: `scripts/maintenance/` |

## Purpose

Replace platform credentials in a controlled way — new value generated, stored, applied,
dependents updated, old value dead, date recorded. Runs quarterly as a review (per the
[operating rhythm](../operations/README.md)) and immediately on a trigger. On success no
service runs on the old credential and the rotation is logged.

## Scope

Covers: secrets the platform owns — the classes inventoried below, all flowing through the
global `.env` at `/opt/dahouselab/.env` or a service's admin surface. Does not cover: personal
account passwords *stored inside* Vaultwarden (user data, not platform credentials), TLS
certificates (Caddy rotates its own), or SSH keys ([configure-ssh](configure-ssh.md)).

### Secret inventory

| Class                     | Examples                                              | Lives in                       | Dependents to update                     |
| ------------------------- | ----------------------------------------------------- | ------------------------------ | ---------------------------------------- |
| Service admin passwords   | Nextcloud admin, Paperless superuser, Immich admin, Uptime Kuma admin | App's own DB (set via UI/CLI) | Human + password manager entry           |
| DB passwords              | `NEXTCLOUD_DB_PASSWORD`, `IMMICH_DB_PASSWORD`, `PAPERLESS_DB_PASSWORD` | `.env`             | The app container(s) in the same stack   |
| API tokens                | Homepage widget tokens, Paperless API tokens          | `.env` / app settings          | Homepage config, any script using them   |
| Tailscale keys            | Auth keys (node enrollment), API access tokens        | Tailscale admin console        | Nothing running (auth keys are enrollment-time) |
| Vaultwarden admin token   | `ADMIN_TOKEN` (argon2 hash recommended)               | `.env`                         | Only the operator's `/admin` access      |
| DNS provider token        | `CLOUDFLARE_API_TOKEN` (DNS-01 issuance, [ADR-0011](../decisions/0011-dns-01-tls-certificates.md)) | `services/caddy/.env` | Caddy (restart after rotation; certs unaffected until next renewal) |

## Triggers

- **Schedule:** quarterly review — rotate anything older than 12 months, verify the rest
- **Suspected exposure:** a secret appeared in shell history, logs, a paste, or a screen share
- **Personnel/device change:** a device that held secrets is lost, sold, or stolen — rotate
  everything that device could read (typically: Vaultwarden master exposure ⇒ everything)

## Prerequisites

- [ ] Access to `/opt/dahouselab/.env` and the password manager (Vaultwarden) to record values
- [ ] `.env` permissions correct before starting: `stat -c '%a %U' /opt/dahouselab/.env` →
      `600` and the operator's user — fix with `chmod 600` if not
- [ ] Platform healthy ([run-health-checks](run-health-checks.md)) — rotation on a broken
      platform confuses two failure sources
- [ ] Recent backup exists ([execute-backup](execute-backup.md)) — a botched DB-password
      rotation is recoverable, but only with one

## Risks

Worst case: rotating a DB password in `.env` without updating the database's actual user
password (or vice versa) — the stack restart loops with auth failures until the two agree; on
Postgres, note the containerized DB only reads `POSTGRES_PASSWORD` at *first initialization*,
so step 3 changes it in SQL, not by restart. Second risk: the new secret leaks during rotation
— into shell history, `ps` output, or a pasted terminal. Rules: **never echo secrets into the
command line or shell history** — use `read -s` into a variable or edit files directly with an
editor; never commit `.env` (it is git-ignored; verify).

## Safety checks

- [ ] `.env` is not tracked by Git:

  ```bash
  git -C /opt/dahouselab check-ignore -q .env && echo "ignored (good)" || echo "DANGER: tracked"
  ```

  Expected: `ignored (good)`.

- [ ] Shell history will not capture secrets in this session:

  ```bash
  set +o history          # re-enable later with: set -o history
  ```

  Expected: subsequent commands in this shell are not written to history.

- [ ] Know every dependent of the secret you are rotating (inventory table above) before
      changing it — a rotation is only complete when all dependents have the new value.

## Procedure

The generic cycle is steps 1–2 + 6–7; steps 3–5 are the per-class specifics.

1. **Generate the new value** — into a shell variable, never onto the command line as an
   argument someone could see in history or `ps`:

   ```bash
   NEW_SECRET=$(openssl rand -base64 32)
   ```

   Expected: `${#NEW_SECRET}` is 44; the value is never printed. For values that must be
   URL/env-safe, use `openssl rand -hex 32` instead.

2. **Store it first** — create/update the entry in Vaultwarden *before* applying it anywhere,
   so a mid-rotation interruption never leaves a secret that exists nowhere.

   Expected: the new value is retrievable from a second device.

3. **DB passwords** (nextcloud / immich / paperless-ngx): change it in the database, in
   `.env`, then restart the stack — in that order, quickly:

   ```bash
   docker exec -i <svc>-postgres psql -U "${POSTGRES_USER:-postgres}" <<SQL
   ALTER USER <db_user> WITH PASSWORD '${NEW_SECRET}';
   SQL
   $EDITOR /opt/dahouselab/.env       # paste the new value into <SVC>_DB_PASSWORD
   docker compose --project-directory /opt/dahouselab/services/<svc> up -d --force-recreate
   ```

   Expected: stack returns to `(healthy)`; app logs show successful DB connections. (The
   heredoc keeps the secret out of `ps`; editing `.env` in an editor keeps it out of history.)

4. **Service admin passwords:** rotate through each app's own mechanism — Nextcloud:
   `docker exec -u www-data nextcloud php occ user:resetpassword <admin>` (prompts, nothing in
   history); Paperless: `docker exec -it paperless-ngx python3 manage.py changepassword <user>`;
   Immich and Uptime Kuma: via their web UI account settings. Update the Vaultwarden entry.

   Expected: old password rejected, new one works.

5. **Class specifics:**
   - **API tokens:** revoke-and-reissue in the issuing app's UI, paste the new token into
     `.env`/Homepage config with an editor, restart the consumer (usually only
     `docker compose --project-directory /opt/dahouselab/services/homepage up -d --force-recreate`).
   - **Tailscale keys:** in the admin console, revoke old auth keys and API tokens, issue new
     ones (short expiry, tagged). Running nodes are unaffected — node keys rotate themselves.
     On device loss, additionally delete that device's *machine* from the tailnet.
   - **Vaultwarden admin token:** generate the argon2 hash inside the container so the plain
     token never touches the host:
     `docker exec -it vaultwarden /vaultwarden hash` (prompts for the new token), put the
     hash in `.env` as `ADMIN_TOKEN`, then
     `docker compose --project-directory /opt/dahouselab/services/vaultwarden up -d --force-recreate`.

   Expected: each dependent works with the new value; each old value verified dead.

6. **Verify the old secret is dead** — attempt one authentication with the old value (old DB
   password via `psql`, old admin password via login form, old token via one API call).

   Expected: authentication *fails*. A rotation where the old value still works is not a
   rotation.

7. **Record the rotation** — date, secret class, trigger, operator — in the operations log
   ([`docs/operations/`](../operations/README.md)); never the values themselves. Re-enable
   history: `set -o history`. Confirm hygiene:

   ```bash
   stat -c '%a' /opt/dahouselab/.env
   ```

   Expected: `600`; log entry committed.

## Verification

- [ ] Affected stacks `(healthy)` and their URLs return 200 ([run-health-checks](run-health-checks.md) checks 1 & 5)
- [ ] New values authenticate; old values rejected (step 6 done for every rotated secret)
- [ ] Vaultwarden entries updated and readable from a second device
- [ ] `.env` mode 600, untracked; `history | grep -i pass` shows nothing sensitive
- [ ] Rotation logged with date and class

## Rollback

Until step 6, the old value still works: revert `.env` to the previous value (kept in
Vaultwarden's entry history) and `up -d --force-recreate` — for DB passwords, also `ALTER USER
... PASSWORD` back. After a botched rotation with both values dead (worst case), restore the
service per [restore-from-backup](restore-from-backup.md). Exposure-triggered rotations must
never roll back to the exposed value — fix forward.

## Troubleshooting

| Symptom                                       | Likely cause                                | Action                                                    |
| ---------------------------------------------- | ------------------------------------------- | ---------------------------------------------------------- |
| App loops on DB auth errors after rotation     | `.env` and `ALTER USER` disagree            | Re-run step 3 both halves; `--force-recreate`              |
| Restart didn't pick up the new value           | `up -d` without recreate reused container   | Use `--force-recreate` (env is injected at creation)       |
| `POSTGRES_PASSWORD` change has no effect       | Only read at first init                     | Expected — the SQL `ALTER USER` is authoritative           |
| Vaultwarden `/admin` rejects the new token     | Plain token in `.env` where hash expected   | Re-generate via `/vaultwarden hash`; paste the hash        |
| Homepage widgets blank after token rotation    | Old token cached in config                  | Update Homepage config, recreate the container             |
| Secret visible in `history`                    | `set +o history` skipped                    | Rotate that secret **again**; then `history -d`/truncate   |

## Automation opportunities

`scripts/maintenance/rotate-secret.sh <class> <service>`: generate → prompt to store →
apply (class-specific function) → verify-old-dead → append log line, with `read -s` for any
human-supplied value. An age report (`.env` var → last-rotated date from the operations log)
belongs in `scripts/healthcheck/` so the quarterly review starts from data, not memory.

## Future improvements

- Per-variable rotation dates tracked in a machine-readable file next to the ops log
- Evaluate Docker secrets / sops-encrypted env as an upgrade from plain `.env` (needs an ADR)
- Break-glass documentation: which secrets are needed to recover which, cross-checked against
  [disaster-recovery](disaster-recovery.md)'s `.env` gap
