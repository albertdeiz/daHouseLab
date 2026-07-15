# Bootstrap Scripts

Host preparation: everything between "fresh OS" and "ready to deploy services".

Implements steps from [bootstrap-raspberry-pi](../../docs/runbooks/bootstrap-raspberry-pi.md)
and [install-docker](../../docs/runbooks/install-docker.md):

- Create the storage tree (`${CONFIG_ROOT}`, `${DATA_ROOT}`) with correct ownership
- Create platform Docker networks (`proxy`)
- Apply host hardening baseline

Scripts here must be idempotent — safe to re-run on an already-bootstrapped host.
