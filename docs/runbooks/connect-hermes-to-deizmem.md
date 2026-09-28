# Runbook: Connect Hermes to deizmem

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-09-27                                   |
| Estimated time  | 15 minutes                                   |
| Risk level      | Medium                                       |
| Automation      | Manual                                       |

## Purpose

Give Hermes the deizmem MCP tools (`mcp_deizmem_*`) and the deizmem skill, over the dedicated
`deizmem_mcp` network ([ADR-0017](../decisions/0017-hermes-reaches-deizmem-over-mcp.md)). When
complete, Hermes can capture files into the memory and answer from it with citations.

## Scope

Covers the network, Hermes's compose change, the token, the `mcp_servers` entry and the skill.
Does **not** cover deploying deizmem itself (its repo: `~/Dev/deizmem`, `scripts/pi.sh up`) or
changing Hermes's LLM provider.

## Prerequisites

- [ ] Hermes is deployed and healthy — `docker ps --filter name=hermes-agent` shows `(healthy)`
- [ ] deizmem is running on the Pi — `curl -s http://127.0.0.1:4319/health` answers `{"ok":true,...}`
- [ ] This repo is pulled on the host — `cd /opt/dahouselab && git log -1 --oneline` shows the ADR-0017 commit

## Risks

- **The agent gains read access to medical and financial documents** (ADR-0017, Cons). Worst case:
  a prompt-injected agent reads and exfiltrates them. Revoking the token (step 7) is the kill switch.
- Recreating Hermes interrupts in-flight conversations for about a minute.
- A malformed `config.yaml` stops Hermes from starting; step 5 keeps a copy to restore.

## Safety checks

- [ ] `config.yaml` has no `mcp_servers` key yet — `sudo grep -n '^mcp_servers' ${DATA_ROOT}/hermes-agent/config.yaml` prints nothing. If it does, merge by hand instead of step 5.
- [ ] Disk has room — `df -h /` shows at least 1 GB free

## Procedure

1. **Create the platform network** (idempotent)

   ```bash
   docker network inspect deizmem_mcp >/dev/null 2>&1 || docker network create --internal deizmem_mcp
   ```

   Expected: the network exists; `docker network inspect deizmem_mcp -f '{{.Internal}}'` prints `true`.

2. **Attach deizmem's `mcp` to it** (in the deizmem checkout)

   ```bash
   cd ~/Dev/deizmem && docker compose up -d mcp
   docker network inspect deizmem_mcp -f '{{range .Containers}}{{.Name}} {{end}}'
   ```

   Expected: `deizmem-mcp-1`.

3. **Mint a token for Hermes** (the raw token is shown once)

   ```bash
   cd ~/Dev/deizmem
   docker compose exec -T worker node /app/dm.js pair
   docker compose exec -T worker node /app/dm.js token <CODE> --label hermes
   ```

   Expected: a line starting with `dm_`. Keep it only long enough for step 4.

4. **Store the token where the gateway will actually read it**

   > **This step used to say `.env.service`, and that silently does not work.** The gateway runs
   > under s6 supervision and inherits **none** of the container environment — not this token, not
   > `API_SERVER_KEY`, nothing from `.env.service`. Hermes reads its own `/opt/data/.env`, which
   > `hermes setup` writes. The trap is that `hermes mcp test` **passes anyway**, because the CLI
   > runs through `docker exec` and does inherit the container env. Two code paths, opposite
   > answers. (Found 2026-09-27.)

   ```bash
   source /opt/dahouselab/.env
   HENV="${DATA_ROOT}/hermes-agent/.env"
   sudo cp -a "$HENV" "${HENV}.bak-deizmem"
   echo 'DEIZMEM_MCP_TOKEN=dm_...' | sudo tee -a "$HENV" >/dev/null   # paste the real token
   ```

   Expected: `sudo grep -c '^DEIZMEM_MCP_TOKEN=' "$HENV"` prints `1`, mode stays `600`.

