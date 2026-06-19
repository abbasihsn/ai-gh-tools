#!/usr/bin/env bash
# install.sh — install the ai-gh-tools commands for the current user.
#
# What it does (all local, idempotent, and reversible):
#   1. Detects this repo's directory.
#   2. Symlinks bin/* into ~/.local/bin and makes the sources executable.
#   3. Ensures ~/.local/bin is on PATH via your shell rc file.
#   4. Creates convenience git aliases.
#   5. Prints usage examples.
#
# It does NOT touch GitHub or any target repo.
set -euo pipefail

REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
BIN_SRC="$REPO_DIR/bin"
INSTALL_DIR="${AGH_INSTALL_DIR:-$HOME/.local/bin}"

COMMANDS=(ai-pr-review ai-explain-pr ai-draft-pr ai-open-pr)

# Commands removed/renamed in past versions, cleaned up on (re)install so an
# upgrade doesn't leave dangling symlinks or stale git aliases behind.
#   - ai-create-pr was renamed to ai-draft-pr.
OBSOLETE_COMMANDS=(ai-create-pr)
OBSOLETE_GIT_ALIASES=(ai-create-pr)

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -d "$BIN_SRC" ] || die "could not find bin/ at $BIN_SRC"

info "Installing ai-gh-tools from: $REPO_DIR"
mkdir -p "$INSTALL_DIR"

# 0. Remove obsolete commands left over from earlier installs (renames, etc.).
for old in "${OBSOLETE_COMMANDS[@]}"; do
  link="$INSTALL_DIR/$old"
  # Only remove our own symlink, never a real file the user may have placed.
  if [ -L "$link" ]; then
    rm -f "$link"
    info "  removed obsolete command $link"
  fi
done

# 1 + 2. Make sources executable and symlink them into the install dir.
for cmd in "${COMMANDS[@]}"; do
  src="$BIN_SRC/$cmd"
  [ -f "$src" ] || die "missing command source: $src"
  chmod +x "$src"
  link="$INSTALL_DIR/$cmd"
  ln -sf "$src" "$link"
  info "  linked $link -> $src"
done
# Ensure lib scripts are readable/executable as needed (sourced, but harmless).
chmod +x "$REPO_DIR"/lib/*.sh 2>/dev/null || true

# 3. Ensure INSTALL_DIR is on PATH via the user's shell rc.
ensure_path() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  # Match INSTALL_DIR only as a whole path segment, so e.g. ".local/bin" does
  # not falsely match an existing ".local/bin2" entry. Escape regex-special
  # characters in the path before anchoring it to a boundary.
  local esc
  esc="$(printf '%s' "$INSTALL_DIR" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"
  if grep -Eq "(^|[:\"' =])${esc}([:\"' ]|\$)" "$rc" 2>/dev/null; then
    return 0
  fi
  {
    printf '\n# Added by ai-gh-tools install.sh\n'
    printf 'export PATH="%s:$PATH"\n' "$INSTALL_DIR"
  } >>"$rc"
  info "  added $INSTALL_DIR to PATH in $rc"
}

case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    info "  $INSTALL_DIR already on PATH"
    ;;
  *)
    updated=0
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
      if [ -f "$rc" ]; then
        ensure_path "$rc"
        updated=1
      fi
    done
    # If neither rc exists, create one matching the current shell.
    if [ "$updated" -eq 0 ]; then
      case "${SHELL:-}" in
        *zsh) ensure_path_target="$HOME/.zshrc" ;;
        *)    ensure_path_target="$HOME/.bashrc" ;;
      esac
      {
        printf '\n# Added by ai-gh-tools install.sh\n'
        printf 'export PATH="%s:$PATH"\n' "$INSTALL_DIR"
      } >>"$ensure_path_target"
      info "  created $ensure_path_target and added $INSTALL_DIR to PATH"
    fi
    info "  open a new shell or 'source' your rc file to pick up PATH changes"
    ;;
esac

# 4. Create git aliases (global, user-level).
if command -v git >/dev/null 2>&1; then
  git config --global alias.ai-review   "!$INSTALL_DIR/ai-pr-review"
  git config --global alias.ai-explain  "!$INSTALL_DIR/ai-explain-pr"
  git config --global alias.ai-draft-pr "!$INSTALL_DIR/ai-draft-pr"
  git config --global alias.ai-open-pr  "!$INSTALL_DIR/ai-open-pr"
  info "  configured git aliases: git ai-review / git ai-explain / git ai-draft-pr / git ai-open-pr"
  # Drop git aliases for renamed/removed commands.
  for old_alias in "${OBSOLETE_GIT_ALIASES[@]}"; do
    if git config --global --get "alias.$old_alias" >/dev/null 2>&1; then
      git config --global --unset "alias.$old_alias" || true
      info "  removed obsolete git alias: git $old_alias"
    fi
  done
else
  warn "git not found; skipped git alias setup"
fi

# 5. Usage examples.
cat <<EOF

ai-gh-tools installed.

Commands:
  ai-pr-review    Strict multi-agent PR review prompt   (read-only)
  ai-explain-pr   Plain-English explanation prompt      (read-only)
  ai-draft-pr     PR title + description prompt          (read-only)
  ai-open-pr      Commit, push, and OPEN a GitHub PR     (modifies remote)

Examples (run from inside any git repo):
  ai-pr-review origin/main --copy
  ai-pr-review --pr 123 --comments --copy
  ai-explain-pr --staged --copy
  ai-draft-pr origin/main --out /tmp/pr-description.md
  ai-open-pr origin/main            # commits + pushes + opens a PR (with prompts)
  ai-open-pr origin/main --dry-run  # preview without changing anything

Git aliases:
  git ai-review origin/main --copy
  git ai-explain --pr 123 --copy
  git ai-draft-pr --staged --copy
  git ai-open-pr origin/main

Note: ai-pr-review / ai-explain-pr / ai-draft-pr are read-only. Only ai-open-pr
modifies your repo and GitHub, and it confirms before each step.
EOF
