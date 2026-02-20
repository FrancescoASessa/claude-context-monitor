# cc-monitor.sh

A rich two-line status monitor for Claude Code that displays model, directory, context usage with color-coded danger levels, session duration, message stats, tool activity, memory breakdown, and smart reset suggestions.

**Example output:**
```
claude-sonnet-4-5 | 📁my-project | ████████░░ 82% 
📜 142K  ⏱ 34m  💬 87 msgs  🔧 23 tools  📂 6 files  🧠 sys:20k chat:144k  ≈ 1k/msg
```

## Installation

1. Copy the script to your Claude scripts directory:
   ```bash
   mkdir -p ~/.claude/scripts
   cp cc-monitor.sh ~/.claude/scripts/
   chmod +x ~/.claude/scripts/cc-monitor.sh
   ```

2. Update your `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/scripts/cc-monitor.sh"
     }
   }
   ```

3. (Optional) Create a config file for personal overrides:
   ```bash
   touch ~/.cc-monitorrc
   ```

## Configuration

Edit the variables at the top of the script to customize behavior:

```bash
COLOR="blue"           # accent color (blue or gray)
BASELINE_TOKENS=20000  # assumed system prompt size
BAR_WIDTH=10           # width of the context bar
```

### Module Toggles

Every indicator can be turned on (`1`) or off (`0`):

| Variable | Default | Description |
|---|---|---|
| `MOD_CONTEXT_DANGER` | `1` | Color-coded danger levels on the bar |
| `MOD_TRANSCRIPT_SIZE` | `1` | Size of the transcript file on disk |
| `MOD_SESSION_DURATION` | `1` | Elapsed time since session start |
| `MOD_MESSAGE_COUNT` | `1` | Total message count |
| `MOD_TOOL_ACTIVITY` | `1` | Number of assistant turns with tool calls |
| `MOD_FILE_COUNT` | `1` | Number of `read_file` tool calls |
| `MOD_MEMORY_BREAKDOWN` | `1` | Estimated system vs. chat token split |
| `MOD_NEXT_TOKEN_ESTIMATE` | `1` | Average tokens per message |
| `MOD_SMART_RESET` | `1` | Reset suggestion when context is high |

### Danger Thresholds

The context bar changes color as usage climbs:

| Color | Default threshold |
|---|---|
| Yellow | ≥ 70% |
| Orange | ≥ 85% |
| Red | ≥ 95% |

### Smart Reset

When context usage exceeds `SMART_RESET_PCT` (default `85%`) **and** the session has more than `SMART_RESET_MSGS` (default `40`) messages, a `♻ suggest reset` warning is appended. Both thresholds are configurable.

### User Config File

All variables can be overridden without editing the script by placing them in `~/.cc-monitorrc`:

```bash
# ~/.cc-monitorrc
COLOR="blue"
SMART_RESET_PCT=80
MOD_FILE_COUNT=0
```

## Requirements

- `bash`
- `jq` (for JSON and transcript parsing)
- Claude Code 2.0.65+

## How It Works

Claude Code passes session metadata to status line commands via stdin as JSON. The script reads the following fields:

- `model.display_name` / `model.id` — model name
- `cwd` — current working directory
- `context_window.context_window_size` — maximum context size
- `transcript_path` — path to the session transcript JSONL file

Token usage and all secondary stats are derived from a **single `jq` pass** over the transcript, counting messages, tool calls, file reads, and the latest `usage` block to get precise input token counts (including cache hits and cache creation tokens).