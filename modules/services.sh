#!/bin/bash
# services 模块 - 系统服务管理

_check_systemctl() {
    if ! command -v systemctl &>/dev/null; then
        error "未找到 systemctl 命令"
        return 1
    fi
}

_show_service_list() {
    systemctl list-units --type=service --no-pager 2>/dev/null |
        head -20 |
        sed 's/^/  /'
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
    echo ""
    echo -e "  ${C_BOLD}已安装的服务${C_RESET}"
    _with_spinner "正在获取服务列表" _show_service_list
    echo ""
    local total
    _start_spinner "正在统计服务数量"
    total=$(systemctl list-units --type=service --no-pager 2>/dev/null | grep -c 'loaded')
    _stop_spinner
    info "共 $total 个已加载服务（显示前 20 个）"
}

do_status() {
    _check_systemctl || return
    echo ""
    read -p "  输入服务名: " svc
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    echo ""
    _with_spinner "正在获取服务状态" _show_service_status "$svc"
}

do_start() {
    _check_systemctl || return
    echo ""
    read -p "  输入服务名: " svc
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    _with_spinner "正在启动服务 $svc" sudo systemctl start "$svc" && success "服务 $svc 已启动" || error "启动失败"
}

do_stop() {
    _check_systemctl || return
    echo ""
    read -p "  输入服务名: " svc
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    echo ""
    read -p "  确认停止服务 $svc? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    _with_spinner "正在停止服务 $svc" sudo systemctl stop "$svc" && success "服务 $svc 已停止" || error "停止失败"
}

do_restart() {
    _check_systemctl || return
    echo ""
    read -p "  输入服务名: " svc
    [ -z "$svc" ] && info "已取消" && return
    _valid_service_name "$svc" || { error "服务名格式不合法"; return 1; }
    _with_spinner "正在重启服务 $svc" sudo systemctl restart "$svc" && success "服务 $svc 已重启" || error "重启失败"
}

do_toggle_enable() {
    _check_systemctl || return
    echo ""
    read -p "  输入服务名: " svc
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
    while true; do
        title "⚙ 系统服务管理"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 查看服务列表"
        echo -e "  ${C_BOLD}[2]${C_RESET} 查看服务状态"
        echo -e "  ${C_BOLD}[3]${C_RESET} 启动服务"
        echo -e "  ${C_BOLD}[4]${C_RESET} 停止服务"
        echo -e "  ${C_BOLD}[5]${C_RESET} 重启服务"
        echo -e "  ${C_BOLD}[6]${C_RESET} 开关开机自启"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_list; echo ""; read -p "  按回车键继续..." ;;
            2) do_status; echo ""; read -p "  按回车键继续..." ;;
            3) do_start; echo ""; read -p "  按回车键继续..." ;;
            4) do_stop; echo ""; read -p "  按回车键继续..." ;;
            5) do_restart; echo ""; read -p "  按回车键继续..." ;;
            6) do_toggle_enable; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
