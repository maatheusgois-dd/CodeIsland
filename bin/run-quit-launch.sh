#!/usr/bin/env bash
# Shared quit-then-launch helper used by `make run` / `make restart`.
#
# Usage: bin/run-quit-launch.sh <APP_PATH>
#   APP_PATH may be a signed .app bundle or a bare executable.
#
# Mirrors the quit_app() / launch_app() logic in
# scripts/dev-hot-restart.sh so behavior stays consistent across both
# entry points.

set -euo pipefail

APP_PATH="${1:?usage: run-quit-launch.sh <APP_PATH>}"
APP_NAME="CodeIsland"

log() { printf '[run] %s\n' "$*"; }
fail() { printf '[run] ERROR: %s\n' "$*" >&2; exit 1; }

# --- Quit any running instance --------------------------------------------

quit_app() {
  local existing_pids
  existing_pids="$(pgrep -x "$APP_NAME" || true)"
  [[ -z "$existing_pids" ]] && return 0

  log "Stopping existing $APP_NAME process(es): $existing_pids"
  local pid
  for pid in $existing_pids; do
    kill -TERM "$pid" >/dev/null 2>&1 || true
  done

  local deadline all_gone
  deadline=$((SECONDS + 2))
  while ((SECONDS < deadline)); do
    all_gone=1
    for pid in $existing_pids; do
      if kill -0 "$pid" >/dev/null 2>&1; then all_gone=0; break; fi
    done
    ((all_gone == 1)) && return 0
    sleep 0.1
  done

  log "SIGTERM did not stop app within 2s; escalating to SIGKILL"
  for pid in $existing_pids; do
    kill -KILL "$pid" >/dev/null 2>&1 || true
  done

  deadline=$((SECONDS + 2))
  while ((SECONDS < deadline)); do
    all_gone=1
    for pid in $existing_pids; do
      if kill -0 "$pid" >/dev/null 2>&1; then all_gone=0; break; fi
    done
    ((all_gone == 1)) && return 0
    sleep 0.1
  done

  fail "Existing $APP_NAME process(es) still alive after SIGKILL; aborting restart"
}

# --- Launch ----------------------------------------------------------------

launch_app() {
  case "$APP_PATH" in
    *.app/Contents/MacOS/*)
      log "Launching bundle: $APP_PATH"
      open -a "$APP_PATH"
      ;;
    *.app)
      log "Launching bundle: $APP_PATH"
      open "$APP_PATH"
      ;;
    *)
      log "Launching bare executable: $APP_PATH"
      log "NOTE: Buddy Bluetooth requires a signed .app bundle with Bluetooth entitlements"
      "$APP_PATH" &
      ;;
  esac
}

# --- Run -------------------------------------------------------------------

quit_app
launch_app
