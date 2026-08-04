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

# 计算字符串终端显示宽度（去除 ANSI 序列后按列计）。
_str_width() {
    printf '%s' "$1" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' | wc -L | tr -d '[:space:]'
}

# 按显示宽度右补空格，使结果对齐到指定列数。
_pad_right() {
    local pad
    printf -v pad '%*s' $(($2 - $(_str_width "$1"))) ''
    printf '%s%s' "$1" "$pad"
}

# 格式化操作按钮行：先对齐每项的 [标记] 列到本行最宽标记（CJK 感知），再按列宽拼接。
# 用法: _menu_actions <列宽> "[1]项" "[编号]项" ...
_menu_actions() {
    local width="$1"; shift
    local item plain max_tag=0 tw pad padsp line=""
    for item in "$@"; do
        plain=$(printf '%s' "$item" | sed -E $'s/\x1b\\[[0-9;]*[mK]//g')
        [[ "$plain" =~ ^(\[[^]]*\]) ]] || continue
        tw=$(_str_width "${BASH_REMATCH[1]}")
        (( tw > max_tag )) && max_tag=$tw
    done
    for item in "$@"; do
        if (( max_tag > 0 )); then
            plain=$(printf '%s' "$item" | sed -E $'s/\x1b\\[[0-9;]*[mK]//g')
            if [[ "$plain" =~ ^(\[[^]]*\]) ]]; then
                tw=$(_str_width "${BASH_REMATCH[1]}")
                pad=$(( max_tag - tw ))
                (( pad > 0 )) && { printf -v padsp '%*s' "$pad" ''; item=${item/]/]"$padsp"}; }
            fi
        fi
        line+="$(_pad_right "$item" "$width")"
    done
    echo -e "  ${line}"
}

# 统一渲染动态编号范围；空列表不显示无效的 [1-0]。
kairo_menu_range() {
    local count="$1" label="$2"
    if [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
        printf '[1-%s] %s' "$count" "$label"
    else
        printf '[--] %s' "$label"
    fi
}

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

# 单工具标准菜单：状态 + 安装/检查升级/返回。
# 用法: _tool_menu <标题>，工具模块需提供 do_status/do_install/do_upgrade。
_tool_menu() {
    local title_text="$1" choice
    while true; do
        clear
        title "$title_text"
        do_status || true
        divider
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 安装"
        _menu_actions 20 "${C_BOLD}[2]${C_RESET} 检查并升级"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_install ;;
            2) do_upgrade ;;
            0) return ;;
            *) error "无效选项" ;;
        esac
        kairo_pause
    done
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

# 刷新 apt 软件源索引；失败时返回非零（错误提示由调用方决定）。
kairo_apt_update() {
    sudo apt-get update
}

# 刷新索引后安装一个或多个 apt 包。用法: kairo_apt_install curl wget htop
kairo_apt_install() {
    [ $# -gt 0 ] || return 0
    kairo_apt_update || return $?
    sudo apt-get install -y "$@"
}

# 刷新索引后仅升级已安装的 apt 包。用法: kairo_apt_upgrade gh sqlite3
kairo_apt_upgrade() {
    [ $# -gt 0 ] || return 0
    kairo_apt_update || return $?
    sudo apt-get install -y --only-upgrade "$@"
}

# apt 渠道单包升级流程：刷新源 → 比对候选版本 → 确认 → 升级。
# 用法: _tool_apt_upgrade <包名> <显示名>，成功返回 0 并打印提示。
_tool_apt_upgrade() {
    local package="$1" display="$2" installed candidate confirm
    sudo -v || { error "升级需要 sudo 权限"; return 1; }
    if ! kairo_apt_update; then
        error "刷新软件源失败"
        return 1
    fi
    installed=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null)
    candidate=$(apt-cache policy "$package" | awk '/Candidate:/ { print $2; exit }')
    [ -n "$candidate" ] && [ "$candidate" != "(none)" ] || { error "无法获取候选版本"; return 1; }
    if [ "$installed" = "$candidate" ]; then
        success "系统包已是最新版本 ($installed)"
        return 0
    fi
    info "$installed → $candidate"
    read -r -p "  通过 apt 升级 ${display}? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    if kairo_apt_upgrade "$package"; then
        return 0
    else
        error "${display} 升级失败"
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

# 下载远端安装脚本到临时文件并执行，结束后清理。
# 用法: _tool_run_remote_installer <URL> [解释器 bash|sh]
_tool_run_remote_installer() {
    local url="$1" interpreter="${2:-bash}" installer rc
    installer=$(mktemp) || return 1
    if ! curl --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 1 -fsSL \
        "$url" -o "$installer"; then
        rm -f -- "$installer"
        return 1
    fi
    "$interpreter" "$installer"
    rc=$?
    rm -f -- "$installer"
    return "$rc"
}

# 由 kairo.sh 与各模块菜单调用，部分调用传入提示文案；单文件分析无法感知跨文件传参。
# shellcheck disable=SC2120
kairo_pause() {
    local prompt="${1:-按回车键继续...}"
    read -r -p "  ${prompt}" _
}
