---
name: jira-draft
description: Turn the bugs found by /project-audit into clean, humanized Jira tickets (plain-language title + structured description), after re-validating each against the live code as a final ticket-worthiness gate. Reads the audit's bug JSON via --from. Use when the user asks to draft Jira tickets/issues from the audit, "make tickets for these bugs", or "write Jira for the audit".
---

# jira-draft (hybrid: bug file in → validated, humanized tickets out)

Reuse `ai-jira-draft` to embed the audited bug JSON with repo context, then use your
live repo access to re-validate each bug and rewrite it as a humanized Jira ticket.

## Step 1 — Locate the bug file

The input is the JSON written by `/project-audit` (default
`${TMPDIR:-/tmp}/agh-audit-bugs.json`). If the user gives a path, use it. If none is
given and the default doesn't exist, tell them to run `/project-audit` first (which
writes that file), then stop.

## Step 2 — Generate the context file

```bash
ai-jira-draft --from "<bug-file>" --out "${TMPDIR:-/tmp}/agh-jira-draft.md"
```

If the tool isn't on `PATH`, tell the user to run `./install.sh` and stop. On a
non-zero exit (missing/invalid `--from`), surface its stderr verbatim and stop. Do
not use `--copy`/`--cursor`.

## Step 3 — Validate (final gate, conservative)

Read the generated file (it embeds the bug JSON). For **each** bug, confirm it
against the live code at the cited `path:line`. **Keep only** bugs that are clearly
real and worth a ticket; **drop** anything not reproducible, already handled, or
low-impact. For higher assurance, spawn `review-correctness` skeptics to refute the
borderline ones. Track what you dropped and why.

## Step 4 — Humanize into tickets

For each survivor, write a Jira ticket using the exact structure in the prompt:
plain-language **Title** (no code jargon / symbol names), then **What's wrong**,
**Why it matters**, **Where** (component/block — affects: dependents), **Suggested
fix**, **Evidence** (`path:line`, for engineers), **Severity**. Group High first,
then Medium. Map Where/affects from each bug's `block`/`dependents`.

## Step 5 — Output

In the chat: a short **Validation summary** (kept N, dropped M with one-line
reasons), then the **tickets**. Optionally also write them to
`${TMPDIR:-/tmp}/agh-jira-tickets.md`.

This skill is read-only: it does not file tickets or modify the repo/GitHub (no Jira
integration is wired). The output is paste-ready for Jira.
