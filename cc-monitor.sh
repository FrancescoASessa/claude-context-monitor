#!/usr/bin/env bash
set -euo pipefail

# CONFIG
COLOR="blue"
BASELINE_TOKENS=20000
BAR_WIDTH=10

# MODULE TOGGLES
MOD_CONTEXT_DANGER=1
MOD_TRANSCRIPT_SIZE=1
MOD_SESSION_DURATION=1
MOD_MESSAGE_COUNT=1
MOD_NEXT_TOKEN_ESTIMATE=1
MOD_MEMORY_BREAKDOWN=1
MOD_FILE_COUNT=1
MOD_TOOL_ACTIVITY=1
MOD_SMART_RESET=1

# Thresholds
DANGER_YELLOW=70
DANGER_ORANGE=85
DANGER_RED=95
SMART_RESET_PCT=85
SMART_RESET_MSGS=40

# Optional user config
[[ -f "$HOME/.cc-monitorrc" ]] && source "$HOME/.cc-monitorrc"

# COLOR SETUP
setup_colors() {
    C_RESET='\033[0m'
    C_GRAY='\033[38;5;245m'
    C_BAR_EMPTY='\033[38;5;238m'
    C_YELLOW='\033[38;5;178m'
    C_ORANGE='\033[38;5;208m'
    C_RED='\033[38;5;196m'

    case "$COLOR" in
        blue) C_ACCENT='\033[38;5;74m' ;;
        *) C_ACCENT="$C_GRAY" ;;
    esac
}

# INPUT
read_input() { INPUT=$(cat); }
json() { echo "$INPUT" | jq -r "$1"; }

# BASIC INFO
get_model() { json '.model.display_name // .model.id // "?"'; }
get_cwd() { json '.cwd // empty'; }
get_dir() { basename "$1" 2>/dev/null || echo "?"; }
get_transcript_path() { json '.transcript_path // empty'; }
get_max_context() { json '.context_window.context_window_size // 200000'; }

# TRANSCRIPT ANALYSIS (single jq pass)
analyze_transcript() {
    local transcript="$1"
    [[ ! -f "$transcript" ]] && return

    jq -s '
    def usage_tokens:
        (.message.usage.input_tokens // 0) +
        (.message.usage.cache_read_input_tokens // 0) +
        (.message.usage.cache_creation_input_tokens // 0);

    {
      total_messages: length,
      user_messages: map(select(.type=="user")) | length,
      tool_calls: map(select(.type=="assistant" and .message.tool_calls)) | length,
      files_loaded:
        map(select(.type=="assistant" and .message.tool_calls)) |
        map(.message.tool_calls[]?.function.arguments? | tostring) |
        map(select(test("read_file"))) | length,
      last_usage:
        (map(select(.message.usage)) | last | usage_tokens),
      first_timestamp: (.[0].timestamp // 0),
      last_timestamp: (.[-1].timestamp // 0)
    }
    ' "$transcript"
}

# CONTEXT BAR + DANGER
build_bar() {
    local pct="$1"
    local color="$C_ACCENT"

    if [[ $MOD_CONTEXT_DANGER -eq 1 ]]; then
        if (( pct >= DANGER_RED )); then color="$C_RED"
        elif (( pct >= DANGER_ORANGE )); then color="$C_ORANGE"
        elif (( pct >= DANGER_YELLOW )); then color="$C_YELLOW"
        fi
    fi

    local bar=""
    for ((i=0; i<BAR_WIDTH; i++)); do
        local threshold=$((i * 10))
        local progress=$((pct - threshold))
        if (( progress >= 8 )); then
            bar+="${color}█${C_RESET}"
        elif (( progress >= 3 )); then
            bar+="${color}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done
    echo "$bar"
}

# MAIN
main() {
    setup_colors
    read_input

    local model cwd dir transcript max_context
    model=$(get_model)
    cwd=$(get_cwd)
    dir=$(get_dir "$cwd")
    transcript=$(get_transcript_path)
    max_context=$(get_max_context)

    local transcript_json
    transcript_json=$(analyze_transcript "$transcript")

    local total_messages user_messages tool_calls files_loaded
    local context_tokens first_ts last_ts

    total_messages=$(echo "$transcript_json" | jq -r '.total_messages // 0')
    user_messages=$(echo "$transcript_json" | jq -r '.user_messages // 0')
    tool_calls=$(echo "$transcript_json" | jq -r '.tool_calls // 0')
    files_loaded=$(echo "$transcript_json" | jq -r '.files_loaded // 0')
    context_tokens=$(echo "$transcript_json" | jq -r '.last_usage // 0')
    first_ts=$(echo "$transcript_json" | jq -r '.first_timestamp // 0')
    last_ts=$(echo "$transcript_json" | jq -r '.last_timestamp // 0')

    if (( context_tokens > 0 )); then
        pct=$((context_tokens * 100 / max_context))
    else
        pct=$((BASELINE_TOKENS * 100 / max_context))
    fi
    (( pct > 100 )) && pct=100

    bar=$(build_bar "$pct")

    ###################################
    # Primary line
    ###################################
    printf "%b\n" \
    "${C_ACCENT}${model}${C_GRAY} | 📁${dir} | ${bar} ${pct}%${C_RESET}"

    ###################################
    # Secondary indicators
    ###################################
    info=""

    # Transcript size
    if [[ $MOD_TRANSCRIPT_SIZE -eq 1 && -f "$transcript" ]]; then
        size=$(du -h "$transcript" | cut -f1)
        info+="📜 ${size}  "
    fi

    # Session duration
    if [[ $MOD_SESSION_DURATION -eq 1 && $first_ts -gt 0 ]]; then
        duration=$((last_ts - first_ts))
        mins=$((duration / 60))
        info+="⏱ ${mins}m  "
    fi

    # Message count
    if [[ $MOD_MESSAGE_COUNT -eq 1 ]]; then
        info+="💬 ${total_messages} msgs  "
    fi

    # Tool activity
    if [[ $MOD_TOOL_ACTIVITY -eq 1 ]]; then
        info+="🔧 ${tool_calls} tools  "
    fi

    # File count
    if [[ $MOD_FILE_COUNT -eq 1 ]]; then
        info+="📂 ${files_loaded} files  "
    fi

    # Memory breakdown
    if [[ $MOD_MEMORY_BREAKDOWN -eq 1 ]]; then
        sys=$BASELINE_TOKENS
        chat=$((context_tokens - BASELINE_TOKENS))
        (( chat < 0 )) && chat=0
        info+="🧠 sys:${sys/1000}k chat:${chat/1000}k  "
    fi

    # Next token estimate (simple heuristic)
    if [[ $MOD_NEXT_TOKEN_ESTIMATE -eq 1 ]]; then
        avg=$(( context_tokens / (total_messages + 1) ))
        info+="≈ ${avg/1000}k/msg  "
    fi

    # Smart reset suggestion
    if [[ $MOD_SMART_RESET -eq 1 ]]; then
        if (( pct > SMART_RESET_PCT && total_messages > SMART_RESET_MSGS )); then
            info+="${C_RED}♻ suggest reset${C_RESET}"
        fi
    fi

    [[ -n "$info" ]] && echo -e "$info"
}

main