5. **Add the MCP server to Hermes's config** — the header references the variable, never the token

   ```bash
   sudo cp ${DATA_ROOT}/hermes-agent/config.yaml ${DATA_ROOT}/hermes-agent/config.yaml.bak-deizmem
   sudo tee -a ${DATA_ROOT}/hermes-agent/config.yaml >/dev/null <<'EOF'
   mcp_servers:
     deizmem:
       url: "http://deizmem-mcp:4319/mcp"
       headers:
         Authorization: "Bearer ${DEIZMEM_MCP_TOKEN}"
       timeout: 180
   EOF
   ```

   Expected: `sudo grep -A5 '^mcp_servers' ${DATA_ROOT}/hermes-agent/config.yaml` shows the block with the literal `${DEIZMEM_MCP_TOKEN}`.

6. **Install the skill and recreate Hermes** (joins the new network, reads the new env)

   ```bash
   docker exec hermes-agent mkdir -p /opt/data/skills/productivity/deizmem
   docker cp ~/Dev/deizmem/skills/deizmem/SKILL.md hermes-agent:/opt/data/skills/productivity/deizmem/SKILL.md
   cd /opt/dahouselab/services/hermes-agent && docker compose up -d --force-recreate
   ```

   Expected: `hermes-agent` returns to `(healthy)` within ~2 minutes.

## Verification

- [ ] **The gateway itself connected**, which is the only check that distinguishes a working
      integration from a parked one. In `~/Dev/deizmem`, compare the session's `last` with now —
      it must be seconds old, not hours:

      ```bash
      docker compose exec -T worker node /app/dm.js sessions </dev/null; date -u
      ```

- [ ] `docker exec hermes-agent hermes mcp test deizmem` connects and lists the tools.
      **On its own this proves nothing** — it passed throughout the outage described in step 4
- [ ] `docker exec hermes-agent curl -s -m5 http://deizmem-mcp:4319/health` answers `{"ok":true,...}`
- [ ] Isolation still holds: `docker exec hermes-agent curl -s -m5 http://vaultwarden:80` fails to resolve
- [ ] In a chat: send a photo or PDF, then ask about it — the answer cites a memory id
- [ ] `docker compose exec -T worker node /app/dm.js sessions` (in `~/Dev/deizmem`) shows `hermes` with a recent `last` time

## Rollback

7. **Kill switch — revoke the token** (instant, no Hermes restart)

   ```bash
   cd ~/Dev/deizmem && docker compose exec -T worker node /app/dm.js revoke <session-id>
   ```

Full rollback: restore `config.yaml.bak-deizmem`, remove `DEIZMEM_MCP_TOKEN` from `.env.service`,
revert the compose change, `docker compose up -d --force-recreate`, then
`docker network rm deizmem_mcp` once nothing is attached.

## Troubleshooting

| Symptom | Likely cause | Action |
| ------- | ------------ | ------ |
| `network deizmem_mcp declared as external, but could not be found` | Step 1 skipped | Run step 1, then `up -d` again |
| `mcp test` passes but the agent has no tools; log says `parking until a reconnect is requested` | The token is in `.env.service`, which the s6 gateway never reads | Move it to `${DATA_ROOT}/hermes-agent/.env` and restart — step 4 |
| `hermes mcp test` → 401 | Token wrong, revoked, or `${DEIZMEM_MCP_TOKEN}` not in the container env | `docker exec hermes-agent printenv DEIZMEM_MCP_TOKEN \| cut -c1-6` must print `dm_...`; re-mint (steps 3-4) |
| `hermes mcp test` → cannot resolve `deizmem-mcp` | deizmem's `mcp` not on the network | Step 2; check `docker network inspect deizmem_mcp` |
| Tools listed but every call says `needs_text` | deizmem lanes down | `~/Dev/deizmem/scripts/pi.sh dm doctor` from the Mac, or `dm doctor` in the worker |
