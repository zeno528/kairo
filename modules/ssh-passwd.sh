#!/usr/bin/env bash
# ssh-passwd 模块 - SSH 密码登录管理

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_D="/etc/ssh/sshd_config.d"
KAIRO_SSH_DROPIN="${SSHD_CONFIG_D}/00-kairo-auth.conf"

restart_ssh() {
    if _with_spinner "正在重启 SSH 服务" sudo systemctl restart ssh 2>/dev/null ||
       _with_spinner "正在重启 SSH 服务" sudo systemctl restart sshd 2>/dev/null; then
        success "SSH 服务已重启"
        return 0
    fi
    error "无法重启 SSH 服务"
    return 1
}

get_effective_sshd_option() {
    local option="$1"
    local effective
    effective=$(sshd -T 2>/dev/null) || effective=$(sudo sshd -T 2>/dev/null) || return 1
    awk -v wanted="${option,,}" \
        'tolower($1) == wanted { print tolower($2); exit }' <<< "$effective"
}

restore_sshd_dropin() {
    local backup="$1" had_backup="$2"
    if [ "$had_backup" -eq 1 ]; then
        sudo install -m 0644 "$backup" "$KAIRO_SSH_DROPIN"
    else
        sudo rm -f -- "$KAIRO_SSH_DROPIN"
    fi
}

set_password_auth() {
    local password_value="$1" root_value="$2"
    local candidate backup had_backup=0 effective_password effective_root

    if ! command -v sshd &>/dev/null; then
        error "未找到 sshd 命令"
        return 1
    fi
    if ! sudo -v; then
        error "此操作需要 sudo 权限"
        return 1
    fi
    if [ ! -d "$SSHD_CONFIG_D" ] ||
       ! grep -Eiq '^[[:space:]]*Include[[:space:]]+.*/sshd_config\.d/\*\.conf' "$SSHD_CONFIG"; then
        error "当前 sshd_config 未启用 ${SSHD_CONFIG_D}/*.conf，拒绝直接改写主配置"
        return 1
    fi

    candidate=$(mktemp)
    backup=$(mktemp)
    printf 'PasswordAuthentication %s\nPermitRootLogin %s\n' \
        "$password_value" "$root_value" > "$candidate"
    if sudo test -f "$KAIRO_SSH_DROPIN"; then
        sudo cat "$KAIRO_SSH_DROPIN" | tee "$backup" >/dev/null
        had_backup=1
    fi

    if ! sudo install -m 0644 "$candidate" "$KAIRO_SSH_DROPIN" || ! sudo sshd -t; then
        restore_sshd_dropin "$backup" "$had_backup"
        rm -f -- "$candidate" "$backup"
        error "SSH 配置语法校验失败，已恢复原配置"
        return 1
    fi

    effective_password=$(get_effective_sshd_option passwordauthentication)
    effective_root=$(get_effective_sshd_option permitrootlogin)
    local root_matches=0
    if [ "$effective_root" = "$root_value" ] ||
       { [ "$root_value" = "prohibit-password" ] && [ "$effective_root" = "without-password" ]; }; then
        root_matches=1
    fi
    if [ "$effective_password" != "$password_value" ] || [ "$root_matches" -ne 1 ]; then
        restore_sshd_dropin "$backup" "$had_backup"
        rm -f -- "$candidate" "$backup"
        error "SSH 配置未成为有效配置，已恢复原配置"
        return 1
    fi

    rm -f -- "$candidate" "$backup"
}

do_on() {
    warn "即将开启 SSH 密码登录，并允许 root 使用密码登录"
    read -r -p "  确认开启? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    if set_password_auth yes yes && restart_ssh; then
        success "密码登录已开启"
    else
        error "开启密码登录失败"
        return 1
    fi
}

do_off() {
    warn "即将关闭 SSH 密码登录，并禁止 root 使用密码登录"
    read -r -p "  确认关闭? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    if set_password_auth no prohibit-password && restart_ssh; then
        success "密码登录已关闭"
    else
        error "关闭密码登录失败"
        return 1
    fi
}

do_status() {
    if ! command -v sshd &>/dev/null; then
        error "未找到 sshd 命令"
        return 1
    fi
    local current root_login
    current=$(get_effective_sshd_option passwordauthentication)
    root_login=$(get_effective_sshd_option permitrootlogin)

    case "$current" in
        no) echo -e "  密码登录:   ${C_RED}关闭${C_RESET}" ;;
        yes) echo -e "  密码登录:   ${C_GREEN}开启${C_RESET}" ;;
        *) echo -e "  密码登录:   ${C_YELLOW}未知${C_RESET}" ;;
    esac
    case "$root_login" in
        yes) echo -e "  Root 登录:   ${C_GREEN}允许${C_RESET}" ;;
        no|prohibit-password|without-password)
            echo -e "  Root 登录:   ${C_RED}禁止密码登录${C_RESET}（${root_login}）"
            ;;
        *) echo -e "  Root 登录:   ${C_YELLOW}未知${C_RESET}" ;;
    esac
}

menu() {
    while true; do
        clear
        title "🔑 SSH 密码登录管理"
        do_status
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 开启密码登录"
        echo -e "  ${C_BOLD}[2]${C_RESET} 关闭密码登录"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -r -p "  请输入选项: " choice
        case "$choice" in
            1) do_on; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            2) do_off; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
