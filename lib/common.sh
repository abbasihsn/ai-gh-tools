#!/usr/bin/env bash
# lib/common.sh — shared helpers: errors, usage, repo detection, base refs, temp files.
#
# This file is meant to be sourced, not executed directly. It deliberately does
# NOT set `set -euo pipefail`; that is the responsibility of the entrypoint
# scripts in bin/. Sourcing it is side-effect free apart from defining
# functions and a couple of read-only-ish globals.

# Resolve the toolkit root (the ai-gh-tools repo that this lib lives in),
# regardless of where the user invokes the command from.
# shellcheck disable=SC2155
_agh_self_dir() {
  local src="${BASH_SOURCE[0]}"
  # Resolve symlinks (install.sh symlinks bin/* into ~/.local/bin).
  while [ -h "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

# AGH_LIB_DIR points at lib/, AGH_TOOLKIT_DIR at the repo root.
AGH_LIB_DIR="$(_agh_self_dir)"
AGH_TOOLKIT_DIR="$(cd "$AGH_LIB_DIR/.." >/dev/null 2>&1 && pwd)"
export AGH_LIB_DIR AGH_TOOLKIT_DIR

# --- Output helpers -------------------------------------------------------

# Whether stderr is a terminal, used to decide on color.
_agh_use_color() {
  [ -t 2 ] && [ -z "${NO_COLOR:-}" ]
}

agh_err() {
  if _agh_use_color; then
    printf '\033[31merror:\033[0m %s\n' "$*" >&2
  else
    printf 'error: %s\n' "$*" >&2
  fi
}

agh_warn() {
  if _agh_use_color; then
    printf '\033[33mwarning:\033[0m %s\n' "$*" >&2
  else
    printf 'warning: %s\n' "$*" >&2
  fi
}

agh_info() {
  printf '%s\n' "$*" >&2
}

# Print an error and exit non-zero.
agh_die() {
  agh_err "$*"
  exit 1
}

# Ensure a command exists, otherwise die with a helpful message.
agh_require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [ -n "$hint" ]; then
      agh_die "required command '$cmd' not found. $hint"
    fi
    agh_die "required command '$cmd' not found in PATH."
  fi
}

# --- Git repo detection ---------------------------------------------------

# Die unless we are inside a git work tree.
agh_require_git_repo() {
  agh_require_cmd git "Install git and run this from inside a Git repository."
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    agh_die "not inside a Git repository. cd into a repo and try again."
  fi
}

# Print the absolute path to the current repo's root.
agh_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# Print the current repo's short name (basename of root, or git remote).
agh_repo_name() {
  local root
  root="$(agh_repo_root)"
  if [ -n "$root" ]; then
    basename "$root"
  fi
}

# Print the current branch name (or a short SHA when detached).
agh_current_branch() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [ "$branch" = "HEAD" ] || [ -z "$branch" ]; then
    git rev-parse --short HEAD 2>/dev/null
  else
    printf '%s' "$branch"
  fi
}

# --- Base ref detection ---------------------------------------------------

# Ordered list of candidate base refs to try when the user did not supply one.
AGH_DEFAULT_BASE_CANDIDATES=(
  "origin/main"
  "main"
  "origin/develop"
  "develop"
  "origin/master"
  "master"
)

# True if a ref resolves to a commit in this repo.
agh_ref_exists() {
  local ref="$1"
  git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1
}

