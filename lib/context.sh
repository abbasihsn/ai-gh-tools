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

# Emit the target repo's own rule files, in every format Cursor / Claude Code
# load natively, so the review honors the repo's standards regardless of which
# tool runs it — and so each isolated --deep subagent sees them too (subagents
# don't reliably inherit a tool's auto-loaded rules; the context file is the
# guaranteed channel). Sources, in order:
#   - .cursor/rules/**/*.mdc  (recursive; Cursor project rules)
#   - .cursorrules            (legacy single-file Cursor rules)
#   - CLAUDE.md               (Claude Code project rules)
#   - AGENTS.md               (cross-agent rules)
#   $1 = repo root
#   honors AGH_NO_PROJECT_RULES=1 to skip.
agh_print_project_rules() {
  local root="${1:-}"
  [ "${AGH_NO_PROJECT_RULES:-}" = "1" ] && return 0
  [ -z "$root" ] && return 0

  local -a rule_files=()
  local seen=" "

  # Add a file once (dedup guards case-insensitive filesystems and repeats).
  _agh_add_rule_file() {
    local p="$1"
    [ -f "$p" ] || return 0
    case "$seen" in
      *" $p "*) return 0 ;;
    esac
    seen="$seen$p "
    rule_files+=("$p")
  }

  # Cursor project rules, recursively. Use find because bash 3.2 (macOS default)
  # has no globstar; sort for stable, deterministic ordering.
  local rules_dir="$root/.cursor/rules"
  if [ -d "$rules_dir" ]; then
    local f
    while IFS= read -r f; do
      _agh_add_rule_file "$f"
    done < <(find "$rules_dir" -type f -name '*.mdc' 2>/dev/null | sort)
  fi

  # Single-file and cross-agent rule formats.
  _agh_add_rule_file "$root/.cursorrules"
  _agh_add_rule_file "$root/CLAUDE.md"
  _agh_add_rule_file "$root/AGENTS.md"

  [ "${#rule_files[@]}" -eq 0 ] && return 0

  printf '\n## Project rules (repo-defined)\n'
  local path
  for path in "${rule_files[@]}"; do
    printf '\n### %s\n\n' "${path#"$root"/}"
    cat "$path"
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
    local rel dir reldir
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      # dirname returns "." for a repo-root file; map that to $root directly so
      # the path matches the root-README entry already in `seen` (otherwise we
      # would add "$root/./README.md" and print the root README twice).
      reldir="$(dirname "$rel")"
      if [ "$reldir" = "." ]; then
        dir="$root"
      else
        dir="$root/$reldir"
      fi
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

# Normalize a user-supplied cap (env var) to a positive integer, falling back to
# the given default. Guards against non-numeric / zero / negative values, which
# would otherwise make `head -n "$cap"` fail and abort the run under `set -e`.
#   $1 = raw value   $2 = default
_agh_cap() {
  case "$1" in
    ''|*[!0-9]*) printf '%s' "$2" ;;
    *) if [ "$1" -gt 0 ]; then printf '%s' "$1"; else printf '%s' "$2"; fi ;;
  esac
}

# Whole-project file inventory: every tracked file, with a per-top-level-block
# count and the full list (capped). Gives the AI the shape of the codebase for the
# project explain/audit commands, and the block list the audit selection is built
# from. Only meaningful in whole-project mode.
#   $1 = repo root
#   AGH_TREE_CAP caps the number of listed files (default 400).
agh_print_file_tree() {
  local root="${1:-}"
  [ -z "$root" ] && return 0
  command -v git >/dev/null 2>&1 || return 0

  local tmp
  tmp="$(agh_mktemp)"
  agh_git_all_files "$root" >"$tmp" || true
  [ -s "$tmp" ] || return 0

  local total cap
  total="$(wc -l <"$tmp" | tr -d ' ')"
  cap="$(_agh_cap "${AGH_TREE_CAP:-}" 400)"

  printf '\n## Project files (whole repo)\n\n'
  printf -- '- tracked files: %s\n' "$total"

  printf '\n### Files per top-level block\n\n'
  printf '```\n'
  # Count files under each top-level path segment ("(root files)" for top-level
  # files), highest count first. awk assoc arrays are bash-3.2 safe.
  awk -F/ '{ if (NF > 1) c[$1]++; else c["(root files)"]++ }
           END { for (k in c) printf "%6d  %s\n", c[k], k }' "$tmp" | sort -rn
  printf '```\n'

  printf '\n### File list\n\n'
  printf '```\n'
  head -n "$cap" "$tmp"
  if [ "$total" -gt "$cap" ]; then
    printf '... (%s more files truncated; raise AGH_TREE_CAP to see more)\n' "$((total - cap))"
  fi
  printf '```\n'
}

# Inventory of existing function/class/method definitions across the repo, so a
# reviewer can detect duplication against code that is NOT in the diff (i.e. what
# already exists on the base/main). Local checkout is the source of truth, so
# this is only meaningful in local/staged mode.
#   $1 = repo root
#   Opt-in: only runs when AGH_WITH_SYMBOLS=1 (the --symbols flag). It's a
#   fallback for non-agentic AI tools; in Cursor, prefer letting the AI explore
#   the codebase directly. AGH_SYMBOLS_CAP caps the number of lines.
agh_print_symbol_inventory() {
  local root="${1:-}"
  [ "${AGH_WITH_SYMBOLS:-}" = "1" ] || return 0
  [ -z "$root" ] && return 0
  command -v git >/dev/null 2>&1 || return 0

  local cap
  cap="$(_agh_cap "${AGH_SYMBOLS_CAP:-}" 500)"
  # Definition-like lines across common languages (captures methods via the
  # leading-whitespace allowance, e.g. `def` inside a class). `function` also
  # covers the `function name` shell style.
  local kw_pattern='^[[:space:]]*(export[[:space:]]+)?(public[[:space:]]+|private[[:space:]]+)?(async[[:space:]]+)?(def|class|func|function|module|interface|type|struct|trait|enum)[[:space:]]+[A-Za-z_]'
  # POSIX-shell function defs (`name() {`) have no leading keyword, so they're
  # matched separately and ONLY in shell files. Requiring the opening brace keeps
  # bare call sites (`foo()`) in any language out of the inventory.
  local sh_pattern='^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{'

  local tmp
  tmp="$(agh_mktemp)"
  ( cd "$root" && git grep -nE "$kw_pattern" -- \
      '*.py' '*.pyi' '*.js' '*.jsx' '*.ts' '*.tsx' '*.go' '*.rb' '*.rs' \
      '*.java' '*.kt' '*.cs' '*.php' '*.scala' '*.swift' \
      '*.sh' '*.bash' 2>/dev/null ) >"$tmp" || true
  ( cd "$root" && git grep -nE "$sh_pattern" -- \
      '*.sh' '*.bash' 2>/dev/null ) >>"$tmp" || true
  [ -s "$tmp" ] || return 0

  local total
  total="$(wc -l <"$tmp" | tr -d ' ')"
  printf '\n## Existing definitions (for duplication / reuse checks)\n\n'
  printf 'Functions/classes/methods already present in the repository (not '
  printf 'necessarily in this diff). Cross-check new code against these and flag '
  printf 'anything that duplicates an existing equivalent (cite its path:line).\n\n'
  printf '```\n'
  head -n "$cap" "$tmp"
  if [ "$total" -gt "$cap" ]; then
    printf '... (%s more definitions truncated; raise AGH_SYMBOLS_CAP to see more)\n' "$((total - cap))"
  fi
  printf '```\n'
}
