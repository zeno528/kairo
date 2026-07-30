#!/usr/bin/env bash
# 内核参数调优 — 生成 sysctl 优化配置，一键应用与恢复。

SYSCTL_CONF="/etc/sysctl.d/99-kairo.conf"

# 输出优化配置内容（BBR 仅在内核支持时加入）。
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
    echo ""
    title "当前内核参数"
    local key val
    for key in \
        net.ipv4.tcp_congestion_control \
        net.core.default_qdisc \
        net.ipv4.tcp_fastopen \
        net.core.somaxconn \
        fs.file-max \
        vm.swappiness; do
        val=$(sysctl -n "$key" 2>/dev/null || echo "未知")
        printf '  %-38s %s\n' "$key" "$val"
    done
    if [ -f "$SYSCTL_CONF" ]; then
        success "已应用 Kairo 优化配置 ($SYSCTL_CONF)"
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

menu() {
    local choice
    while true; do
        clear
        title "⚙ 内核参数调优"
        do_status
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 一键应用优化    ${C_BOLD}[2]${C_RESET} 恢复默认"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_apply ;;
            2) do_restore ;;
            0) return ;;
            *) error "无效选项" ;;
        esac
        echo ""
        kairo_pause "按 Enter 返回内核调优菜单..."
    done
}
