#!/bin/bash
# services 模块 - 系统服务管理

_check_systemctl() {
    if ! command -v systemctl &>/dev/null; then
        error "未找到 systemctl 命令"
        return 1
    fi
}

_show_service_status() {
    systemctl status "$1" --no-pager -l 2>/dev/null |
        head -15 |
        sed 's/^/  /'
}

_valid_service_name() {
    [[ "$1" =~ ^[a-zA-Z0-9_.@:-]+$ ]]
}

do_list() {
    _check_systemctl || return
    local svc i
    SERVICE_ITEMS=()
    mapfile -t SERVICE_ITEMS < <(systemctl list-units --type=service --no-pager --no-legend 2>/dev/null | awk '{print $1}' | head -20)
    echo ""
    echo -e "  ${C_BOLD}已加载的服务${C_RESET}"
    for i in "${!SERVICE_ITEMS[@]}"; do
        svc="${SERVICE_ITEMS[$i]}"
        printf "  [%d] %-34s %s\n" "$((i + 1))" "$svc" "$(systemctl is-active "$svc" 2>/dev/null)"
    done
    echo ""
    local total
    _start_spinner "正在统计服务数量"
    total=$(systemctl list-units --type=service --no-pager 2>/dev/null | grep -c 'loaded')
    _stop_spinner
    info "共 $total 个已加载服务（显示前 20 个）"
}

do_status() {
    _check_systemctl || return
    local svc="${1:-}"
    [ -n "$svc" ] || { echo ""; read -p "  输入服务名: " svc; }
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    echo ""
    _with_spinner "正在获取服务状态" _show_service_status "$svc"
}

do_start() {
    _check_systemctl || return
    local svc="${1:-}"
    [ -n "$svc" ] || { echo ""; read -p "  输入服务名: " svc; }
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    _with_spinner "正在启动服务 $svc" sudo systemctl start "$svc" && success "服务 $svc 已启动" || error "启动失败"
}

do_stop() {
    _check_systemctl || return
    local svc="${1:-}"
    [ -n "$svc" ] || { echo ""; read -p "  输入服务名: " svc; }
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    echo ""
    read -p "  确认停止服务 $svc? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    _with_spinner "正在停止服务 $svc" sudo systemctl stop "$svc" && success "服务 $svc 已停止" || error "停止失败"
}

do_restart() {
    _check_systemctl || return
    local svc="${1:-}"
    [ -n "$svc" ] || { echo ""; read -p "  输入服务名: " svc; }
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    _with_spinner "正在重启服务 $svc" sudo systemctl restart "$svc" && success "服务 $svc 已重启" || error "重启失败"
}

do_toggle_enable() {
    _check_systemctl || return
    local svc="${1:-}"
    [ -n "$svc" ] || { echo ""; read -p "  输入服务名: " svc; }
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    echo ""
    local is_enabled
    is_enabled=$(systemctl is-enabled "$svc" 2>/dev/null)
    if [ "$is_enabled" = "enabled" ]; then
        echo -e "  当前: ${C_GREEN}已启用${C_RESET} 开机自启"
        echo ""
        read -p "  关闭开机自启? [y/N]: " confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
        _with_spinner "正在关闭开机自启" sudo systemctl disable "$svc" && success "已关闭 $svc 开机自启"
    else
        echo -e "  当前: ${C_YELLOW}未启用${C_RESET} 开机自启"
        echo ""
        read -p "  开启开机自启? [y/N]: " confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
        _with_spinner "正在开启开机自启" sudo systemctl enable "$svc" && success "已开启 $svc 开机自启"
    fi
}

menu() {
    local choice svc
    while true; do
        title "⚙ 系统服务管理"
        do_list || { kairo_pause "按 Enter 返回上级..."; return; }
        divider
        echo -e "  ${C_BOLD}[编号]${C_RESET} 选择服务    ${C_BOLD}[N]${C_RESET} 输入服务名"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  选择服务或操作: " choice
        case "$choice" in
            0) return ;;
            [Nn]) read -p "  输入服务名: " svc ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#SERVICE_ITEMS[@]} ]; then
                    svc="${SERVICE_ITEMS[$((choice - 1))]}"
                else
                    error "无效选项"; sleep 1; continue
                fi
                ;;
        esac
        [ -z "${svc:-}" ] && continue
        echo ""
        echo "  ${C_BOLD}${svc}${C_RESET}"
        echo "  [1] 查看状态  [2] 启动  [3] 停止"
        echo "  [4] 重启      [5] 开关开机自启  [0] 返回列表"
        read -p "  选择操作: " choice
        case "$choice" in
            1) do_status "$svc" ;;
            2) do_start "$svc" ;;
            3) do_stop "$svc" ;;
            4) do_restart "$svc" ;;
            5) do_toggle_enable "$svc" ;;
            0) continue ;;
            *) error "无效选项"; sleep 1; continue ;;
        esac
        echo ""; kairo_pause "按 Enter 返回服务列表..."
    done
}
