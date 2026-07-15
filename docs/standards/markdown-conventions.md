# Markdown Conventions

## Why

All documentation is Markdown so it diffs, reviews and greps like code. A single style keeps
hundreds of documents readable as one body of work.

## Document skeleton

Every document follows this shape:

```markdown
# Title (one H1, matches the document's purpose)

One-paragraph summary: what this document is and when to read it.

## Why            ← reasoning before mechanics, always
## <Content sections>
## Tradeoffs / Rules / References (as applicable)
```

## Style rules

| Rule                                    | Convention                                                   |
| --------------------------------------- | ------------------------------------------------------------ |
| Headings                                | `#` ATX style; exactly one H1; never skip levels              |
| Heading case                            | Sentence case (`## Backup strategy`, not `## Backup Strategy`) — proper nouns keep their case |
| Lists                                   | `-` for unordered, `1.` for ordered; indent nested items 2 spaces |
| Emphasis                                | `**bold**` for key terms, `*italic*` sparingly; never bold as pseudo-heading |
| Code                                    | Backticks for identifiers, paths, commands; fenced blocks with a language tag (`bash`, `yaml`, `text`) |
| Tables                                  | Pipe tables with aligned pipes where practical; keep cells short — explanation goes in prose |
| Links                                   | Relative links within the repo (`../decisions/0003-docker-first.md`); never absolute filesystem paths |
| Diagrams                                | Mermaid fenced blocks (` ```mermaid `); binary exports go to `/assets` |
| Line length                             | No hard wrap requirement; break lines at sentence or clause boundaries (~100–120 chars) for clean diffs |
| Checklists                              | `- [ ]` for procedures meant to be executed                  |
| Admonitions                             | `> **Warning:** …` blockquotes; use sparingly and only for real risk |

## Command blocks

Commands the reader will execute are always in `bash` fences, one logical step per block, with a
comment stating intent when not obvious:

```bash
# Verify the container is healthy before proceeding
docker compose ps
```

Never mix commands and their expected output in the same block — show expected output in a
separate `text` block introduced by "Expected output:".

## Anti-patterns

- Walls of prose where a table or checklist would do.
- "As mentioned above/below" — link to the section instead.
- Documenting *how* without *why*.
- Screenshots of text (unsearchable, undiffable) — use text.
