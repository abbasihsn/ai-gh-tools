---
name: pr-review
description: Strict code review of a change set (local branch, staged diff, or GitHub PR), using the ai-gh-tools context builder. Default is a single-pass review; pass --deep to fan out to parallel reviewer subagents and --verify to adversarially refute high-severity findings. Use when the user asks to review a PR, review the current branch/diff, review staged changes, or "run a code review". Triggers on "review this PR", "review my branch", "code review", "deep review".
---

# pr-review (hybrid: deterministic context + live codebase exploration)

This skill reuses the `ai-pr-review` tool to assemble **deterministic, complete**
review context (the exact diff, changed files, repo metadata, README context, and
the toolkit + project rules), then has the AI — with live repo access — do the
parts a static prompt cannot: explore the codebase to catch semantic duplication
and confirm findings against real code.

Do NOT re-implement the diff/rule gathering yourself. The tool's value is that it
is identical every run and never forgets a file. Your value is the agentic
exploration on top.

## Step 1 — Parse the request

Two of the flags are **handled by this skill, not the tool** — strip them before
calling `ai-pr-review`:

- `--deep` — fan out to parallel reviewer subagents (higher quality, ~N× tokens).
- `--verify` — after findings are collected, adversarially refute every `[high]`
  finding before reporting it (kills false positives). Implies `--deep`.

Everything else is passed straight through to `ai-pr-review`. Map the change set:

- **Current branch vs a base** (default): `ai-pr-review <BASE_REF>` (omit base to
  auto-detect: `origin/main`, `main`, …).
- **Staged changes**: `ai-pr-review --staged`
- **A GitHub PR**: `ai-pr-review --pr <NUMBER|URL|BRANCH>` (`--comments` to include
  discussion, `--repo OWNER/REPO` to target another repo).
- Pass `--ticket <ID>` if given; `--include-working-tree` to include unstaged edits.

Never pass `--copy`, `--cursor`, or `--symbols` — you have live repo access, so the
clipboard path and the symbol-inventory fallback are unnecessary.

## Step 2 — Generate the context file

Run the tool, writing to a temp file (it never modifies the repo or GitHub):

```bash
ai-pr-review <PASSED-THROUGH-ARGS> --out "$TMPDIR/agh-review.md"
```

If `ai-pr-review` is not on `PATH`, tell the user to run `./install.sh` from the
ai-gh-tools repo, then stop. If the tool exits non-zero (empty PR diff, bad `gh`
auth, etc.), surface its stderr verbatim — its messages are specific and
actionable — and stop.

## Step 3 — Review

### Default (no --deep): single-pass

Read the generated file and review it yourself. It contains, in order: the review
instructions, the binding rules (toolkit + this repo's `.cursor/rules`), README
context, repo metadata, the changed-file list, and the full diff. Before calling
any new helper/class "novel", grep and read the **base branch** for an existing
equivalent and read its body to judge real (semantic) duplication. Cite every
match as `path:line`.

### --deep: parallel reviewer subagents

Launch these reviewer subagents **concurrently** (one message, multiple Task
calls so they run in parallel), giving each the **path** to the context file from
Step 2 (do not paste the whole diff into each prompt — tell them to read the file):

- `review-correctness`
- `review-architecture`
- `review-code-quality`
- `review-types-apis`
- `review-security`
- `review-performance`
- `review-config-devops`
- `review-testing-docs`

Prompt template for each: *"Read the review context at `<path>`. Review the diff
**only** through your lens, exploring the live repo to confirm. Return findings as
a list (path:line, severity, what's wrong and what it causes, fix)."* These
subagents are read-only — they must not edit files or touch git/GitHub.

Collect all findings, then **deduplicate** across agents (multiple lenses often
flag the same line — merge into one finding, keeping the highest severity and
tagging which lenses raised it).

### --verify: adversarial refute pass (implies --deep)

For each `[high]` finding, spawn one skeptic subagent (`review-correctness` is a
good default agent type) prompted to **try to refute it** against the real code:
*"Here is a claimed high-severity issue: <finding>. Read the cited code and
attempt to prove it is NOT a real problem. Conclude real / not-real with
evidence (path:line)."* Drop or downgrade any finding the skeptic refutes with
concrete evidence. This removes plausible-but-wrong findings, the main failure
mode of LLM review.

## Step 4 — Output

Produce the review **directly in the chat** following the exact output template in
the generated prompt (Title, Branches, Overview, Diagram, Merge risk, Must-fix
items, Reviewer-ready comments). In `--deep` mode you (the orchestrator) write the
single synthesized review from the deduplicated findings — do **not** dump a
per-agent section. Tag each comment with the lens it came from, keep severity
tags, and ground every finding in a specific `path:line`.

This skill is read-only: never post comments, push, or open/modify a PR.
