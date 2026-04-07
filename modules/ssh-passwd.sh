#!/bin/bash
# ssh-passwd 模块 - SSH 密码登录管理

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_D="/etc/ssh/sshd_config.d"

restart_ssh() {
    if systemctl restart ssh 2>/dev/null; then
        success "SSH 服务已重启"
    elif systemctl restart sshd 2>/dev/null; then
        success "SSH 服务已重启"
    else
        error "无法重启 SSH 服务"
        return 1
    fi
}

# 在所有配置文件中设置指定项
set_sshd_option() {
    local option="$1"
    local value="$2"
    sed -i 's/^#\?'"$option"'.*/'"$option"' '"$value"'/' "$SSHD_CONFIG"
    if [ -d "$SSHD_CONFIG_D" ]; then
        for conf in "$SSHD_CONFIG_D"/*.conf; do
            [ -f "$conf" ] || continue
            if grep -qi "$option" "$conf"; then
                sed -i 's/^#\?'"$option"'.*/'"$option"' '"$value"'/' "$conf"
                info "已更新: $conf"
            fi
        done
    fi
}

set_password_auth() {
    set_sshd_option "PasswordAuthentication" "$1"
}

do_on() {
    set_password_auth "yes"
    set_sshd_option "PermitRootLogin" "yes"
    restart_ssh
    success "密码登录已开启"
}

do_off() {
    set_password_auth "no"
    set_sshd_option "PermitRootLogin" "prohibit-password"
    restart_ssh
    success "密码登录已关闭"
}

do_status() {
    local current=""
    if [ -d "$SSHD_CONFIG_D" ]; then
        current=$(grep -Ei '^\s*PasswordAuthentication' "$SSHD_CONFIG_D"/*.conf 2>/dev/null | tail -1 | grep -oiP '(yes|no)')
    fi
    if [ -z "$current" ]; then
        current=$(grep -Ei '^\s*PasswordAuthentication' "$SSHD_CONFIG" | tail -1 | grep -oiP '(yes|no)')
    fi
    if [ "$current" = "no" ]; then
        echo -e "  密码登录:   ${C_RED}关闭${C_RESET}"
    elif [ "$current" = "yes" ]; then
        echo -e "  密码登录:   ${C_GREEN}开启${C_RESET}"
    else
        echo -e "  密码登录:   ${C_YELLOW}未配置${C_RESET}（默认开启）"
    fi

    local root_login=""
    if [ -d "$SSHD_CONFIG_D" ]; then
        root_login=$(grep -Ei '^\s*PermitRootLogin' "$SSHD_CONFIG_D"/*.conf 2>/dev/null | tail -1 | grep -oiP '(yes|no|prohibit-password|without-password)')
    fi
    if [ -z "$root_login" ]; then
        root_login=$(grep -Ei '^\s*PermitRootLogin' "$SSHD_CONFIG" | tail -1 | grep -oiP '(yes|no|prohibit-password|without-password)')
    fi
    if [ "$root_login" = "prohibit-password" ] || [ "$root_login" = "without-password" ]; then
        echo -e "  Root 登录:   ${C_RED}禁止${C_RESET}（prohibit-password）"
    elif [ "$root_login" = "yes" ]; then
        echo -e "  Root 登录:   ${C_GREEN}允许${C_RESET}"
    elif [ "$root_login" = "no" ]; then
        echo -e "  Root 登录:   ${C_RED}禁止${C_RESET}"
    fi
}

menu() {
    while true; do
        title "🔑 SSH 密码登录管理"
        do_status
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 开启密码登录"
        echo -e "  ${C_BOLD}[2]${C_RESET} 关闭密码登录"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_on; echo ""; read -p "  按回车键继续..." ;;
            2) do_off; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
