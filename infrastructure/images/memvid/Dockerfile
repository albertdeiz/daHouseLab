# memvid CLI, pinned — used by the nightly knowledge-base job (ADR-0016).
# Built locally like the Caddy image; never installed on the host (ADR-0003).
#
# The npm package resolves a prebuilt native binary per platform via optional
# dependencies (@memvid/cli-linux-arm64 on the Pi, -linux-x64 after migration),
# so this Dockerfile is architecture-independent.
#
# Update procedure: bump the version here AND the workstation's global install
# in lockstep — both read the same .mv2 format (update-containers runbook).
FROM node:22-bookworm-slim

RUN npm install -g memvid-cli@2.0.160 \
 && npm cache clean --force

# Embedder cache: the local BGE model is downloaded on first use. Persisting
# this path across runs avoids re-downloading it every night.
ENV XDG_CACHE_HOME=/cache

ENTRYPOINT ["memvid"]
