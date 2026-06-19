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

# Low-level clipboard put: copy stdin to the clipboard with no fallback and no
# logging. Returns 0 only if a clipboard command exists AND succeeded; non-zero
# otherwise. Callers that need to know whether the clipboard actually received
# the content (e.g. agh_send_to_cursor) should use this instead of
# agh_copy_to_clipboard, which always returns 0 because it falls back to stdout.
_agh_clipboard_put() {
  local cmd
  cmd="$(agh_clipboard_cmd)" || return 1
  # `cmd` is one of the fixed literals from agh_clipboard_cmd (never user input);
  # eval only splits the command and its static args into words.
  # shellcheck disable=SC2086
  eval "$cmd"
}

# Copy stdin to the clipboard. Falls back to printing to stdout with a
# warning when no clipboard command is available.
agh_copy_to_clipboard() {
  local cmd
  if cmd="$(agh_clipboard_cmd)"; then
    # `cmd` is always one of the fixed literals returned by agh_clipboard_cmd
    # (e.g. "pbcopy", "xclip -selection clipboard") — never user input — so the
    # eval below cannot be influenced externally. eval is used only to split the
    # command and its static args into words. Keep this invariant if editing.
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

# Send assembled content (a file) to Cursor's chat: copy it to the clipboard,
# then activate Cursor, open the chat (Cmd+L), and paste (Cmd+V). macOS only;
# elsewhere (or on failure) it leaves the prompt on the clipboard with a hint.
#   $1 = path to the content file
#   honors AGH_CURSOR_SUBMIT=1 to also press Return (auto-send the prompt).
agh_send_to_cursor() {
  local file="$1"

  # Try to put the prompt on the clipboard, tracking whether it actually
  # worked so we don't tell the user it's on the clipboard when it isn't (e.g.
  # a headless box with no pbcopy/xclip/wl-copy).
  local clip_hint
  if _agh_clipboard_put <"$file" >/dev/null 2>&1; then
    clip_hint="the prompt is on your clipboard"
  else
    clip_hint="no clipboard tool was found, so the prompt is NOT on your clipboard — re-run with --out FILE to save it"
  fi

  if [ "$(uname -s)" != "Darwin" ]; then
    agh_warn "--cursor auto-paste is macOS-only; $clip_hint."
    return 0
  fi
  if ! command -v osascript >/dev/null 2>&1; then
    agh_warn "osascript not found; $clip_hint."
    return 0
  fi

  local submit_line=""
  if [ "${AGH_CURSOR_SUBMIT:-}" = "1" ]; then
    submit_line="keystroke return"
  fi

  # Ordering: activate Cursor -> focus the chat pane (Cmd+L) -> open a NEW chat
  # tab (Cmd+T, a chat-context shortcut that needs the chat focused) -> paste.
  if osascript >/dev/null 2>&1 <<OSA
tell application "Cursor" to activate
delay 0.8
tell application "System Events"
  tell process "Cursor"
    keystroke "l" using {command down}
    delay 0.4
    keystroke "t" using {command down}
    delay 0.4
    keystroke "v" using {command down}
    delay 0.2
    $submit_line
  end tell
end tell
OSA
  then
    agh_info "opened Cursor and pasted the prompt into the chat."
  else
    agh_warn "couldn't drive Cursor automatically — $clip_hint (paste with Cmd+V if so)."
    agh_warn "If this keeps failing, grant Accessibility permission to your terminal app:"
    agh_warn "  System Settings > Privacy & Security > Accessibility > enable your terminal."
  fi
}