# Discover a default base ref by probing common candidates.
# Prints the first match on stdout; returns non-zero if none found.
agh_detect_base_ref() {
  local cand
  for cand in "${AGH_DEFAULT_BASE_CANDIDATES[@]}"; do
    if agh_ref_exists "$cand"; then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

# Resolve and validate a base ref. If $1 is empty, auto-detect.
# Dies with a clear error when the ref is invalid or none can be found.
agh_resolve_base_ref() {
  local requested="${1:-}"
  if [ -n "$requested" ]; then
    if ! agh_ref_exists "$requested"; then
      agh_die "invalid base ref '$requested' (not a known commit/branch). Try 'git fetch' or pass a valid ref."
    fi
    printf '%s' "$requested"
    return 0
  fi
  local detected
  if detected="$(agh_detect_base_ref)"; then
    printf '%s' "$detected"
    return 0
  fi
  agh_die "could not auto-detect a base ref (tried: ${AGH_DEFAULT_BASE_CANDIDATES[*]}). Pass one explicitly, e.g. 'origin/main'."
}

# --- Temp file handling ---------------------------------------------------

# Registry of temp files to clean up on exit.
AGH_TMP_FILES=()

# Create a temp file, register it for cleanup, and print its path.
agh_mktemp() {
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/ai-gh-tools.XXXXXX")" || agh_die "failed to create temp file."
  AGH_TMP_FILES+=("$tmp")
  printf '%s' "$tmp"
}

# Remove all registered temp files. Safe to call multiple times.
agh_cleanup_tmp() {
  local f
  for f in "${AGH_TMP_FILES[@]:-}"; do
    [ -n "$f" ] && rm -f "$f" 2>/dev/null || true
  done
  AGH_TMP_FILES=()
}

# Install the cleanup trap. Call once from the entrypoint after sourcing.
agh_install_cleanup_trap() {
  trap 'agh_cleanup_tmp' EXIT INT TERM
}

# --- Output dispatch ------------------------------------------------------

# Given assembled content (a file path), deliver it according to flags:
#   $1 = path to the generated content file
#   $2 = out file path ("" to skip)
#   $3 = copy flag ("1" to copy)
# When neither --out nor --copy is given, print to stdout.
agh_deliver_output() {
  local content_file="$1"
  local out_file="${2:-}"
  local do_copy="${3:-}"
  local delivered=0

  if [ -n "$out_file" ]; then
    cp "$content_file" "$out_file" || agh_die "failed to write output to '$out_file'."
    agh_info "wrote prompt to $out_file"
    delivered=1
  fi

  if [ "$do_copy" = "1" ]; then
    agh_copy_to_clipboard <"$content_file"
    delivered=1
  fi

  if [ "$delivered" -eq 0 ]; then
    cat "$content_file"
  fi
}

# --- Shared CLI driver ----------------------------------------------------
#
# The three entrypoints share most of their logic. Each one sets a couple of
# capability/labeling variables and then calls `agh_run "$@"`.
#
# Inputs (set by the entrypoint before calling agh_run):
#   AGH_PROMPT_NAME  — prompt file under prompts/ (e.g. pr-review.md)
#   AGH_ALLOW_PR     — "1" if --pr / --comments / --repo / --exclude are allowed
#   AGH_USAGE        — usage/help text printed for -h/--help
#
# These functions live here (rather than in each bin) so behavior stays
# consistent across commands. They are strictly read-only on the target repo.

# Parsed-option globals (reset on each run).
agh_reset_opts() {
  OPT_BASE=""
  OPT_PR=""
  OPT_COMMENTS=0
  OPT_REPO=""
  OPT_COPY=0
  OPT_OUT=""
  OPT_STAGED=0
  OPT_INCLUDE_WT=0
  OPT_CURSOR=0
  AGH_CURSOR_SUBMIT=0
  OPT_TICKET=""
  OPT_FROM=""
  OPT_EXCLUDES=()
  # Context toggles are exported as env-style flags read by context.sh.
  AGH_NO_PROJECT_RULES=""
  AGH_NO_TOOL_RULES=""
  AGH_NO_READMES=""
  AGH_WITH_SYMBOLS=""
}

agh_print_usage() {
  printf '%s\n' "${AGH_USAGE:-No usage available.}"
}

# Parse CLI args into the OPT_* globals. Dies on invalid usage.
agh_parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        agh_print_usage
        exit 0
        ;;
      --pr)
        [ "$AGH_ALLOW_PR" = "1" ] || agh_die "this command does not support --pr (local/staged only)."
        [ "$#" -ge 2 ] || agh_die "--pr requires a value (number, URL, or branch)."
        OPT_PR="$2"; shift 2 ;;
      --pr=*)
        [ "$AGH_ALLOW_PR" = "1" ] || agh_die "this command does not support --pr (local/staged only)."
        OPT_PR="${1#*=}"; shift ;;
      --comments)
        [ "$AGH_ALLOW_PR" = "1" ] || agh_die "this command does not support --comments."
        OPT_COMMENTS=1; shift ;;
      --repo)
        [ "$AGH_ALLOW_PR" = "1" ] || agh_die "this command does not support --repo."
        [ "$#" -ge 2 ] || agh_die "--repo requires an OWNER/REPO value."
        OPT_REPO="$2"; shift 2 ;;
      --repo=*)
        [ "$AGH_ALLOW_PR" = "1" ] || agh_die "this command does not support --repo."
        OPT_REPO="${1#*=}"; shift ;;
      --copy)
        OPT_COPY=1; shift ;;
      --out)
        [ "$#" -ge 2 ] || agh_die "--out requires a FILE value."
        OPT_OUT="$2"; shift 2 ;;
      --out=*)
        OPT_OUT="${1#*=}"; shift ;;
      --staged)
        OPT_STAGED=1; shift ;;
      --include-working-tree)
        OPT_INCLUDE_WT=1; shift ;;
      --cursor)
        OPT_CURSOR=1; shift ;;
      --cursor-submit)
        OPT_CURSOR=1; AGH_CURSOR_SUBMIT=1; shift ;;
      --ticket)
        [ "$#" -ge 2 ] || agh_die "--ticket requires a value (e.g. PROJ-123)."
        OPT_TICKET="$2"; shift 2 ;;
      --ticket=*)
        OPT_TICKET="${1#*=}"; shift ;;
      --from)
        [ "${AGH_FROM_MODE:-0}" = "1" ] || agh_die "this command does not support --from."
        [ "$#" -ge 2 ] || agh_die "--from requires a FILE value (the bug JSON from ai-project-audit)."
        OPT_FROM="$2"; shift 2 ;;
      --from=*)
        [ "${AGH_FROM_MODE:-0}" = "1" ] || agh_die "this command does not support --from."
        OPT_FROM="${1#*=}"; shift ;;
      --no-project-rules)
        AGH_NO_PROJECT_RULES=1; shift ;;
      --no-tool-rules)
        AGH_NO_TOOL_RULES=1; shift ;;
      --no-readmes)
        AGH_NO_READMES=1; shift ;;
      --symbols)
        AGH_WITH_SYMBOLS=1; shift ;;
      --exclude)
        [ "$AGH_ALLOW_PR" = "1" ] || agh_die "this command does not support --exclude."
        [ "$#" -ge 2 ] || agh_die "--exclude requires a PATTERN value."
        OPT_EXCLUDES+=("$2"); shift 2 ;;
      --exclude=*)
        [ "$AGH_ALLOW_PR" = "1" ] || agh_die "this command does not support --exclude."
        OPT_EXCLUDES+=("${1#*=}"); shift ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do OPT_BASE="$1"; shift; done
        ;;
      -*)
        agh_die "unknown option '$1'. Use -h for help."
        ;;
      *)
        if [ -n "$OPT_BASE" ]; then
          agh_die "unexpected extra argument '$1' (base ref already set to '$OPT_BASE')."
        fi
        OPT_BASE="$1"; shift ;;
    esac
  done

  export AGH_NO_PROJECT_RULES AGH_NO_TOOL_RULES AGH_NO_READMES AGH_WITH_SYMBOLS

  # Cross-flag validation.
  if [ "$OPT_COMMENTS" = "1" ] && [ -z "$OPT_PR" ]; then
    agh_die "--comments is only valid together with --pr."
  fi
  if [ -n "$OPT_PR" ] && [ "$OPT_STAGED" = "1" ]; then
    agh_die "--pr and --staged are mutually exclusive."
  fi
  if [ -n "$OPT_PR" ] && [ -n "$OPT_BASE" ]; then
    agh_die "a base ref ('$OPT_BASE') cannot be combined with --pr."
  fi
  if [ "$OPT_STAGED" = "1" ] && [ -n "$OPT_BASE" ]; then
    agh_die "a base ref ('$OPT_BASE') cannot be combined with --staged."
  fi
  if [ "${AGH_WITH_SYMBOLS:-}" = "1" ] && [ -n "$OPT_PR" ]; then
    agh_warn "--symbols has no effect in --pr mode (local/staged only); ignoring it."
  fi

  # Whole-project mode (explain / audit): no change set is involved.
  if [ "${AGH_PROJECT_MODE:-0}" = "1" ]; then
    [ -z "$OPT_BASE" ] || agh_die "this command reviews the whole project; it takes no base ref ('$OPT_BASE')."
    [ "$OPT_STAGED" != "1" ] || agh_die "this command reviews the whole project; --staged is not supported."
    # These are accepted by the parser but unused in whole-project mode; warn
    # rather than silently ignore so a user isn't misled.
    [ -z "$OPT_TICKET" ] || agh_warn "--ticket has no effect in whole-project mode; ignoring it."
    [ "$OPT_INCLUDE_WT" != "1" ] || agh_warn "--include-working-tree has no effect in whole-project mode; ignoring it."
  fi
  # From-file mode (jira-draft): consumes a bug file, not a change set.
  if [ "${AGH_FROM_MODE:-0}" = "1" ]; then
    [ -n "$OPT_FROM" ] || agh_die "--from FILE is required (the bug JSON written by ai-project-audit)."
    [ -z "$OPT_BASE" ] || agh_die "this command takes --from FILE, not a base ref ('$OPT_BASE')."
    [ "$OPT_STAGED" != "1" ] || agh_die "this command takes --from FILE; --staged is not supported."
    [ "$OPT_INCLUDE_WT" != "1" ] || agh_die "this command takes --from FILE; --include-working-tree is not supported."
    # jira-draft embeds only the bug JSON + metadata + toolkit rules, so these
    # context toggles do nothing here; warn rather than silently ignore.
    if [ "${AGH_NO_PROJECT_RULES:-}" = "1" ] || [ "${AGH_NO_READMES:-}" = "1" ] || [ "${AGH_WITH_SYMBOLS:-}" = "1" ]; then
      agh_warn "--no-project-rules / --no-readmes / --symbols have no effect in jira-draft mode; ignoring them."
    fi
    [ -z "$OPT_TICKET" ] || agh_warn "--ticket has no effect in jira-draft mode; ignoring it."
  fi
}

