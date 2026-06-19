#!/usr/bin/env bash
# lib/github.sh — read-only wrappers around the GitHub CLI (`gh`).
#
# Sourced by entrypoints. These functions ONLY read PR data; they never call
# `gh pr review`, `gh pr comment`, `gh pr merge`, or anything that mutates the
# remote. The PR reference can be a number, URL, or branch name.

# Ensure gh is available; used by PR mode only.
agh_require_gh() {
  agh_require_cmd gh "Install the GitHub CLI from https://cli.github.com/ to use --pr mode."
}

# Build the shared `--repo` argument array for gh, if an override was given.
# Usage: read into an array, e.g. `local args=(); agh_gh_repo_args args "$repo"`
# We instead expose AGH_GH_REPO_ARGS as a global array for simplicity.
AGH_GH_REPO_ARGS=()
agh_gh_set_repo() {
  local repo="${1:-}"
  AGH_GH_REPO_ARGS=()
  if [ -n "$repo" ]; then
    AGH_GH_REPO_ARGS=(--repo "$repo")
  fi
}

# Call sites below expand AGH_GH_REPO_ARGS as
#   "${AGH_GH_REPO_ARGS[@]+"${AGH_GH_REPO_ARGS[@]}"}"
# which is the portable idiom that stays safe under `set -u` on bash 3.2
# (macOS default) when the array is empty, without injecting an empty argument.

# True (exit 0) if the PR can actually be fetched with the current gh auth/repo.
#   $1 = pr ref
agh_gh_pr_accessible() {
  local pr="$1"
  gh pr view "$pr" "${AGH_GH_REPO_ARGS[@]+"${AGH_GH_REPO_ARGS[@]}"}" --json number >/dev/null 2>&1
}

# Fetch PR metadata as formatted text (title, author, state, branches, body).
#   $1 = pr ref (number/url/branch)
agh_gh_pr_view() {
  local pr="$1"
  gh pr view "$pr" "${AGH_GH_REPO_ARGS[@]+"${AGH_GH_REPO_ARGS[@]}"}" \
    --json number,title,author,state,isDraft,baseRefName,headRefName,url,additions,deletions,changedFiles,labels,body \
    --template '{{- printf "PR #%v: %s\n" .number .title -}}
{{- printf "URL: %s\n" .url -}}
{{- printf "Author: %s\n" .author.login -}}
{{- printf "State: %s (draft: %v)\n" .state .isDraft -}}
{{- printf "Base: %s  Head: %s\n" .baseRefName .headRefName -}}
{{- printf "Changes: +%v -%v across %v files\n" .additions .deletions .changedFiles -}}
{{- if .labels }}{{- printf "Labels:" -}}{{- range .labels }}{{- printf " %s" .name -}}{{- end }}{{- printf "\n" -}}{{- end -}}
{{- printf "\n--- PR description ---\n%s\n" .body -}}' 2>/dev/null
}

# Raw patch diff for a PR.
#   $1 = pr ref
agh_gh_pr_diff() {
  local pr="$1"
  gh pr diff "$pr" "${AGH_GH_REPO_ARGS[@]+"${AGH_GH_REPO_ARGS[@]}"}" --patch 2>/dev/null
}

# Changed file names for a PR.
#   $1 = pr ref
agh_gh_pr_changed_files() {
  local pr="$1"
  gh pr diff "$pr" "${AGH_GH_REPO_ARGS[@]+"${AGH_GH_REPO_ARGS[@]}"}" --name-only 2>/dev/null
}

# Existing PR review/issue comments, formatted for context.
#   $1 = pr ref
agh_gh_pr_comments() {
  local pr="$1"
  gh pr view "$pr" "${AGH_GH_REPO_ARGS[@]+"${AGH_GH_REPO_ARGS[@]}"}" \
    --json comments \
    --template '{{- if .comments -}}{{- range .comments -}}
{{- printf "## %s (%s)\n%s\n\n" .author.login .createdAt .body -}}
{{- end -}}{{- else -}}{{- printf "(no comments)\n" -}}{{- end -}}' 2>/dev/null
}

# Shared awk snippet: defines glob2rx() and matches(path). Callers populate the
# `pats[1..n]` array (read from a one-pattern-per-line file in their BEGIN block)
# and then call matches(). Reading patterns from a file — rather than joining on
# spaces — keeps patterns that contain spaces intact. Matching is anchored so a
# pattern only matches a full path or a complete trailing path segment (e.g.
# `foo` matches `foo` and `a/foo` but not `foobar`).
_AGH_GLOB_AWK='
function glob2rx(g,   rx) {
  rx = g
  gsub(/[.[\](){}+^$|]/, "\\\\&", rx)
  gsub(/\*/, ".*", rx)
  gsub(/\?/, ".", rx)
  return rx
}
function matches(path,   i, rx) {
  for (i = 1; i <= n; i++) {
    rx = glob2rx(pats[i])
    if (path ~ ("^" rx "$") || path ~ ("(^|/)" rx "$")) return 1
  }
  return 0
}
'

# Write the given patterns (one per line) to a fresh temp file and print its
# path. The file is registered for cleanup via agh_mktemp.
_agh_write_pattern_file() {
  local pat_file
  pat_file="$(agh_mktemp)"
  printf '%s\n' "$@" >"$pat_file"
  printf '%s' "$pat_file"
}

# Apply exclude patterns to a unified diff coming from gh.
# Reads the diff on stdin, removes file sections whose path matches any of the
# provided shell glob patterns. Patterns are passed as remaining args.
agh_gh_filter_diff() {
  if [ "$#" -eq 0 ]; then
    cat
    return 0
  fi
  local pat_file
  pat_file="$(_agh_write_pattern_file "$@")"
  awk -v pf="$pat_file" "$_AGH_GLOB_AWK"'
    BEGIN {
      n = 0
      while ((getline p < pf) > 0) { if (p != "") pats[++n] = p }
      close(pf)
    }
    /^diff --git / {
      # Path looks like: diff --git a/foo b/foo
      # Note: $3 is the first whitespace-delimited token, so paths containing
      # spaces are not matched precisely here (rare for excludable paths).
      p = $3; sub(/^a\//, "", p)
      skip = matches(p)
    }
    { if (!skip) print }
  '
}

# Apply the same exclude patterns to a newline-delimited list of file paths on
# stdin (e.g. the changed-file list), dropping any path that matches a pattern.
# Keeps the changed-file list consistent with the filtered diff.
agh_gh_filter_file_list() {
  if [ "$#" -eq 0 ]; then
    cat
    return 0
  fi
  local pat_file
  pat_file="$(_agh_write_pattern_file "$@")"
  awk -v pf="$pat_file" "$_AGH_GLOB_AWK"'
    BEGIN {
      n = 0
      while ((getline p < pf) > 0) { if (p != "") pats[++n] = p }
      close(pf)
    }
    { if ($0 != "" && !matches($0)) print }
  '
}
