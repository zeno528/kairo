#!/usr/bin/env bash
# 系统优化 — 内核参数调优与 BBR 加速（调用 tcpx.sh）。

# 第三方脚本固定到明确 commit，避免上游分支变化后执行未知内容。
TCPX_REF="420c87c0f4dd43771a68f95cb47413cc50f23ad1"
TCPX_URL="https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/${TCPX_REF}/tcpx.sh"
BBRV3_REF="0923a1362bfb37f91b4bd18b84e17007b92a46d7"
BBRV3_URL="https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/${BBRV3_REF}/install.sh"

SYSCTL_CONF="/etc/sysctl.d/99-kairo.conf"

# 优化配置内容（BBR 仅在内核支持时加入）。
_kernel_tune_conf() {
    cat <<'EOF'
# Kairo 内核参数优化
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
fs.file-max = 1048576
vm.swappiness = 10
EOF
    if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        printf 'net.ipv4.tcp_congestion_control = bbr\n'
    fi
}

do_status() {
    title "当前状态"
    local cc qdisc avail
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    avail=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "未知")
    printf '  当前拥塞算法    %s\n' "$cc"
    printf '  当前队列规则    %s\n' "$qdisc"
    printf '  内核可用算法    %s\n' "$avail"
    if [ -f "$SYSCTL_CONF" ]; then
        success "已应用 Kairo 优化配置"
    else
        info "未应用 Kairo 优化"
    fi
}

do_apply() {
    echo ""
    warn "将写入 $SYSCTL_CONF 并应用以下优化参数:"
    _kernel_tune_conf | sed 's/^/  /'
    echo ""
    read -r -p "  确认应用? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    sudo -v || { error "需要 sudo 权限"; return 1; }
    if _kernel_tune_conf | sudo tee "$SYSCTL_CONF" >/dev/null && sudo sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1; then
        success "内核优化已应用"
    else
        error "应用失败"
        return 1
    fi
}

do_restore() {
    echo ""
    if [ ! -f "$SYSCTL_CONF" ]; then
        info "未找到 Kairo 优化配置，无需恢复"
        return 0
    fi
    warn "将删除 $SYSCTL_CONF 并恢复系统默认参数"
    read -r -p "  确认恢复? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    sudo -v || { error "需要 sudo 权限"; return 1; }
    if sudo rm -f -- "$SYSCTL_CONF" && sudo sysctl --system >/dev/null 2>&1; then
        success "已恢复系统默认参数"
    else
        error "恢复失败"
        return 1
    fi
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

do_bbrv3() {
    echo ""
    warn "即将启动 BBRv3 管理脚本（社区脚本: byJoey/Actions-bbr-v3）"
    warn "该脚本会安装 BBRv3 内核，安装后需要重启系统生效"
    warn "仅支持 Ubuntu 24.04+ / Debian 12+，旧系统会被脚本自身拦截"
    read -r -p "  确认启动? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }

    if [ "$(id -u)" -ne 0 ]; then
        sudo -v || { error "BBRv3 脚本需要 sudo 权限"; return 1; }
    fi
    local elevate=()
    [ "$(id -u)" -eq 0 ] || elevate=(sudo)

    info "正在下载并启动 BBRv3 管理脚本..."
    (
        local tmp
        tmp=$(mktemp -d "${TMPDIR:-/tmp}/kairo-bbrv3.XXXXXX") || { error "创建临时目录失败"; exit 1; }
        trap 'rm -rf -- "$tmp"' EXIT
        cd -- "$tmp" || exit 1
        if curl --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 -fsSL -o bbrv3.sh "$BBRV3_URL"; then
            "${elevate[@]}" bash bbrv3.sh
        else
            error "下载 BBRv3 脚本失败，请检查网络或代理"
            exit 1
        fi
    )
}

menu() {
    local choice
    while true; do
        clear
        title "⚙ 网络与BBR内核优化"
        do_status
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 一键应用优化    ${C_BOLD}[2]${C_RESET} 恢复默认"
        echo -e "  ${C_BOLD}[3]${C_RESET} BBR 面板（tcpx.sh 综合切换）"
        echo -e "  ${C_BOLD}[4]${C_RESET} BBRv3 内核管理（byJoey）"
        echo -e "  ${C_BOLD}[0]${C_RESET}  返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_apply ;;
            2) do_restore ;;
            3) do_launch ;;
            4) do_bbrv3 ;;
            0) return ;;
            *) error "无效选项" ;;
        esac
        echo ""
        kairo_pause "按 Enter 返回网络与内核优化菜单..."
    done
}
