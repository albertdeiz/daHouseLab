# Maintenance Scripts

Recurring upkeep: container updates, image/log cleanup, disk housekeeping.

Implements steps from [update-containers](../../docs/runbooks/update-containers.md) and the
operating rhythm in [`docs/operations/`](../../docs/operations/README.md).

Rules:

- Update scripts respect pinned versions — they surface available updates; applying them is a
  deliberate, per-service action (no auto-upgrades).
- Cleanup scripts (`docker system prune`-class) always run with explicit filters and report what
  they reclaimed.
