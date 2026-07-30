#!/bin/bash
# network-test 模块 - 网络测试

# 第三方脚本和数据固定到明确 commit，避免上游分支变化后直接执行未知内容。
BENCH_REF="fdb40962837b2e24bc94b87c2b1786ad2308489a"
NODE_DATA_REF="3443ba80e9114b9732ceadd8d35561c728e8e05f"
BENCH_URL="https://raw.githubusercontent.com/teddysun/across/${BENCH_REF}/bench.sh"
BACKTRACE_RELEASE_URL="https://github.com/zhanghanyun/backtrace/releases/latest/download"
NODE_BASE_URL="https://raw.githubusercontent.com/spiritLHLS/speedtest.cn-CN-ID/${NODE_DATA_REF}"
IPQUALITY_REF="44a55baec6cdd166a68b37f9c07d62d9e0a04f23"
STREAMING_REF="b6d4a6f9a87fc6eae6d3e62d0092ececcec8e844"
IPQUALITY_URL="https://raw.githubusercontent.com/xykt/IPQuality/${IPQUALITY_REF}/ip.sh"
STREAMING_URL="https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/${STREAMING_REF}/check.sh"

do_speedtest() (
    echo ""
    local tmp_dir
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kairo-speedtest.XXXXXX") || {
        error "无法创建测速临时目录"
        return 1
    }
    trap 'rm -rf -- "$tmp_dir"' EXIT
    cd -- "$tmp_dir" || return 1

    bash -c \
        'curl --connect-timeout 10 --max-time 120 --retry 2 -fsSL "$0" | bash' "$BENCH_URL"
)

do_backtrace() (
    echo ""
    local tmp_dir arch release_url
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kairo-backtrace.XXXXXX") || {
        error "无法创建回程测试临时目录"
        return 1
    }
    trap 'rm -rf -- "$tmp_dir"' EXIT
    cd -- "$tmp_dir" || return 1

    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) error "不支持的 CPU 架构: $(uname -m)"; return 1 ;;
    esac
    release_url="${BACKTRACE_RELEASE_URL}/backtrace-linux-${arch}.tar.gz"
    bash -c '
        curl --connect-timeout 10 --max-time 120 --retry 2 -fsSL -o backtrace.tar.gz "$1" &&
            tar -xzf backtrace.tar.gz && [ -x ./backtrace ] && ./backtrace
    ' _ "$release_url"
)

# 获取单个运营商的节点，供并发下载任务调用。
_fetch_ping_nodes() (
    local csv_url="$1"
    local host city operator ip

    set -o pipefail
    curl --connect-timeout 5 --max-time 10 --retry 1 -fsSL "$csv_url" 2>/dev/null |
        tail -n +2 |
        while IFS=, read -r _ _ _ _ _ host _ _ city _ operator _; do
            [ -z "$host" ] && continue
            ip=${host%%:*}
            [ -z "$ip" ] && continue
            printf '%s,%s,%s\n' "$ip" "$city" "$operator"
        done
)

_ping_node() {
    local ip="$1"
    local city="$2"
    local operator="$3"
    local latency

    latency=$(ping -c 1 -W 2 "$ip" 2>/dev/null | awk -F'/' 'END{print $5}')
    [ -n "$latency" ] && printf '%s,%s,%s\n' "$latency" "$city" "$operator"
    return 0
}

# 从 speedtest.cn 节点列表获取 IP 并 ping，按延迟排序
do_ping_test() (
    echo ""
    echo -e "  ${C_BOLD}全国节点 Ping 延迟测试${C_RESET}"
    echo -e "  ${C_DIM}正在获取节点列表...${C_RESET}"

    local tmp_dir
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kairo-ping.XXXXXX") || {
        error "无法创建临时目录"
        return 1
    }
    trap 'rm -rf -- "$tmp_dir"' EXIT

    # 三网节点列表相互独立，后台并发下载以避免串行等待。
    local isp csv_url pid fetch_failed=0
    local -a fetch_pids=()
    for isp in telecom unicom mobile; do
        csv_url="${NODE_BASE_URL}/${isp}.csv"
        _fetch_ping_nodes "$csv_url" > "${tmp_dir}/${isp}.csv" &
        fetch_pids+=("$!")
    done
    for pid in "${fetch_pids[@]}"; do
        wait "$pid" || fetch_failed=1
    done
    [ "$fetch_failed" -eq 0 ] || warn "部分节点列表获取失败，将使用已获取的数据"

    cat "${tmp_dir}"/*.csv | shuf -n 30 > "${tmp_dir}/nodes.csv"

    local total
    total=$(wc -l < "${tmp_dir}/nodes.csv")
    if [ "$total" -eq 0 ]; then
        error "无法获取节点列表"
        return 1
    fi

    info "测试 $total 个节点..."
    echo ""

    # 限制并发数，缩短不可达节点的总等待时间而不制造 ICMP 突发。
    local max_ping_jobs=6
    local -a ping_pids=()
    local i=0
    while IFS=, read -r ip city operator; do
        i=$((i + 1))
        [ -z "$ip" ] && continue
        printf "\r  ${C_DIM}已提交 %d/%d 个测试...${C_RESET}" "$i" "$total"
        _ping_node "$ip" "$city" "$operator" > "${tmp_dir}/result-${i}" &
        ping_pids+=("$!")
        if [ "${#ping_pids[@]}" -ge "$max_ping_jobs" ]; then
            wait "${ping_pids[0]}"
            ping_pids=("${ping_pids[@]:1}")
        fi
    done < "${tmp_dir}/nodes.csv"
    for pid in "${ping_pids[@]}"; do
        wait "$pid"
    done

    echo ""
    echo ""

    local results
    results=$(cat "${tmp_dir}"/result-*)
    if [ -z "$results" ]; then
        error "所有节点均不可达"
        return 1
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
)

do_ip_quality() (
    echo ""
    local tmp_dir
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kairo-ipq.XXXXXX") || {
        error "无法创建临时目录"
        return 1
    }
    trap 'rm -rf -- "$tmp_dir"' EXIT
    cd -- "$tmp_dir" || return 1

    bash -c \
        'curl --connect-timeout 10 --max-time 120 --retry 2 -fsSL "$0" | bash' "$IPQUALITY_URL"
)

do_streaming() (
    echo ""
    local tmp_dir
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kairo-stream.XXXXXX") || {
        error "无法创建临时目录"
        return 1
    }
    trap 'rm -rf -- "$tmp_dir"' EXIT
    cd -- "$tmp_dir" || return 1

    bash -c \
        'curl --connect-timeout 10 --max-time 120 --retry 2 -fsSL "$0" | bash' "$STREAMING_URL"
)

menu() {
    while true; do
        clear
        title "🌐 网络测试"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 网络测速        ${C_BOLD}[2]${C_RESET} 三网回程路由"
        echo -e "  ${C_BOLD}[3]${C_RESET} Ping 延迟测试   ${C_BOLD}[4]${C_RESET} IP 质量体检"
        echo -e "  ${C_BOLD}[5]${C_RESET} 流媒体解锁"
        echo -e "  ${C_BOLD}[0]${C_RESET}  返回主菜单"
        divider
        echo ""
        read -r -p "  请输入选项: " choice
        case "$choice" in
            1) do_speedtest ;;
            2) do_backtrace ;;
            3) do_ping_test ;;
            4) do_ip_quality ;;
            5) do_streaming ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
        echo ""
        kairo_pause "按 Enter 返回当前菜单..."
    done
}
