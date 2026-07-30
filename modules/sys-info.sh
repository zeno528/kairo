#!/bin/bash
# sys-info 模块 - 系统信息查看

do_overview() {
    echo ""
    echo -e "  ${C_BOLD}主机名${C_RESET}  $(hostname)"
    echo -e "  ${C_BOLD}系  统${C_RESET}  $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
    echo -e "  ${C_BOLD}内  核${C_RESET}  $(uname -r)"
    echo -e "  ${C_BOLD}架  构${C_RESET}  $(uname -m)"
    echo -e "  ${C_BOLD}运  行${C_RESET}  $(uptime -p 2>/dev/null || uptime | sed 's/.*up/up/')"
    echo -e "  ${C_BOLD}负  载${C_RESET}  $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
}

do_cpu() {
    local cpu_info model cores threads
    echo ""
    if command -v lscpu &>/dev/null; then
        cpu_info=$(lscpu | awk -F: '
            /^Model name:/ {sub(/^[[:space:]]*/, "", $2); model=$2}
            /^CPU\(s\):/ {sub(/^[[:space:]]*/, "", $2); cores=$2}
            /^Thread\(s\) per core:/ {sub(/^[[:space:]]*/, "", $2); threads=$2}
            END {printf "%s\t%s\t%s", model, cores, threads}
        ')
        IFS=$'\t' read -r model cores threads <<< "$cpu_info"
        echo -e "  ${C_BOLD}型号${C_RESET}    $model"
        echo -e "  ${C_BOLD}核心${C_RESET}    $cores"
        echo -e "  ${C_BOLD}线程${C_RESET}    $threads"
    else
        echo -e "  ${C_BOLD}型号${C_RESET}    $(cat /proc/cpuinfo | grep 'model name' | head -1 | sed 's/model name[[:space:]]*: *//')"
        echo -e "  ${C_BOLD}核心${C_RESET}    $(nproc)"
    fi
    echo -e "  ${C_BOLD}使用率${C_RESET}"
    top -bn1 | head -5 | tail -1
}

do_memory() {
    echo ""
    echo -e "  ${C_BOLD}内存${C_RESET}"
    free -h | awk '/^Mem:/{printf "    总量: %-8s 已用: %-8s 可用: %-8s 缓存: %s\n", $2, $3, $7, $6}'
    echo -e "  ${C_BOLD}Swap${C_RESET}"
    free -h | awk '/^Swap:/{printf "    总量: %-8s 已用: %-8s 可用: %s\n", $2, $3, $4}'
}

do_disk() {
    echo ""
    df -h --total 2>/dev/null | awk '
    NR==1 {printf "  %-20s %8s %8s %8s %5s  %s\n", "文件系统", "大小", "已用", "可用", "使用%", "挂载点"; printf "  %s\n", "-------------------- -------- -------- -------- -----  -----"}
    /^\/dev/ || /^total/ {printf "  %-20s %8s %8s %8s %5s  %s\n", $1, $2, $3, $4, $5, $6}'
}

do_network() {
    local ipv4 ipv6
    echo ""
    if command -v ip &>/dev/null; then
        ipv4=$(ip -o -4 addr show scope global 2>/dev/null | awk '{split($4, a, "/"); print a[1]}')
        ipv6=$(ip -o -6 addr show scope global 2>/dev/null | awk '{split($4, a, "/"); print a[1]}')
        echo -e "  ${C_BOLD}IPv4 地址${C_RESET}"
        [ -n "$ipv4" ] && printf '%s\n' "$ipv4" | sed 's/^/    /' || echo "    （无）"
        echo -e "  ${C_BOLD}IPv6 地址${C_RESET}"
        [ -n "$ipv6" ] && printf '%s\n' "$ipv6" | sed 's/^/    /' || echo "    （无）"
    else
        echo -e "  ${C_BOLD}IP 地址（未分类）${C_RESET}"
        hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' | while read -r ip; do
            echo "    $ip"
        done
    fi
    echo ""
    echo -e "  ${C_BOLD}网卡状态${C_RESET}"
    if command -v ip &>/dev/null; then
        ip -o link show 2>/dev/null | awk -F': ' '{
            name=$2
            sub(/@.*/, "", name)
            state=($0 ~ /<[^>]*UP[^>]*>/ ? "UP" : "DOWN")
            printf "    %-16s %s\n", name, state
        }'
    else
        cat /proc/net/dev | tail -n +3 | awk -F: '{printf "    %-16s UP\n", $1}' | sed 's/ //g'
    fi
}

menu() {
    while true; do
        clear
        title "📊 系统信息"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 系统概览"
        echo -e "  ${C_BOLD}[2]${C_RESET} CPU 信息"
        echo -e "  ${C_BOLD}[3]${C_RESET} 内存信息"
        echo -e "  ${C_BOLD}[4]${C_RESET} 磁盘信息"
        echo -e "  ${C_BOLD}[5]${C_RESET} 网络信息"
        echo -e "  ${C_BOLD}[0]${C_RESET}  返回主菜单"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_overview; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            2) do_cpu; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            3) do_memory; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            4) do_disk; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            5) do_network; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
