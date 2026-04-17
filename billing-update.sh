#!/bin/bash
# Fetches today + this week billing data from Wisers API and writes a
# pre-formatted ANSI line to billing-cache.txt.
# Runs in the background; uses a lock file to avoid concurrent fetches.

CACHE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/claude-hud"
CACHE_FILE="$CACHE_DIR/billing-cache.txt"
LOCK_FILE="$CACHE_DIR/billing-update.lock"

# Bail if another update is already running
[ -f "$LOCK_FILE" ] && exit 0
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

TODAY=$(date +%Y-%m-%d)
MONDAY=$(date -d "$(date +%Y-%m-%d) -$(( $(date +%u) - 1 )) days" +%Y-%m-%d 2>/dev/null \
         || date -v-$(( $(date +%u) - 1 ))d +%Y-%m-%d 2>/dev/null \
         || echo "$TODAY")

TMPDIR_LOCAL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LOCAL"; rm -f "$LOCK_FILE"' EXIT

API='http://aiapi.wisers.com/wisers-prompt-layer-library-service/v2/query/billing/tags'

# Read tags from config.json; fall back to empty array if not set
TAGS=$(node -e "
const fs = require('fs');
try {
  const cfg = JSON.parse(fs.readFileSync(require('os').homedir() + '/.claude/plugins/claude-hud/config.json', 'utf8'));
  const tags = (cfg.billing && cfg.billing.customTags) || [];
  console.log(JSON.stringify(tags));
} catch(e) { console.log('[]'); }
" 2>/dev/null || echo '[]')

if [ "\$TAGS" = "[]" ]; then
  echo "" > "\$CACHE_FILE"
  exit 0
fi

# Fetch today and week in parallel
curl -s --connect-timeout 5 -m 15 -X POST "$API" \
  -H 'Content-Type: application/json' \
  -d "{\"tags\":{\"custom_tags\":$TAGS},\"start_date\":\"$TODAY\",\"end_date\":\"$TODAY\"}" \
  > "$TMPDIR_LOCAL/today.json" &

curl -s --connect-timeout 5 -m 15 -X POST "$API" \
  -H 'Content-Type: application/json' \
  -d "{\"tags\":{\"custom_tags\":$TAGS},\"start_date\":\"$MONDAY\",\"end_date\":\"$TODAY\"}" \
  > "$TMPDIR_LOCAL/week.json" &

wait

TODAY_DATA=$(cat "$TMPDIR_LOCAL/today.json" 2>/dev/null)
WEEK_DATA=$(cat "$TMPDIR_LOCAL/week.json" 2>/dev/null)

# Format and write cache using node
/usr/local/bin/node -e "
const DIM   = '\x1b[2m';
const RESET = '\x1b[0m';
const CYAN  = '\x1b[36m';
const GREEN = '\x1b[32m';

function fmt(n) {
  if (n >= 1e9) return (n / 1e9).toFixed(1) + 'B';
  if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
  if (n >= 1000) return Math.round(n / 1000) + 'k';
  return String(n);
}

let todayTokens = 0, todayCost = 0;
let weekTokens  = 0, weekCost  = 0;

try {
  const t = JSON.parse(process.argv[1]);
  todayCost   = t.cost_aggregate?.USD ?? 0;
  todayTokens = (t.details ?? []).reduce((s, d) => s + (d.sum_tokens || 0), 0);
} catch (_) {}

try {
  const w = JSON.parse(process.argv[2]);
  weekCost   = w.cost_aggregate?.USD ?? 0;
  weekTokens = (w.details ?? []).reduce((s, d) => s + (d.sum_tokens || 0), 0);
} catch (_) {}

const line =
  DIM + 'Billing  ' + RESET +
  DIM + 'Today ' + RESET +
  '\$' + todayCost.toFixed(2) +
  DIM + ' (' + fmt(todayTokens) + ')' + RESET +
  DIM + '  │  ' + RESET +
  DIM + 'Week '  + RESET +
  '\$' + weekCost.toFixed(2) +
  DIM + ' (' + fmt(weekTokens) + ')' + RESET;

process.stdout.write(line + '\n');
" "$TODAY_DATA" "$WEEK_DATA" > "$CACHE_FILE.tmp" \
  && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
