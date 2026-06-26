# Explain this whole project (for someone new to it)

You are a senior engineer onboarding a teammate who has **never** seen this
codebase. Explain the **whole project** so they can find their way around quickly:
plain English, short sentences, define jargon, no assumed context. Be accurate and
grounded — base everything on the files, rules, README, and metadata provided below
and on the live repository you can read. Do not invent features, dependencies, or
history that the code does not show. When you infer intent, label it as an inference.

Use the rules, README context, repository metadata, the project file tree, and the
existing-definitions inventory that follow this prompt. You may read any file in the
repo to confirm details before describing them.

## What is a "block"

Treat the repo as a set of **blocks** — cohesive parts of the system, usually a
top-level directory or a small group of related files (e.g. an entrypoints layer, a
shared library, configuration, tests). Identify the blocks from the file tree, then
explain what each does and how they depend on one another.

## Diagram (required unless trivial)

Include a **Mermaid** diagram (a ```mermaid fenced block) showing the blocks and the
dependency arrows between them (who uses / is based on whom). This is the single most
useful artifact for a newcomer — show the real shape, not an idealized one.

## Produce these sections

- **TL;DR** — 2–3 sentences: what this project is and what it does.
- **How to run it** — the entry points and the main commands/usage, grounded in the
  actual files (e.g. installer, CLI entrypoints, scripts).
- **Blocks** — for each block: its path(s), what it is responsible for, and the key
  files inside it. Keep each to a few lines.
- **Dependency map** — the Mermaid diagram, plus 1–2 sentences naming the core
  dependencies ("X is the engine everything else calls", etc.).
- **Key flows** — 1–3 important end-to-end flows traced through the blocks (e.g.
  "user runs command → entrypoint → library → output"), in plain steps.
- **Where to start reading** — the order to read the code to understand it fastest.
- **Conventions & gotchas** — patterns the project relies on, and anything subtle or
  easy to misread (spell out acronyms and domain terms).

Keep it simple and effective. Prefer bullet points and short paragraphs over dense
prose.
