---
name: explain-project
description: Plain-English explanation of a WHOLE project (architecture, blocks, how they connect) for someone new to it, using the ai-gh-tools whole-project context builder. Use when the user asks to explain the project/codebase/repo, "how does this project work", or wants an architecture overview. Pass --deep to explain each block with parallel subagents.
---

# explain-project (hybrid: deterministic whole-repo context + live exploration)

Reuse the `ai-explain-project` tool to assemble deterministic, complete
whole-project context (file tree, rules, READMEs, metadata, definition inventory),
then use your live repo access to ground the explanation in the real code.

`--deep` is handled by this skill, not the tool — strip it before calling
`ai-explain-project`.

## Step 1 — Generate the context file

```bash
ai-explain-project --out "${TMPDIR:-/tmp}/agh-project-explain.md"
```

If the tool isn't on `PATH`, tell the user to run `./install.sh` and stop. On a
non-zero exit, surface its stderr verbatim and stop. Do not use
`--copy`/`--cursor`.

## Step 2 — Identify the blocks

Read the generated file. From the "Project files (whole repo)" tree (especially the
per-top-level-block counts), derive the **blocks** — cohesive parts of the system
(usually a top-level directory or a small group of related files).

## Step 3 — Explain

### Default (no --deep): single-pass
Explore the repo yourself — read the key files in each block and trace how they
connect — and write the explanation.

### --deep: one explainer subagent per block
Launch `project-explainer` subagents **concurrently** (one message, multiple Task
calls), one per block, each given the **path** to the context file from Step 1 and
the block it owns (tell it to read the file, not paste it). Collect their
per-block explanations, then synthesize a single coherent overview (do not dump a
per-agent section).

## Step 4 — Output

Produce the explanation directly in the chat following the template in the prompt
(TL;DR, How to run it, Blocks, Dependency map with a Mermaid diagram, Key flows,
Where to start reading, Conventions & gotchas). Plain English, grounded in the real
code. Read-only — never modify the repo or GitHub.
