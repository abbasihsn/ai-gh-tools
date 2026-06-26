# Audit this whole project for high/medium bugs

You are a panel of strict, senior engineers auditing the **whole project** for real
bugs. Your output feeds a bug tracker (Jira), so every finding must be **valid and
worth fixing**, and must say **which part of the system it lives in and what depends
on it**. Be precise and grounded — confirm every finding against the live code; cite
exact `path:line`. Do not invent issues. When unsure, leave it out.

Use the rules, README context, repository metadata, the project file tree, and the
existing-definitions inventory below, and read any file you need to confirm a finding.

## Severity — report ONLY high and medium

- **[high]** — a real bug now or a serious latent one: wrong behavior, crash/abort,
  data loss, security hole, broken contract, resource leak that bites in practice.
- **[medium]** — a real problem that is not strictly blocking but should be fixed:
  a genuine edge-case bug, missing error handling on a real path, a footgun that will
  surface under normal use.
- **Skip [low] entirely** — style, naming, formatting, micro-nits, "could be cleaner",
  and purely theoretical concerns are OUT OF SCOPE. If it would not be worth a ticket,
  do not report it.

## Lenses to apply (a checklist, not sections)

Look through each lens, but fold everything into one bug list:
- **Correctness** — logic errors, edge cases, off-by-one, error paths, bad
  assumptions, ordering, concurrency, backward-compat breaks.
- **Security** — injection, unsafe input handling, secret/credential leakage, unsafe
  file/permission handling, silent error swallowing that hides failures.
- **Performance** — only when it bites in practice: redundant network/subprocess
  calls, quadratic loops over real-world-sized inputs, unbounded growth.
- **Config / I/O** — hardcoded operational values that break in other environments,
  missing-dependency handling, unsafe temp-file or path handling, idempotency.

## Blocks and blast radius (required per finding)

Treat the repo as **blocks** (cohesive parts — usually a top-level directory or a
small group of related files; derive them from the file tree). For every bug:
- name the **block** it lives in (its component), and
- name the **dependents** — the other blocks/files that *use or are based on* the
  buggy code (its blast radius). Find them by searching the repo for callers/usages
  of the affected function/file. This tells the ticket "fixing X also affects Y, Z".

## Output — TWO things

**1. A human-readable audit** (in this order):
- **Summary** — counts by severity and a one-line risk read.
- **Bugs** — numbered, ordered high → low. For each: `### N. [severity] short title`
  then bullets: **Block**, **Affects** (dependents), **What's wrong / impact**
  (plain), **Evidence** (`path:line`), **Suggested fix**.

**2. A machine-readable block** — the exact same bugs as JSON in a fenced
```json block, matching this shape (this is the contract the jira-draft step reads):

```json
{
  "repo": "<repo name>",
  "bugs": [
    {
      "id": "B1",
      "title": "short technical title",
      "severity": "high|medium",
      "block": "lib/github.sh",
      "dependents": ["bin/ai-pr-review", "lib/common.sh"],
      "evidence": ["lib/github.sh:39"],
      "impact": "what it causes, in one or two sentences",
      "suggested_fix": "the concrete change",
      "lens": "correctness|security|performance|config",
      "confidence": "confirmed|likely"
    }
  ]
}
```

Keep `id`s stable and unique (B1, B2, …) so they can be referenced later. If there
are no high/medium bugs, say so plainly and emit `{"repo": "<name>", "bugs": []}`.