# Assemble the full prompt for PR mode into the given file.
_agh_build_pr() {
  local out="$1"
  agh_require_gh
  agh_gh_set_repo "$OPT_REPO"

  # Preflight: fail loudly (not silently) if gh can't fetch the PR, and report
  # WHO gh is acting as and WHICH repo it resolved — the usual culprit is gh
  # being logged in as the wrong account, or org SSO not being authorized.
  if ! agh_gh_pr_accessible "$OPT_PR"; then
    agh_err "could not fetch PR '$OPT_PR' via gh."
    agh_gh_print_identity "${OPT_REPO:-}"
    agh_err "Likely that account can't access this repo (wrong account or org SSO not authorized)."
    agh_err "Fix: 'gh auth status' · 'gh auth switch' / 'gh auth login' (right account) · 'gh auth refresh' (authorize org SSO)."
    agh_err "Then verify with: gh pr view $OPT_PR"
    exit 1
  fi

  local repo_root repo_name
  repo_root="$(agh_repo_root)"
  repo_name="$(agh_repo_name)"

  # Gather changed files (filtered by --exclude) into a temp file for READMEs.
  # Both the changed-file list and the diff are filtered with the same patterns
  # so excluded paths never leak into the prompt (list, diff, or README lookup).
  local files_tmp diff_tmp
  files_tmp="$(agh_mktemp)"
  diff_tmp="$(agh_mktemp)"
  agh_gh_pr_changed_files "$OPT_PR" | agh_gh_filter_file_list "${OPT_EXCLUDES[@]+"${OPT_EXCLUDES[@]}"}" >"$files_tmp" || true
  agh_gh_pr_diff "$OPT_PR" | agh_gh_filter_diff "${OPT_EXCLUDES[@]+"${OPT_EXCLUDES[@]}"}" >"$diff_tmp" || true

  if [ ! -s "$diff_tmp" ]; then
    agh_err "PR '$OPT_PR' returned an EMPTY diff via gh — nothing to review; aborting (no prompt generated)."
    agh_gh_print_identity "${OPT_REPO:-}"
    agh_err "Verify with: gh pr diff $OPT_PR"
    agh_err "If this PR should have changes, it's likely org SSO scope ('gh auth refresh') or the wrong gh account ('gh auth switch'); or double-check the PR number."
    exit 1
  fi

  {
    agh_print_toolkit_prompt "$AGH_PROMPT_NAME"
    agh_print_toolkit_rules "$repo_name"
    agh_print_project_rules "$repo_root"
    agh_print_readmes "$repo_root" "$files_tmp"
    agh_print_repo_metadata "$repo_root" "$repo_name"

    if [ -n "$OPT_TICKET" ]; then
      printf '\n## Ticket\n\n- %s\n' "$OPT_TICKET"
    fi

    printf '\n## Pull request metadata\n\n'
    { agh_gh_pr_view "$OPT_PR" | sed 's/^/    /'; } || true

    if [ "$OPT_COMMENTS" = "1" ]; then
      printf '\n## Existing PR comments\n\n'
      agh_gh_pr_comments "$OPT_PR" || true
    fi

    printf '\n## Changed files\n\n'
    if [ -s "$files_tmp" ]; then
      sed 's/^/- /' "$files_tmp"
    else
      printf '(none reported)\n'
    fi

    printf '\n## Full diff\n\n'
    printf '```diff\n'
    cat "$diff_tmp"
    printf '\n```\n'
  } >"$out"
}

