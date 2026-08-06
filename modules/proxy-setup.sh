#!/bin/bash
# proxy-setup - 代理节点搭建（3x-ui / sing-box）

_3XUI_INSTALL_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
_SINGBOX_EOOCE_URL="https://raw.githubusercontent.com/eooce/sing-box/main/sing-box.sh"
_SINGBOX_YONGGEKKK_URL="https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh"

do_3xui() {
    echo ""
    info "即将运行 3x-ui 官方安装脚本（同时用于安装和升级）"
    info "3x-ui 是 Xray 代理面板，支持多协议、流量统计、订阅管理"
    read -r -p "  确认继续? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    _tool_run_remote_installer "$_3XUI_INSTALL_URL"
}

do_singbox_eooce() {
    echo ""
    info "即将运行 sing-box 一键脚本（eooce 版）"
    info "轻量方案，基于 Docker 部署"
    read -r -p "  确认继续? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    _tool_run_remote_installer "$_SINGBOX_EOOCE_URL"
}

do_singbox_yonggekkk() {
    echo ""
    info "即将运行 sing-box 一键脚本（yonggekkk 版）"
    info "功能丰富：reality / hysteria2 / vless / 订阅生成"
    read -r -p "  确认继续? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    _tool_run_remote_installer "$_SINGBOX_YONGGEKKK_URL"
}

menu() {
    local choice
    while true; do
        clear
        title "🚀 节点搭建"
        divider
        _menu_actions 24 "${C_BOLD}[1]${C_RESET} 3x-ui 面板"
        _menu_actions 24 "${C_BOLD}[2]${C_RESET} sing-box（eooce 版）"
        _menu_actions 24 "${C_BOLD}[3]${C_RESET} sing-box（yonggekkk 版）"
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_3xui; echo ""; kairo_pause ;;
            2) do_singbox_eooce; echo ""; kairo_pause ;;
            3) do_singbox_yonggekkk; echo ""; kairo_pause ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
