#!/bin/bash
# proxy-setup - 代理节点搭建（第三方一键脚本统一管理）

# 第三方一键脚本注册表：key|菜单名|描述|脚本 URL
# 新增脚本只需在此追加一行，并在 modules/registry.sh 的 proxy-setup action 白名单加上对应 key。
PROXY_INSTALLERS=(
    "3xui|3x-ui 面板|Xray 面板，多协议/流量统计/订阅|https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
    "singbox_eooce|sing-box（eooce 版）|四合一协议一键安装（reality/vmess/hy2/tuic5）|https://raw.githubusercontent.com/eooce/sing-box/main/sing-box.sh"
    "singbox_yonggekkk|sing-box（yonggekkk 版）|五合一协议+订阅生成/Argo 隧道|https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh"
)

do_install() {
    local key="$1" entry label url confirm
    [ -n "$key" ] || { error "用法: ka proxy-setup install <key>"; return 1; }
    for entry in "${PROXY_INSTALLERS[@]}"; do
        if [ "${entry%%|*}" = "$key" ]; then
            IFS='|' read -r _ label _ url <<< "$entry"
            break
        fi
    done
    [ -n "$url" ] || { error "未知安装脚本: $key"; return 1; }
    echo ""
    info "即将运行第三方一键脚本：$label"
    info "来源：$url"
    info "启动后由脚本自身接管交互，Kairo 不干预后续流程"
    read -r -p "  确认继续? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    _tool_run_remote_installer "$url"
}

menu() {
    local choice i entry key label desc url
    while true; do
        clear
        title "🚀 节点搭建"
        divider
        i=0
        for entry in "${PROXY_INSTALLERS[@]}"; do
            i=$((i + 1))
            IFS='|' read -r key label desc url <<< "$entry"
            _menu_actions 24 "${C_BOLD}[${i}]${C_RESET} ${label} ${C_DIM}— ${desc}${C_RESET}"
        done
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            0) return ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#PROXY_INSTALLERS[@]}" ]; then
                    IFS='|' read -r key _ _ _ <<< "${PROXY_INSTALLERS[$((choice - 1))]}"
                    do_install "$key"
                    echo ""
                    kairo_pause
                else
                    error "无效选项"; sleep 1
                fi
                ;;
        esac
    done
}
