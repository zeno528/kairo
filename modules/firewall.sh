#!/bin/bash
# firewall 模块 - 防火墙管理（Debian/Ubuntu）

# 检测防火墙工具: ufw 优先，备选 iptables
FW=""
if command -v ufw &>/dev/null; then
    FW="ufw"
elif command -v iptables &>/dev/null; then
    FW="iptables"
fi

do_status() {
    echo ""
    if [ -z "$FW" ]; then
        error "未检测到防火墙工具 (ufw/iptables)"
        return
    fi
    echo -e "  ${C_BOLD}防火墙${C_RESET}  $FW"
    case "$FW" in
        ufw)
            local status
            status=$(ufw status | head -1 | sed 's/Status: //')
            echo -e "  ${C_BOLD}状态${C_RESET}  $status"
            if [ "$status" = "inactive" ]; then
                warn "防火墙未启用；放行规则会保存，但暂不会影响流量"
                info "启用前请先确认 SSH 端口已放行，再选择 [E] 开启防火墙"
            fi
            echo ""
            ufw status numbered 2>/dev/null | tail -n +4
            ;;
        iptables)
            echo -e "  ${C_BOLD}当前规则${C_RESET}（INPUT 链）"
            sudo iptables -nL INPUT --line-numbers 2>/dev/null
            ;;
    esac
}

do_open_port() {
    [ -z "$FW" ] && error "未检测到防火墙工具" && return
    echo ""
    read -r -p "  输入端口号: " port
    [ -z "$port" ] && info "已取消" && return
    kairo_is_port "$port" || { error "端口必须是 1-65535"; return 1; }
    read -r -p "  协议 (tcp/udp，默认 tcp): " proto
    proto=${proto:-tcp}
    [[ "$proto" =~ ^(tcp|udp)$ ]] || { error "协议只能是 tcp 或 udp"; return 1; }
    warn "即将放行入站端口 $port/$proto"
    read -r -p "  确认放行? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }

    case "$FW" in
        ufw)
            sudo ufw allow "$port/$proto" && success "已开放 $port/$proto"
            ;;
        iptables)
            sudo iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT \
                && success "已开放 $port/$proto (当前会话，重启后失效)"
            ;;
    esac
}

do_close_port() {
    [ -z "$FW" ] && error "未检测到防火墙工具" && return
    echo ""
    read -r -p "  输入端口号: " port
    [ -z "$port" ] && info "已取消" && return
    kairo_is_port "$port" || { error "端口必须是 1-65535"; return 1; }
    read -r -p "  协议 (tcp/udp，默认 tcp): " proto
    proto=${proto:-tcp}
    [[ "$proto" =~ ^(tcp|udp)$ ]] || { error "协议只能是 tcp 或 udp"; return 1; }
    warn "即将关闭 $port/$proto，可能中断现有服务"
    read -r -p "  确认关闭? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }

    case "$FW" in
        ufw)
            sudo ufw delete allow "$port/$proto" && success "已关闭 $port/$proto"
            ;;
        iptables)
            if sudo iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT; then
                success "已移除 $port/$proto 的放行规则（当前会话，重启后失效）"
            else
                error "未找到 $port/$proto 的 INPUT ACCEPT 规则"
                return 1
            fi
            ;;
    esac
}

do_delete_rule() {
    local rule="$1"
    [[ "$rule" =~ ^[1-9][0-9]*$ ]] || { error "规则编号无效"; return 1; }
    warn "即将删除 ${FW} 规则 #$rule"
    read -r -p "  确认删除? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    case "$FW" in
        ufw) sudo ufw --force delete "$rule" ;;
        iptables) sudo iptables -D INPUT "$rule" ;;
        *) error "未检测到防火墙工具"; return 1 ;;
    esac || { error "删除规则失败"; return 1; }
    success "已删除规则 #$rule"
}

do_enable() {
    [ -z "$FW" ] && error "未检测到防火墙工具" && return
    echo ""
    case "$FW" in
        ufw)
            warn "确保已放行 SSH 端口 (22)，否则可能无法远程连接"
            warn "开启后，未明确放行的入站连接可能被阻止"
            read -r -p "  确认开启? [y/N]: " confirm
            [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
            sudo ufw enable && success "防火墙已开启"
            ;;
        iptables)
            error "iptables 不支持全局开启；请手动管理规则"
            return 1
            ;;
    esac
}

do_disable() {
    [ -z "$FW" ] && error "未检测到防火墙工具" && return
    echo ""
    case "$FW" in
        ufw)
            read -r -p "  确认关闭防火墙? [y/N]: " confirm
            [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
            sudo ufw disable && success "防火墙已关闭"
            ;;
        iptables)
            error "iptables 不支持全局关闭；请手动管理规则"
            return 1
            ;;
    esac
}

menu() {
    local choice
    while true; do
        clear
        title "🛡 防火墙管理"
        do_status
        divider
        _menu_actions 18 "${C_BOLD}[编号]${C_RESET} 删除规则" "${C_BOLD}[O]${C_RESET} 开放端口" "${C_BOLD}[C]${C_RESET} 按端口关闭"
        _menu_actions 18 "${C_BOLD}[E]${C_RESET} 开启防火墙" "${C_BOLD}[D]${C_RESET} 关闭防火墙"
        _menu_actions 18 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  选择规则或操作: " choice
        case "$choice" in
            [Oo]) do_open_port; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Cc]) do_close_port; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Ee]) do_enable; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Dd]) do_disable; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            0) return ;;
            *)
                if [[ "$choice" =~ ^[1-9][0-9]*$ ]]; then
                    do_delete_rule "$choice"
                    echo ""; kairo_pause "按 Enter 返回防火墙规则..."
                else
                    error "无效选项"; sleep 1
                fi
                ;;
        esac
    done
}
