#!/usr/bin/env bash
# tests/test_helpers.sh — deterministic unit tests for the pure shell helpers.
#
# These cover logic with no network/PR dependency: branch humanizing, the
# glob-based exclude filters, and remote-owner parsing. Run: ./tests/test_helpers.sh
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# shellcheck source=/dev/null
. "$ROOT/lib/common.sh"
# shellcheck source=/dev/null
. "$ROOT/lib/git.sh"
# shellcheck source=/dev/null
. "$ROOT/lib/github.sh"
# shellcheck source=/dev/null
. "$ROOT/lib/submit.sh"
# shellcheck source=/dev/null
. "$ROOT/lib/context.sh"

agh_install_cleanup_trap

TESTS=0
FAILS=0

# check DESC EXPECTED ACTUAL
check() {
  TESTS=$((TESTS + 1))
  if [ "$2" = "$3" ]; then
    printf 'ok   - %s\n' "$1"
  else
    FAILS=$((FAILS + 1))
    printf 'FAIL - %s\n       expected: [%s]\n       actual:   [%s]\n' "$1" "$2" "$3"
  fi
}

# contains DESC HAYSTACK NEEDLE EXPECT(present|absent)
contains() {
  local got=absent
  case "$2" in *"$3"*) got=present ;; esac
  check "$1" "$4" "$got"
}

# order_ok HAYSTACK FIRST SECOND -> "yes" if FIRST occurs before SECOND (both
# must be present), else "no". Used to assert deterministic source ordering.
order_ok() {
  local h="$1" a="$2" b="$3" pa pb
  case "$h" in *"$a"*) ;; *) printf 'no'; return ;; esac
  case "$h" in *"$b"*) ;; *) printf 'no'; return ;; esac
  pa="${h%%"$a"*}"; pb="${h%%"$b"*}"
  if [ "${#pa}" -lt "${#pb}" ]; then printf 'yes'; else printf 'no'; fi
}

# --- agh_humanize_branch --------------------------------------------------
check "humanize drops type prefix and dashes" "Add fast resize" \
  "$(agh_humanize_branch 'feat/add-fast-resize')"
check "humanize handles underscores" "Update docs" \
  "$(agh_humanize_branch 'chore/update_docs')"
check "humanize empty branch -> empty" "" \
  "$(agh_humanize_branch '')"

# --- agh_gh_filter_file_list ----------------------------------------------
FILES="$(printf '%s\n' 'a.txt' 'b.log' 'sub/c.txt' 'sub/d.log')"
OUT="$(printf '%s\n' "$FILES" | agh_gh_filter_file_list '*.log')"
contains "file filter drops top-level *.log"  "$OUT" "b.log"     "absent"
contains "file filter drops nested *.log"     "$OUT" "sub/d.log" "absent"
contains "file filter keeps non-matching"     "$OUT" "a.txt"     "present"
contains "file filter keeps nested non-match" "$OUT" "sub/c.txt" "present"

OUT_EXACT="$(printf '%s\n' "$FILES" | agh_gh_filter_file_list 'sub/c.txt')"
contains "file filter exact path drops it"      "$OUT_EXACT" "sub/c.txt" "absent"
contains "file filter exact path keeps sibling" "$OUT_EXACT" "a.txt"     "present"

OUT_NONE="$(printf '%s\n' "$FILES" | agh_gh_filter_file_list)"
contains "no patterns is a passthrough" "$OUT_NONE" "b.log" "present"

# --- agh_gh_filter_diff ---------------------------------------------------
DIFF="$(cat <<'EOF'
diff --git a/keep.txt b/keep.txt
index 1111111..2222222 100644
--- a/keep.txt
+++ b/keep.txt
@@ -1 +1 @@
-old
+new
diff --git a/drop.log b/drop.log
index 3333333..4444444 100644
--- a/drop.log
+++ b/drop.log
@@ -1 +1 @@
-x
+y
EOF
)"
DIFF_OUT="$(printf '%s\n' "$DIFF" | agh_gh_filter_diff '*.log')"
contains "diff filter drops excluded section" "$DIFF_OUT" "drop.log" "absent"
contains "diff filter keeps other section"    "$DIFF_OUT" "keep.txt" "present"

