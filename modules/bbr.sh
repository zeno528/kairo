#!/usr/bin/env bash
# BBR/内核加速 — 调用社区标准脚本 tcpx.sh（ylx2016/Linux-NetSpeed）切换拥塞控制算法。

# 第三方脚本固定到明确 commit，避免上游分支变化后执行未知内容。
TCPX_REF="420c87c0f4dd43771a68f95cb47413cc50f23ad1"
TCPX_URL="https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/${TCPX_REF}/tcpx.sh"

do_status() {
    echo ""
    title "当前状态"
    local cc qdisc avail
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    avail=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "未知")
    printf '  当前拥塞算法    %s\n' "$cc"
    printf '  当前队列规则    %s\n' "$qdisc"
    printf '  内核可用算法    %s\n' "$avail"
}

do_launch() {
    echo ""
    warn "即将启动 tcpx.sh 加速面板（社区脚本: ylx2016/Linux-NetSpeed）"
    warn "该面板会修改内核参数，请在面板内按提示操作"
    read -r -p "  确认启动? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }

    if [ "$(id -u)" -ne 0 ]; then
        sudo -v || { error "加速面板需要 sudo 权限"; return 1; }
    fi
    local elevate=()
    [ "$(id -u)" -eq 0 ] || elevate=(sudo)

    info "正在下载并启动 tcpx.sh ..."
    (
        local tmp
        tmp=$(mktemp -d "${TMPDIR:-/tmp}/kairo-tcpx.XXXXXX") || { error "创建临时目录失败"; exit 1; }
        trap 'rm -rf -- "$tmp"' EXIT
        cd -- "$tmp" || exit 1
        if curl --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 -fsSL -o tcpx.sh "$TCPX_URL"; then
            chmod +x tcpx.sh
            "${elevate[@]}" ./tcpx.sh
        else
            error "下载 tcpx.sh 失败，请检查网络或代理"
            exit 1
        fi
    )
}

menu() {
    local choice
    while true; do
        clear
        title "🚀 BBR 加速"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 查看当前算法    ${C_BOLD}[2]${C_RESET} 启动加速面板"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_status ;;
            2) do_launch ;;
            0) return ;;
            *) error "无效选项" ;;
        esac
        echo ""
        kairo_pause "按 Enter 返回 BBR 菜单..."
    done
}
