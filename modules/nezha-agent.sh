#!/bin/bash
# nezha-agent - 哪吒监控 Agent 管理

NZ_AGENT_DIR="${NZ_AGENT_DIR:-/opt/nezha/agent}"

# 发现所有 nezha-agent* systemd 服务
_find_agents() {
    systemctl list-unit-files --type=service 2>/dev/null | awk '/^nezha-agent.*\.service/ {print $1}'
}

_agent_service_file() {
    local svc="$1"
    systemctl show -p FragmentPath --value "$svc" 2>/dev/null
}

_agent_install_date() {
    local svc_file="$1"
    local ts
    ts=$(stat -c '%Y' "$svc_file" 2>/dev/null) || return
    date -d "@$ts" '+%Y-%m-%d' 2>/dev/null
}

_agent_binary() {
    local svc_file="$1"
    grep -oP '^ExecStart=\K\S+' "$svc_file" 2>/dev/null | head -1
}

# landing page：列出所有 agent 实例
_render_agent_list() {
    local i=1 svc svc_file status install_date
    mapfile -t NEZHA_AGENTS < <(_find_agents)
    echo ""
    if [ "${#NEZHA_AGENTS[@]}" -eq 0 ]; then
        info "未发现 nezha-agent 服务"
        return
    fi
    echo -e "  ${C_BOLD}Agent 列表${C_RESET}"
    for svc in "${NEZHA_AGENTS[@]}"; do
        svc_file=$(_agent_service_file "$svc")
        install_date=$(_agent_install_date "$svc_file")
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            status="${C_GREEN}运行中${C_RESET}"
        else
            status="${C_YELLOW}已停止${C_RESET}"
        fi
        printf '  [%d] %-18s %b     安装于 %s\n' \
            "$i" "${svc%.service}" "$status" "${install_date:-未知}"
        ((i++))
    done
}

do_status() {
    kairo_require_systemctl || return
    local svc="${1:-}"
    if [ -z "$svc" ]; then
        local agents=()
        mapfile -t agents < <(_find_agents)
        if [ "${#agents[@]}" -eq 0 ]; then
            info "未发现 nezha-agent"
            return 1
        fi
        _render_agent_list
        return
    fi
    echo ""
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        success "${svc%.service} 运行中"
        local since
        since=$(systemctl show -p ActiveEnterTimestamp --value "$svc" 2>/dev/null)
        [ -n "$since" ] && echo "  启动时间: $since"
    else
        warn "${svc%.service} 已停止"
    fi
    local svc_file install_date
    svc_file=$(_agent_service_file "$svc")
    install_date=$(_agent_install_date "$svc_file")
    [ -n "$install_date" ] && echo "  安装时间: $install_date"
}

do_start() {
    kairo_require_systemctl || return
    local svc="${1:-}"
    [ -z "$svc" ] && return 1
    echo ""
    if sudo systemctl start "$svc"; then
        success "${svc%.service} 已启动"
    else
        error "启动失败"
        return 1
    fi
}

do_stop() {
    kairo_require_systemctl || return
    local svc="${1:-}"
    [ -z "$svc" ] && return 1
    echo ""
    read -r -p "  确认停止 ${svc%.service}? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    if sudo systemctl stop "$svc"; then
        success "${svc%.service} 已停止"
    else
        error "停止失败"
        return 1
    fi
}

do_remove() {
    kairo_require_systemctl || return
    local svc="${1:-}"
    [ -z "$svc" ] && return 1
    echo ""
    warn "即将卸载 ${svc%.service}，Agent 数据将被删除"
    read -r -p "  确认卸载? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }

    local svc_file binary
    svc_file=$(_agent_service_file "$svc")
    binary=$(_agent_binary "$svc_file")

    sudo systemctl stop "$svc" 2>/dev/null || true
    sudo systemctl disable "$svc" 2>/dev/null || true

    if [ -n "$binary" ] && [ -x "$binary" ]; then
        sudo "$binary" service uninstall 2>/dev/null || true
    fi

    [ -n "$svc_file" ] && sudo rm -f "$svc_file" 2>/dev/null
    sudo systemctl daemon-reload 2>/dev/null || true

    success "${svc%.service} 已卸载"
}

do_logs() {
    local svc="${1:-}"
    [ -z "$svc" ] && return 1
    echo ""
    local lines
    read -r -p "  查看行数 (默认 50): " lines
    lines=${lines:-50}
    kairo_is_positive_integer "$lines" || { error "行数必须是正整数"; return 1; }
    sudo journalctl -u "$svc" --no-pager -n "$lines" 2>&1
}

menu() {
    local choice svc svc_name
    while true; do
        clear
        title "🛰 哪吒监控 Agent"
        _render_agent_list
        divider
        _menu_actions 20 "${C_BOLD}[编号]${C_RESET} 选择 Agent"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            0) return ;;
            *)
                if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#NEZHA_AGENTS[@]}" ]; then
                    svc="${NEZHA_AGENTS[$((choice - 1))]}"
                    svc_name="${svc%.service}"
                else
                    error "无效选项"; sleep 1; continue
                fi
                ;;
        esac

        while true; do
            clear
            title "🛰 Agent: $svc_name"
            do_status "$svc"
            divider
            _menu_actions 20 "${C_BOLD}[1]${C_RESET} 启动"
            _menu_actions 20 "${C_BOLD}[2]${C_RESET} 停止"
            _menu_actions 20 "${C_BOLD}[3]${C_RESET} 查看日志"
            _menu_actions 20 "${C_BOLD}[4]${C_RESET} 卸载此 Agent"
            _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回"
            divider
            echo ""
            read -r -p "  请选择: " choice
            case "$choice" in
                1) do_start "$svc"; echo ""; kairo_pause ;;
                2) do_stop "$svc"; echo ""; kairo_pause ;;
                3) do_logs "$svc"; echo ""; kairo_pause ;;
                4) do_remove "$svc"; echo ""; kairo_pause; break ;;
                0) break ;;
                *) error "无效选项"; sleep 1 ;;
            esac
        done
    done
}
