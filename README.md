# ai-gh-tools

Private, **local** CLI toolkit that turns a change set (local branch, staged
diff, or GitHub PR) into a ready-to-paste prompt for Cursor or another AI tool.

It generates **review prompts and summaries only**. It does the boring context
gathering — diff, changed files, repo rules, README context, PR metadata — and
hands you a single prompt you can paste into your AI tool of choice.

> **These tools never write to GitHub.** No comments, no reviews, no pushes, no
> commits. All logic stays on your machine. See [Privacy & security](#privacy--security).

## What you get

| Command         | Purpose                                                        |
| --------------- | ------------------------------------------------------------- |
| `ai-pr-review`  | Strict multi-agent code review prompt                          |
| `ai-explain-pr` | Plain-English explanation of a change set                     |
| `ai-create-pr`  | Clean GitHub PR description from your branch diff              |

Each command can read from:

- a **local branch** vs a base ref (`git diff BASE...HEAD`),
- **staged** changes (`git diff --cached`), or
- a **GitHub PR** via the `gh` CLI (`ai-pr-review` / `ai-explain-pr` only).

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
- create git aliases (`git ai-review`, `git ai-explain`, `git ai-create-pr`).

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

# Generate a PR description from the branch diff
ai-create-pr origin/main --copy
ai-create-pr --staged --out /tmp/pr-description.md
```

If you omit the base ref, the tools auto-detect one by trying, in order:
`origin/main`, `main`, `origin/develop`, `develop`, `origin/master`, `master`.

### Common options

| Option                   | Commands            | Meaning                                       |
| ------------------------ | ------------------- | --------------------------------------------- |
| `--pr REF`               | review, explain     | Review a GitHub PR (number, URL, or branch)   |
| `--comments`             | review, explain     | Include existing PR comments (needs `--pr`)   |
| `--repo OWNER/REPO`      | review, explain     | Override the GitHub repo for `gh`             |
| `--staged`               | all                 | Use staged changes                            |
| `--include-working-tree` | all                 | Also include unstaged changes (local mode)    |
| `--exclude PATTERN`      | review, explain     | Drop matching files from a PR diff (repeat)   |
| `--copy`                 | all                 | Copy prompt to clipboard                      |
| `--out FILE`             | all                 | Write prompt to a file                        |
| `--no-project-rules`     | all                 | Skip the target repo's `.cursor/rules`        |
| `--no-tool-rules`        | all                 | Skip this toolkit's rules                     |
| `--no-readmes`           | all                 | Skip README context                           |
| `-h`, `--help`           | all                 | Show help                                     |

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

## How to generate a PR description

```bash
cd ~/code/some-repo
ai-create-pr origin/main --copy
```

Paste the result into the GitHub "Open a pull request" body. You decide whether
to actually open the PR — the tool only drafts the text.

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

- **Read-only by design.** The scripts only run read-only git/`gh` commands.
  They never call `gh pr review`, `gh pr comment`, `gh pr merge`, `git push`, or
  create commits.
- **Local-first.** Output goes to stdout, your clipboard, or a file you choose.
  The tools themselves make no network calls beyond `gh`'s read-only PR fetches
  in `--pr` mode.
- **You control what leaves your machine.** Whatever AI tool you paste the
  prompt into is up to you; mind your diffs for secrets/PII before pasting.
- Use `--exclude PATTERN` (PR mode) to drop noisy or sensitive paths from a diff.

## Repo layout

```
ai-gh-tools/
  bin/            # the three commands
  lib/            # shared bash helpers (sourced by bin/)
  prompts/        # the AI instruction templates
  rules/          # general.mdc + optional rules/<repo-name>.mdc overlays
  examples/       # sample generated output
  install.sh
  README.md
```
