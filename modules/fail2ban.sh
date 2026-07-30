#!/usr/bin/env bash
# fail2ban — 用官方 apt 包保护 SSH 免遭暴力破解。

do_status() {
    title "当前状态"
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        warn "未安装"
        return 1
    fi
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        success "fail2ban 运行中"
    else
        warn "fail2ban 未运行"
    fi
    local banned
    banned=$(fail2ban-client status sshd 2>/dev/null | awk -F: '/Currently banned/ { gsub(/^[ ]+/, "", $2); print $2; exit }')
    printf '  sshd 当前封禁 IP 数    %s\n' "${banned:-0}"
}

do_install() {
    echo ""
    command -v apt-get >/dev/null 2>&1 || { error "仅支持 Debian/Ubuntu"; return 1; }
    sudo -v || { error "安装需要 sudo 权限"; return 1; }
    if sudo apt-get update && sudo apt-get install -y fail2ban; then
        sudo systemctl enable --now fail2ban 2>/dev/null || true
        success "fail2ban 安装完成，已保护 SSH"
        info "默认策略：10 分钟内失败 5 次即封禁 10 分钟"
    else
        error "fail2ban 安装失败"
        return 1
    fi
}

do_bans() {
    echo ""
    command -v fail2ban-client >/dev/null 2>&1 || { error "fail2ban 未安装"; return 1; }
    title "sshd 封禁列表"
    if ! sudo fail2ban-client status sshd 2>/dev/null; then
        error "无法获取 sshd jail 状态（服务可能未运行）"
        return 1
    fi
}

do_uninstall() {
    echo ""
    command -v fail2ban-client >/dev/null 2>&1 || { info "fail2ban 未安装"; return 0; }
    warn "即将卸载 fail2ban（SSH 暴破防护将关闭）"
    read -r -p "  确认卸载? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    sudo -v || { error "卸载需要 sudo 权限"; return 1; }
    if sudo apt-get purge -y fail2ban; then
        success "fail2ban 已卸载"
    else
        error "卸载失败"
        return 1
    fi
}

menu() {
    local choice
    while true; do
        clear
        title "🛡 fail2ban 防暴破"
        do_status || true
        divider
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 安装并启用" "${C_BOLD}[2]${C_RESET} 查看封禁 IP" "${C_BOLD}[3]${C_RESET} 卸载"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_install ;;
            2) do_bans ;;
            3) do_uninstall ;;
            0) return ;;
            *) error "无效选项" ;;
        esac
        echo ""
        kairo_pause "按 Enter 返回 fail2ban 菜单..."
    done
}
