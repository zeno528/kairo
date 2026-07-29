#!/bin/bash
# OPSTOOL - 运维工具箱主入口
# 用法: ot                    # 交互菜单
#       ot <模块> [操作] [参数]  # CLI 调用

LIB_DIR="/usr/local/lib/opstool"
MODULES_DIR="${LIB_DIR}/modules"
VERSION=$(cat "${LIB_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
REPO="zeno528/opstool"
CONTENTS_URL="https://api.github.com/repos/${REPO}/contents"

# 非终端模式自动确认
[ ! -t 0 ] && export AUTO_YES=1

# ── 颜色定义 ──
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_GREEN="\033[1;32m"
C_CYAN="\033[1;36m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_GRAY="\033[37m"

# ── 辅助函数 ──
divider() {
    local width line
    width=$(tput cols 2>/dev/null || echo 80)
    width=$((width - 4))
    [ "$width" -lt 40 ] && width=40
    # 与右侧横向菜单的最宽内容对齐，避免铺满整个终端。
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

# ── 旋转指示器 ──
# 用法: _with_spinner "提示信息" command args...
# 功能: 后台运行命令，前台显示动画指示器；命令输出逐行透传不干扰，
#       静默期间指示器持续旋转，让用户知道"还在跑"。
_with_spinner() {
    local msg="${1:-处理中}"
    shift

    # 非终端（管道/重定向/CI）直接运行，不显示指示器
    [ -t 1 ] || { "$@"; return $?; }

    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0 line partial=""
    local fifo
    fifo=$(mktemp -u)
    mkfifo "$fifo"

    # 命令输出写入 fifo，后台运行
    "$@" >"$fifo" 2>&1 &
    local cmd_pid=$!

    # 打开 fifo 读取端（同时解除写端 open 阻塞）
    exec 9<"$fifo"

    # 主循环：100ms 超时读 + 旋转动画
    while true; do
        if IFS= read -r -t 0.1 -u 9 line 2>/dev/null; then
            printf "\r\033[K%s%s\n" "$partial" "$line"
            partial=""
        else
            # 超时：累积可能的半行数据
            partial="${partial}${line}"
        fi
        # 命令结束则退出循环
        kill -0 "$cmd_pid" 2>/dev/null || break
        # 画旋转指示器
        printf "\r\033[K  ${C_CYAN}%s${C_RESET} %s..." "${spin:i++%10:1}" "$msg"
    done

    # 排空残留输出
    while IFS= read -r -t 0.1 -u 9 line 2>/dev/null; do
        printf "\r\033[K%s%s\n" "$partial" "$line"
        partial=""
    done
    [ -n "$partial" ] && printf "\r\033[K%s\n" "$partial"

    exec 9<&-
    rm -f "$fifo"
    printf "\r\033[K"
    wait "$cmd_pid" 2>/dev/null
    return $?
}

# ── 旋转指示器（轻量版，用于 $(...) 命令替换场景）──
# 用法: _start_spinner "提示信息"; var=$(慢命令); _stop_spinner
# 功能: 纯后台动画，不拦截输出。适合输出需要被 $(...) 捕获的场景。
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

# 通过 GitHub Contents API 获取 main 分支文件，避免 raw CDN 返回陈旧缓存。
fetch_remote_file() {
    local path="$1"
    curl -fsSL -H "Accept: application/vnd.github.raw+json" \
        "${CONTENTS_URL}/${path}?ref=main&t=$(date +%s)"
}

show_banner() {
    local W=42
    local header="─ O P S T O O L "
    local l1="  v${VERSION}"
    local l2="  https://github.com/zeno528/opstool"
    local i dash="" fill="" p1="" p2=""
    for ((i=${#header}; i<W; i++)); do fill+="─"; done
    for ((i=0; i<W; i++)); do dash+="─"; done
    for ((i=${#l1}; i<W; i++)); do p1+=" "; done
    for ((i=${#l2}; i<W; i++)); do p2+=" "; done
    echo -e "  ${C_CYAN}╭${C_BOLD}${header}${C_RESET}${C_CYAN}${fill}╮${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}${C_BOLD}${C_CYAN}${l1}${C_RESET}${p1}${C_CYAN}│${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}${C_DIM}${l2}${C_RESET}${p2}${C_CYAN}│${C_RESET}"
    echo -e "  ${C_CYAN}╰${dash}╯${C_RESET}"
}

do_update() {
    echo ""
    _start_spinner "正在检查更新"
    remote_ver=$(fetch_remote_file VERSION 2>/dev/null | tr -d '[:space:]')
    _stop_spinner
    if [ -z "$remote_ver" ]; then
        error "无法连接远程仓库"
        return
    fi
    if [ "$VERSION" = "$remote_ver" ]; then
        success "已是最新版本 v${VERSION}"
        return
    fi
    warn "发现新版本 v${VERSION} → v${remote_ver}"
    _with_spinner "正在更新 OPSTOOL" bash -c 'fetch_remote_file install.sh | bash'
}

do_uninstall() {
    echo ""
    warn "即将卸载 OPSTOOL，以下文件将被删除:"
    echo -e "  ${C_GRAY}/usr/local/bin/ot${C_RESET}"
    echo -e "  ${C_GRAY}${LIB_DIR}/${C_RESET}"
    echo ""
    read -p "  确认卸载? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm -f /usr/local/bin/ot
        rm -rf "$LIB_DIR"
        success "卸载完成"
        exit 0
    else
        info "已取消"
    fi
}

# 加载模块（统一入口）
_load_module() {
    local module="$1"
    local module_file="${MODULES_DIR}/${module}.sh"
    if [ ! -f "$module_file" ]; then
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        module_file="${SCRIPT_DIR}/modules/${module}.sh"
    fi
    if [ ! -f "$module_file" ]; then
        error "模块不存在: $module"
        return
    fi
    export OPSTOOL_MODE="module"
    # shellcheck disable=SC1090
    source "$module_file"
    if type menu &>/dev/null; then menu; fi
}

# ── CLI 参数入口 ──
if [ $# -gt 0 ]; then
    case "$1" in
        update) do_update; exit $? ;;
        uninstall) do_uninstall; exit $? ;;
        help|--help|-h)
            echo "用法: ot                    # 交互菜单"
            echo "      ot <模块> [操作] [参数]  # CLI 调用"
            echo "      ot update               # 检查更新"
            echo "      ot uninstall            # 卸载"
            echo ""
            echo "模块: ssh-keys ssh-passwd sys-info port-proc firewall"
            echo "      services crontab ssl-check security-update network-test"
            echo "      docker nginx"
            exit 0
            ;;
        *)
            _CLI_MODULE="$1"; shift
            # 查找模块文件
            _CLI_FILE="${MODULES_DIR}/${_CLI_MODULE}.sh"
            if [ ! -f "$_CLI_FILE" ]; then
                SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
                _CLI_FILE="${SCRIPT_DIR}/modules/${_CLI_MODULE}.sh"
            fi
            if [ ! -f "$_CLI_FILE" ]; then
                error "模块不存在: $_CLI_MODULE"; exit 1
            fi
            # shellcheck disable=SC1090
            source "$_CLI_FILE"
            if [ $# -eq 0 ]; then
                type menu &>/dev/null && menu
            else
                _CLI_ACTION="$1"; shift
                _CLI_FUNC="do_${_CLI_ACTION}"
                if type "$_CLI_FUNC" &>/dev/null; then
                    "$_CLI_FUNC" "$@"
                else
                    error "操作不存在: $_CLI_ACTION"; exit 1
                fi
            fi
            exit $?
            ;;
    esac
fi

# 主菜单
while true; do
    show_banner
    divider
    R=42
    echo -ne "  ${C_GREEN}${C_BOLD}🔒 SSH${C_RESET}"; printf "\033[${R}G"; echo -e "  ${C_BOLD}[U]${C_RESET} 检查更新"
    echo -ne "   ${C_BOLD}[1]${C_RESET} 密码登录管理"; printf "\033[${R}G"; echo -e "  ${C_BOLD}[X]${C_RESET} 卸载 OPSTOOL"
    echo -ne "   ${C_BOLD}[2]${C_RESET} 公钥管理"; printf "\033[${R}G"; echo -e "  ${C_BOLD}[0]${C_RESET} 退出"
    echo ""
    echo -e "  ${C_CYAN}${C_BOLD}🖥  系统${C_RESET}"
    echo -e "   ${C_BOLD}[3]${C_RESET} 系统信息查看"
    echo -e "   ${C_BOLD}[4]${C_RESET} 端口/进程管理"
    echo -e "   ${C_BOLD}[5]${C_RESET} 防火墙管理"
    echo -e "   ${C_BOLD}[6]${C_RESET} 系统服务管理"
    echo -e "   ${C_BOLD}[7]${C_RESET} 定时任务"
    echo -e "   ${C_BOLD}[8]${C_RESET} SSL 证书检查"
    echo -e "   ${C_BOLD}[9]${C_RESET} 安全更新"
    echo -e "   ${C_BOLD}[10]${C_RESET} 网络测试"
    echo -e "   ${C_BOLD}[11]${C_RESET} Docker 管理"
    echo ""
    echo -e "  ${C_CYAN}${C_BOLD}🌐  反代${C_RESET}"
    echo -e "   ${C_BOLD}[12]${C_RESET} Nginx 管理"
    divider
    echo ""
    read -p "  请输入选项: " choice

    case "$choice" in
        1) _load_module ssh-passwd ;;
        2) _load_module ssh-keys ;;
        3) _load_module sys-info ;;
        4) _load_module port-proc ;;
        5) _load_module firewall ;;
        6) _load_module services ;;
        7) _load_module crontab ;;
        8) _load_module ssl-check ;;
        9) _load_module security-update ;;
        10) _load_module network-test ;;
        11) _load_module docker ;;
        12) _load_module nginx ;;
        [Uu])
            do_update
            echo ""; read -p "  按回车键重启 OPSTOOL..." -r _
            exec "$0"
            ;;
        [Xx])
            do_uninstall; echo ""; read -p "  按回车键继续..."
            ;;
        0)
            echo -e "\n  👋 后会有期！\n"; exit 0
            ;;
        *)
            error "无效选项"; sleep 1
            ;;
    esac
done
