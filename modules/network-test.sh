#!/bin/bash
# network-test 模块 - 网络测试

BACKTRACE_URL="https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh"

do_speedtest() {
    echo ""
    if command -v speedtest &>/dev/null; then
        info "使用 speedtest (Ookla) 测速..."
        echo ""
        speedtest
    elif command -v speedtest-cli &>/dev/null; then
        info "使用 speedtest-cli 测速..."
        echo ""
        speedtest-cli
    else
        warn "未安装测速工具"
        echo ""
        echo -e "  ${C_DIM}安装: sudo apt install speedtest-cli${C_RESET}"
        echo ""
        read -p "  是否现在安装? [y/N]: " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            sudo apt install -y speedtest-cli 2>/dev/null && speedtest-cli
        else
            info "已取消"
        fi
    fi
}

do_backtrace() {
    echo ""
    if command -v backtrace &>/dev/null; then
        backtrace
    else
        warn "未安装 backtrace"
        echo -e "  ${C_DIM}项目: https://github.com/zhanghanyun/backtrace${C_RESET}"
        echo -e "  ${C_DIM}功能: 测试三网回程路由（电信/联通/移动线路类型）${C_RESET}"
        echo ""
        read -p "  是否现在安装? [y/N]: " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            curl -fsSL "$BACKTRACE_URL" | bash && backtrace
        else
            info "已取消"
        fi
    fi
}

do_ping_test() {
    echo ""
    echo -e "  ${C_BOLD}Ping 延迟测试${C_RESET}"
    echo ""
    local targets=("8.8.8.8:Google DNS" "1.1.1.1:Cloudflare" "223.5.5.5:阿里 DNS")
    for item in "${targets[@]}"; do
        local ip="${item%%:*}"
        local name="${item##*:}"
        local result
        result=$(ping -c 3 -W 2 "$ip" 2>/dev/null | tail -1)
        if [ -n "$result" ]; then
            local avg
            avg=$(echo "$result" | grep -oP 'rtt min/avg/max/mdev = [\d.]+/[\d.]+' | grep -oP '[\d.]+$')
            if [ -n "$avg" ]; then
                printf "  %-16s %-12s ${C_GREEN}%s ms${C_RESET}\n" "$name" "$ip" "$avg"
            else
                printf "  %-16s %-12s %s\n" "$name" "$ip" "$result"
            fi
        else
            printf "  %-16s %-12s ${C_RED}超时${C_RESET}\n" "$name" "$ip"
        fi
    done

    echo ""
    read -p "  自定义 Ping 目标 (可选，回车跳过): " custom
    if [ -n "$custom" ]; then
        echo ""
        ping -c 4 "$custom" 2>/dev/null || error "无法 Ping $custom"
    fi
}

menu() {
    while true; do
        title "🌐 网络测试"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 网络测速"
        echo -e "  ${C_BOLD}[2]${C_RESET} 三网回程路由"
        echo -e "  ${C_BOLD}[3]${C_RESET} Ping 延迟测试"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_speedtest; echo ""; read -p "  按回车键继续..." ;;
            2) do_backtrace; echo ""; read -p "  按回车键继续..." ;;
            3) do_ping_test; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