# Assemble the full prompt for local-branch or staged mode.
_agh_build_local() {
  local out="$1"
  agh_require_git_repo

  local repo_root repo_name
  repo_root="$(agh_repo_root)"
  repo_name="$(agh_repo_name)"

  local files_tmp
  files_tmp="$(agh_mktemp)"

  local base=""
  if [ "$OPT_STAGED" != "1" ]; then
    base="$(agh_resolve_base_ref "$OPT_BASE")"
    agh_git_branch_changed_files "$base" >"$files_tmp" || true
  else
    agh_git_staged_changed_files >"$files_tmp" || true
    if [ ! -s "$files_tmp" ]; then
      agh_die "no staged changes found. Stage changes with 'git add' or drop --staged."
    fi
  fi

  {
    agh_print_toolkit_prompt "$AGH_PROMPT_NAME"
    agh_print_toolkit_rules "$repo_name"
    agh_print_project_rules "$repo_root"
    agh_print_readmes "$repo_root" "$files_tmp"
    agh_print_repo_metadata "$repo_root" "$repo_name"

    if [ -n "$OPT_TICKET" ]; then
      printf '\n## Ticket\n\n- %s\n' "$OPT_TICKET"
    fi

    if [ "$OPT_STAGED" = "1" ]; then
      agh_print_staged_metadata
    else
      agh_print_local_metadata "$base"
    fi

    printf '\n## Changed files\n\n'
    if [ -s "$files_tmp" ]; then
      sed 's/^/- /' "$files_tmp"
    else
      printf '(none)\n'
    fi

    local stat
    if [ "$OPT_STAGED" = "1" ]; then
      stat="$(agh_git_staged_diffstat)"
    else
      stat="$(agh_git_branch_diffstat "$base")"
    fi
    if [ -n "$stat" ]; then
      printf '\n## Diff stat\n\n'
      printf '```\n%s\n```\n' "$stat"
    fi

    agh_print_symbol_inventory "$repo_root"

    printf '\n## Full diff\n\n'
    printf '```diff\n'
    if [ "$OPT_STAGED" = "1" ]; then
      agh_git_staged_diff
    else
      agh_git_branch_diff "$base" "$OPT_INCLUDE_WT"
    fi
    printf '\n```\n'
  } >"$out"
}

