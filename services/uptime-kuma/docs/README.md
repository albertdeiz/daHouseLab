# uptime-kuma — Documentation

Deep documentation for the monitoring service. Front page: [`../README.md`](../README.md).

## Monitor inventory

| Monitor         | Type    | Target                       | Interval | Cert expiry alert | Notifications |
| --------------- | ------- | ---------------------------- | -------- | ----------------- | ------------- |
| `homepage`      | HTTP(s) | `https://home.dahub.casa`    | 60 s     | ✅                | Telegram      |
| `caddy-ingress` | HTTP(s) | `https://status.dahub.casa`  | 60 s     | ✅                | Telegram      |

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

## Known limitations

- Uptime Kuma runs on the same host it monitors: a total host failure produces **no alert**.
  Mitigation on the roadmap: external dead-man's-switch check (e.g. a free external monitor
  watching `status.dahub.casa`, or a heartbeat push to a third-party service).
