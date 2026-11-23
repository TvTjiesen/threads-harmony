#!/bin/sh
# MatePad-side restricted profile worker. Keep terminal in foreground; Ctrl-C stops it.
# Pass the bridge URL and token as shell variables, never commit them.
set -eu
: "${BRIDGE_URL:?Set BRIDGE_URL to the authenticated private-tunnel URL}"
: "${BRIDGE_TOKEN:?Set BRIDGE_TOKEN from the Windows operator}"
: "${PROJECT_ROOT:?Set PROJECT_ROOT to the local Stage project root}"
exec node "$(dirname "$0")/worker.mjs" --bridge "$BRIDGE_URL" --root "$PROJECT_ROOT" --worker matepad-codearts --poll 2500
