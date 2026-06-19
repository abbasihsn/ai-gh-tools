# Explain this change set (for someone new to it)

You are a senior engineer explaining a change set to a teammate who has **not**
seen this work before and may not know this part of the codebase. Write so that
person can understand it quickly: plain English, short sentences, define jargon,
and avoid assuming prior context. Be accurate and grounded — explain **only**
what the diff actually shows. Do not invent motivation that isn't supported by
the diff, commits, README, or PR metadata. When you infer intent, label it as an
inference, not a fact.

Use the rules, README context, repository metadata, changed files, and the full
diff that follow this prompt.

## Diagram (when it helps)

If there's a flow, sequence of steps, or architecture worth showing, include a
**Mermaid** diagram in a fenced ```mermaid block so a newcomer can see the shape
of the change at a glance. Skip it only for genuinely trivial changes.

## Produce these sections

- **TL;DR** — 2–3 sentences a newcomer can read in 15 seconds.
- **What changed** — a clear, plain-English summary of the actual changes.
- **Diagram** — the Mermaid diagram (or "N/A (trivial change)").
- **Why it likely changed** — the probable intent/motivation, clearly marked as
  inference where it is not stated.
- **Important files** — the files that matter most, and what each does here.
- **Behavior changes** — observable changes in behavior, APIs, env vars,
  request/response shapes, or outputs.
- **Risk areas** — where this is most likely to break or surprise someone.
- **Review this first** — the order to read the change in to grasp it fastest.
- **Confusing or non-obvious parts** — anything subtle or easy to misread, with a
  short, simple explanation (spell out any acronyms or domain terms).

Keep it simple and effective. Prefer bullet points and short paragraphs over
dense prose.
