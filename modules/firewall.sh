#!/bin/bash
# firewall 模块 - 防火墙管理

# 检测可用的防火墙工具
detect_fw() {
    if command -v ufw &>/dev/null; then
        echo "ufw"
    elif command -v firewall-cmd &>/dev/null; then
        echo "firewalld"
    elif command -v iptables &>/dev/null; then
        echo "iptables"
    else
        echo ""
    fi
}

FW=$(detect_fw)

do_status() {
    echo ""
    if [ -z "$FW" ]; then
        error "未检测到防火墙工具 (ufw/firewalld/iptables)"
        return
    fi
    echo -e "  ${C_BOLD}防火墙${C_RESET}  $FW"
    case "$FW" in
        ufw)
            echo -e "  ${C_BOLD}状态${C_RESET}  $(ufw status | head -1 | sed 's/Status: //')"
            echo ""
            ufw status numbered 2>/dev/null | tail -n +4
            ;;
        firewalld)
            echo -e "  ${C_BOLD}状态${C_RESET}  $(firewall-cmd --state 2>/dev/null)"
            echo ""
            echo -e "  ${C_BOLD}开放服务${C_RESET}"
            firewall-cmd --list-services 2>/dev/null | tr ' ' '\n' | sed 's/^/    /'
            echo ""
            echo -e "  ${C_BOLD}开放端口${C_RESET}"
            firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | sed 's/^/    /'
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
    read -p "  协议 (tcp/udp，默认 tcp): " proto
    proto=${proto:-tcp}

    case "$FW" in
        ufw)
            sudo ufw allow "$port/$proto" && success "已开放 $port/$proto"
            ;;
        firewalld)
            sudo firewall-cmd --permanent --add-port="$port/$proto" \
                && sudo firewall-cmd --reload \
                && success "已开放 $port/$proto"
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
    read -p "  协议 (tcp/udp，默认 tcp): " proto
    proto=${proto:-tcp}

    case "$FW" in
        ufw)
            sudo ufw delete allow "$port/$proto" && success "已关闭 $port/$proto"
            ;;
        firewalld)
            sudo firewall-cmd --permanent --remove-port="$port/$proto" \
                && sudo firewall-cmd --reload \
                && success "已关闭 $port/$proto"
            ;;
        iptables)
            sudo iptables -A INPUT -p "$proto" --dport "$port" -j DROP \
                && success "已关闭 $port/$proto (当前会话，重启后失效)"
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
        firewalld)
            sudo systemctl enable --now firewalld && success "防火墙已开启"
            ;;
        iptables)
            info "iptables 无全局开关，需手动管理规则"
            ;;
    esac
}

do_disable() {
    [ -z "$FW" ] && error "未检测到防火墙工具" && return
    echo ""
    read -p "  确认关闭防火墙? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    case "$FW" in
        ufw)
            sudo ufw disable && success "防火墙已关闭"
            ;;
        firewalld)
            sudo systemctl stop firewalld && sudo systemctl disable firewalld && success "防火墙已关闭"
            ;;
        iptables)
            info "iptables 无全局开关，需手动清空规则"
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
