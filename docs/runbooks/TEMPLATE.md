# Runbook: Title (verb-object)

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | YYYY-MM-DD                                   |
| Estimated time  | e.g. 30 minutes                              |
| Risk level      | Low \| Medium \| High                        |
| Automation      | Manual \| Partially scripted \| Scripted (`scripts/…`) |

## Purpose

Why this procedure exists and what state the system is in when it completes successfully.

## Scope

What this runbook covers and — just as important — what it explicitly does not.

## Prerequisites

- [ ] Conditions that must be true before starting (access, hardware, prior runbooks)
- [ ] Commands to verify each one where possible

## Risks

What can go wrong during this procedure and the blast radius if it does. Name the worst case.

## Safety checks

- [ ] Checks performed **before** any mutating step (backups current? service quiesced? disk space?)
- [ ] Each check has a command and an expected result — do not proceed on unexpected output

## Procedure

Numbered steps. Each step: intent, exact command(s) in a `bash` block, expected outcome.
Mark destructive steps clearly:

> **Warning:** step N is destructive/irreversible beyond this point.

1. **Step name**

   ```bash
   command
   ```

   Expected: what success looks like.

## Verification

- [ ] Objective checks proving the procedure achieved its purpose (commands + expected output)
- [ ] The system is healthy overall, not just the touched component

## Rollback

How to return to the pre-procedure state, and up to which step rollback is possible.
If rollback is impossible past a point, that point must be marked in the procedure.

## Troubleshooting

| Symptom                     | Likely cause          | Action                          |
| --------------------------- | --------------------- | ------------------------------- |
|                             |                       |                                 |

## Automation opportunities

Which steps could be scripted, and what blocks that today. When this section is fully realized,
the runbook shrinks to "run the script; here is how to verify".

## Future improvements

Known weaknesses of the current procedure worth fixing.
