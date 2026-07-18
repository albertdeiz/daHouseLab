# uptime-kuma — Documentation

Deep documentation for the monitoring service. Front page: [`../README.md`](../README.md).

## Monitor inventory

| Monitor         | Type    | Target                       | Interval | Cert expiry alert | Notifications |
| --------------- | ------- | ---------------------------- | -------- | ----------------- | ------------- |
| `homepage`      | HTTP(s) | `https://home.dahub.casa`    | 60 s     | ✅                | Telegram      |
| `caddy-ingress` | HTTP(s) | `https://status.dahub.casa`  | 60 s     | ✅                | Telegram      |
| `vaultwarden`   | HTTP(s) | `https://vault.dahub.casa/alive` | 60 s | ✅                | Telegram      |
| `nextcloud`     | HTTP(s) | `https://cloud.dahub.casa/status.php` (keyword `"installed":true`) | 60 s | ✅ | Telegram      |
| `netalertx`     | HTTP(s) | `https://net.dahub.casa/` (keyword `NetAlertX`) | 60 s | ✅ | Telegram      |
| `backup-nightly`| Push    | pinged by `dahouselab-backup.service` on success | 25 h | —    | Telegram (dead-man: alert fires when the ping is MISSING) |

Rule: every newly deployed service gets an HTTP(s) monitor against its canonical URL with
certificate-expiry alerting enabled, attached to the Telegram channel — this is the last step of
every deploy runbook.

## Notification channels

| Channel               | Type     | Notes                                                        |
| --------------------- | -------- | ------------------------------------------------------------ |
| `Telegram daHouseLab` | Telegram | Bot via @BotFather; token/chat-id live only in Kuma's DB. Set as "Default enabled". |

> **Gotcha (learned 2026-07-17):** "Default enabled" only auto-attaches the channel to monitors
> created *after* the notification exists. Monitors created earlier must be edited and the
> channel checkbox ticked manually — alerts silently don't fire otherwise.

## Validation log

| Date       | Test                                                            | Result |
| ---------- | --------------------------------------------------------------- | ------ |
| 2026-07-17 | Fire drill: `docker stop homepage` (~110 s outage), then restart | ✅ 🔴 down and 🟢 up alerts received on Telegram; dashboard reflected both transitions |
| 2026-07-17 | Backup dead-man circuit: manual `systemctl start dahouselab-backup.service` | ✅ backup ran, push delivered (after fixing a 502 race — ping now retries while kuma's embedded MariaDB boots), monitor green |

## Known quirks

- **Password reset (v2.x) fails with `ERROR: Try to restart Embedded MariaDB as it is not
  stopped by user`.** Kuma 2.x uses an embedded MariaDB and the reset script needs exclusive DB
  access. Procedure (2026-07-17, verified): stop the container, run the reset in a throwaway
  container on the same data mount, restart:

  ```bash
  docker stop uptime-kuma
  docker run -it --rm -v ${DATA_ROOT}/uptime-kuma:/app/data louislam/uptime-kuma:2.0.1 npm run reset-password
  docker start uptime-kuma
  ```

  Monitors pause during the ~2 minute window. Credentials live in Vaultwarden.

## Known limitations

- Uptime Kuma runs on the same host it monitors: a total host failure produces **no alert**.
  Mitigation on the roadmap: external dead-man's-switch check (e.g. a free external monitor
  watching `status.dahub.casa`, or a heartbeat push to a third-party service).
