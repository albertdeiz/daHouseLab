# Context: the personal knowledge base

A context document for AI assistants working in this repository or on the workstation. It exists
because an assistant cannot use a capability it does not know about.

## What it is

The documents stored in [Nextcloud](../../services/nextcloud/README.md) are indexed nightly into a
single [memvid](https://memvid.com/) file that supports semantic search. It is rebuilt at 04:30 by
[build-knowledge-base](../runbooks/build-knowledge-base.md) and delivered to the workstation
through Nextcloud's own sync ([ADR-0016](../decisions/0016-memvid-personal-knowledge-base.md)).

| Where | Path |
| ----- | ---- |
| On the Pi (source of truth) | `${DATA_ROOT}/knowledge/knowledge.mv2` |
| On the workstation (read-only copy) | `~/Nextcloud/Knowledge/knowledge.mv2` |

## How to query it

There is **no MCP server** — deliberately. Any assistant with a shell can use the CLI directly:

```bash
memvid ask   ~/Nextcloud/Knowledge/knowledge.mv2 "<question in natural language>"
memvid find  ~/Nextcloud/Knowledge/knowledge.mv2 "<keywords>"
memvid stats ~/Nextcloud/Knowledge/knowledge.mv2
```

`ask` returns an answer with its sources; `find` returns matching passages. Prefer `find` when you
want to read the raw material and judge it yourself.

## When to use it

Use it when the question is about **the operator's own documents** — manuals, contracts, notes,
references, receipts, anything filed in Nextcloud. Do not use it for questions about this
repository: the repo is right here and is better read directly.

Cite what it returns. An answer from the knowledge base is only as good as the document behind it,
so name the source rather than presenting a retrieved claim as your own knowledge.

## What it does not contain

- **Anything added today.** The index is rebuilt nightly; a document saved this afternoon is not in
  it until tomorrow. If an expected answer is missing, this is the first thing to suspect.
- **Non-textual files.** Photos, videos and binaries are excluded by an extension allowlist — memvid
  cannot usefully embed them without optional models, and the Pi cannot afford the attempt.
- **Old versions.** Nextcloud's `files_versions/` and `files_trashbin/` are excluded on purpose.

## Handling

The index contains the full text of everything ingested, so it is exactly as sensitive as the
documents themselves. Do not copy passages into anywhere they would leave the operator's control,
and never share the `.mv2` with a public link.

If the file is missing or `memvid stats` fails, do not try to rebuild it from the workstation —
that is the Pi's job. Report it; the likely cause is a failed nightly run, which the
`knowledge-nightly` monitor in Uptime Kuma should already be flagging.
