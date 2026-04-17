#!/bin/bash
# Wraps the claude-hud node process, appending a live billing line below
# the normal HUD output.  Billing data is read from a local cache file
# (billing-cache.txt) so this script never blocks on a network call.
# A background update is triggered whenever the cache is >10 minutes old.

PLUGIN_DIR=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null \
  | awk -F/ '{ print $(NF-1) "\t" $0 }' \
  | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
  | tail -1 \
  | cut -f2-)

CACHE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/claude-hud"
CACHE_FILE="$CACHE_DIR/billing-cache.txt"
UPDATE_SCRIPT="$CACHE_DIR/billing-update.sh"

# ── 1. Run original HUD (stdin is passed through via temp file) ──────────────
TMPSTDIN=$(mktemp)
cat > "$TMPSTDIN"
/usr/local/bin/node "${PLUGIN_DIR}dist/index.js" < "$TMPSTDIN"
EXIT_CODE=$?
rm -f "$TMPSTDIN"

# ── 2. Append billing line from cache ────────────────────────────────────────
if [ -f "$CACHE_FILE" ]; then
  cat "$CACHE_FILE"
fi

# ── 3. Trigger background cache refresh if stale (>10 min) or missing ────────
NEEDS_UPDATE=false
if [ ! -f "$CACHE_FILE" ]; then
  NEEDS_UPDATE=true
else
  CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
  [ "$CACHE_AGE" -gt 600 ] && NEEDS_UPDATE=true
fi

if [ "$NEEDS_UPDATE" = true ] && [ -x "$UPDATE_SCRIPT" ]; then
  "$UPDATE_SCRIPT" > /dev/null 2>&1 &
fi

exit $EXIT_CODE
