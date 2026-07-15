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

## Rules

- When a service is added, removed or renamed, update the inventory here in the same commit.
- A service without documentation does not get deployed. The structure every service must follow
  is defined in [`../standards/service-structure.md`](../standards/service-structure.md) and
  scaffolded by [`/templates/service`](../../templates/service/).