# --- agh_remote_owner -----------------------------------------------------
TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/agh-test.XXXXXX")"
(
  cd "$TMP_REPO" || exit 1
  git init -q
  git remote add ssh_remote   'git@github.com:ssh-owner/repo.git'
  git remote add https_remote 'https://github.com/https-owner/repo.git'
  git remote add ssh_scheme   'ssh://git@github.com/ssh2-owner/repo.git'
)
check "owner from SSH URL"        "ssh-owner"   "$(cd "$TMP_REPO" && agh_remote_owner ssh_remote)"
check "owner from HTTPS URL"      "https-owner" "$(cd "$TMP_REPO" && agh_remote_owner https_remote)"
check "owner from ssh:// URL"     "ssh2-owner"  "$(cd "$TMP_REPO" && agh_remote_owner ssh_scheme)"
check "owner from missing remote" ""            "$(cd "$TMP_REPO" && agh_remote_owner nope)"
rm -rf "$TMP_REPO"

# --- agh_print_project_rules ----------------------------------------------
RULES_REPO="$(mktemp -d "${TMPDIR:-/tmp}/agh-rules.XXXXXX")"
mkdir -p "$RULES_REPO/.cursor/rules/nested"
printf 'CURSOR_TOP_RULE\n'    >"$RULES_REPO/.cursor/rules/a.mdc"
printf 'CURSOR_NESTED_RULE\n' >"$RULES_REPO/.cursor/rules/nested/b.mdc"
printf 'LEGACY_CURSORRULES\n' >"$RULES_REPO/.cursorrules"
printf 'CLAUDE_RULE\n'        >"$RULES_REPO/CLAUDE.md"
printf 'AGENTS_RULE\n'        >"$RULES_REPO/AGENTS.md"
RULES_OUT="$(agh_print_project_rules "$RULES_REPO")"
contains "project rules include .cursor/rules"        "$RULES_OUT" "CURSOR_TOP_RULE"    "present"
contains "project rules recurse into nested dirs"     "$RULES_OUT" "CURSOR_NESTED_RULE" "present"
contains "project rules include .cursorrules"         "$RULES_OUT" "LEGACY_CURSORRULES" "present"
contains "project rules include CLAUDE.md"            "$RULES_OUT" "CLAUDE_RULE"        "present"
contains "project rules include AGENTS.md"            "$RULES_OUT" "AGENTS_RULE"        "present"
# Ordering: sources must appear in the documented order
# (.cursor/rules sorted -> .cursorrules -> CLAUDE.md -> AGENTS.md).
check "rules order: .cursor top before nested"   "yes" "$(order_ok "$RULES_OUT" CURSOR_TOP_RULE CURSOR_NESTED_RULE)"
check "rules order: .cursor before .cursorrules" "yes" "$(order_ok "$RULES_OUT" CURSOR_NESTED_RULE LEGACY_CURSORRULES)"
check "rules order: .cursorrules before CLAUDE"  "yes" "$(order_ok "$RULES_OUT" LEGACY_CURSORRULES CLAUDE_RULE)"
check "rules order: CLAUDE before AGENTS"        "yes" "$(order_ok "$RULES_OUT" CLAUDE_RULE AGENTS_RULE)"
# Dedup: exactly one heading per rule file (5), no file emitted twice.
check "rules emit one heading per file (no dups)" "5" "$(printf '%s\n' "$RULES_OUT" | grep -c '^### ')"
RULES_OFF="$(AGH_NO_PROJECT_RULES=1 agh_print_project_rules "$RULES_REPO")"
check "no-project-rules suppresses output" "" "$RULES_OFF"
EMPTY_REPO="$(mktemp -d "${TMPDIR:-/tmp}/agh-empty.XXXXXX")"
check "no rule files -> empty output" "" "$(agh_print_project_rules "$EMPTY_REPO")"
rm -rf "$RULES_REPO" "$EMPTY_REPO"

