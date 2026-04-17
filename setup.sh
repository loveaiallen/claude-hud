#!/usr/bin/env bash
set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PLUGIN_CONFIG_DIR="$CLAUDE_DIR/plugins/claude-hud"
FORK_RAW="https://raw.githubusercontent.com/loveaiallen/claude-hud/main"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()  { echo -e "${GREEN}✓${NC} $*"; }
warn(){ echo -e "${YELLOW}!${NC} $*"; }
err() { echo -e "${RED}✗${NC} $*"; exit 1; }

echo "Claude HUD Setup"
echo "────────────────"

# ── Step 1: Check claude-hud is installed ─────────────────────────────────
CACHE_DIR=$(ls -d "$CLAUDE_DIR/plugins/cache/claude-hud/claude-hud"/*/ 2>/dev/null \
  | awk -F/ '{ print $(NF-1)"\t"$0 }' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -f2-)

if [ -z "$CACHE_DIR" ]; then
  err "claude-hud not found.\nPlease run /plugin install claude-hud in Claude Code first, then re-run this script."
fi
ok "Found claude-hud: $CACHE_DIR"

# ── Step 2: Download token-usage.md ───────────────────────────────────────
curl -fsSL "$FORK_RAW/commands/token-usage.md" -o "${CACHE_DIR}commands/token-usage.md" \
  || err "Download failed. Check your network connection."
ok "token-usage.md installed"

# ── Step 3: Download billing wrapper scripts ───────────────────────────────
mkdir -p "$PLUGIN_CONFIG_DIR"

curl -fsSL "$FORK_RAW/billing-wrapper.sh" -o "$PLUGIN_CONFIG_DIR/billing-wrapper.sh" \
  || err "Failed to download billing-wrapper.sh"
curl -fsSL "$FORK_RAW/billing-update.sh"  -o "$PLUGIN_CONFIG_DIR/billing-update.sh" \
  || err "Failed to download billing-update.sh"

chmod +x "$PLUGIN_CONFIG_DIR/billing-wrapper.sh" "$PLUGIN_CONFIG_DIR/billing-update.sh"
ok "billing-wrapper.sh + billing-update.sh installed"

# ── Step 4: Update settings.json statusLine ────────────────────────────────
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

node - "$SETTINGS_FILE" "$PLUGIN_CONFIG_DIR/billing-wrapper.sh" << 'JSEOF'
const [,, settingsPath, wrapperPath] = process.argv;
const fs = require('fs');

let settings = {};
if (fs.existsSync(settingsPath)) {
  try { settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch(e) {}
}

settings.statusLine = { type: 'command', command: `bash ${wrapperPath}` };
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');
JSEOF

ok "settings.json updated  →  statusLine → billing-wrapper.sh"

# ── Step 5: Get billing tag(s) ─────────────────────────────────────────────
if [ "$#" -gt 0 ]; then
  TAGS=("$@")
else
  printf "Enter your billing tag (e.g. ALLEN): "
  read -r TAG
  [ -z "$TAG" ] && err "Billing tag cannot be empty."
  TAGS=("$TAG")
fi

# ── Step 6: Write config.json ──────────────────────────────────────────────
CONFIG_FILE="$PLUGIN_CONFIG_DIR/config.json"
TAGS_JSON=$(node -e "console.log(JSON.stringify(process.argv.slice(1)))" -- "${TAGS[@]}")

node - "$CONFIG_FILE" "$TAGS_JSON" << 'JSEOF'
const [,, configPath, tagsJson] = process.argv;
const fs = require('fs');
const tags = JSON.parse(tagsJson);

let cfg = {};
if (fs.existsSync(configPath)) {
  try { cfg = JSON.parse(fs.readFileSync(configPath, 'utf8')); } catch(e) {}
}

cfg.billing = { customTags: tags };

if (!cfg.display) {
  cfg.display = {
    showTools: true, showAgents: true, showTodos: true,
    showDuration: true, showConfigCounts: true, showSessionName: true,
    showTokenBreakdown: true, showSpeed: true, showUsage: true,
    showSessionTokens: true, usageBarEnabled: true
  };
}
if (!cfg.lineLayout)                  cfg.lineLayout = 'compact';
if (cfg.showSeparators === undefined) cfg.showSeparators = true;
if (!cfg.gitStatus) cfg.gitStatus = {
  enabled: true, showDirty: true, showAheadBehind: false, showFileStats: false
};

fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2) + '\n');
JSEOF

ok "config.json saved  →  billing tags: [${TAGS[*]}]"
echo ""
echo "All done! Restart Claude Code — the Billing line will appear in the HUD."
