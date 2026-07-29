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
            echo -e "  ${C_BOLD}状态${C_RESET}  $(ufw status | head -1 | sed 's/Status: //')"
            echo ""
            ufw status numbered 2>/dev/null | tail -n +4
            ;;
        iptables)
            echo -e "  ${C_BOLD}当前规则${C_RESET}"
            iptables -L -n --line-numbers 2>/dev/null | head -30
            ;;
    esac
}

do_open_port() {
    [ -z "$FW" ] && error "未检测到防火墙工具" && return
    echo ""
    read -p "  输入端口号: " port
    [ -z "$port" ] && info "已取消" && return
    kairo_is_port "$port" || { error "端口必须是 1-65535"; return 1; }
    read -p "  协议 (tcp/udp，默认 tcp): " proto
    proto=${proto:-tcp}
    [[ "$proto" =~ ^(tcp|udp)$ ]] || { error "协议只能是 tcp 或 udp"; return 1; }

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
    read -p "  输入端口号: " port
    [ -z "$port" ] && info "已取消" && return
    kairo_is_port "$port" || { error "端口必须是 1-65535"; return 1; }
    read -p "  协议 (tcp/udp，默认 tcp): " proto
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

do_enable() {
    [ -z "$FW" ] && error "未检测到防火墙工具" && return
    echo ""
    case "$FW" in
        ufw)
            warn "确保已放行 SSH 端口 (22)，否则可能无法远程连接"
            read -p "  确认开启? [y/N]: " confirm
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
            read -p "  确认关闭防火墙? [y/N]: " confirm
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
    while true; do
        title "🛡 防火墙管理"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 查看防火墙状态"
        echo -e "  ${C_BOLD}[2]${C_RESET} 开放端口"
        echo -e "  ${C_BOLD}[3]${C_RESET} 关闭端口"
        echo -e "  ${C_BOLD}[4]${C_RESET} 开启防火墙"
        echo -e "  ${C_BOLD}[5]${C_RESET} 关闭防火墙"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_status; echo ""; read -p "  按回车键继续..." ;;
            2) do_open_port; echo ""; read -p "  按回车键继续..." ;;
            3) do_close_port; echo ""; read -p "  按回车键继续..." ;;
            4) do_enable; echo ""; read -p "  按回车键继续..." ;;
            5) do_disable; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
