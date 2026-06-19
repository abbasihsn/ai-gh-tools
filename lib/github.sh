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

# Apply exclude patterns to a unified diff coming from gh.
# Reads the diff on stdin, removes file sections whose path matches any of the
# provided shell glob patterns. Patterns are passed as remaining args.
agh_gh_filter_diff() {
  if [ "$#" -eq 0 ]; then
    cat
    return 0
  fi
  awk -v patterns="$*" '
    BEGIN {
      n = split(patterns, pats, " ")
    }
    function matches(path,   i) {
      for (i = 1; i <= n; i++) {
        # Convert glob to a simple match using shell-style fnmatch via gsub.
        # awk lacks fnmatch; approximate by anchoring and translating * and ?.
        rx = pats[i]
        gsub(/[.[\](){}+^$|]/, "\\\\&", rx)
        gsub(/\*/, ".*", rx)
        gsub(/\?/, ".", rx)
        if (path ~ ("(^|/)" rx "$") || path ~ rx) return 1
      }
      return 0
    }
    /^diff --git / {
      # Path looks like: diff --git a/foo b/foo
      p = $3; sub(/^a\//, "", p)
      skip = matches(p)
    }
    { if (!skip) print }
  '
}
