#!/usr/bin/env bash
# lib/git.sh — thin wrappers around local git for diff/changed-file gathering.
#
# Sourced by entrypoints. All functions are read-only with respect to the
# target repo: they never commit, stage, push, or otherwise mutate state.

# Print the merge-base between BASE and HEAD, or empty if none.
agh_git_merge_base() {
  local base="$1"
  git merge-base "$base" HEAD 2>/dev/null
}

# Three-dot diff of a local branch against its base: changes introduced on
# HEAD since it diverged from BASE. Optionally include working-tree changes.
#   $1 = base ref
#   $2 = include working tree ("1" to also show unstaged changes)
agh_git_branch_diff() {
  local base="$1"
  local include_wt="${2:-}"
  if [ "$include_wt" = "1" ]; then
    # Committed changes since base, plus uncommitted (staged + unstaged).
    git diff "${base}...HEAD"
    git diff HEAD
  else
    git diff "${base}...HEAD"
  fi
}

# Diff stat for a local branch against base.
agh_git_branch_diffstat() {
  local base="$1"
  git diff --stat "${base}...HEAD" 2>/dev/null
}

# Names of files changed on the branch relative to base.
agh_git_branch_changed_files() {
  local base="$1"
  git diff --name-only "${base}...HEAD" 2>/dev/null
}

# Staged changes (git diff --cached).
agh_git_staged_diff() {
  git diff --cached
}

agh_git_staged_diffstat() {
  git diff --cached --stat 2>/dev/null
}

agh_git_staged_changed_files() {
  git diff --cached --name-only 2>/dev/null
}

# True (exit 0) if there are staged changes.
agh_git_has_staged() {
  ! git diff --cached --quiet 2>/dev/null
}

# A short, human-readable description of the base..HEAD range for metadata.
#   $1 = base ref
agh_git_range_summary() {
  local base="$1"
  local mb
  mb="$(agh_git_merge_base "$base")"
  local ahead behind
  ahead="$(git rev-list --count "${base}..HEAD" 2>/dev/null || echo '?')"
  printf 'base=%s merge-base=%s commits-ahead=%s' \
    "$base" "${mb:0:12}" "$ahead"
}

# List of commit subjects on the branch since base (most recent first).
agh_git_branch_commits() {
  local base="$1"
  git log --no-merges --format='- %h %s' "${base}..HEAD" 2>/dev/null
}