# --- agh_git_all_files / agh_print_file_tree (whole-project mode) ----------
TREE_REPO="$(mktemp -d "${TMPDIR:-/tmp}/agh-tree.XXXXXX")"
(
  cd "$TREE_REPO" || exit 1
  git init -q
  mkdir -p lib bin
  printf 'top\n'    >README.md
  printf 'engine\n' >lib/common.sh
  printf 'util\n'   >lib/util.sh
  printf 'cli\n'    >bin/tool
  printf '%s\n' 'def real_def():' '    pass' '' 'do_work()'  >app.py
  # shell file: a paren def, a `function`-keyword def, a builtin call, a
  # braceless call (the last two must NOT be picked up as definitions).
  printf '%s\n' 'my_shell_fn() {' '  echo hi' '}' \
                'function fn_kw {' '  :' '}' \
                'type some_builtin_call' \
                'bare_call()' >lib/fns.sh
  git add -A
)
ALL_FILES="$(cd "$TREE_REPO" && agh_git_all_files)"
contains "all-files lists tracked lib file" "$ALL_FILES" "lib/common.sh" "present"
contains "all-files lists tracked bin file" "$ALL_FILES" "bin/tool"      "present"
contains "all-files lists root file"        "$ALL_FILES" "README.md"     "present"

# count for a block from the tree output (awk: count is $1, block name is $2)
tree_block_count() { printf '%s\n' "$1" | awk -v b="$2" '$2==b {print $1; exit}'; }

TREE_OUT="$(agh_print_file_tree "$TREE_REPO")"
contains "file-tree has section header"    "$TREE_OUT" "## Project files (whole repo)" "present"
contains "file-tree has per-block section" "$TREE_OUT" "Files per top-level block"     "present"
contains "file-tree lists a tracked file"  "$TREE_OUT" "lib/common.sh"                 "present"
check "file-tree counts lib block (3 files)" "3" "$(tree_block_count "$TREE_OUT" lib)"
check "file-tree counts bin block (1 file)"  "1" "$(tree_block_count "$TREE_OUT" bin)"

# AGH_TREE_CAP truncates and reports the remainder
contains "file-tree truncates at AGH_TREE_CAP=1" \
  "$(AGH_TREE_CAP=1 agh_print_file_tree "$TREE_REPO")" "more files truncated" "present"
# Invalid / zero / negative caps must NOT break the listing; _agh_cap falls back
# to the default (so the file list still appears, with no truncation/crash).
contains "invalid AGH_TREE_CAP falls back (still lists files)" \
  "$(AGH_TREE_CAP=abc agh_print_file_tree "$TREE_REPO")" "lib/common.sh" "present"
contains "AGH_TREE_CAP=0 falls back (still lists files)" \
  "$(AGH_TREE_CAP=0 agh_print_file_tree "$TREE_REPO")" "lib/common.sh" "present"
contains "negative AGH_TREE_CAP falls back (still lists files)" \
  "$(AGH_TREE_CAP=-3 agh_print_file_tree "$TREE_REPO")" "lib/common.sh" "present"

# --- agh_print_symbol_inventory --------------------------------------------
SYM_ON="$(AGH_WITH_SYMBOLS=1 agh_print_symbol_inventory "$TREE_REPO")"
contains "symbol inventory detects shell paren def"     "$SYM_ON" "my_shell_fn"        "present"
contains "symbol inventory detects function-keyword def" "$SYM_ON" "fn_kw"             "present"
contains "symbol inventory detects keyword def"         "$SYM_ON" "real_def"           "present"
contains "symbol inventory excludes python bare call"   "$SYM_ON" "do_work"            "absent"
contains "symbol inventory excludes shell builtin call" "$SYM_ON" "some_builtin_call"  "absent"
contains "symbol inventory excludes braceless shell call" "$SYM_ON" "bare_call"        "absent"
# AGH_SYMBOLS_CAP truncates the inventory
contains "symbol inventory truncates at AGH_SYMBOLS_CAP=1" \
  "$(AGH_WITH_SYMBOLS=1 AGH_SYMBOLS_CAP=1 agh_print_symbol_inventory "$TREE_REPO")" \
  "more definitions truncated" "present"
contains "symbol inventory is off without --symbols" \
  "$(agh_print_symbol_inventory "$TREE_REPO")" "my_shell_fn" "absent"
rm -rf "$TREE_REPO"

# --- Summary --------------------------------------------------------------
printf '\n%s test(s), %s failure(s)\n' "$TESTS" "$FAILS"
[ "$FAILS" -eq 0 ]