# Assemble the full prompt for whole-project mode (explain / audit). There is no
# diff: the context is the whole tracked tree, the repo rules, READMEs, metadata,
# and the symbol inventory (forced on so the AI gets a definition map even when a
# non-agentic tool consumes the prompt).
_agh_build_project() {
  local out="$1"
  agh_require_git_repo

  local repo_root repo_name
  repo_root="$(agh_repo_root)"
  repo_name="$(agh_repo_name)"

  # Whole-project review always wants the definition inventory.
  AGH_WITH_SYMBOLS=1

  {
    agh_print_toolkit_prompt "$AGH_PROMPT_NAME"
    agh_print_toolkit_rules "$repo_name"
    agh_print_project_rules "$repo_root"
    agh_print_readmes "$repo_root" ""
    agh_print_repo_metadata "$repo_root" "$repo_name"
    agh_print_file_tree "$repo_root"
    agh_print_symbol_inventory "$repo_root"
  } >"$out"
}

# Assemble the prompt for jira-draft mode: embed the bug file produced by
# ai-project-audit plus repo context, so the AI can re-validate each bug against
# the live code and draft humanized Jira tickets.
_agh_build_jira() {
  local out="$1"
  agh_require_git_repo
  # Presence of --from is validated in agh_parse_args; here we only confirm the
  # file exists (the one check the parser can't do).
  [ -f "$OPT_FROM" ] || agh_die "--from file not found: $OPT_FROM"

  local repo_root repo_name
  repo_root="$(agh_repo_root)"
  repo_name="$(agh_repo_name)"

  {
    agh_print_toolkit_prompt "$AGH_PROMPT_NAME"
    agh_print_toolkit_rules "$repo_name"
    agh_print_repo_metadata "$repo_root" "$repo_name"
    printf '\n## Bugs to turn into Jira tickets (from ai-project-audit)\n\n'
    printf -- '- source file: %s\n\n' "$OPT_FROM"
    printf '```json\n'
    cat -- "$OPT_FROM"
    printf '\n```\n'
  } >"$out"
}

