#!/bin/bash
# network-test 模块 - 网络测试

BENCH_URL="https://raw.githubusercontent.com/teddysun/across/master/bench.sh"
BACKTRACE_URL="https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh"
NODE_BASE_URL="https://raw.githubusercontent.com/spiritLHLS/speedtest.cn-CN-ID/main"

do_speedtest() {
    echo ""
    curl -fsSL "$BENCH_URL" | bash
}

do_backtrace() {
    echo ""
    if command -v backtrace &>/dev/null; then
        backtrace
    else
        curl -fsSL "$BACKTRACE_URL" | bash && backtrace
    fi
}

# 从 speedtest.cn 节点列表获取 IP 并 ping，按延迟排序
do_ping_test() {
    echo ""
    echo -e "  ${C_BOLD}全国节点 Ping 延迟测试${C_RESET}"
    echo -e "  ${C_DIM}正在获取节点列表...${C_RESET}"

    local tmp_dir="/tmp/opstool-ping-$$"
    mkdir -p "$tmp_dir"

    # 并行拉取三网节点 CSV，提取 host 和城市信息
    (
        for isp in telecom unicom mobile; do
            local csv_url="${NODE_BASE_URL}/${isp}.csv"
            curl -fsSL --max-time 10 "$csv_url" 2>/dev/null | tail -n +2 | while IFS=, read -r _ _ _ _ _ host _ _ city _ operator _; do
                [ -z "$host" ] && continue
                # 提取 IP（从 host 中取第一个）
                local ip
                ip=$(echo "$host" | cut -d: -f1)
                [ -z "$ip" ] && continue
                echo "${ip},${city},${operator}"
            done
        done
    ) | shuf | head -30 > "${tmp_dir}/nodes.csv"

    local total
    total=$(wc -l < "${tmp_dir}/nodes.csv")
    if [ "$total" -eq 0 ]; then
        error "无法获取节点列表"
        rm -rf "$tmp_dir"
        return
    fi

    info "测试 $total 个节点..."
    echo ""

    # 逐个 ping，收集结果
    local results=""
    local i=0
    while IFS=, read -r ip city operator; do
        i=$((i + 1))
        [ -z "$ip" ] && continue
        printf "\r  ${C_DIM}测试中 %d/%d...${C_RESET}" "$i" "$total"
        local latency
        latency=$(ping -c 1 -W 2 "$ip" 2>/dev/null | awk -F'/' 'END{print $5}')
        if [ -n "$latency" ]; then
            results="${results}${latency},${city},${operator}\n"
        fi
    done < "${tmp_dir}/nodes.csv"

    echo ""
    echo ""

    if [ -z "$results" ]; then
        error "所有节点均不可达"
        rm -rf "$tmp_dir"
        return
    fi

    # 按延迟排序，显示前 15 个
    echo -e "  ${C_BOLD}运营商  城市      延迟${C_RESET}"
    echo -e "  ${C_GRAY}────── ──────── ─────${C_RESET}"
    echo -e "$results" | sort -t, -k1 -n | head -15 | while IFS=, read -r latency city operator; do
        local color="$C_GREEN"
        if [ "$(echo "${latency%%.*}")" -ge 100 ]; then
            color="$C_YELLOW"
        fi
        if [ "$(echo "${latency%%.*}")" -ge 200 ]; then
            color="$C_RED"
        fi
        printf "  %-6s %-8s ${color}%s ms${C_RESET}\n" "${operator:-未知}" "${city:-未知}" "$latency"
    done

    rm -rf "$tmp_dir"
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
