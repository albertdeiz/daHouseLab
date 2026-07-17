# caddy — Documentation

Deep documentation for the Caddy service. The front page is [`../README.md`](../README.md);
routing is the version-controlled
[Caddyfile](../../../infrastructure/configs/Caddyfile).

Incidents and configuration references get documented as they happen
([documentation conventions](../../../docs/standards/documentation-conventions.md)).

## Incidents

- **2026-07-17 — new `vault.{$DOMAIN}` route silently not served after `git pull` + reload.**
  Root cause: the Caddyfile was bind-mounted as a *single file*; `git pull` replaces files by
  inode, so the container kept reading the pre-pull version while reloads reported success.
  Fix: mount the `infrastructure/configs/` directory at `/etc/caddy` instead (directory mounts
  follow inode replacement). Detection tip: `docker exec caddy grep <new-route> /etc/caddy/Caddyfile`
  vs the host file.

## Known quirks

- **2026-07-16 — `Caddyfile input is not formatted` warning on every load/reload.** False
  positive: the file is byte-identical to `caddy fmt` output (verified with
  `docker exec -i caddy caddy fmt - < Caddyfile | diff Caddyfile -`). The adapter's format check
  is confused by tab characters inside the commented example site block. Harmless (`warn` level,
  config valid); safe to ignore.
