# System Overview

## High-Level Architecture

```text
                Internet
                     │
               Tailscale VPN
                     │
               Home Router
                     │
             Gigabit Ethernet
                     │
           Raspberry Pi 4
                     │
      ┌──────────────┴──────────────┐
      │                             │
 Docker Infrastructure         Storage
      │                             │
 ┌────┴────┐                   SSD
 │ Services│                     │
 └────┬────┘               Shared Directories
      │
 Reverse Proxy
      │
 Applications
```

## Logical Layers

1. Hardware
2. Operating System
3. Container Platform
4. Infrastructure Services
5. User Applications
6. Monitoring
7. Backup

Each layer should remain as independent as possible.

Dependencies should always point downward.

Higher layers should never directly depend on implementation details of lower layers.
