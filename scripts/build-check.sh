#!/usr/bin/env bash
#
# build-check.sh — BUILD-ONLY compile check for Clicky (OpenClicky).
#
# Compiles the `leanring-buddy` scheme (Debug, macOS arm64) into an ISOLATED
# DerivedData dir (./.build-check) with code signing DISABLED, then prints a clean
# PASS/FAIL summary with file:line for every error. It NEVER runs, installs, or
# launches the app.
#
# ──────────────────────────────────────────────────────────────────────────────
# TCC TRADE-OFF (READ THIS) — why CLAUDE.md says "do NOT run xcodebuild"
# ──────────────────────────────────────────────────────────────────────────────
#   macOS TCC grants (Screen Recording, Accessibility, Microphone, Automation)
#   are keyed to the app's code-signing identity + bundle id + the binary on disk.
#   Rebuilding the SAME bundle id (com.yourcompany.leanring-buddy) with a different
#   / ad-hoc / unsigned signature can make macOS treat it as a new principal and
#   DROP the grants your Xcode-run copy relies on. That is the real mechanism
#   behind "xcodebuild invalidates TCC permissions".
#
#   This script is the LOWEST-RISK way to do a terminal compile-check because:
#     1. action is `build` ONLY — no run/test/install/launch/archive. TCC is
#        evaluated when an app RUNS, not when it compiles.
#     2. -derivedDataPath points at ./.build-check, NOT Xcode's default
#        DerivedData — the unsigned Clicky.app never overwrites the binary Xcode
#        launches, so the inode/signature TCC remembers is untouched.
#     3. CODE_SIGNING_ALLOWED=NO produces an UNSIGNED product; never executed, it
#        never registers with TCC and can't collide with your Xcode build's grants.
#
#   RESIDUAL RISK is real only if some copy of the same bundle id at a different
#   path/signature gets LAUNCHED. Mitigation: NEVER run ./.build-check/...; this
#   script doesn't, and deletes it on exit. For zero collision risk, prefer the
#   Xcode GUI build (Cmd+B). Run this only when a terminal compile-check is needed.
# ──────────────────────────────────────────────────────────────────────────────

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT="${REPO_ROOT}/leanring-buddy.xcodeproj"
SCHEME="leanring-buddy"
CONFIGURATION="Debug"
DESTINATION="platform=macOS,arch=arm64"
DERIVED_DATA="${REPO_ROOT}/.build-check"
RAW_LOG="${DERIVED_DATA}/xcodebuild.log"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "FAIL: 'xcodebuild' not found. Install Xcode + command line tools (xcode-select --install)." >&2
  exit 127
fi

rm -rf "${DERIVED_DATA}"
mkdir -p "${DERIVED_DATA}"

echo "==> Build-check (compile only, unsigned, isolated DerivedData)"
echo "    scheme ${SCHEME} | config ${CONFIGURATION} | dest ${DESTINATION}"
echo "    derived ${DERIVED_DATA}"
echo ""

# Build action ONLY — never run/install/launch. | cat disables xcodebuild's pager.
set +e
/usr/bin/xcodebuild build \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -skipPackagePluginValidation -skipMacroValidation 2>&1 | tee "${RAW_LOG}" | cat
BUILD_STATUS=${PIPESTATUS[0]}
set -e

echo ""
echo "────────────────────────────────────────────────────────────────────────"
echo "  BUILD-CHECK SUMMARY"
echo "────────────────────────────────────────────────────────────────────────"

# Parse the raw log. xcodebuild prints `file:line:col: error:/warning: message`,
# which gives clean file:line telemetry without depending on xcresulttool versions.
ERR_COUNT=$(grep -cE '^/.*: (error|fatal error):' "${RAW_LOG}" 2>/dev/null || true); ERR_COUNT=${ERR_COUNT:-0}
WARN_COUNT=$(grep -cE '^/.*: warning:' "${RAW_LOG}" 2>/dev/null || true); WARN_COUNT=${WARN_COUNT:-0}

if [ "${ERR_COUNT}" -gt 0 ]; then
  echo "  Errors (${ERR_COUNT}):"
  grep -E '^/.*: (error|fatal error):' "${RAW_LOG}" | sed 's/^/    /'
  echo ""
fi
echo "  Warnings: ${WARN_COUNT} (Swift 6 concurrency + deprecated onChange are known/non-blocking)"
echo "  Raw log : ${RAW_LOG}  (KEEP_BUILD_CHECK=1 to retain after run)"
echo "────────────────────────────────────────────────────────────────────────"

# Gate on BUILD SUCCEEDED + zero errors (a successful build still prints warnings).
SUCCEEDED=0
grep -q "BUILD SUCCEEDED" "${RAW_LOG}" 2>/dev/null && SUCCEEDED=1

if [ "${SUCCEEDED}" -eq 1 ] && [ "${ERR_COUNT}" -eq 0 ] && [ "${BUILD_STATUS}" -eq 0 ]; then
  echo "  RESULT: PASS  (BUILD SUCCEEDED, 0 errors, ${WARN_COUNT} warnings)"
  VERDICT=0
else
  echo "  RESULT: FAIL  (xcodebuild exit ${BUILD_STATUS}, ${ERR_COUNT} errors)"
  VERDICT=1
fi

# Leave nothing with the same bundle id lingering on disk (TCC hygiene).
if [ "${KEEP_BUILD_CHECK:-0}" != "1" ]; then
  rm -rf "${DERIVED_DATA}"
fi

exit ${VERDICT}
