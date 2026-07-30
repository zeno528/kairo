#!/bin/bash
# 3x-ui - Xray 代理面板安装与管理 (mhsanaei/3x-ui)

_3XUI_INSTALL_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"

do_status() {
    echo ""
    if command -v x-ui >/dev/null 2>&1; then
        success "3x-ui 已安装"
        x-ui version 2>/dev/null || true
    else
        warn "3x-ui 未安装"
        return 1
    fi
}

do_install() {
    echo ""
    info "即将运行 3x-ui 官方安装脚本（同时用于安装和升级）"
    read -r -p "  确认继续? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    bash -c \
        'curl --connect-timeout 10 --max-time 300 --retry 2 -fsSL "$0" | bash' \
        "$_3XUI_INSTALL_URL"
}

menu() {
    local choice
    while true; do
        clear
        title "📦 3x-ui 面板"
        do_status || true
        divider
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 安装 / 升级"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_install; echo ""; kairo_pause ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
