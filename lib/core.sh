#!/usr/bin/env bash
# Kairo 公共运行时：UI、异步提示和远程文件获取。

C_RESET="\033[0m"
C_BOLD="\033[1m"
# shellcheck disable=SC2034 # 由模块和主入口使用。
C_DIM="\033[2m"
C_GREEN="\033[1;32m"
C_CYAN="\033[1;36m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_GRAY="\033[37m"

divider() {
    local width line
    width=$(tput cols 2>/dev/null || echo 80)
    width=$((width - 4))
    [ "$width" -lt 40 ] && width=40
    [ "$width" -gt 60 ] && width=60
    printf -v line '%*s' "$width" ''
    line=${line// /-}
    echo -e "  ${C_GRAY}${line}${C_RESET}"
}

title() { echo -e "\n  ${C_CYAN}${C_BOLD}── $1 ──${C_RESET}"; }
info() { echo -e "  ${C_CYAN}ℹ $1${C_RESET}"; }
success() { echo -e "  ${C_GREEN}✔ $1${C_RESET}"; }
warn() { echo -e "  ${C_YELLOW}⚠ $1${C_RESET}"; }
error() { echo -e "  ${C_RED}✘ $1${C_RESET}"; }

_with_spinner() {
    local msg="${1:-处理中}"
    shift

    [ -t 1 ] || { "$@"; return $?; }

    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0 line partial="" fifo cmd_pid
    fifo=$(mktemp -u)
    mkfifo "$fifo"

    "$@" >"$fifo" 2>&1 &
    cmd_pid=$!
    exec 9<"$fifo"

    while true; do
        if IFS= read -r -t 0.1 -u 9 line 2>/dev/null; then
            printf "\r\033[K%s%s\n" "$partial" "$line"
            partial=""
        else
            partial="${partial}${line}"
        fi
        kill -0 "$cmd_pid" 2>/dev/null || break
        printf "\r\033[K  ${C_CYAN}%s${C_RESET} %s..." "${spin:i++%10:1}" "$msg"
    done

    while IFS= read -r -t 0.1 -u 9 line 2>/dev/null; do
        printf "\r\033[K%s%s\n" "$partial" "$line"
        partial=""
    done
    [ -n "$partial" ] && printf "\r\033[K%s\n" "$partial"

    exec 9<&-
    rm -f "$fifo"
    printf "\r\033[K"
    wait "$cmd_pid" 2>/dev/null
}

_SPINNER_PID=""
_start_spinner() {
    [ -t 1 ] || return
    local msg="${1:-处理中}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while true; do
        printf "\r\033[K  ${C_CYAN}%s${C_RESET} %s..." "${spin:i++%10:1}" "$msg"
        sleep 0.1
    done &
    _SPINNER_PID=$!
}

_stop_spinner() {
    [ -n "$_SPINNER_PID" ] && kill "$_SPINNER_PID" 2>/dev/null
    _SPINNER_PID=""
    [ -t 1 ] && printf "\r\033[K"
}

fetch_remote_file() {
    local path="$1"
    curl -fsSL -H "Accept: application/vnd.github.raw+json" \
        "${CONTENTS_URL}/${path}?ref=${KAIRO_BRANCH}&t=$(date +%s)"
}

kairo_pause() {
    read -r -p "  按回车键继续..." _
}