# Entry point: parse args, build the prompt, deliver it.
agh_run() {
  : "${AGH_PROMPT_NAME:?AGH_PROMPT_NAME must be set by the entrypoint}"
  : "${AGH_ALLOW_PR:=0}"
  : "${AGH_PROJECT_MODE:=0}"
  : "${AGH_FROM_MODE:=0}"
  agh_reset_opts
  agh_install_cleanup_trap
  agh_parse_args "$@"

  # Most operations need a git repo; PR mode also benefits from repo context.
  agh_require_git_repo

  local out
  out="$(agh_mktemp)"
  if [ "$AGH_FROM_MODE" = "1" ]; then
    _agh_build_jira "$out"
  elif [ "$AGH_PROJECT_MODE" = "1" ]; then
    _agh_build_project "$out"
  elif [ -n "$OPT_PR" ]; then
    _agh_build_pr "$out"
  else
    _agh_build_local "$out"
  fi

  if [ "$OPT_CURSOR" = "1" ]; then
    # Optionally still honor --out, then hand the prompt to Cursor.
    if [ -n "$OPT_OUT" ]; then
      cp "$out" "$OPT_OUT" || agh_die "failed to write output to '$OPT_OUT'."
      agh_info "wrote prompt to $OPT_OUT"
    fi
    agh_send_to_cursor "$out"
  else
    agh_deliver_output "$out" "$OPT_OUT" "$OPT_COPY"
  fi
}
