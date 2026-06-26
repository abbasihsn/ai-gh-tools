---
name: project-audit
description: Audit a WHOLE project for high/medium bugs (skip low-impact), each attributed to a system block and its blast radius, adversarially verified so findings are valid/worth-filing. Shows the audit in chat AND writes a structured bug JSON for the jira-draft step. Use when the user asks to find bugs across the whole codebase, audit the project, or "what's broken in this repo". Triggers on "audit the project", "find bugs in the whole repo", "project audit".
---

# project-audit (hybrid: whole-repo context + block-based multi-agent bug hunt)

Reuse `ai-project-audit` to assemble deterministic whole-project context, then run a
block-based audit on top: let the user pick which blocks to audit, find high/medium
bugs per block, **adversarially verify** each so only valid/worth-filing bugs remain,
attribute each to its block and blast radius, and emit both a chat report and a
structured bug JSON for `/jira-draft`.

Two flags are handled by this skill, not the tool — strip them before calling
`ai-project-audit`:
- `--deep` — fan out to one `bug-hunter` subagent per selected block (default is a
  single-pass audit you do yourself).
- `--no-verify` — skip the adversarial verify pass. **Verify is ON by default** here
  because Jira-bound findings must be valid.

## Step 1 — Generate the context file

```bash
ai-project-audit --out "${TMPDIR:-/tmp}/agh-project-audit.md"
```

If the tool isn't on `PATH`, tell the user to run `./install.sh` and stop. On a
non-zero exit, surface its stderr verbatim and stop. Do not use `--copy`/`--cursor`.

## Step 2 — Derive and rank the blocks

Read the generated file. From the "Files per top-level block" counts and the file
tree, derive the **blocks** (cohesive parts — usually a top-level dir or a small
related group). Rank them by audit value: **logic-heavy and system-mutating code
ranks highest** (e.g. shared libraries, CLI entrypoints, installers), **data,
templates, and tests rank lowest**.

## Step 3 — Let the user select blocks (checkbox)

Present the top-ranked blocks with **AskUserQuestion** as a **multi-select**
(`multiSelect: true`) question — "Which blocks should I audit?". The dialog supports
**at most 4 options**, so list the 4 highest-value blocks (pre-recommend the
riskiest in the labels). If there are more than 4 blocks, fold the lower-value ones
together or note they're skipped. Audit **only the selected blocks**; `log`/state
which blocks were skipped.

## Step 4 — Find (per selected block)

### --deep: one bug-hunter per selected block
Launch `bug-hunter` subagents **concurrently** (one message, multiple Task calls),
one per selected block, each given the **path** to the context file from Step 1 and
the block it owns. Each returns **high/medium only** findings with `path:line`,
severity, the block, candidate dependents, impact, and fix.

### Default (no --deep): single-pass
Audit the selected blocks yourself, reading the real files. Same output shape.

## Step 5 — Verify (default on; skip with --no-verify)

For **each** candidate bug, spawn a skeptic subagent (`review-correctness` is a good
default) prompted to **refute** it against the real code: "Here is a claimed
high/medium bug: <finding>. Read the cited code and try to prove it is NOT real, or
that it is only low-impact. Conclude real-and-worth-fixing / not." **Drop** any bug
the skeptic refutes or downgrades to low-impact. This is the validity gate.

## Step 6 — Blast radius

For each surviving bug, confirm its **dependents** — grep the repo for callers/usages
of the affected function/file and list the concrete blocks/files that depend on it.

## Step 7 — Emit (BOTH, always)

1. **Print the audit in the chat**: a Summary (counts by severity, one-line risk
   read) and the bugs ordered high → low, each with block, dependents (affects),
   impact, evidence (`path:line`), and suggested fix.
2. **Write the bug JSON** to `${TMPDIR:-/tmp}/agh-audit-bugs.json` matching the
   contract in `prompts/project-audit.md` (`{ "repo", "bugs": [ { id, title,
   severity, block, dependents, evidence, impact, suggested_fix, lens, confidence }
   ] }`). Tell the user the path and that they can draft tickets with
   `/jira-draft` (or `ai-jira-draft --from <that file>`).

This skill is read-only: never post comments, push, or modify the repo/GitHub.
