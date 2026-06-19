#!/usr/bin/env bash
# lib/clipboard.sh — copy stdin to the system clipboard across platforms.
#
# Sourced by entrypoints. Depends on agh_warn/agh_info from common.sh.

# Detect an available clipboard command for the current environment.
# Prints the command name (and any required leading args) on stdout, or
# nothing if none is available.
agh_clipboard_cmd() {
  # macOS
  if command -v pbcopy >/dev/null 2>&1; then
    printf 'pbcopy'
    return 0
  fi
  # Wayland (Linux)
  if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
    printf 'wl-copy'
    return 0
  fi
  # X11 (Linux)
  if command -v xclip >/dev/null 2>&1; then
    printf 'xclip -selection clipboard'
    return 0
  fi
  if command -v xsel >/dev/null 2>&1; then
    printf 'xsel --clipboard --input'
    return 0
  fi
  # Wayland fallback even without WAYLAND_DISPLAY set.
  if command -v wl-copy >/dev/null 2>&1; then
    printf 'wl-copy'
    return 0
  fi
  # Windows / Git Bash / WSL
  if command -v clip.exe >/dev/null 2>&1; then
    printf 'clip.exe'
    return 0
  fi
  if command -v clip >/dev/null 2>&1; then
    printf 'clip'
    return 0
  fi
  return 1
}

# Copy stdin to the clipboard. Falls back to printing to stdout with a
# warning when no clipboard command is available.
agh_copy_to_clipboard() {
  local cmd
  if cmd="$(agh_clipboard_cmd)"; then
    # shellcheck disable=SC2086
    if eval "$cmd"; then
      agh_info "copied prompt to clipboard (via ${cmd%% *})"
      return 0
    fi
    agh_warn "clipboard command '${cmd%% *}' failed; printing to stdout instead."
    cat
    return 0
  fi
  agh_warn "no clipboard command found (tried pbcopy/wl-copy/xclip/xsel/clip.exe); printing to stdout instead."
  cat
}
