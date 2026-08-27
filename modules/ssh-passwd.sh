#!/usr/bin/env bash
# ssh-passwd 模块 - SSH 密码登录管理

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_D="/etc/ssh/sshd_config.d"
KAIRO_SSH_DROPIN="${SSHD_CONFIG_D}/00-kairo-auth.conf"

restart_ssh() {
    if sudo systemctl restart ssh 2>/dev/null ||
       sudo systemctl restart sshd 2>/dev/null; then
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

do_root_key() {
    local src="$HOME/.ssh/authorized_keys" keys effective pw
    if [ ! -s "$src" ]; then
        error "当前用户 (${USER:-$(id -un)}) 没有可用公钥，请先用「公钥管理」添加"
        return 1
    fi
    warn "即将把当前用户的公钥安装到 root，实现 root 免密（公钥）登录"
    read -r -p "  确认开启? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    if ! sudo -v; then
        error "此操作需要 sudo 权限"
        return 1
    fi

    # 剥离 AWS/OCI 风格的 command=/限制前缀，否则复制过去的 key 仍会拒绝 root 登录
    keys=$(mktemp)
    awk '{
        if ($1 ~ /^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-|sk-)/) print
        else { $1 = ""; sub(/^ +/, ""); if (length($0) > 0) print }
    }' "$src" > "$keys"
    if [ ! -s "$keys" ]; then
        rm -f -- "$keys"
        error "未从 authorized_keys 解析到有效公钥"
        return 1
    fi
    if ! sudo install -d -m 0700 -o root -g root /root/.ssh ||
       ! sudo install -m 0600 -o root -g root "$keys" /root/.ssh/authorized_keys; then
        rm -f -- "$keys"
        error "安装 root 公钥失败"
        return 1
    fi
    rm -f -- "$keys"

    # 默认 prohibit-password 已允许 root 公钥登录，只有被显式禁成 no 时才需要改配置
    effective=$(get_effective_sshd_option permitrootlogin)
    if [ "$effective" = "no" ]; then
        pw=$(get_effective_sshd_option passwordauthentication)
        if ! set_password_auth "${pw:-yes}" prohibit-password || ! restart_ssh; then
            error "root 公钥已安装，但放开 root 公钥登录失败"
            return 1
        fi
    fi
    success "root 免密登录已就绪，可直接 ssh root@服务器IP"
}

do_root_login() {
    warn "即将开启 root 直接登录：先设置 root 密码，再允许 root 密码登录"
    read -r -p "  确认开启? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    if ! sudo -v; then
        error "此操作需要 sudo 权限"
        return 1
    fi
    info "请输入 root 的新密码（需要输入两次）："
    sudo passwd root || { error "设置 root 密码失败"; return 1; }
    if set_password_auth yes yes && restart_ssh; then
        success "root 直接登录已开启，可用 ssh root@服务器IP 登录"
    else
        error "开启 root 直接登录失败"
        return 1
    fi
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
    local current root_login root_pw label_w=12
    current=$(get_effective_sshd_option passwordauthentication)
    root_login=$(get_effective_sshd_option permitrootlogin)
    root_pw=$(sudo passwd -S root 2>/dev/null | awk '{print $2}')
    local root_key=""
    if sudo -n test -s /root/.ssh/authorized_keys 2>/dev/null; then
        root_key="yes"
    elif sudo -n true 2>/dev/null; then
        root_key="no"
    fi

    case "$current" in
        no) echo -e "  $(_pad_right "密码登录:" $label_w) ${C_RED}关闭${C_RESET}" ;;
        yes) echo -e "  $(_pad_right "密码登录:" $label_w) ${C_GREEN}开启${C_RESET}" ;;
        *) echo -e "  $(_pad_right "密码登录:" $label_w) ${C_YELLOW}未知${C_RESET}" ;;
    esac
    case "$root_login" in
        yes) echo -e "  $(_pad_right "Root 登录:" $label_w) ${C_GREEN}允许${C_RESET}" ;;
        no|prohibit-password|without-password)
            echo -e "  $(_pad_right "Root 登录:" $label_w) ${C_RED}禁止密码登录${C_RESET}（${root_login}）"
            ;;
        *) echo -e "  $(_pad_right "Root 登录:" $label_w) ${C_YELLOW}未知${C_RESET}" ;;
    esac
    case "$root_pw" in
        P) echo -e "  $(_pad_right "Root 密码:" $label_w) ${C_GREEN}已设置${C_RESET}" ;;
        L) echo -e "  $(_pad_right "Root 密码:" $label_w) ${C_RED}未设置（锁定）${C_RESET}，无法用密码登录 root" ;;
        *) echo -e "  $(_pad_right "Root 密码:" $label_w) ${C_YELLOW}未知${C_RESET}" ;;
    esac
    case "$root_key" in
        yes) echo -e "  $(_pad_right "Root 公钥:" $label_w) ${C_GREEN}已安装${C_RESET}，可免密登录" ;;
        no) echo -e "  $(_pad_right "Root 公钥:" $label_w) ${C_RED}未安装${C_RESET}，无法免密登录 root" ;;
        *) echo -e "  $(_pad_right "Root 公钥:" $label_w) ${C_YELLOW}未知${C_RESET}（需要 sudo 免密缓存）" ;;
    esac
}

menu() {
    while true; do
        clear
        title "🔑 SSH 密码/root 登录管理"
        echo ""
        do_status
        divider
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 一键开启 root 免密（公钥）登录"
        _menu_actions 20 "${C_BOLD}[2]${C_RESET} 一键开启 root 密码登录"
        _menu_actions 20 "${C_BOLD}[3]${C_RESET} 开启密码登录"
        _menu_actions 20 "${C_BOLD}[4]${C_RESET} 关闭密码登录"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请输入选项: " choice
        case "$choice" in
            1) do_root_key; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            2) do_root_login; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            3) do_on; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            4) do_off; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
