#!/usr/bin/env bash
#
# monitor.sh — live os.Logger feed for Clicky, filtered to the app's subsystem.
#
# Clicky's structured telemetry (ClickyTelemetry / os.Logger) is emitted under a
# single subsystem. Unlike the legacy print() calls (which go to stdout and are
# invisible once the app detaches from Xcode), os.Logger entries flow into the
# unified logging system and are readable here EVEN WHEN the app runs in the
# background — which is exactly the case Watch Mode / Live Companion exercise.
#
# USAGE
#   scripts/monitor.sh                 # live stream, default level=debug, all categories
#   scripts/monitor.sh oauth           # live stream, only the 'oauth' category
#   scripts/monitor.sh --level info    # live stream at info+ (drops debug)
#   scripts/monitor.sh --since 10m     # HISTORY: last 10 minutes via `log show`
#   scripts/monitor.sh --since 10m oauth
#
# Categories (one per feature + build/pipeline):
#   handsOn  screenMemory  watchMode  liveAudio  spokenMacros  oauth
#   terminalBridge  pipeline  provider  worker  build
#
# CONSOLE.APP ALTERNATIVE
#   Open /Applications/Utilities/Console.app, pick this Mac under Devices, and in
#   the search bar type:  subsystem:com.yourcompany.leanring-buddy
#   Use Action ▸ "Include Info Messages" + "Include Debug Messages" to see .debug
#   / .info lines (Console hides them by default), then Start streaming. Add
#   `category:oauth` to the search to scope to one feature. This script is the
#   headless equivalent and is what an agent should use during a test pass.

set -u

# The subsystem MUST equal the value passed to Logger(subsystem:) in
# ClickyTelemetry, which is the app bundle id. If you change the bundle id, change
# this too (and the subsystem in ClickyTelemetry.swift).
SUBSYSTEM="com.yourcompany.leanring-buddy"

LEVEL="debug"     # debug | info | default(notice) — `log` floor for stream/show
SINCE=""          # if set, switch from live `log stream` to historical `log show`
CATEGORY=""       # optional single-category filter

# ── Parse args ──────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --level)  LEVEL="${2:-debug}"; shift 2 ;;
    --since)  SINCE="${2:-}";      shift 2 ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)        CATEGORY="$1";       shift   ;;
  esac
done

# ── Build the predicate (subsystem, optionally narrowed to one category) ────
PREDICATE="subsystem == \"${SUBSYSTEM}\""
if [ -n "${CATEGORY}" ]; then
  PREDICATE="${PREDICATE} AND category == \"${CATEGORY}\""
fi

echo "==> subsystem: ${SUBSYSTEM}"
[ -n "${CATEGORY}" ] && echo "==> category : ${CATEGORY}"
echo "==> level    : ${LEVEL}"

if [ -n "${SINCE}" ]; then
  # HISTORY MODE: replay what already happened (e.g. after a background nudge you
  # missed). --since accepts forms like 10m, 1h, '2026-06-23 14:00:00'.
  echo "==> mode     : history (log show --last ${SINCE})"
  echo ""
  exec /usr/bin/log show \
    --predicate "${PREDICATE}" \
    --level "${LEVEL}" \
    --last "${SINCE}" \
    --style compact \
    --info --debug
else
  # LIVE MODE: stream new entries as the app emits them.
  echo "==> mode     : live stream (Ctrl-C to stop)"
  echo ""
  exec /usr/bin/log stream \
    --predicate "${PREDICATE}" \
    --level "${LEVEL}" \
    --style compact
fi
