# Turn audited bugs into clean Jira tickets

You are turning a list of already-found bugs (from `ai-project-audit`, embedded
below as JSON) into **Jira tickets**. Two jobs, in order:

## 1. Validate (final gate — be conservative)

For each bug in the input, **confirm it against the live code** (read the cited
`path:line` and surrounding code). Keep a bug only if it is **clearly real and worth
a ticket**. **Drop** anything that is:
- not reproducible / not actually a bug on a real path,
- already handled elsewhere in the code,
- low-impact, stylistic, or speculative.

It is better to file fewer, solid tickets than to file noise. Briefly list what you
dropped and why, separately from the tickets.

## 2. Draft a humanized ticket for each survivor

Write for a **mixed audience** (PMs and engineers). The **title and description must
be plain language** — no code jargon, no internal symbol names, in the title/summary.
Explain the problem in terms of behavior and impact. Keep the engineer-only details
(file:line) in the Evidence line.

Use **exactly this structure** per ticket:

```
Title: <plain, action-oriented — what to fix and the outcome; no code jargon>

What's wrong:   <1–2 plain sentences: the observable problem>
Why it matters: <the impact on users / the system, plain language>
Where:          <component (the block)> — affects: <dependent blocks>
Suggested fix:  <plain description of the fix; optional but preferred>
Evidence:       <path:line[, path:line]>   (for engineers)
Severity:       High | Medium
```

Guidelines:
- The **Title** is a sentence a non-engineer can understand, e.g.
  "Show the sign-in help message when the wrong account is used" — not
  "Fix `agh_gh_print_identity` set -e abort".
- Map each ticket's **Where / affects** from the bug's `block` / `dependents`.
- Preserve **Severity** from the input unless validation clearly changes it (say so).
- Group the tickets High first, then Medium.

## Output

- A short **Validation summary** (kept N, dropped M with one-line reasons).
- The **tickets**, one per kept bug, in the structure above.

Base everything on the embedded bug JSON and the live code. Do not invent new bugs
here — this step only validates and rewrites; new discovery belongs to the audit.
