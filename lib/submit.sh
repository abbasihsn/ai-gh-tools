#!/usr/bin/env bash
# lib/submit.sh — WRITE operations used by ai-open-pr.
#
# Unlike the rest of this toolkit, ai-open-pr intentionally mutates state: it
# can commit, push, and open a GitHub PR. Those actions live here so the
# read-only helpers (git.sh / github.sh) stay strictly read-only. Every
# mutating action is gated behind an explicit confirmation (unless --yes) and
# is skipped entirely in --dry-run mode.

# True if the working tree has any changes (staged, unstaged, or untracked).
agh_has_uncommitted() {
  [ -n "$(git status --porcelain 2>/dev/null)" ]
}

# Prompt for y/N confirmation. Returns 0 on yes. Auto-yes when AGH_ASSUME_YES=1.
# In non-interactive shells without --yes, defaults to NO for safety.
#   $1 = prompt text
agh_confirm() {
  local prompt="$1"
  if [ "${AGH_ASSUME_YES:-}" = "1" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    agh_warn "non-interactive shell and --yes not given; refusing '$prompt'."
    return 1
  fi
  local reply
  printf '%s [y/N] ' "$prompt" >&2
  read -r reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Turn a branch name into a human-ish title, e.g. feat/add-fast-resize ->
# "Add fast resize".
#   $1 = branch name
agh_humanize_branch() {
  local b="$1"
  # Drop a leading type/scope segment like feat/, fix/, chore/.
  b="${b##*/}"
  # Replace separators with spaces.
  b="${b//-/ }"
  b="${b//_/ }"
  # Capitalize the first character portably (BSD sed has no \U; bash 3.2 has
  # no ${var^}). Fall back gracefully on an empty string.
  [ -n "$b" ] || return 0
  local first rest
  first="$(printf '%s' "$b" | cut -c1 | tr '[:lower:]' '[:upper:]')"
  rest="$(printf '%s' "$b" | cut -c2-)"
  printf '%s%s' "$first" "$rest"
}

# Derive a default PR title: the single commit subject if exactly one commit is
# ahead of base, otherwise a humanized branch name.
#   $1 = base ref, $2 = branch
agh_default_pr_title() {
  local base="$1" branch="$2"
  local n
  n="$(git rev-list --count "${base}..HEAD" 2>/dev/null || echo 0)"
  if [ "$n" = "1" ]; then
    git log -1 --format='%s' 2>/dev/null
  else
    agh_humanize_branch "$branch"
  fi
}

# A generated commit message when the user supplies none (auto/--yes path).
agh_default_commit_message() {
  local files count
  count="$(git diff --cached --name-only | wc -l | tr -d ' ')"
  # Join the first few file names with ", " portably.
  files="$(git diff --cached --name-only | head -3 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  if [ -z "$files" ]; then
    return 0
  fi
  if [ "$count" -gt 3 ]; then
    printf 'Update %s (+%s more files)' "$files" "$((count - 3))"
  else
    printf 'Update %s' "$files"
  fi
}

# Append a git-derived "Changes Introduced" hint into a copy of the template,
# so even a non-AI body has the real change list. Reads template path, writes a
# new body file path on stdout.
#   $1 = template file, $2 = base ref (or "" for staged), $3 = out file
agh_prefill_body() {
  local template="$1" base="$2" out="$3"
  local changes
  if [ -n "$base" ]; then
    changes="$(git diff --name-status "${base}...HEAD" 2>/dev/null | sed 's/^/- /')"
  else
    changes="$(git diff --cached --name-status 2>/dev/null | sed 's/^/- /')"
  fi
  # Insert the file list right under the "### Changes Introduced" heading.
  awk -v changes="$changes" '
    { print }
    /^### Changes Introduced$/ {
      print ""
      print "<!-- auto-filled from the diff; edit as needed -->"
      print changes
    }
  ' "$template" >"$out"
}

# Open $EDITOR (or a sensible fallback) on a file for the user to edit.
#   $1 = file path
agh_edit_file() {
  local file="$1"
  local ed="${EDITOR:-${VISUAL:-}}"
  if [ -z "$ed" ]; then
    if command -v nano >/dev/null 2>&1; then ed=nano
    elif command -v vim >/dev/null 2>&1; then ed=vim
    elif command -v vi >/dev/null 2>&1; then ed=vi
    else
      agh_warn "no editor found (\$EDITOR unset); using the body as-is."
      return 0
    fi
  fi
  "$ed" "$file" </dev/tty >/dev/tty 2>&1 || agh_warn "editor exited non-zero; using the body as-is."
}
