#!/usr/bin/env bash
# lib/context.sh — assemble the prompt context blocks.
#
# Sourced by entrypoints. Every function prints a Markdown-friendly section to
# stdout. The entrypoints concatenate these into a single prompt and then
# deliver it (stdout / --out / --copy). Nothing here mutates any repo.

# Emit the toolkit prompt file (the task instructions for the AI).
#   $1 = prompt file name under prompts/ (e.g. pr-review.md)
agh_print_toolkit_prompt() {
  local name="$1"
  local path="$AGH_TOOLKIT_DIR/prompts/$name"
  if [ -f "$path" ]; then
    cat "$path"
  else
    agh_warn "toolkit prompt '$name' not found at $path"
  fi
}

# Emit the toolkit's shared rules plus any repo-specific overlay rule.
#   $1 = repo name (used to look up rules/<repo-name>.mdc)
#   honors AGH_NO_TOOL_RULES=1 to skip entirely.
agh_print_toolkit_rules() {
  local repo_name="${1:-}"
  [ "${AGH_NO_TOOL_RULES:-}" = "1" ] && return 0

  local general="$AGH_TOOLKIT_DIR/rules/general.mdc"
  local printed=0
  if [ -f "$general" ]; then
    printf '\n## Toolkit review rules (general)\n\n'
    cat "$general"
    printf '\n'
    printed=1
  fi

  if [ -n "$repo_name" ]; then
    local repo_rule="$AGH_TOOLKIT_DIR/rules/${repo_name}.mdc"
    if [ -f "$repo_rule" ]; then
      printf '\n## Toolkit review rules (%s)\n\n' "$repo_name"
      cat "$repo_rule"
      printf '\n'
      printed=1
    fi
  fi

  : "$printed"
  return 0
}

# Emit the target repo's own .cursor/rules/*.mdc files, if present.
#   $1 = repo root
#   honors AGH_NO_PROJECT_RULES=1 to skip.
agh_print_project_rules() {
  local root="${1:-}"
  [ "${AGH_NO_PROJECT_RULES:-}" = "1" ] && return 0
  [ -z "$root" ] && return 0

  local rules_dir="$root/.cursor/rules"
  [ -d "$rules_dir" ] || return 0

  local found=0
  local f
  # Use a glob; nullglob-safe via the for/test pattern.
  for f in "$rules_dir"/*.mdc; do
    [ -f "$f" ] || continue
    if [ "$found" -eq 0 ]; then
      printf '\n## Project rules (.cursor/rules)\n'
      found=1
    fi
    printf '\n### %s\n\n' "${f#"$root"/}"
    cat "$f"
    printf '\n'
  done
}

# Emit README context: root README plus READMEs near changed files.
#   $1 = repo root
#   $2 = path to a file containing the list of changed files (one per line)
#   honors AGH_NO_READMES=1 to skip.
agh_print_readmes() {
  local root="${1:-}"
  local changed_files="${2:-}"
  [ "${AGH_NO_READMES:-}" = "1" ] && return 0
  [ -z "$root" ] && return 0

  local -a readmes=()
  local seen=" "

  _agh_add_readme() {
    local p="$1"
    [ -f "$p" ] || return 0
    case "$seen" in
      *" $p "*) return 0 ;;
    esac
    seen="$seen$p "
    readmes+=("$p")
  }

  # Root README: pick the first existing variant (avoids duplicates on
  # case-insensitive filesystems where README.md == readme.md).
  local r
  for r in README.md README.MD readme.md README.rst README; do
    if [ -f "$root/$r" ]; then
      _agh_add_readme "$root/$r"
      break
    fi
  done

  # READMEs in the directories of changed files (and their parents up to root).
  if [ -n "$changed_files" ] && [ -f "$changed_files" ]; then
    local rel dir
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      dir="$root/$(dirname "$rel")"
      # Walk up from the file's dir to the repo root.
      while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        _agh_add_readme "$dir/README.md"
        [ "$dir" = "$root" ] && break
        dir="$(dirname "$dir")"
      done
    done <"$changed_files"
  fi

  [ "${#readmes[@]}" -eq 0 ] && return 0

  printf '\n## README context\n'
  local path
  for path in "${readmes[@]}"; do
    printf '\n### %s\n\n' "${path#"$root"/}"
    cat "$path"
    printf '\n'
  done
}

# Generic repo metadata block.
#   $1 = repo root, $2 = repo name
agh_print_repo_metadata() {
  local root="$1"
  local name="$2"
  printf '\n## Repository metadata\n\n'
  printf -- '- name: %s\n' "$name"
  printf -- '- root: %s\n' "$root"
  printf -- '- branch: %s\n' "$(agh_current_branch)"
  printf -- '- HEAD: %s\n' "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
}

# Local branch metadata block.
#   $1 = base ref
agh_print_local_metadata() {
  local base="$1"
  printf '\n## Change set (local branch)\n\n'
  printf -- '- %s\n' "$(agh_git_range_summary "$base")"
  local commits
  commits="$(agh_git_branch_commits "$base")"
  if [ -n "$commits" ]; then
    printf -- '- commits in range:\n'
    printf '%s\n' "$commits" | sed 's/^/  /'
  fi
}

# Staged metadata block.
agh_print_staged_metadata() {
  printf '\n## Change set (staged)\n\n'
  printf -- '- mode: staged changes (git diff --cached)\n'
  printf -- '- branch: %s\n' "$(agh_current_branch)"
}
