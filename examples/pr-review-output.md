<!--
Sample output of:  ai-pr-review main
This is exactly what the tool prints/copies — a single self-contained prompt
(task instructions + rules + README context + metadata + diff) ready to paste
into Cursor or another AI tool. Repo paths below are illustrative.
-->

# Multi-agent pull request review

You are a panel of strict, senior reviewers performing a thorough review of the
change set provided below. Be strict but fair. Review **only** the changes
introduced by the diff — do not invent context, files, or requirements that are
not present. When something is ambiguous, **state the assumption** explicitly
instead of guessing silently.

Read the rules, README context, repository metadata, changed files, and the
full diff that follow this prompt. Ground every finding in specific files and
line references from the diff.

Run each of the following reviewer roles in turn. For every role, give concrete
findings (with file + hunk references) or explicitly say "no issues found".

## Reviewer roles

1. **Architecture reviewer** — module boundaries, responsibilities, coupling,
   reuse vs. copy-paste, placement of shared logic, naming of public APIs.
2. **Correctness reviewer** — logic bugs, edge cases, off-by-one, error paths,
   concurrency, data validation, backward compatibility.
3. **Python typing / model reviewer** — explicit types on public surfaces,
   `dict[str, Any]` / `Mapping` / `TypedDict` usage, Pydantic v2 patterns,
   discriminated/validated fields, `model_dump()` over hand-built dicts.
4. **Logging / tracing / security reviewer** — structured logging, correct log
   levels, no silent exception swallowing, no secrets/PHI/PII in logs, input
   validation, injection and auth concerns.
5. **Config / I/O / DevOps reviewer** — hardcoded operational values that should
   be env/config, timeouts/retries/limits, client typing, secrets handling,
   Dockerfiles, infra, and deploy concerns.
6. **Testing / CI reviewer** — new/changed behavior covered by deterministic
   tests, fixtures, pytest config pointing at real paths, CI implications.
7. **Documentation / README reviewer** — when behavior, env vars, request/
   response shape, deployment, or run/test commands change, are the relevant
   `README.md` files (root and/or beside the touched code) updated?

## Required output sections

After the role-by-role findings, produce these sections:

- **Merge risk** — `low` / `medium` / `high`, with a one-line justification.
- **Must-fix items** — numbered, blocking issues that should be addressed before
  merge. Empty list if none.
- **Should-fix / nice-to-have** — non-blocking improvements.
- **Open questions / assumptions** — anything you assumed or that needs author
  clarification.
- **Reviewer-ready GitHub comments** — a list of copy-pasteable review comments.
  For each: the file path, a line/hunk anchor, and the comment body, phrased as
  a real reviewer would write it. Do **not** post these anywhere; just output
  the text.

Keep it concise and skimmable. Prefer bullet points over prose.

## Toolkit review rules (general)

---
description: General AI review standards for ai-gh-tools (always on)
alwaysApply: true
---

# General review standards

These are the default, always-on standards applied by the `ai-gh-tools`
commands. They tell the AI **how** to review a change set. Repo-specific
overlays may be added as `rules/<repo-name>.mdc` and the target repo's own
`.cursor/rules/*.mdc` are included when present.

## Stance

- Be **strict but fair**. Flag real problems; don't nitpick style that tooling
  already enforces.
- Review **only the changes introduced by the diff**. Do not review unchanged
  code unless the diff clearly breaks it.
- **No invented context.** Do not assume files, requirements, tests, or
  behavior that are not present in the provided diff and context.
- **Identify assumptions explicitly.** When something is ambiguous, state the
  assumption you are making rather than guessing silently.

## What to check

- **Docs** — when behavior, env vars, request/response shapes, deployment, or
  run/test commands change, the relevant `README.md` (root and/or beside the
  touched code) must be updated. Out-of-date docs count as a defect.
- **Tests** — non-trivial and shared logic should have or extend deterministic
  tests. Flag missing coverage for new behavior and brittle/non-deterministic
  tests.
- **Security** — no secrets in source; no PHI/PII, secrets, or tokens in logs;
  validate external input at the boundary; watch for injection and auth gaps.
- **Logging** — structured logging with sensible, consistent levels; no silent
  exception swallowing (`except Exception` needs a stated reason).
- **Hardcoded config** — operational/environment-specific values (URLs,
  timeouts, retries, limits, bucket/queue names, regions, feature flags) belong
  in env/config, not as buried literals. Named constants are fine only for
  values fixed by an external standard.
- **Error handling** — catch specific errors first; preserve context when
  re-raising; return clear, typed error shapes.
- **Typing and public APIs** — explicit types on public surfaces; prefer
  `dict[str, Any]` / `Mapping[str, Any]` / `TypedDict` over bare `dict` for
  JSON-like data; public classes/methods need accurate docstrings; names should
  not mislead about I/O, side effects, or mutability.

## Output discipline

- Ground every finding in a specific file and hunk from the diff.
- Separate **must-fix** (blocking) from **should-fix** (non-blocking).
- Keep findings concise and skimmable.


## README context

### README.md

# imaging-pipelines

Image processing pipelines. See `imaging/steps/README.md` for step docs.

## Running

    poetry run python -m imaging.run


### imaging/steps/README.md

# Steps

Each step reads from S3 and writes results back. Configure via env vars.


## Repository metadata

- name: imaging-pipelines
- root: /Users/you/code/imaging-pipelines
- branch: feat/configurable-timeout
- HEAD: 0fe9e38

## Change set (local branch)

- base=main merge-base=ce234b42bca5 commits-ahead=1
- commits in range:
  - 0fe9e38 support non-square resize and add logging

## Changed files

- imaging/steps/resize.py

## Diff stat

```
 imaging/steps/resize.py | 14 ++++++++++++--
 1 file changed, 12 insertions(+), 2 deletions(-)
```

## Full diff

```diff
diff --git a/imaging/steps/resize.py b/imaging/steps/resize.py
index 09035f8..1eec02c 100644
--- a/imaging/steps/resize.py
+++ b/imaging/steps/resize.py
@@ -1,2 +1,12 @@
-def resize(image, width):
-    return image.resize((width, width))
+import logging
+from typing import Any
+
+logger = logging.getLogger("imaging.steps.resize")
+
+DEFAULT_TIMEOUT = 30
+
+
+def resize(image: Any, width: int, height: int | None = None) -> Any:
+    height = height or width
+    logger.info("resizing image to %sx%s", width, height)
+    return image.resize((width, height))

```
