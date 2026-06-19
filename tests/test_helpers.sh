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
. "$ROOT/lib/github.sh"
# shellcheck source=/dev/null
. "$ROOT/lib/submit.sh"

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

# --- Summary --------------------------------------------------------------
printf '\n%s test(s), %s failure(s)\n' "$TESTS" "$FAILS"
[ "$FAILS" -eq 0 ]
