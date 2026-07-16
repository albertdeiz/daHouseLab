# caddy — Documentation

Deep documentation for the Caddy service. The front page is [`../README.md`](../README.md);
routing is the version-controlled
[Caddyfile](../../../infrastructure/configs/Caddyfile).

Incidents and configuration references get documented as they happen
([documentation conventions](../../../docs/standards/documentation-conventions.md)).

## Known quirks

- **2026-07-16 — `Caddyfile input is not formatted` warning on every load/reload.** False
  positive: the file is byte-identical to `caddy fmt` output (verified with
  `docker exec -i caddy caddy fmt - < Caddyfile | diff Caddyfile -`). The adapter's format check
  is confused by tab characters inside the commented example site block. Harmless (`warn` level,
  config valid); safe to ignore.
