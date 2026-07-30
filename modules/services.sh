#!/bin/bash
# services 模块 - 系统服务管理

_show_service_status() {
    systemctl status "$1" --no-pager -l 2>/dev/null |
        head -15 |
        sed 's/^/  /'
}

_valid_service_name() {
    [[ "$1" =~ ^[a-zA-Z0-9_.@:-]+$ ]]
}

do_list() {
    kairo_require_systemctl || return
    local svc state i total row max_svc=0 svc_width
    local -a service_rows=()
    SERVICE_ITEMS=()
    mapfile -t service_rows < <(systemctl list-units --type=service --no-pager --no-legend 2>/dev/null |
        awk '$2 == "loaded" { print $1 "\t" $3 }')
    total=${#service_rows[@]}
    # 先扫一遍算最长服务名宽度，让状态列上下对齐
    for row in "${service_rows[@]}"; do
        IFS=$'\t' read -r svc _ <<< "$row"
        [ "${#svc}" -gt "$max_svc" ] && max_svc=${#svc}
    done
    svc_width=$((max_svc + 2))
    echo ""
    echo -e "  ${C_BOLD}已加载的服务${C_RESET}"
    for i in "${!service_rows[@]}"; do
        [ "$i" -lt 20 ] || break
        IFS=$'\t' read -r svc state <<< "${service_rows[$i]}"
        SERVICE_ITEMS+=("$svc")
        printf "  [%d] %s %s\n" "$((i + 1))" "$(_pad_right "$svc" "$svc_width")" "$state"
    done
    echo ""
    info "共 $total 个已加载服务（显示前 20 个）"
}

do_status() {
    kairo_require_systemctl || return
    local svc="${1:-}"
    [ -n "$svc" ] || { echo ""; read -p "  输入服务名: " svc; }
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    echo ""
    _with_spinner "正在获取服务状态" _show_service_status "$svc"
}

do_start() {
    kairo_require_systemctl || return
    local svc="${1:-}"
    [ -n "$svc" ] || { echo ""; read -p "  输入服务名: " svc; }
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    if _with_spinner "正在启动服务 $svc" sudo systemctl start "$svc"; then
        success "服务 $svc 已启动"
    else
        error "启动失败"
        return 1
    fi
}

do_stop() {
    kairo_require_systemctl || return
    local svc="${1:-}"
    [ -n "$svc" ] || { echo ""; read -p "  输入服务名: " svc; }
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    echo ""
    read -p "  确认停止服务 $svc? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    if _with_spinner "正在停止服务 $svc" sudo systemctl stop "$svc"; then
        success "服务 $svc 已停止"
    else
        error "停止失败"
        return 1
    fi
}

do_restart() {
    kairo_require_systemctl || return
    local svc="${1:-}"
    [ -n "$svc" ] || { echo ""; read -p "  输入服务名: " svc; }
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    if _with_spinner "正在重启服务 $svc" sudo systemctl restart "$svc"; then
        success "服务 $svc 已重启"
    else
        error "重启失败"
        return 1
    fi
}

do_toggle_enable() {
    kairo_require_systemctl || return
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
        if _with_spinner "正在关闭开机自启" sudo systemctl disable "$svc"; then
            success "已关闭 $svc 开机自启"
        else
            error "关闭开机自启失败"
            return 1
        fi
    else
        echo -e "  当前: ${C_YELLOW}未启用${C_RESET} 开机自启"
        echo ""
        read -p "  开启开机自启? [Y/n]: " confirm
        [ "$confirm" = "n" ] || [ "$confirm" = "N" ] && info "已取消" && return
        if _with_spinner "正在开启开机自启" sudo systemctl enable "$svc"; then
            success "已开启 $svc 开机自启"
        else
            error "开启开机自启失败"
            return 1
        fi
    fi
}

menu() {
    local choice svc
    while true; do
        clear
        title "⚙ 系统服务管理"
        do_list || { kairo_pause "按 Enter 返回上级..."; return; }
        divider
        echo -e "  ${C_BOLD}[编号]${C_RESET} 选择服务    ${C_BOLD}[N]${C_RESET} 输入服务名"
        echo -e "  ${C_BOLD}[0]${C_RESET}  返回主菜单"
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
        echo "  [4] 重启      [5] 开关开机自启  [0] 返回上级"
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
