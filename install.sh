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
SKILLS_SRC="$REPO_DIR/skills"
AGENTS_SRC="$REPO_DIR/agents"
INSTALL_DIR="${AGH_INSTALL_DIR:-$HOME/.local/bin}"
SKILLS_DIR="${AGH_SKILLS_DIR:-$HOME/.claude/skills}"
AGENTS_DIR="${AGH_AGENTS_DIR:-$HOME/.claude/agents}"

# Optional: also install skills + agents into a target project's .cursor/ tree.
# Cursor only reads project-scoped skills (.cursor/skills), so pass the repo you
# want them available in:  ./install.sh --cursor-project /path/to/repo
CURSOR_PROJECT=""

COMMANDS=(ai-gh ai-pr-review ai-explain-pr ai-draft-pr ai-open-pr)

# Claude Code / Cursor skills (each is a directory holding a SKILL.md). They wrap
# the read-only prompt tools as the "hybrid" flow: the tool assembles
# deterministic context, then the AI reviews/explains/drafts with live repo access.
SKILLS=(pr-review explain-pr draft-pr)

# Reviewer subagents (cross-agent markdown; read by both Claude Code and Cursor)
# used by the pr-review skill's --deep mode to review each lens in parallel.
AGENTS=(
  review-correctness review-architecture review-code-quality
  review-types-apis review-security review-performance
  review-config-devops review-testing-docs
)

# Commands removed/renamed in past versions, cleaned up on (re)install so an
# upgrade doesn't leave dangling symlinks or stale git aliases behind.
#   - ai-create-pr was renamed to ai-draft-pr.
OBSOLETE_COMMANDS=(ai-create-pr)
OBSOLETE_GIT_ALIASES=(ai-create-pr)

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# Parse install options.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --cursor-project)
      [ "$#" -ge 2 ] || die "--cursor-project requires a path to a git repo."
      CURSOR_PROJECT="$2"; shift 2 ;;
    --cursor-project=*)
      CURSOR_PROJECT="${1#*=}"; shift ;;
    -h|--help)
      cat <<'USAGE'
install.sh — install ai-gh-tools (CLI commands, Claude Code skills + subagents).

USAGE:
  ./install.sh [--cursor-project DIR]

OPTIONS:
  --cursor-project DIR   Also install the skills + reviewer subagents into DIR's
                         .cursor/skills and .cursor/agents (Cursor is project-
                         scoped and has no global skills dir). DIR must be a repo.
USAGE
      exit 0 ;;
    *)
      die "unknown argument '$1'. Use --help." ;;
  esac
done

# Symlink each named skill directory (src_root/<name>) into dest_dir/<name>.
link_skills() {
  local src_root="$1" dest_dir="$2" name src link
  [ -d "$src_root" ] || { info "  no skills/ at $src_root; skipping"; return 0; }
  mkdir -p "$dest_dir"
  for name in "${SKILLS[@]}"; do
    src="$src_root/$name"
    if [ ! -f "$src/SKILL.md" ]; then
      warn "skill source missing SKILL.md: $src (skipping)"; continue
    fi
    link="$dest_dir/$name"
    # Only replace our own symlink; never clobber a real directory the user owns.
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      warn "skipping skill '$name': $link exists and is not a symlink"; continue
    fi
    ln -sfn "$src" "$link"
    info "  linked skill $link -> $src"
  done
}

# Symlink each named agent file (src_root/<name>.md) into dest_dir/<name>.md.
link_agents() {
  local src_root="$1" dest_dir="$2" name src link
  [ -d "$src_root" ] || { info "  no agents/ at $src_root; skipping"; return 0; }
  mkdir -p "$dest_dir"
  for name in "${AGENTS[@]}"; do
    src="$src_root/$name.md"
    if [ ! -f "$src" ]; then
      warn "agent source missing: $src (skipping)"; continue
    fi
    link="$dest_dir/$name.md"
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      warn "skipping agent '$name': $link exists and is not a symlink"; continue
    fi
    ln -sfn "$src" "$link"
    info "  linked agent $link -> $src"
  done
}

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

# 2b. Install Claude Code skills + reviewer subagents globally (~/.claude/...)
# so they're available in every repo.
link_skills "$SKILLS_SRC" "$SKILLS_DIR"
link_agents "$AGENTS_SRC" "$AGENTS_DIR"

# 2c. Optionally install into a target project's .cursor/ tree. Cursor has no
# global skills dir, so skills must live inside each repo you use them in.
if [ -n "$CURSOR_PROJECT" ]; then
  if [ ! -d "$CURSOR_PROJECT" ]; then
    die "--cursor-project '$CURSOR_PROJECT' is not a directory."
  fi
  proj="$(cd -P "$CURSOR_PROJECT" >/dev/null 2>&1 && pwd)"
  info "Installing Cursor skills + agents into: $proj/.cursor"
  link_skills "$SKILLS_SRC" "$proj/.cursor/skills"
  link_agents "$AGENTS_SRC" "$proj/.cursor/agents"
fi

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
  git config --global alias.ai-gh       "!$INSTALL_DIR/ai-gh"
  git config --global alias.ai-review   "!$INSTALL_DIR/ai-pr-review"
  git config --global alias.ai-explain  "!$INSTALL_DIR/ai-explain-pr"
  git config --global alias.ai-draft-pr "!$INSTALL_DIR/ai-draft-pr"
  git config --global alias.ai-open-pr  "!$INSTALL_DIR/ai-open-pr"
  info "  configured git aliases: git ai-gh / git ai-review / git ai-explain / git ai-draft-pr / git ai-open-pr"
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
  ai-gh           Umbrella + cheat sheet (ai-gh help, ai-gh review ...)
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

Skills (run inside any repo, in Claude Code or Cursor):
  /pr-review  origin/main          Single-pass review (cheap default)
  /pr-review  origin/main --deep   Fan out to 8 parallel reviewer subagents
  /pr-review  --pr 123 --deep --verify   ...and adversarially refute high findings
  /explain-pr --staged             Explain a change set in plain English
  /draft-pr   origin/main          Draft a PR title + description

  The skills shell out to the read-only tools above for deterministic context,
  then the AI reviews/explains/drafts with live codebase access. --deep delegates
  to the review-* subagents (installed in ~/.claude/agents).

For Cursor (project-scoped skills), also run:
  ./install.sh --cursor-project /path/to/your/repo

Note: ai-pr-review / ai-explain-pr / ai-draft-pr are read-only. Only ai-open-pr
modifies your repo and GitHub, and it confirms before each step.
EOF
