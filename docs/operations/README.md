# Operations Documentation

Day-2 operations: the recurring work that keeps the platform healthy after deployment.

## Scope

| Concern            | Content                                                          |
| ------------------ | ----------------------------------------------------------------- |
| Update policy      | How and when OS packages and container images are updated         |
| Maintenance windows | When disruptive work happens; what "disruptive" means here       |
| Monitoring         | What Uptime Kuma watches, alert channels, escalation (i.e. me)    |
| Health checks      | Routine verification of the whole platform                        |
| Capacity           | Disk/memory watermarks and what to do when they are crossed       |
| Operations log     | Dated log of significant operational events and incidents         |

## Operating rhythm

| Cadence   | Task                                                        | Runbook / script                                        |
| --------- | ----------------------------------------------------------- | ------------------------------------------------------- |
| Continuous | Uptime monitoring and alerting                             | [deploy-uptime-kuma](../runbooks/deploy-uptime-kuma.md) |
| Weekly    | Review alerts, disk usage, pending updates                   | [run-health-checks](../runbooks/run-health-checks.md)   |
| Monthly   | Container updates                                            | [update-containers](../runbooks/update-containers.md)   |
| Monthly   | Backup validation                                            | [validate-backup](../runbooks/validate-backup.md)       |
| Quarterly | Restore rehearsal, secret review                             | [restore-from-backup](../runbooks/restore-from-backup.md), [rotate-secrets](../runbooks/rotate-secrets.md) |
| Yearly    | Disaster-recovery exercise, hardware/roadmap review          | [disaster-recovery](../runbooks/disaster-recovery.md)   |

## Ground rules

- Recurring manual work is a bug: after the second manual execution, open a task to automate it
  in [`/scripts`](../../scripts/).
- Incidents get a short dated post-mortem here: what broke, why, what changed to prevent it.
- Never update more than one critical service in the same session; verify between updates.
