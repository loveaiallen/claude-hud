---
description: Query your token usage and cost for a selected time period
allowed-tools: Bash, AskUserQuestion
---

# Token Usage Query

Query token usage and cost from the Wisers billing API for a given time period.

## Step 1: Select Time Period

Use AskUserQuestion:
- header: "Time Period"
- question: "Select the time period to query:"
- multiSelect: false
- options:
  - "Today" — From 00:00 today to today
  - "This week" — From Monday of the current week to today
  - "This month" — From the 1st of the current month to today
  - "Custom" — Enter a custom start and end date

## Step 2: Calculate Dates

Use Bash to compute `START_DATE` and `END_DATE` in `YYYY-MM-DD` format based on the selection.

**Today:**
```bash
date +%Y-%m-%d
```
Both start_date and end_date = today's date.

**This week (Monday → today):**
```bash
# Monday of current week
date -d "$(date +%Y-%m-%d) -$(( ($(date +%u) - 1) )) days" +%Y-%m-%d 2>/dev/null \
  || date -v-$(( $(date +%u) - 1 ))d +%Y-%m-%d  # macOS fallback
# End date = today
date +%Y-%m-%d
```

**This month (1st → today):**
```bash
date +%Y-%m-01   # start
date +%Y-%m-%d   # end (today)
```

**Custom:**
Use AskUserQuestion to ask for start and end dates:
- header: "Start Date"
- question: "Enter start date (YYYY-MM-DD):"
- options: ["Enter date"] — user types date in the Other field

Then:
- header: "End Date"
- question: "Enter end date (YYYY-MM-DD):"
- options: ["Enter date"] — user types date in the Other field

Validate that both dates match the pattern `YYYY-MM-DD`. If invalid, say "Invalid date format, please use YYYY-MM-DD." and stop.

## Step 3: Call the Billing API

First, read `~/.claude/plugins/claude-hud/config.json` to get `billing.customTags`. If the field is missing or the file doesn't exist, fall back to `["CODE", "AILAB", "ALLEN"]`.

Build and run the curl command, substituting `{START_DATE}`, `{END_DATE}`, and the tags array from config:

```bash
TAGS=$(node -e "
const fs = require('fs');
try {
  const cfg = JSON.parse(fs.readFileSync(require('os').homedir() + '/.claude/plugins/claude-hud/config.json', 'utf8'));
  const tags = (cfg.billing && cfg.billing.customTags) || ['CODE','AILAB','ALLEN'];
  console.log(JSON.stringify(tags));
} catch(e) { console.log('[\"CODE\",\"AILAB\",\"ALLEN\"]'); }
")
curl -s -X POST 'http://aiapi.wisers.com/wisers-prompt-layer-library-service/v2/query/billing/tags' \
  --header 'Content-Type: application/json' \
  --data "{\"tags\":{\"custom_tags\":$TAGS},\"start_date\":\"{START_DATE}\",\"end_date\":\"{END_DATE}\"}"
```

If the command fails or returns non-JSON output, say "API request failed. Please check your network connection." and stop.

## Step 4: Parse and Display Results

Parse the JSON response. The structure is:
```json
{
  "cost_aggregate": { "USD": 23.81 },
  "details": [
    {
      "llm_service_name": "...",
      "count": 526,
      "prompt_tokens": 32799151,
      "prompt_tokens_details": {
        "prompt_cached_tokens": 29414719,
        "prompt_store_5m_tokens": 3371531
      },
      "completion_tokens": 153700,
      "sum_tokens": 32952851,
      "sum_cost": 23.81
    }
  ]
}
```

Display results in a clean format. Use Bash with `node -e` or `python3 -c` to parse JSON and format numbers with comma separators.

Example parsing and display with node:
```bash
echo '{JSON}' | node -e "
const data = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
const total_usd = data.cost_aggregate?.USD ?? 0;
const details = data.details ?? [];
const total_tokens = details.reduce((s,d) => s + (d.sum_tokens||0), 0);
const prompt_tokens = details.reduce((s,d) => s + (d.prompt_tokens||0), 0);
const cached_tokens = details.reduce((s,d) => s + (d.prompt_tokens_details?.prompt_cached_tokens||0), 0);
const output_tokens = details.reduce((s,d) => s + (d.completion_tokens||0), 0);
const calls = details.reduce((s,d) => s + (d.count||0), 0);
const cache_pct = prompt_tokens > 0 ? (cached_tokens/prompt_tokens*100).toFixed(1) : '0.0';
const fmt = n => n.toLocaleString('en-US');
console.log('');
console.log('  Token Usage: {START_DATE} → {END_DATE}');
console.log('  ─────────────────────────────────────');
console.log('  API Calls:       ' + fmt(calls));
console.log('  Prompt tokens:   ' + fmt(prompt_tokens) + '  (cached: ' + fmt(cached_tokens) + ' = ' + cache_pct + '%)');
console.log('  Output tokens:   ' + fmt(output_tokens));
console.log('  Total tokens:    ' + fmt(total_tokens));
console.log('  ─────────────────────────────────────');
console.log('  Total cost:      \$' + total_usd.toFixed(4));
if (details.length > 1) {
  console.log('');
  console.log('  Breakdown by model:');
  details.forEach(d => {
    console.log('    ' + d.llm_service_name + ': \$' + d.sum_cost.toFixed(4) + ' (' + fmt(d.sum_tokens) + ' tokens)');
  });
}
console.log('');
"
```

If `details` is empty or the response has no data, display:
```
  No usage data found for {START_DATE} → {END_DATE}
```

After displaying results, ask the user if they want to query another time period:
- Use AskUserQuestion:
  - header: "Again?"
  - question: "Query another time period?"
  - options: ["Yes, query again", "No, done"]

If "Yes", go back to Step 1.
If "No", finish.
