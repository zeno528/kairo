#!/bin/bash
# nezha-agent - 哪吒监控 Agent 守护进程管理

_nezha_installed() {
    systemctl list-unit-files 2>/dev/null | grep -q 'nezha-agent'
}

do_status() {
    kairo_require_systemctl || return
    echo ""
    if ! _nezha_installed; then
        warn "nezha-agent 未安装"
        return 1
    fi
    if systemctl is-active --quiet nezha-agent 2>/dev/null; then
        success "nezha-agent 运行中"
    else
        warn "nezha-agent 未运行"
    fi
    systemctl status nezha-agent --no-pager -l 2>/dev/null | head -15 | sed 's/^/  /'
}

do_start() {
    kairo_require_systemctl || return
    echo ""
    _nezha_installed || { warn "nezha-agent 未安装"; return 1; }
    if sudo systemctl start nezha-agent && sudo systemctl is-active nezha-agent >/dev/null; then
        success "nezha-agent 已启动"
    else
        error "启动失败"
        return 1
    fi
}

do_stop() {
    kairo_require_systemctl || return
    echo ""
    _nezha_installed || { warn "nezha-agent 未安装"; return 1; }
    read -r -p "  确认停止 nezha-agent? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    if sudo systemctl stop nezha-agent; then
        success "nezha-agent 已停止"
    else
        error "停止失败"
        return 1
    fi
}

menu() {
    local choice
    while true; do
        clear
        title "🛰 哪吒监控 Agent"
        do_status || true
        divider
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 启动"
        _menu_actions 20 "${C_BOLD}[2]${C_RESET} 停止"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_start ;;
            2) do_stop ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
        echo ""
        kairo_pause "按 Enter 返回..."
    done
}
