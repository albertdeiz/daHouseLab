# Runbook: Deploy Hermes Agent

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-09-21                                   |
| Estimated time  | 75 minutes                                   |
| Risk level      | Medium — step 3 recreates Caddy (brief ingress outage); the agent adds real RAM pressure |
| Automation      | Manual                                       |

## Purpose

Deploy [Hermes Agent](https://hermes-agent.nousresearch.com/docs/) at `https://hermes.${DOMAIN}`.
When complete: the agent runs on its **own** `hermes_ingress` network reachable only through Caddy,
talks to OpenAI for inference, publishes no ports, is capped at 4 GB, and **cannot reach any
other service on the platform** ([ADR-0015](../decisions/0015-hermes-agent-self-hosted-ai.md)).

## Scope

Covers: the `services/hermes-agent/` stack, the `hermes_ingress` network, attaching Caddy to it,
the provider setup, and enabling browser + messaging features.

Does not cover: a local LLM (impossible on this hardware — ADR-0015 Option B); egress filtering;
spend limits on the provider (set those in OpenAI's dashboard, not here).

## Prerequisites

- [ ] [ADR-0015](../decisions/0015-hermes-agent-self-hosted-ai.md) read — especially the Cons. This
      service costs money per use, depends on a vendor, and executes tools autonomously
- [ ] [deploy-caddy](deploy-caddy.md) complete and Caddy healthy
- [ ] An OpenAI **API** key with billing enabled: <https://platform.openai.com/api-keys>.
      A ChatGPT Plus subscription does **not** include API access — it is a separate key
- [ ] A spend/budget limit set in OpenAI's dashboard — the platform has no spend cap, and an
      agent that loops bills every iteration
- [ ] Tokens ready for any messaging connector you intend to enable
- [ ] Uptime Kuma green across the board

## Risks

- **Worst case: the platform runs out of memory.** Full scope with browser automation asks 2–4 GB
  on an 8 GB host. If the cap is missing or wrong, Chromium can starve Nextcloud and Vaultwarden.
  The `deploy.resources.limits` in the compose file is what prevents this — never remove it.
- Recreating Caddy (step 3) drops **all** web ingress for a few seconds. Do this knowingly.
- A misconfigured network would place the agent on `proxy`, giving it a direct route to
  `vaultwarden:80`. Step 8 exists to prove that did not happen.
- The API key is live credit. Leaking it is a billing incident.

## Safety checks

- [ ] **The memory cgroup is enabled** — without it the 4 GB cap is silently discarded:
      `grep ^memory /proc/cgroups` → 4th column is `1`. On Raspberry Pi OS it is **disabled by
      default** (the firmware appends `cgroup_disable=memory`, which is why `cmdline.txt` can look
      clean while `/proc/cmdline` disagrees — check `/proc/cmdline`, not the file). Fix: append
      `cgroup_enable=memory cgroup_memory=1` to the single line in `/boot/firmware/cmdline.txt` and
      **reboot**. Docker only warns ("Limitation discarded") and starts anyway
- [ ] Memory headroom **before** starting: `free -h` → ≥ 4 GB available. Below that, stop: the cap
      will not save you if the host is already tight
- [ ] `hermes.${DOMAIN}` not already routed:
      `grep -n "hermes" /opt/dahouselab/infrastructure/configs/Caddyfile` → no output
- [ ] The network does not already exist: `docker network ls | grep hermes_ingress` → no output
- [ ] Current Caddy state is known-good: `curl -I https://home.${DOMAIN}` → 200 (you are about to
      recreate it; know what "working" looked like)
- [ ] Uptime Kuma green across the board

## Procedure

1. **Pull the repo and create the data directory.**

   ```bash
   cd /opt/dahouselab && git pull
   source /opt/dahouselab/.env
   sudo install -d -o 1000 -g 1000 "${DATA_ROOT}/hermes-agent"
   ```

   Expected: `${DATA_ROOT}/hermes-agent` exists, owned by `1000:1000`.

2. **Create the isolation network.**

   ```bash
   docker network create hermes_ingress
   docker network ls | grep hermes_ingress
   ```

   Expected: the network exists. It is platform-owned, like `proxy` — services reference it as
   `external: true` and never create it as a side effect.

3. **Attach Caddy to it.**

   > **Warning: this step recreates Caddy — all web ingress drops for a few seconds.** A
   > `caddy reload` is **not** sufficient: network membership is a container property, not config.

   The compose change is already in Git (step 1). Apply it:

   ```bash
   cd /opt/dahouselab/services/caddy
   docker compose up -d --force-recreate
   docker network inspect hermes_ingress --format '{{range .Containers}}{{.Name}} {{end}}'
   ```

   Expected: `caddy` appears in that list, and `curl -I https://home.${DOMAIN}` → 200 again.

4. **Wire the environment layers.**

   ```bash
   cd /opt/dahouselab/services/hermes-agent
   ln -sf ../../.env .env
   cp .env.service.example .env.service && chmod 600 .env.service
   openssl rand -base64 24        # for API_SERVER_KEY — copy, do not pipe
   ```

   Edit `.env.service` **with an editor**: paste the OpenAI key, the generated `API_SERVER_KEY`,
   and only the connector tokens you will actually enable. Store both secrets in Vaultwarden.
   Expected: `ls -l` shows `.env -> ../../.env` and `-rw------- .env.service`.

5. **Validate and start.**

   ```bash
   docker compose config --quiet && echo OK
   docker compose config | grep -A3 'networks:'   # must show hermes_ingress, NOT proxy
   docker compose up -d && watch docker compose ps
   ```

   Expected: `OK`, the network is `hermes_ingress`, and the container reaches `healthy` within
   ~2 minutes. First boot initialises Playwright/Chromium and is slow — `start_period` allows 60 s.

   > If it never becomes healthy, check `docker compose logs hermes-agent` for **Chromium failing
   > on arm64**. If browser automation cannot start on this architecture, disable it in step 7 and
   > record that here and in the service's `docs/README.md` — it changes the RAM picture and is
   > worth knowing.

6. **Add the Caddy route.**

   The Caddyfile block is already in Git. Validate and reload (a reload is enough here — only
   config changed, not networks):

   ```bash
   docker compose -f /opt/dahouselab/services/caddy/compose.yaml exec caddy \
     caddy validate --config /etc/caddy/Caddyfile
   docker compose -f /opt/dahouselab/services/caddy/compose.yaml exec caddy \
     caddy reload --config /etc/caddy/Caddyfile
   ```

   Expected: `Valid configuration`, clean reload, and `curl -sk https://hermes.${DOMAIN}/` (over
   Tailscale) returns the dashboard.

7. **Run the provider setup.**

   ```bash
   docker compose exec -it hermes-agent hermes setup
   ```

   In the interactive flow: choose **OpenAI**, paste the API key, and select model `gpt-5.4`
   (the base URL is only needed for a non-standard endpoint such as Azure).
   Then enable browser tools and the messaging connectors you want.

   **Configure dashboard auth in the same sitting — the dashboard will not start without it.**
   Upstream refuses to bind a non-loopback address with no auth provider registered ("There is no
   unauthenticated public-dashboard option"), and Caddy reaches this container over the network,
   not loopback. Until this is done the container runs but nothing listens on 9119 and Caddy
   returns 502. Generate a hash and put it in `config.yaml`:

   ```bash
   docker compose exec hermes-agent python -c \
     "from plugins.dashboard_auth.basic import hash_password; print(hash_password('YOUR-PASSWORD'))"
   ```

   ```yaml
   # ${DATA_ROOT}/hermes-agent/config.yaml
   dashboard:
     basic_auth:
       username: <you>
       password_hash: <the hash>
   ```

   Store the password in Vaultwarden. The alternative is `hermes dashboard register` (Nous Portal
   OAuth), which adds a second third party to the stack.

   > **There is no environment variable for the model.** `LLM_MODEL` was removed upstream, and
   > `HERMES_MODEL` only overrides a single `hermes -z`/`hermes chat` invocation — not the
   > gateway. The model is written to `config.yaml` by this step. Upstream's rule is "secrets in
   > `.env`, everything else in `config.yaml`".
   >
   > Provider choice is a parameter, not architecture
   > ([ADR-0015](../decisions/0015-hermes-agent-self-hosted-ai.md) condition 1). `hermes model`
   > adds or reconfigures providers later without a redeploy; `/model` switches between ones
   > already configured.

   Expected: a test prompt from the dashboard returns an answer. **This is the first step that
   spends money.**

8. **Prove the isolation.** This is not optional — it is the condition the service was accepted
   under ([ADR-0015](../decisions/0015-hermes-agent-self-hosted-ai.md), condition 2).

   ```bash
   docker exec hermes-agent curl -s -m3 http://vaultwarden/alive   # must FAIL / time out
   docker exec hermes-agent curl -s -m3 http://nextcloud/status.php # must FAIL / time out
   docker exec hermes-agent curl -s -m5 https://api.openai.com/v1/models   # must answer (401 is fine — it routed)
   ```

   Expected: the first two fail, the third answers. **If any internal service is reachable, stop
   and fix the network before going further** — the agent is on the wrong network.

9. **Watch the memory for a real workload.**

   ```bash
   docker stats --no-stream hermes-agent
   free -h
   ```

   Expected: well under the 4 GB cap at idle, and `free -h` still shows ≥ 1.5 GiB available with
   everything running. Then ask the agent to browse a page and re-check — browsing is the peak.

10. **Register the service.**

    - Uptime Kuma: HTTP(s) monitor on `https://hermes.dahub.casa/`, 60 s, cert-expiry on, Telegram.
      Note in the monitor's description that **green means the dashboard is up, not that inference
      works** — a dead API key looks healthy here
    - Homepage tile in `infrastructure/configs/homepage/services.yaml`
    - Confirm the resource-budget table in [docs/services/README](../services/README.md) lists this
      service, and the portfolio and ADR/runbook indexes are updated

    Commit any host-side corrections back to Git — never leave a fix only on the host.

## Verification

- [ ] `docker compose ps` → `hermes-agent` `healthy`
- [ ] `docker compose config | grep -c proxy` → **0** (it must not be on the proxy network)
- [ ] `curl -sk https://hermes.${DOMAIN}/` (over Tailscale) → dashboard, HTTP 200
- [ ] `sudo ss -ltnp | grep -E '8642|9119'` → **no output** (nothing published on the host)
- [ ] Isolation: `docker exec hermes-agent curl -s -m3 http://vaultwarden/alive` → fails
- [ ] Provider: a prompt in the dashboard returns an answer
- [ ] `docker stats --no-stream hermes-agent` → within the 4 GB cap
- [ ] `free -h` → ≥ 1.5 GiB available with the whole platform running
- [ ] No `/var/run/docker.sock` anywhere: `grep -r docker.sock services/hermes-agent/` → no output
- [ ] Everything else still green: `curl -I https://vault.${DOMAIN}`, `https://cloud.${DOMAIN}`,
      `https://dns.${DOMAIN}` → 200; Uptime Kuma all green
- [ ] Persistence: `docker compose restart hermes-agent` → provider config and memory survive

## Rollback

```bash
cd /opt/dahouselab/services/hermes-agent
docker compose down
```

Remove the `hermes.{$DOMAIN}` block from the Caddyfile and reload Caddy. To fully undo the network
change, revert the Caddy compose file, `docker compose up -d --force-recreate` it (another brief
ingress outage), then `docker network rm hermes_ingress`.

`${DATA_ROOT}/hermes-agent` persists, so a later `up -d` resumes with the agent's memory intact.
**Revoke the OpenAI API key** if rolling back because of a leak or runaway spend — stopping the
container stops usage, but a leaked key does not care whether the container runs.

## Troubleshooting

| Symptom                                     | Likely cause                              | Action                                                                 |
| ------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------------------- |
| 502 via `hermes.dahub.casa`                 | Caddy not on `hermes_ingress`             | `docker network inspect hermes_ingress`; Caddy must be **recreated**, not reloaded |
| Container never becomes healthy             | Chromium failing to start on arm64        | `docker compose logs`; disable browser tools and record the finding     |
| Container healthy-ish but Caddy returns 502, nothing on :9119 | Dashboard auth not configured | Expected before step 7. `docker logs` says "Refusing to bind dashboard to 0.0.0.0". Configure `dashboard.basic_auth` |
| `docker inspect` shows `Memory: 0` despite the cap | Memory cgroup disabled in the kernel | Pi OS default. See the safety check; requires a cmdline change **and a reboot**. Docker only warns |
| Container OOM-killed / restart loop         | Browser automation against the 4 GB cap   | Disable browser tools (ADR-0015's first lever) before raising the cap   |
| Dashboard fine, agent answers nothing       | Provider: key expired, no credit, or down | `docker compose logs`; test the key with a direct `curl` to OpenAI      |
| Tool calls fail repeatedly                  | Usually the model, not the config         | Small models drift on tool schemas — move up a tier (`hermes model`)    |
| Agent reaches another service               | It is on `proxy` — a serious misconfiguration | Stop it, fix `networks:` in the compose, recreate, re-run step 8    |
| Platform slow after deploy                  | RAM pressure                              | `free -h` vs the ≥1.5 GiB floor; `docker stats` to find the consumer    |
| Unexpected agent actions                    | Possible prompt injection (page or message) | Disable the connector involved; the isolation bounds reach inside the platform, not the agent's own tools |
| Unexpected provider bill                    | A loop or an over-eager schedule          | Stop the container first, investigate second. Set a budget alert        |

## Automation opportunities

- Steps 1, 4 and 5 are the generic [deploy-with-compose](deploy-with-compose.md) flow and would be
  covered by the planned `scripts/deploy-service.sh`.
- **Step 8's isolation check should be a recurring health check**, not a one-off: a future network
  change could silently undo it. It belongs in
  [run-health-checks](run-health-checks.md) as an assertion that Hermes cannot reach `proxy`.
- Creating platform networks belongs with the other bootstrap scripts
  ([`scripts/bootstrap/`](../../scripts/bootstrap/)), alongside `docker network create proxy`.

## Future improvements

- **Egress filtering.** The agent needs its provider, so today it can reach anything outbound. An
  allowlist would meaningfully shrink the prompt-injection blast radius.
- **A spend guard.** Provider-side budget alerts are the only control; a local usage monitor fed
  into Uptime Kuma would surface a runaway agent faster than a monthly invoice.
- **A real inference check** in Kuma — the HTTP monitor proves the dashboard, not the brain.
- **Local inference** at the Mini PC migration removes the vendor dependency entirely
  ([ADR-0015](../decisions/0015-hermes-agent-self-hosted-ai.md) Option B).
