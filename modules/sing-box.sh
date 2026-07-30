#!/bin/bash
# sing-box - 代理一键脚本（eooce / yonggekkk 双版本）

_SINGBOX_EOOCE_URL="https://raw.githubusercontent.com/eooce/sing-box/main/sing-box.sh"
_SINGBOX_YONGGEKKK_URL="https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh"

do_install() {
    local version
    echo ""
    _menu_actions 24 "${C_BOLD}[1]${C_RESET} eooce 版（轻量，Docker 部署）"
    _menu_actions 24 "${C_BOLD}[2]${C_RESET} yonggekkk 版（reality/hysteria2/订阅）"
    _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回"
    divider
    echo ""
    read -r -p "  选择版本: " version
    case "$version" in
        1) bash -c \
            'curl --connect-timeout 10 --max-time 300 --retry 2 -fsSL "$0" | bash' \
            "$_SINGBOX_EOOCE_URL" ;;
        2) bash -c \
            'curl --connect-timeout 10 --max-time 300 --retry 2 -fsSL "$0" | bash' \
            "$_SINGBOX_YONGGEKKK_URL" ;;
        0) return 0 ;;
        *) error "无效选项"; return 1 ;;
    esac
}

menu() {
    local choice
    while true; do
        clear
        title "📦 sing-box 代理"
        divider
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 安装 / 运行"
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
