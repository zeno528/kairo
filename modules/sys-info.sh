#!/bin/bash
# sys-info 模块 - 系统信息查看。
# menu 一屏全显（do_overview，含联网查公网/运营商/地理位置）；
# do_cpu/memory/disk/network 为 CLI 单项查看（本地、不联网）。

# 标签对齐输出（CJK 感知，标签+冒号对齐到 16 列）。
_info_line() {
    local label="$1" value="$2" w pad
    w=$(printf '%s' "$label" | wc -L)
    pad=$((15 - w))
    [ "$pad" -lt 1 ] && pad=1
    printf "  ${C_CYAN}%s:${C_RESET}%*s %s\n" "$label" "$pad" "" "$value"
}

_info_sep() {
    echo -e "  ${C_DIM}-------------${C_RESET}"
}

do_overview() {
    title "📊 系统信息"

    # --- 基础 ---
    _info_sep
    _info_line "主机名" "$(hostname)"
    _info_line "系统版本" "$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release 2>/dev/null)"
    _info_line "Linux版本" "$(uname -r)"

    # --- CPU ---
    _info_sep
    local cpu_model cpu_cores cpu_mhz
    if command -v lscpu >/dev/null 2>&1; then
        cpu_model=$(lscpu | awk -F': +' '/^Model name:/{print $2; exit}')
        cpu_cores=$(lscpu | awk -F': +' '/^CPU\(s\):/{print $2; exit}')
        cpu_mhz=$(lscpu | awk -F': +' '/^CPU max MHz:/{print $2; exit}')
        [ -n "$cpu_mhz" ] || cpu_mhz=$(lscpu | awk -F': +' '/^CPU MHz:/{print $2; exit}')
    else
        cpu_model=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)
        cpu_cores=$(grep -c '^processor' /proc/cpuinfo)
    fi
    # lscpu 无频率字段时回退到 /proc/cpuinfo 当前频率
    [ -n "$cpu_mhz" ] || cpu_mhz=$(awk -F': +' '/^cpu MHz/{print $2; exit}' /proc/cpuinfo)
    cpu_mhz=${cpu_mhz%.*}
    _info_line "CPU架构" "$(uname -m)"
    _info_line "CPU型号" "${cpu_model:-未知}"
    _info_line "CPU核心数" "${cpu_cores:-未知}"
    [ -n "$cpu_mhz" ] && _info_line "CPU主频" "${cpu_mhz} MHz"

    # --- 性能 / 资源 ---
    _info_sep
    local cpu_usage load mem_total mem_used swap_total swap_used disk_total disk_used disk_pct
    cpu_usage=$(top -bn1 2>/dev/null | awk -F'[, ]+' '/%Cpu/{for(i=1;i<=NF;i++) if($i=="id"){printf "%d", 100-$(i-1); exit}}')
    _info_line "CPU占用" "${cpu_usage:-0}%"
    load=$(cut -d' ' -f1-3 /proc/loadavg)
    _info_line "系统负载" "$load"
    if command -v ss >/dev/null 2>&1; then
        _info_line "TCP|UDP连接数" "$(ss -t 2>/dev/null | tail -n +2 | wc -l)|$(ss -u 2>/dev/null | tail -n +2 | wc -l)"
    else
        _info_line "TCP|UDP连接数" "需要 ss 命令"
    fi
    read -r mem_total mem_used _ <<< "$(free -b 2>/dev/null | awk '/^Mem:/{print $2, $3}')"
    if [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ] 2>/dev/null; then
        _info_line "物理内存" "$(awk -v u="$mem_used" -v t="$mem_total" 'BEGIN{printf "%.0fM/%.0fM (%.1f%%)", u/1048576, t/1048576, u/t*100}')"
    fi
    local mem_type mem_speed mem_info
    if command -v dmidecode >/dev/null 2>&1; then
        mem_info=$(sudo dmidecode -t memory 2>/dev/null)
        mem_type=$(printf '%s' "$mem_info" | awk -F': +' '/Type:/{print $2; exit}')
        mem_speed=$(printf '%s' "$mem_info" | awk -F': +' '/Speed:/{print $2; exit}')
    fi
    if [ -n "$mem_type" ] && [ "$mem_type" != "Unknown" ]; then
        _info_line "内存类型" "${mem_type}${mem_speed:+ $mem_speed}"
    fi
    read -r swap_total swap_used _ <<< "$(free -b 2>/dev/null | awk '/^Swap:/{print $2, $3}')"
    if [ -n "$swap_total" ] && [ "$swap_total" -gt 0 ] 2>/dev/null; then
        _info_line "虚拟内存" "$(awk -v u="$swap_used" -v t="$swap_total" 'BEGIN{printf "%.0fM/%.0fM (%.0f%%)", u/1048576, t/1048576, u/t*100}')"
    else
        _info_line "虚拟内存" "未启用"
    fi
    read -r disk_total disk_used disk_pct <<< "$(df -B1 --output=size,used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2, $3}')"
    if [ -n "$disk_total" ]; then
        disk_pct=${disk_pct%\%}
        _info_line "硬盘占用" "$(awk -v u="$disk_used" -v t="$disk_total" -v p="$disk_pct" 'BEGIN{printf "%.1fG/%.1fG (%d%%)", u/1073741824, t/1073741824, p}')"
    fi

    # --- 流量 ---
    _info_sep
    local rx tx
    read -r rx tx <<< "$(awk '!/lo:/{r+=$2; t+=$10} END{printf "%.2f %.2f", r/1073741824, t/1073741824}' /proc/net/dev)"
    _info_line "总接收" "${rx:-0}G"
    _info_line "总发送" "${tx:-0}G"

    # --- 网络算法 ---
    _info_sep
    _info_line "网络算法" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) $(sysctl -n net.core.default_qdisc 2>/dev/null)"

    # --- 网络信息（联网 + 本地）---
    _info_sep
    local info pub_ip org country city geo dns tz
    info=$(curl -fsSL --connect-timeout 5 --max-time 5 https://ipinfo.io/json 2>/dev/null)
    if [ -n "$info" ]; then
        pub_ip=$(printf '%s' "$info" | sed -n 's/.*"ip":[[:space:]]*"\([^"]*\)".*/\1/p')
        org=$(printf '%s' "$info" | sed -n 's/.*"org":[[:space:]]*"\([^"]*\)".*/\1/p')
        country=$(printf '%s' "$info" | sed -n 's/.*"country":[[:space:]]*"\([^"]*\)".*/\1/p')
        city=$(printf '%s' "$info" | sed -n 's/.*"city":[[:space:]]*"\([^"]*\)".*/\1/p')
        geo="${country}${city:+ $city}"
    fi
    _info_line "运营商" "${org:-查询失败}"
    _info_line "IPv4地址" "${pub_ip:-查询失败}"
    local ipv6_local
    ipv6_local=$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/{split($2,a,"/");print a[1]; exit}')
    [ -n "$ipv6_local" ] && _info_line "IPv6地址" "$ipv6_local"
    dns=$(grep -E '^[[:space:]]*nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -3 | paste -sd ' ')
    _info_line "DNS地址" "${dns:-无}"
    _info_line "地理位置" "${geo:-查询失败}"
    tz=$(timedatectl 2>/dev/null | awk -F': +' '/Time zone/{print $2; exit}' | awk '{print $1}')
    [ -n "$tz" ] || tz=$(date +%Z 2>/dev/null)
    _info_line "系统时间" "${tz} $(date '+%Y-%m-%d %H:%M')"

    # --- 运行时长 ---
    _info_sep
    local up_sec days hours mins
    up_sec=$(cut -d. -f1 /proc/uptime 2>/dev/null)
    if [ -n "$up_sec" ]; then
        days=$((up_sec / 86400))
        hours=$(((up_sec % 86400) / 3600))
        mins=$(((up_sec % 3600) / 60))
        _info_line "运行时长" "${days}天 ${hours}时 ${mins}分"
    fi
}

do_cpu() {
    local cpu_info model cores threads
    title "CPU"
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
        echo -e "  ${C_BOLD}型号${C_RESET}    $(grep 'model name' /proc/cpuinfo | head -1 | sed 's/model name[[:space:]]*: *//')"
        echo -e "  ${C_BOLD}核心${C_RESET}    $(nproc)"
    fi
    echo -e "  ${C_BOLD}使用率${C_RESET}"
    top -bn1 | head -5 | tail -1
}

do_memory() {
    title "内存"
    echo -e "  ${C_BOLD}内存${C_RESET}"
    free -h | awk '/^Mem:/{printf "    总量: %-8s 已用: %-8s 可用: %-8s 缓存: %s\n", $2, $3, $7, $6}'
    echo -e "  ${C_BOLD}Swap${C_RESET}"
    free -h | awk '/^Swap:/{printf "    总量: %-8s 已用: %-8s 可用: %s\n", $2, $3, $4}'
}

do_disk() {
    title "磁盘"
    df -h --total 2>/dev/null | awk '
    NR==1 {printf "  %-20s %8s %8s %8s %5s  %s\n", "文件系统", "大小", "已用", "可用", "使用%", "挂载点"; printf "  %s\n", "-------------------- -------- -------- -------- -----  -----"}
    /^\/dev/ || /^total/ {printf "  %-20s %8s %8s %8s %5s  %s\n", $1, $2, $3, $4, $5, $6}'
}

do_network() {
    local ipv4 ipv6
    title "网络"
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
    clear
    do_overview
    echo ""
    kairo_pause "按 Enter 返回主菜单..."
}
