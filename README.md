# ai-gh-tools

Private, **local** CLI toolkit that turns a change set (local branch, staged
diff, or GitHub PR) into a ready-to-paste prompt for Cursor or another AI tool.

Most of it generates **review prompts and summaries only** — it does the boring
context gathering (diff, changed files, repo rules, README context, PR metadata)
and hands you a single prompt to paste into your AI tool of choice. One command,
`ai-open-pr`, additionally **commits, pushes, and opens a PR** for you.

> **The three prompt tools never write to GitHub** (no comments, reviews, pushes,
> or commits). The fourth tool, **`ai-open-pr`, does modify your repo and the
> remote** — it confirms before each step. See [Privacy & security](#privacy--security).

## What you get

| Command         | Purpose                                              | Modifies anything? |
| --------------- | ---------------------------------------------------- | ------------------ |
| `ai-pr-review`  | Strict multi-agent code review prompt                | No (read-only)     |
| `ai-explain-pr` | Plain-English explanation of a change set            | No (read-only)     |
| `ai-draft-pr`   | Drafts a PR title + description (fills team template) | No (read-only)     |
| `ai-open-pr`    | Commits, pushes, and **opens** a GitHub PR           | **Yes**            |

The read-only commands can work from:

- a **local branch** vs a base ref (`git diff BASE...HEAD`),
- **staged** changes (`git diff --cached`), or
- a **GitHub PR** via the `gh` CLI (`ai-pr-review` / `ai-explain-pr` only).

`ai-open-pr` always works on the **current branch** vs a base ref.

## Installation

Requirements: `bash`, `git`. For PR mode you also need the
[GitHub CLI](https://cli.github.com/) (`gh`) authenticated (`gh auth login`).
Clipboard support uses `pbcopy` / `wl-copy` / `xclip` / `xsel` / `clip.exe`.

```bash
git clone <your-private-remote>/ai-gh-tools.git
cd ai-gh-tools
./install.sh
```

`install.sh` will:

- symlink the commands into `~/.local/bin`,
- make them executable,
- add `~/.local/bin` to your `PATH` (in `.zshrc` or `.bashrc`) if missing,
- create git aliases (`git ai-review`, `git ai-explain`, `git ai-draft-pr`,
  `git ai-open-pr`).

Open a new shell (or `source ~/.zshrc`) afterwards.

## Command examples

Run these from inside **any** git repo:

```bash
# Review the current branch against origin/main, copy prompt to clipboard
ai-pr-review origin/main --copy

# Review a GitHub PR (and include its existing comments)
ai-pr-review --pr 123 --comments --copy

# Review only staged changes
ai-pr-review --staged --copy

# Include unstaged local edits in a branch review
ai-pr-review origin/main --include-working-tree --copy

# Write a review prompt to a file instead of the clipboard
ai-pr-review origin/main --out /tmp/pr-review.md

# Explain a change set in plain English
ai-explain-pr --pr 123 --copy
ai-explain-pr --staged --copy

# Draft a PR title + description (fills the team template via AI)
ai-draft-pr origin/main --copy
ai-draft-pr --staged --out /tmp/pr-description.md

# Actually open a PR: commit pending work, push, and create it on GitHub
ai-open-pr origin/main             # prompts before commit / push / create
ai-open-pr origin/main --dry-run   # preview only; changes nothing
```

If you omit the base ref, the tools auto-detect one by trying, in order:
`origin/main`, `main`, `origin/develop`, `develop`, `origin/master`, `master`.

### Common options

These apply to the read-only prompt commands (`ai-pr-review`, `ai-explain-pr`,
`ai-draft-pr`). `ai-open-pr` has its own options — see `ai-open-pr --help`.

| Option                   | Commands             | Meaning                                       |
| ------------------------ | -------------------- | --------------------------------------------- |
| `--pr REF`               | review, explain      | Review a GitHub PR (number, URL, or branch)   |
| `--comments`             | review, explain      | Include existing PR comments (needs `--pr`)   |
| `--repo OWNER/REPO`      | review, explain      | Override the GitHub repo for `gh`             |
| `--staged`               | review, explain, draft | Use staged changes                          |
| `--include-working-tree` | review, explain, draft | Also include unstaged changes (local mode)  |
| `--exclude PATTERN`      | review, explain      | Drop matching files from a PR diff (repeat)   |
| `--ticket ID`            | review, explain, draft (& open-pr) | Ticket id; adds a `## Ticket` context block (and `[ID]` to drafted titles) |
| `--copy`                 | review, explain, draft | Copy prompt to clipboard                    |
| `--cursor`               | review, explain, draft | Copy, then open Cursor and paste into chat (macOS) |
| `--cursor-submit`        | review, explain, draft | Like `--cursor`, but also presses Return to send |
| `--out FILE`             | review, explain, draft | Write prompt to a file                      |
| `--no-project-rules`     | review, explain, draft | Skip the target repo's `.cursor/rules`      |
| `--no-tool-rules`        | review, explain, draft | Skip this toolkit's rules                   |
| `--no-readmes`           | review, explain, draft | Skip README context                         |
| `-h`, `--help`           | all                  | Show help                                     |

### Send a prompt straight into Cursor (macOS)

Instead of `--copy` + manual paste, use `--cursor` to copy the prompt and have it
opened and pasted into the Cursor chat automatically:

```bash
ai-pr-review --pr 123 --comments --cursor
ai-explain-pr origin/main --cursor
ai-draft-pr origin/main --cursor-submit   # also presses Return to send it
```

How it works: it copies the prompt, then uses AppleScript (`osascript`) to
activate Cursor, focus the chat (Cmd+L), open a **new chat tab** (Cmd+T), and
paste (Cmd+V). It never sends your code anywhere itself — it just drives the
Cursor app on your machine.

If the pasted text shows up as a context attachment "pill" instead of as text in
the input box (Cursor turns code/log clipboards into attachments on Cmd+V), tell
me and I'll switch the paste to Cmd+Shift+V, which forces it into the input box.

**One-time setup:** macOS will ask to allow your terminal to control the
computer. If pasting doesn't happen, grant it manually under
**System Settings → Privacy & Security → Accessibility** and enable your
terminal app (Terminal/iTerm) or Cursor's integrated terminal. On non-macOS, or
if anything fails, the prompt is still left on your clipboard to paste manually.

## How to review my own PR

```bash
cd ~/code/some-repo
git fetch origin
ai-pr-review origin/main --copy      # or: git ai-review origin/main --copy
```

Paste the prompt into Cursor / your AI tool and read the findings. Nothing is
sent to GitHub.

## How to review someone else's PR

```bash
cd ~/code/some-repo
ai-pr-review --pr 123 --comments --copy
# or against a different repo without checking it out:
ai-pr-review --pr 123 --repo owner/other-repo --copy
```

This uses `gh pr view` / `gh pr diff` (read-only) to fetch the PR. With
`--comments`, existing discussion is included as context for the AI.

> **Note:** `--pr` mode must still be run from inside a git repo, and the
> toolkit rules, project `.cursor/rules`, README context, and repo metadata are
> taken from your **local** working directory — not from the PR's repo. When
> reviewing a PR for a repo you don't have checked out, run the command from a
> checkout of that repo (or pass `--no-project-rules` / `--no-readmes`) so
> unrelated local context doesn't leak into the prompt.

## How to draft a PR description (read-only)

```bash
cd ~/code/some-repo
ai-draft-pr origin/main --copy
```

This produces a prompt that asks an AI to fill the team PR template
([`templates/pr-body.md`](templates/pr-body.md)). Paste it into Cursor, get the
filled-in title + body, and either paste it into GitHub yourself or feed it to
`ai-open-pr --body-file`. `ai-draft-pr` never touches GitHub.

## How to actually open a PR

`ai-open-pr` is the one command that changes things. From your feature branch:

```bash
cd ~/code/some-repo
ai-open-pr origin/main
```

What it does, in order (confirming before each mutating step):

1. **Commits** any uncommitted changes (`git add -A` + `git commit`). Provide the
   message with `-m "..."`, or you'll be prompted, or it auto-generates one.
2. **Pushes** the current branch to the push remote (`git push -u origin HEAD`
   by default; override with `--remote NAME` for fork workflows).
3. **Opens** the PR against the base with `gh pr create`, using the team template
   as the body (pre-filled with the changed-file list). Your `$EDITOR` opens so
   you can edit the body first.

Useful flags:

```bash
ai-open-pr origin/main -m "Add fast resize" --title "Add fast resize" --draft
ai-open-pr origin/main --ticket PROJ-123  # title becomes "[PROJ-123] ...", fills Related Issue
ai-open-pr origin/main --dry-run        # show the plan, change nothing
ai-open-pr origin/main --yes            # non-interactive: skip all prompts
ai-open-pr --body-file /tmp/pr-body.md  # use an AI-filled body from ai-draft-pr
ai-open-pr origin/main --no-edit        # don't open the editor for the body
ai-open-pr upstream/main --remote fork  # base on upstream, push to your 'fork' remote
```

Combined flow (AI-written body, then open the PR):

```bash
ai-draft-pr origin/main --out /tmp/draft.md   # paste into AI, save filled body to /tmp/pr-body.md
ai-open-pr origin/main --body-file /tmp/pr-body.md
```

`ai-open-pr` never force-pushes, never amends, and never bypasses git hooks.

## Custom & repo-specific rules

The prompt always includes this toolkit's shared rules from
[`rules/general.mdc`](rules/general.mdc). You can add focused overlays:

- **Per target repo:** create `rules/<repo-name>.mdc` in this toolkit, where
  `<repo-name>` is the basename of the repo you run the command in. It is
  appended automatically.
- **From the target repo itself:** any `.cursor/rules/*.mdc` in the repo you're
  reviewing is included automatically (disable with `--no-project-rules`).

Root `README.md` plus README files near the changed areas are added as context
too (disable with `--no-readmes`).

## Updating the tools

The commands are symlinks into this repo, so updating is just:

```bash
cd ~/code/ai-gh-tools
git pull --rebase
```

No re-install needed unless `install.sh` itself changed (re-run it if so).

## Privacy & security

- **Three tools are read-only.** `ai-pr-review`, `ai-explain-pr`, and
  `ai-draft-pr` only run read-only git/`gh` commands. They never call
  `gh pr review`, `gh pr comment`, `gh pr merge`, `git push`, or create commits.
- **`ai-open-pr` is the exception.** It intentionally commits, pushes, and opens
  a PR. It confirms before each mutating step (unless `--yes`), supports
  `--dry-run`, and never force-pushes, amends, or skips git hooks.
- **Local-first.** Output goes to stdout, your clipboard, or a file you choose.
  Network access is limited to `gh` (read-only PR fetches, plus `gh pr create`
  for `ai-open-pr`).
- **You control what leaves your machine.** Whatever AI tool you paste a prompt
  into is up to you; mind your diffs for secrets/PII before pasting.
- Use `--exclude PATTERN` (PR mode) to drop noisy or sensitive paths from a diff.

## Repo layout

```
ai-gh-tools/
  bin/            # ai-pr-review, ai-explain-pr, ai-draft-pr, ai-open-pr
  lib/            # shared bash helpers (sourced by bin/)
  prompts/        # the AI instruction templates
  rules/          # general.mdc + optional rules/<repo-name>.mdc overlays
  templates/      # pr-body.md (the team PR template used by ai-open-pr)
  examples/       # sample generated output
  install.sh
  README.md
```
