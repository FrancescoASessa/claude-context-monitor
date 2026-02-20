#!/usr/bin/env bash

set -euo pipefail

# CONFIG
COLOR="blue"
BASELINE_TOKENS=20000
BAR_WIDTH=10

# COLOR SETUP
setup_colors() {
    C_RESET='\033[0m'
    C_GRAY='\033[38;5;245m'
    C_BAR_EMPTY='\033[38;5;238m'

    case "$COLOR" in
        orange)   C_ACCENT='\033[38;5;173m' ;;
        blue)     C_ACCENT='\033[38;5;74m' ;;
        teal)     C_ACCENT='\033[38;5;66m' ;;
        green)    C_ACCENT='\033[38;5;71m' ;;
        lavender) C_ACCENT='\033[38;5;139m' ;;
        rose)     C_ACCENT='\033[38;5;132m' ;;
        gold)     C_ACCENT='\033[38;5;136m' ;;
        slate)    C_ACCENT='\033[38;5;60m' ;;
        cyan)     C_ACCENT='\033[38;5;37m' ;;
        *)        C_ACCENT="$C_GRAY" ;;
    esac
}

# JSON HELPERS
read_input() {
    INPUT=$(cat)
}

json() {
    echo "$INPUT" | jq -r "$1"
}

# BASIC INFO
get_model() {
    json '.model.display_name // .model.id // "?"'
}

get_cwd() {
    json '.cwd // empty'
}

get_dir() {
    basename "$1" 2>/dev/null || echo "?"
}

get_transcript_path() {
    json '.transcript_path // empty'
}

get_max_context() {
    json '.context_window.context_window_size // 200000'
}

# GIT STATUS
get_git_branch() {
    git -C "$1" branch --show-current 2>/dev/null || true
}

get_uncommitted_count() {
    git -C "$1" --no-optional-locks status --porcelain -uall 2>/dev/null \
        | wc -l | tr -d ' '
}

get_single_uncommitted_file() {
    git -C "$1" --no-optional-locks status --porcelain -uall 2>/dev/null \
        | head -1 | sed 's/^...//'
}

get_sync_status() {
    local cwd="$1"
    local upstream
    upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null || true)

    [[ -z "$upstream" ]] && { echo "no upstream"; return; }

    local counts
    counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)

    local ahead behind
    ahead=$(echo "$counts" | cut -f1)
    behind=$(echo "$counts" | cut -f2)

    if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
        echo "synced"
    elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
        echo "${ahead} ahead"
    elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
        echo "${behind} behind"
    else
        echo "${ahead} ahead, ${behind} behind"
    fi
}

build_git_status() {
    local cwd="$1"
    local branch file_count sync_status

    branch=$(get_git_branch "$cwd")
    [[ -z "$branch" ]] && return

    file_count=$(get_uncommitted_count "$cwd")
    sync_status=$(get_sync_status "$cwd")

    if [[ "$file_count" -eq 0 ]]; then
        echo "🔀${branch} (0 files uncommitted, ${sync_status})"
    elif [[ "$file_count" -eq 1 ]]; then
        local file
        file=$(get_single_uncommitted_file "$cwd")
        echo "🔀${branch} (${file} uncommitted, ${sync_status})"
    else
        echo "🔀${branch} (${file_count} files uncommitted, ${sync_status})"
    fi
}

# CONTEXT BAR
get_context_length() {
    local transcript="$1"
    [[ ! -f "$transcript" ]] && echo 0 && return

    jq -s '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) |
        last |
        if . then
            (.message.usage.input_tokens // 0) +
            (.message.usage.cache_read_input_tokens // 0) +
            (.message.usage.cache_creation_input_tokens // 0)
        else 0 end
    ' < "$transcript"
}

build_bar() {
    local pct="$1"
    local bar=""

    for ((i=0; i<BAR_WIDTH; i++)); do
        local threshold=$((i * 10))
        local progress=$((pct - threshold))

        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    echo "$bar"
}

build_context() {
    local transcript="$1"
    local max_context="$2"

    local context_length pct prefix
    context_length=$(get_context_length "$transcript")

    if [[ "$context_length" -gt 0 ]]; then
        pct=$((context_length * 100 / max_context))
        prefix=""
    else
        pct=$((BASELINE_TOKENS * 100 / max_context))
        prefix="~"
    fi

    [[ $pct -gt 100 ]] && pct=100

    local bar
    bar=$(build_bar "$pct")

    echo "${bar} ${C_GRAY}${prefix}${pct}% of $((max_context/1000))k tokens"
}

# LAST USER MESSAGE
get_last_user_message() {
    local transcript="$1"
    [[ ! -f "$transcript" ]] && return

    jq -rs '
        [.[] | select(.type == "user") |
         select(.message.content | type == "string" or
                (type == "array" and any(.[]; .type == "text")))] |
        reverse |
        map(.message.content |
            if type == "string" then .
            else [.[] | select(.type == "text") | .text] | join(" ") end |
            gsub("\n"; " ") | gsub("  +"; " ")) |
        map(select(. != "")) |
        first // ""
    ' < "$transcript"
}

# MAIN
main() {
    setup_colors
    read_input

    local model cwd dir transcript max_context git_info context_bar

    model=$(get_model)
    cwd=$(get_cwd)
    dir=$(get_dir "$cwd")
    transcript=$(get_transcript_path)
    max_context=$(get_max_context)

    git_info=""
    [[ -n "$cwd" && -d "$cwd" ]] && \
        git_info=$(build_git_status "$cwd")

    context_bar=$(build_context "$transcript" "$max_context")

    printf "%b\n" \
        "${C_ACCENT}${model}${C_GRAY} | 📁${dir} \
${git_info:+| ${git_info}} | ${context_bar}${C_RESET}"

    local last_msg
    last_msg=$(get_last_user_message "$transcript")

    [[ -n "$last_msg" ]] && echo "💬 $last_msg"
}

main
