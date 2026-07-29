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

kairo_is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

kairo_is_port() {
    kairo_is_positive_integer "$1" && [ "$1" -le 65535 ]
}

kairo_is_host() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9.:-]*$ ]]
}

kairo_validate_runtime_paths() {
    local bin_dir="$1" lib_dir="$2" legacy_lib_dir="$3" path
    for path in "$bin_dir" "$lib_dir" "$legacy_lib_dir"; do
        case "$path" in
            *..*|*//*)
                printf 'Kairo 卸载路径包含非法片段: %s\n' "$path" >&2
                return 1
                ;;
            /*) ;;
            *)
                printf 'Kairo 卸载路径不是绝对路径: %s\n' "$path" >&2
                return 1
                ;;
        esac
        case "${path%/}" in
            ""|/|/usr|/usr/local|/etc|/var|/opt|/home)
                printf 'Kairo 拒绝使用过宽的卸载路径: %s\n' "$path" >&2
                return 1
                ;;
        esac
    done
    [ "${bin_dir%/}" != "${lib_dir%/}" ] &&
        [ "${bin_dir%/}" != "${legacy_lib_dir%/}" ] &&
        [ "${lib_dir%/}" != "${legacy_lib_dir%/}" ]
}

kairo_remove_runtime() {
    local bin_dir="$1" lib_dir="$2" legacy_lib_dir="$3"
    local lib_parent needs_sudo=0 target stage
    local -a elevate=() stages=() remnants=()

    kairo_validate_runtime_paths "$bin_dir" "$lib_dir" "$legacy_lib_dir" || return 1
    lib_parent=$(dirname "$lib_dir")

    for target in "$bin_dir" "$(dirname "$lib_dir")" "$(dirname "$legacy_lib_dir")"; do
        [ -w "$target" ] || needs_sudo=1
    done
    if [ "$needs_sudo" -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
        if ! command -v sudo &>/dev/null || ! sudo -v; then
            printf 'Kairo 卸载需要 sudo 权限\n' >&2
            return 1
        fi
        elevate=(sudo)
    fi

    "${elevate[@]}" rm -f -- "${bin_dir}/ka" "${bin_dir}/ot" || return 1
    "${elevate[@]}" rm -rf -- "$lib_dir" "$legacy_lib_dir" || return 1

    # 清理安装被 SIGKILL 等强制中断时可能留下的私有 staging 目录。
    for stage in "${lib_parent}"/.kairo-stage.*; do
        if [ -e "$stage" ] || [ -L "$stage" ]; then
            stages+=("$stage")
        fi
    done
    if [ "${#stages[@]}" -gt 0 ]; then
        "${elevate[@]}" rm -rf -- "${stages[@]}" || return 1
    fi

    for target in "${bin_dir}/ka" "${bin_dir}/ot" "$lib_dir" "$legacy_lib_dir" "${stages[@]}"; do
        if [ -e "$target" ] || [ -L "$target" ]; then
            remnants+=("$target")
        fi
    done
    if [ "${#remnants[@]}" -gt 0 ]; then
        printf 'Kairo 卸载后仍有残留:\n' >&2
        printf '  %s\n' "${remnants[@]}" >&2
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

        while true; do
            if IFS= read -r -t 0.1 -u "$fifo_fd" line 2>/dev/null; then
                printf "\r\033[K%s%s\n" "$partial" "$line"
                partial=""
            else
                partial="${partial}${line}"
            fi
            kill -0 "$cmd_pid" 2>/dev/null || break
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
    read -r -p "  按回车键继续..." _
}
