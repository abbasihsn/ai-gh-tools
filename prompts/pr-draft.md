# Draft a pull request title and description

You are preparing a clean, professional pull request for the change set below.
Base everything **only** on what the diff actually contains plus the README/repo
context provided — do not invent features, tests, issues, or rollout steps that
are not present. Where you infer intent, keep it grounded in the diff.

Read the rules, README context, repository metadata, changed files, and the full
diff that follow this prompt, then produce TWO things:

## 1. Title

A single concise, conventional PR title on one line (follow any team title
format hinted at in the rules/README).

## 2. Description

Fill in the team PR template below. Keep every heading exactly as written.
Rules for filling it in:

- **Description** — replace the guidance bullets with a real, plain-English
  summary of what changed and why.
- **Related Issue (Optional)** — leave the placeholder if no issue is referenced
  in the diff/commits; otherwise link it.
- **Changes Introduced** — replace with a concrete bulleted list of the notable
  changes, grouped logically. Include short code snippets only for genuinely
  complex changes.
- **Type of Change** — keep only the checkboxes that apply and check them
  (`- [x]`); delete the rest, per the template's instruction.
- **Checklist** — keep all items; do not pre-check them (leave `- [ ]`), they are
  for the author to confirm. Preserve the links exactly.
- **Additional Notes** — add deployment/rollback/migration notes if the diff
  implies any; otherwise leave it empty.

Output the title first (prefixed with `Title:`), then a blank line, then the
filled-in template starting at `### Description`. Output nothing else.

---

TEMPLATE TO FILL:

### Description
Briefly describe the changes made in this pull request.

- Explain the motivation behind these changes, highlighting any bug fixes, feature implementations, or improvements.
- If applicable, mention any external libraries or dependencies introduced.

### Related Issue (Optional)

- Link to any related issue(s) in your project tracker (e.g., Jira).

### Changes Introduced

- List the nature of the changes (e.g., bug fix, new function, refactoring).
- Consider including relevant code snippets for clarity, especially for complex changes.

### Type of Change
Please delete options that are not relevant.
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality not to work as expected)
- [ ] This change requires a documentation update

### Checklist

- [ ] [I have performed a self-review of my code.](https://prenuvo.atlassian.net/wiki/spaces/CVT/pages/1845231636/Code+Review)
- [ ] I have commented my code, particularly for refactoring or in hard-to-understand areas.
- [ ] I have updated relevant documentation (if the changes affect existing documentation) such as Confluence.

Optional
- [ ] [I have added unit tests for the Python backend changes (if applicable).](https://prenuvo.atlassian.net/wiki/spaces/CVT/pages/2283438187/Unit+Functional+and+Integration+Testing+Strategy)


### Additional Notes
