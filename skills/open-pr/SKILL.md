---
name: open-pr
description: Commit pending work, push the current branch, and OPEN a GitHub PR via the ai-gh-tools `ai-open-pr` command — optionally drafting the PR body from the change set first. This MODIFIES your repo and GitHub. Use when the user asks to open/create/submit a PR, "push and open a PR", or "create the pull request". Triggers on "open a PR", "create a PR", "submit my branch".
---

# open-pr (hybrid: AI-drafted body + the deterministic `ai-open-pr` mutation)

Unlike the other ai-gh-tools skills, this one **modifies state**: `ai-open-pr`
runs `git add -A` + `git commit`, `git push`, and `gh pr create`. Your job is to
draft an accurate PR body, show the user exactly what will happen, get one
explicit go-ahead, and only then execute.

> **Critical:** the CLI confirms each mutation interactively, but this skill runs
> it without a TTY, so those prompts auto-**refuse** unless you pass `--yes`. That
> means your in-chat approval (Step 4) is the *only* confirmation gate — never run
> the real command before the user has approved the dry-run summary.

## Step 1 — Map the request to flags

`ai-open-pr` always works on the **current branch** vs a base ref. There is no
`--pr` / `--staged` mode.

- **Base**: `ai-open-pr <BASE_REF>` (omit to auto-detect: `origin/main`, `main`, …).
- `--ticket <ID>` — prefixes the title `[ID]` and fills "Related Issue".
- `--draft` — open as a draft PR.
- `--title <TITLE>` — explicit title (else derived from the commit/branch).
- `-m <MSG>` — commit message for any uncommitted changes.
- `--remote <NAME>` — push remote (default `origin`; use for fork workflows).
- `--repo OWNER/REPO` — target repo override for `gh`.

If `ai-open-pr` isn't on `PATH`, tell the user to run `./install.sh` from the
ai-gh-tools repo, then stop.

## Step 2 — Draft the PR body (recommended)

Unless the user passed `--body-file` or asked to skip it, draft a real body so the
PR isn't just the blank template. Reuse the **draft-pr** flow:

```bash
ai-draft-pr <BASE_REF> --out "$TMPDIR/agh-openpr-body.md"
```

Read that file, fill the team template against what the diff actually contains
(confirm against real files; do not invent features/tests/rollout steps), and
write the finished body — the template starting at `### Description`, no title
line — back to `$TMPDIR/agh-openpr-body.md`. You'll pass it as `--body-file`.
Capture the drafted title to pass via `--title`.

## Step 3 — Dry-run and show the plan

Run with `--dry-run` (changes nothing) so the user sees the exact commit message,
base, head, title, and body that would be used:

```bash
ai-open-pr <BASE_REF> [--ticket ID] [--draft] \
  --title "<DRAFTED TITLE>" --body-file "$TMPDIR/agh-openpr-body.md" --dry-run
```

Surface its summary. If it exits non-zero (detached HEAD, branch == base, nothing
ahead of base, missing remote), relay its stderr verbatim and stop.

## Step 4 — Get explicit approval, then execute

Show the user the plan from Step 3 and ask them to confirm opening the PR. Only
after they say yes, run the real command. Because there's no TTY, add `--yes` so
the CLI doesn't refuse its own prompts (your in-chat confirmation replaced them):

```bash
ai-open-pr <BASE_REF> [same flags as the dry-run, minus --dry-run] --yes
```

Do **not** pass `--yes` before the user has approved. If the user prefers to run
it themselves with the CLI's interactive per-step prompts, give them the exact
command (without `--yes`) to paste into their terminal instead.

## Step 5 — Report

`gh pr create` prints the PR URL on success — relay it. If any step failed, the
branch may already be committed/pushed; say what completed and what didn't so the
user can finish manually. This is the one skill that writes to GitHub — be precise
about what changed.