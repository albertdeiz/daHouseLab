# Services Documentation

Cross-cutting documentation about the service portfolio as a whole.

Detailed documentation for each service lives **next to the service** in
[`/services/<name>/docs/`](../../services/) — this directory covers what no single service owns:

| Concern            | Example content                                              |
| ------------------ | ------------------------------------------------------------ |
| Service inventory  | What runs, where, on which port, behind which hostname       |
| Dependency map     | Which services depend on which (proxy, databases, SSO)       |
| Deployment order   | The order services must come up after a rebuild              |
| Resource budget    | Memory/CPU expectations per service on constrained hardware  |

## Resource budget

8 GB of RAM, shared, on a Raspberry Pi 4 ([ADR-0005](../decisions/0005-raspberry-pi-platform.md)).
The health floor is **≥ 1.5 GiB available** with everything resident
([run-health-checks](../runbooks/run-health-checks.md)). Only two workloads are capped in their
compose files; the rest are small and uncapped.

| Service        | Cap (hard)      | Notes                                                        |
| -------------- | --------------- | ------------------------------------------------------------ |
| `hermes-agent` | 4 GB / 2 CPU    | Browser automation (Chromium) is the consumer. First lever under pressure is disabling browser tools ([ADR-0015](../decisions/0015-hermes-agent-self-hosted-ai.md)) |
| `immich` (ML)  | 2 GB            | `MACHINE_LEARNING_WORKERS: 1`; pausable during bulk import ([deploy-immich](../runbooks/deploy-immich.md)) |
| everything else| uncapped        | Caddy, Homepage, Uptime Kuma, Vaultwarden, Pi-hole, NetAlertX — tens to low hundreds of MB each |

Rule: a service that can consume unbounded memory (an ML model, a browser, a transcoder) **must**
declare `deploy.resources.limits` and appear in this table. Deploy runbooks for such services carry
a `free -h` pre-flight gate.

## Rules

- When a service is added, removed or renamed, update the inventory here in the same commit.
- A service without documentation does not get deployed. The structure every service must follow
  is defined in [`../standards/service-structure.md`](../standards/service-structure.md) and
  scaffolded by [`/templates/service`](../../templates/service/).
