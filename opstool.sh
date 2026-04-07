#!/bin/bash
# OPSTOOL - 运维工具箱主入口
# 用法: ot

LIB_DIR="/usr/local/lib/opstool"
MODULES_DIR="${LIB_DIR}/modules"
VERSION=$(cat "${LIB_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
REPO_URL="https://raw.githubusercontent.com/Ekko7778/opstool/main"

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
divider() { echo -e "  ${C_GRAY}────────────────────────────${C_RESET}"; }
title() { echo -e "\n  ${C_CYAN}${C_BOLD}── $1 ──${C_RESET}"; }
info() { echo -e "  ${C_CYAN}ℹ $1${C_RESET}"; }
success() { echo -e "  ${C_GREEN}✔ $1${C_RESET}"; }
warn() { echo -e "  ${C_YELLOW}⚠ $1${C_RESET}"; }
error() { echo -e "  ${C_RED}✘ $1${C_RESET}"; }

show_banner() {
    echo -e "
${C_BOLD}  █████    ██████╗  ██████╗
██═══  ██  ██╔══██╗ ██║
██║    ██╗ █████╔╝  ██████╗
██║    ██║ ██╔═         ██║
╚██████╔╝  ██║      ██████╔
 ╚═════╝   ╚═╝      ╚═════╝${C_RESET}
${C_DIM}  TOOL${C_RESET}             ${C_GRAY}v${VERSION}${C_RESET}
${C_DIM}  By Ekko7778  ·  github.com/Ekko7778/opstool${C_RESET}"
}

do_update() {
    echo ""
    info "正在检查更新..."
    remote_ver=$(curl -fsSL "${REPO_URL}/VERSION?t=$(date +%s)" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$remote_ver" ]; then
        error "无法连接远程仓库"
        return
    fi
    if [ "$VERSION" = "$remote_ver" ]; then
        success "已是最新版本 v${VERSION}"
        return
    fi
    warn "发现新版本 v${VERSION} → v${remote_ver}"
    curl -fsSL "${REPO_URL}/install.sh?t=$(date +%s)" | bash
}

do_uninstall() {
    echo ""
    warn "即将卸载 OPSTOOL，以下文件将被删除:"
    echo -e "  ${C_GRAY}/usr/local/bin/ot${C_RESET}"
    echo -e "  ${C_GRAY}${LIB_DIR}/${C_RESET}"
    for f in "$MODULES_DIR"/*.sh; do
        [ -f "$f" ] || continue
        alias_name=$(grep -oP 'alias:\s*\K\S+' "$f" 2>/dev/null) || true
        [ -n "$alias_name" ] && echo -e "  ${C_GRAY}/usr/local/bin/${alias_name}${C_RESET}"
    done
    echo ""
    read -p "  确认卸载? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        for f in "$MODULES_DIR"/*.sh; do
            [ -f "$f" ] || continue
            alias_name=$(grep -oP 'alias:\s*\K\S+' "$f" 2>/dev/null) || true
            [ -n "$alias_name" ] && rm -f "/usr/local/bin/${alias_name}"
        done
        rm -f /usr/local/bin/ot
        rm -rf "$LIB_DIR"
        success "卸载完成"
        exit 0
    else
        info "已取消"
    fi
}

# 主菜单
while true; do
    show_banner
    divider
    echo -e "  ${C_BOLD}[1]${C_RESET} 🔑  SSH 密码登录管理"
    echo -e "  ${C_BOLD}[2]${C_RESET} 🗝   SSH 公钥管理"
    echo -e "  ${C_BOLD}[3]${C_RESET} 📊  系统信息查看"
    echo -e "  ${C_BOLD}[4]${C_RESET} 📡  端口/进程管理"
    echo -e "  ${C_BOLD}[5]${C_RESET} 🛡️   防火墙管理"
    divider
    echo -e "  ${C_BOLD}[6]${C_RESET} 🔄  检查更新"
    echo -e "  ${C_BOLD}[7]${C_RESET} 🗑️   卸载 OPSTOOL"
    echo -e "  ${C_BOLD}[0]${C_RESET} 👋  退出"
    divider
    echo ""
    read -p "  请输入选项: " choice

    case "$choice" in
        1)
            export OPSTOOL_MODE="module"
            source "${MODULES_DIR}/ssh-passwd.sh"
            unset OPSTOOL_MODE
            if type menu &>/dev/null; then menu; fi
            ;;
        2)
            export OPSTOOL_MODE="module"
            source "${MODULES_DIR}/ssh-keys.sh"
            unset OPSTOOL_MODE
            if type menu &>/dev/null; then menu; fi
            ;;
        3)
            export OPSTOOL_MODE="module"
            source "${MODULES_DIR}/sys-info.sh"
            unset OPSTOOL_MODE
            if type menu &>/dev/null; then menu; fi
            ;;
        4)
            export OPSTOOL_MODE="module"
            source "${MODULES_DIR}/port-proc.sh"
            unset OPSTOOL_MODE
            if type menu &>/dev/null; then menu; fi
            ;;
        5)
            export OPSTOOL_MODE="module"
            source "${MODULES_DIR}/firewall.sh"
            unset OPSTOOL_MODE
            if type menu &>/dev/null; then menu; fi
            ;;
        6)
            do_update
            # 更新后重新启动脚本以加载新版本
            echo ""; read -p "  按回车键重启 OPSTOOL..." dummy
            exec "$0"
            ;;
        7)
            do_uninstall; echo ""; read -p "  按回车键继续..."
            ;;
        0)
            echo -e "\n  👋 再见！\n"; exit 0
            ;;
        *)
            error "无效选项"; sleep 1
            ;;
    esac
done
