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
    echo ""
    if command -v lscpu &>/dev/null; then
        echo -e "  ${C_BOLD}型号${C_RESET}    $(lscpu | grep 'Model name' | sed 's/Model name:[[:space:]]*//')"
        echo -e "  ${C_BOLD}核心${C_RESET}    $(lscpu | grep '^CPU(s):' | awk '{print $2}')"
        echo -e "  ${C_BOLD}线程${C_RESET}    $(lscpu | grep 'Thread(s) per core' | awk '{print $NF}')"
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
    echo ""
    echo -e "  ${C_BOLD}IP 地址${C_RESET}"
    if command -v ip &>/dev/null; then
        ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | while read -r ip; do
            echo "    $ip"
        done
    else
        hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' | while read -r ip; do
            echo "    $ip"
        done
    fi
    echo ""
    echo -e "  ${C_BOLD}网卡状态${C_RESET}"
    if command -v ip &>/dev/null; then
        ip link show 2>/dev/null | grep -E '^[0-9]' | awk '{printf "    %-16s %s\n", $2, ($2 ~ /UP/ ? "UP" : "DOWN")}'
    else
        cat /proc/net/dev | tail -n +3 | awk -F: '{printf "    %-16s UP\n", $1}' | sed 's/ //g'
    fi
}

menu() {
    while true; do
        title "📊 系统信息"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 系统概览"
        echo -e "  ${C_BOLD}[2]${C_RESET} CPU 信息"
        echo -e "  ${C_BOLD}[3]${C_RESET} 内存信息"
        echo -e "  ${C_BOLD}[4]${C_RESET} 磁盘信息"
        echo -e "  ${C_BOLD}[5]${C_RESET} 网络信息"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_overview; echo ""; read -p "  按回车键继续..." ;;
            2) do_cpu; echo ""; read -p "  按回车键继续..." ;;
            3) do_memory; echo ""; read -p "  按回车键继续..." ;;
            4) do_disk; echo ""; read -p "  按回车键继续..." ;;
            5) do_network; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
