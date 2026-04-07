#!/bin/bash
# sys-info 模块 - 系统信息查看

do_overview() {
    echo ""
    echo "  主机名: $(hostname)"
    echo "  系统:   $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "  内核:   $(uname -r)"
    echo "  架构:   $(uname -m)"
    echo "  运行:   $(uptime -p 2>/dev/null || uptime | sed 's/.*up/up/')"
    echo "  负载:   $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
}

do_cpu() {
    echo ""
    if command -v lscpu &>/dev/null; then
        echo "  型号:   $(lscpu | grep 'Model name' | sed 's/Model name:[[:space:]]*//')"
        echo "  核心:   $(lscpu | grep '^CPU(s):' | awk '{print $2}')"
        echo "  线程:   $(lscpu | grep 'Thread(s) per core' | awk '{print $NF}')"
    else
        echo "  型号:   $(cat /proc/cpuinfo | grep 'model name' | head -1 | sed 's/model name[[:space:]]*: *//')"
        echo "  核心:   $(nproc)"
    fi
    echo "  使用率:"
    # 取 CPU 总使用率（取前两行相减）
    top -bn1 | head -5 | tail -1
}

do_memory() {
    echo ""
    echo "  内存:"
    free -h | awk '/^Mem:/{printf "    总量: %-8s 已用: %-8s 可用: %-8s 缓存: %s\n", $2, $3, $7, $6}'
    echo ""
    echo "  Swap:"
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
    echo "  IP 地址:"
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
    echo "  网卡状态:"
    if command -v ip &>/dev/null; then
        ip link show 2>/dev/null | grep -E '^[0-9]' | awk '{printf "    %-16s %s\n", $2, ($2 ~ /UP/ ? "UP" : "DOWN")}'
    else
        cat /proc/net/dev | tail -n +3 | awk -F: '{printf "    %-16s UP\n", $1}' | sed 's/ //g'
    fi
}

menu() {
    while true; do
        echo ""
        echo "  [1] 系统概览"
        echo "  [2] CPU 信息"
        echo "  [3] 内存信息"
        echo "  [4] 磁盘信息"
        echo "  [5] 网络信息"
        echo "  [0] 返回上级"
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_overview; echo ""; read -p "  按回车键继续..." ;;
            2) do_cpu; echo ""; read -p "  按回车键继续..." ;;
            3) do_memory; echo ""; read -p "  按回车键继续..." ;;
            4) do_disk; echo ""; read -p "  按回车键继续..." ;;
            5) do_network; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) echo "  无效选项"; sleep 1 ;;
        esac
    done
}
