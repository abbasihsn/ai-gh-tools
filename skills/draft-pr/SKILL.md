---
name: draft-pr
description: Draft a pull request title and description by filling the team PR template from a change set (local branch or staged diff), using the ai-gh-tools context builder. Use when the user asks to draft/write a PR description, fill the PR template, or "write a PR body".
---

# draft-pr (hybrid: deterministic context + live codebase exploration)

Reuse the `ai-draft-pr` tool to assemble deterministic context and the team PR
template, then use your live repo access to make the description accurate.

## Step 1 — Map the request to flags

- **Current branch vs a base** (default): `ai-draft-pr <BASE_REF>` (omit base to
  auto-detect).
- **Staged changes**: `ai-draft-pr --staged`
- Pass `--ticket <ID>` if given — it prefixes the title `[ID]` and fills Related Issue.

`ai-draft-pr` has no `--pr` mode (you draft from local/staged changes). Do not use
`--copy`/`--cursor`/`--symbols`.

## Step 2 — Generate the context file

```bash
ai-draft-pr <ARGS> --out "${TMPDIR:-/tmp}/agh-draft.md"
```

If the tool isn't on `PATH`, tell the user to run `./install.sh` and stop. On a
non-zero exit, surface its stderr verbatim and stop.

## Step 3 — Read it and draft

Read the generated file. It includes the fill-in rules and the exact team template
to complete. Base everything only on what the diff actually contains plus the
README/repo context — confirm against real files when unsure; do not invent
features, tests, or rollout steps. Keep every template heading exactly as written;
don't pre-check the author checklist.

## Step 4 — Output

Output the title first (prefixed with `Title:`), a blank line, then the filled-in
template starting at `### Description`, and nothing else — so it can be fed to
`ai-open-pr --body-file` or pasted into GitHub. Read-only — never modify the repo
or GitHub.
