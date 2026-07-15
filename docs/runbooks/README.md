# Runbooks

Step-by-step procedures for every manual operation on the platform. If a human touches the
infrastructure, the procedure lives here — written to be executed under stress, at 2 AM, by
someone (me) who has forgotten everything.

## Why runbooks

Reproducibility applies to operations, not just deployments. A runbook turns tribal knowledge
into an executable document, makes procedures reviewable like code, and is the staging area for
automation: every runbook lists its automation opportunities, and mature runbooks graduate into
[`/scripts`](../../scripts/).

## Rules

- Written from [`TEMPLATE.md`](TEMPLATE.md); every section present, "N/A" allowed but explicit.
- Filename: `verb-object.md` (`deploy-nextcloud.md`, `rotate-secrets.md`).
- Every step is a checkbox with the exact command and its expected outcome.
- If an execution deviates from the runbook, the runbook is fixed in the same sitting.
- Destructive steps are preceded by an explicit safety check and a stated rollback point.

## Index

### Platform bootstrap

| Runbook                                                   | Purpose                                        |
| --------------------------------------------------------- | ---------------------------------------------- |
| [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md)       | From empty SD/SSD to managed host              |
| [configure-ssh](configure-ssh.md)                         | Key-only SSH, hardened daemon                  |
| [configure-static-ip](configure-static-ip.md)             | Fixed LAN address for the host                 |
| [configure-usb-boot](configure-usb-boot.md)               | Boot the Pi from SSD instead of SD card        |
| [install-docker](install-docker.md)                       | Docker Engine + Compose plugin                 |
| [deploy-with-compose](deploy-with-compose.md)             | The generic service deployment procedure       |

### Service deployment (in dependency order)

| Runbook                                                   | Service                                        |
| --------------------------------------------------------- | ---------------------------------------------- |
| [deploy-tailscale](deploy-tailscale.md)                   | Remote access — first, so everything after can be done remotely |
| [deploy-caddy](deploy-caddy.md)                           | Reverse proxy — required by all web services   |
| [deploy-homepage](deploy-homepage.md)                     | Dashboard                                      |
| [deploy-uptime-kuma](deploy-uptime-kuma.md)               | Monitoring — early, so later deploys are watched |
| [deploy-vaultwarden](deploy-vaultwarden.md)               | Password manager                               |
| [deploy-nextcloud](deploy-nextcloud.md)                   | Files, calendar, contacts                      |
| [deploy-immich](deploy-immich.md)                         | Photos                                         |
| [deploy-paperless](deploy-paperless.md)                   | Documents                                      |

### Backup & recovery

| Runbook                                                   | Purpose                                        |
| --------------------------------------------------------- | ---------------------------------------------- |
| [execute-backup](execute-backup.md)                       | Run a full platform backup                     |
| [validate-backup](validate-backup.md)                     | Prove the latest backup is restorable          |
| [restore-from-backup](restore-from-backup.md)             | Restore service(s) from backup                 |
| [disaster-recovery](disaster-recovery.md)                 | Total loss → running platform                  |

### Maintenance & lifecycle

| Runbook                                                   | Purpose                                        |
| --------------------------------------------------------- | ---------------------------------------------- |
| [run-health-checks](run-health-checks.md)                 | Routine platform verification                  |
| [update-containers](update-containers.md)                 | Controlled image updates                       |
| [rotate-secrets](rotate-secrets.md)                       | Credential rotation                            |
| [replace-ssd](replace-ssd.md)                             | Storage replacement                            |
| [replace-raspberry-pi](replace-raspberry-pi.md)           | Same-platform hardware swap                    |
| [migrate-to-mini-pc](migrate-to-mini-pc.md)               | Cross-platform migration                       |
