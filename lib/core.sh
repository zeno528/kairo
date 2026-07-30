#!/usr/bin/env bash
# Kairo 公共运行时：UI、异步提示和远程文件获取。

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
# shellcheck disable=SC2034 # 由模块和主入口使用。
C_DIM=$'\033[2m'
C_GREEN=$'\033[1;32m'
C_CYAN=$'\033[1;36m'
C_YELLOW=$'\033[1;33m'
C_RED=$'\033[1;31m'
C_GRAY=$'\033[37m'

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

kairo_is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

kairo_is_port() {
    kairo_is_positive_integer "$1" && [ "$1" -le 65535 ]
}

kairo_is_host() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9.:-]*$ ]]
}

kairo_version_is_newer() {
    local candidate="$1" current="$2"
    [ -n "$candidate" ] && [ -n "$current" ] && [ "$candidate" != "$current" ] || return 1
    [ "$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n 1)" = "$candidate" ]
}

kairo_deb_package_for_path() {
    local path="$1" owner packages
    path=$(readlink -f -- "$path") || return 1
    owner=$(dpkg-query -S "$path" 2>/dev/null) || return 1
    packages=${owner%%: *}
    printf '%s\n' "${packages%%,*}"
}

kairo_require_systemctl() {
    if ! command -v systemctl &>/dev/null; then
        error "未找到 systemctl 命令"
        return 1
    fi
}

_with_spinner() {
    local msg="${1:-处理中}"
    shift

    [ -t 1 ] || { "$@"; return $?; }

    (
        local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0 line partial="" temp_dir fifo cmd_pid="" fifo_fd rc
        temp_dir=$(mktemp -d)
        fifo="${temp_dir}/output.fifo"
        mkfifo "$fifo"

        spinner_command_cleanup() {
            if [ -n "$cmd_pid" ] && kill -0 "$cmd_pid" 2>/dev/null; then
                kill "$cmd_pid" 2>/dev/null || true
                wait "$cmd_pid" 2>/dev/null || true
            fi
            if [ -n "${fifo_fd:-}" ]; then
                exec {fifo_fd}<&- 2>/dev/null || true
            fi
            rm -rf -- "$temp_dir"
            printf "\r\033[K"
        }
        trap spinner_command_cleanup EXIT
        trap 'exit 130' INT TERM

        "$@" >"$fifo" 2>&1 &
        cmd_pid=$!
        exec {fifo_fd}<"$fifo"

        while jobs -pr | grep -qx "$cmd_pid"; do
            if IFS= read -r -t 0.1 -u "$fifo_fd" line 2>/dev/null; then
                printf "\r\033[K%s%s\n" "$partial" "$line"
                partial=""
            else
                partial="${partial}${line}"
            fi
            printf "\r\033[K  ${C_CYAN}%s${C_RESET} %s..." "${spin:i++%10:1}" "$msg"
        done

        while IFS= read -r -t 0.1 -u "$fifo_fd" line 2>/dev/null; do
            printf "\r\033[K%s%s\n" "$partial" "$line"
            partial=""
        done
        [ -n "$partial" ] && printf "\r\033[K%s\n" "$partial"

        wait "$cmd_pid" 2>/dev/null
        rc=$?
        cmd_pid=""
        exit "$rc"
    )
}

_SPINNER_PID=""
_start_spinner() {
    [ -t 1 ] || return
    _stop_spinner
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
    if [ -n "$_SPINNER_PID" ]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
    fi
    _SPINNER_PID=""
    [ -t 1 ] && printf "\r\033[K"
}

fetch_remote_file() {
    local path="$1"
    curl --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 \
        -fsSL -H "Accept: application/vnd.github.raw+json" \
        "${CONTENTS_URL}/${path}?ref=${KAIRO_BRANCH}&t=$(date +%s)"
}

kairo_pause() {
    local prompt="${1:-按回车键继续...}"
    read -r -p "  ${prompt}" _
}
