---
name: explain-pr
description: Plain-English explanation of a change set (local branch, staged diff, or GitHub PR) for someone new to it, using the ai-gh-tools context builder. Use when the user asks to explain a PR/diff/branch, summarize changes, or "what does this change do".
---

# explain-pr (hybrid: deterministic context + live codebase exploration)

Reuse the `ai-explain-pr` tool to assemble deterministic, complete context, then
use your live repo access to ground the explanation in the real code.

## Step 1 — Map the request to flags

- **Current branch vs a base** (default): `ai-explain-pr <BASE_REF>` (omit base to
  auto-detect).
- **Staged changes**: `ai-explain-pr --staged`
- **A GitHub PR**: `ai-explain-pr --pr <NUMBER|URL|BRANCH>` (`--comments` to include
  discussion, `--repo OWNER/REPO` for another repo).

Do not use `--copy`/`--cursor`/`--symbols`.

## Step 2 — Generate the context file

```bash
ai-explain-pr <ARGS> --out "$TMPDIR/agh-explain.md"
```

If the tool isn't on `PATH`, tell the user to run `./install.sh` and stop. On a
non-zero exit, surface its stderr verbatim and stop.

## Step 3 — Read it and explain

Read the generated file (instructions + rules + README + metadata + changed files +
diff). When it helps a newcomer, open the referenced files to confirm intent and
behavior rather than guessing. Label inferences as inferences.

## Step 4 — Output

Produce the explanation directly in the chat following the template in the prompt
(TL;DR, What changed, Diagram, Why it likely changed, Important files, Behavior
changes, Risk areas, Review this first, Confusing parts). Plain English, grounded
in the actual diff. Read-only — never modify the repo or GitHub.
