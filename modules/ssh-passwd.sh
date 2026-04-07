#!/bin/bash
# ssh-passwd 模块 - SSH 密码登录管理

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_D="/etc/ssh/sshd_config.d"

restart_ssh() {
    if systemctl restart ssh 2>/dev/null; then
        echo "SSH 服务已重启"
    elif systemctl restart sshd 2>/dev/null; then
        echo "SSH 服务已重启"
    else
        echo "错误: 无法重启 SSH 服务" >&2
        return 1
    fi
}

# 在所有配置文件中设置指定项
set_sshd_option() {
    local option="$1"
    local value="$2"
    # 1. 修改主配置
    sed -i 's/^#\?'"$option"'.*/'"$option"' '"$value"'/' "$SSHD_CONFIG"
    # 2. 修改 sshd_config.d 下的所有 conf 文件（优先级更高，必须一起改）
    if [ -d "$SSHD_CONFIG_D" ]; then
        for conf in "$SSHD_CONFIG_D"/*.conf; do
            [ -f "$conf" ] || continue
            if grep -qi "$option" "$conf"; then
                sed -i 's/^#\?'"$option"'.*/'"$option"' '"$value"'/' "$conf"
                echo "  已更新: $conf"
            fi
        done
    fi
}

set_password_auth() {
    set_sshd_option "PasswordAuthentication" "$1"
}

do_on() {
    set_password_auth "yes"
    # Ubuntu 默认 PermitRootLogin prohibit-password，需要改为 yes 才允许 root 密码登录
    set_sshd_option "PermitRootLogin" "yes"
    restart_ssh
    echo "密码登录: 已开启"
}

do_off() {
    set_password_auth "no"
    # 恢复为仅允许密钥登录，与 Ubuntu 默认安全策略一致
    set_sshd_option "PermitRootLogin" "prohibit-password"
    restart_ssh
    echo "密码登录: 已关闭"
}

do_status() {
    # 优先读取 sshd_config.d 下的配置（后加载，优先级更高）
    local current=""
    if [ -d "$SSHD_CONFIG_D" ]; then
        current=$(grep -Ei '^\s*PasswordAuthentication' "$SSHD_CONFIG_D"/*.conf 2>/dev/null | tail -1 | grep -oiP '(yes|no)')
    fi
    # 如果 sshd_config.d 没有配置，则读主配置
    if [ -z "$current" ]; then
        current=$(grep -Ei '^\s*PasswordAuthentication' "$SSHD_CONFIG" | tail -1 | grep -oiP '(yes|no)')
    fi
    if [ "$current" = "no" ]; then
        echo "当前密码登录: 关闭"
    elif [ "$current" = "yes" ]; then
        echo "当前密码登录: 开启"
    else
        echo "当前密码登录: 未配置（默认开启）"
    fi

    # 检查 PermitRootLogin
    local root_login=""
    if [ -d "$SSHD_CONFIG_D" ]; then
        root_login=$(grep -Ei '^\s*PermitRootLogin' "$SSHD_CONFIG_D"/*.conf 2>/dev/null | tail -1 | grep -oiP '(yes|no|prohibit-password|without-password)')
    fi
    if [ -z "$root_login" ]; then
        root_login=$(grep -Ei '^\s*PermitRootLogin' "$SSHD_CONFIG" | tail -1 | grep -oiP '(yes|no|prohibit-password|without-password)')
    fi
    if [ "$root_login" = "prohibit-password" ] || [ "$root_login" = "without-password" ]; then
        echo "Root 密码登录: 禁止（PermitRootLogin $root_login）"
    elif [ "$root_login" = "yes" ]; then
        echo "Root 密码登录: 允许"
    elif [ "$root_login" = "no" ]; then
        echo "Root 密码登录: 禁止（PermitRootLogin no）"
    fi
}

# 二级菜单（被 ot 主菜单调用）
menu() {
    while true; do
        echo ""
        do_status
        echo ""
        echo "  [1] 开启密码登录"
        echo "  [2] 关闭密码登录"
        echo "  [0] 返回上级"
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_on; echo ""; read -p "  按回车键继续..." ;;
            2) do_off; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) echo "  无效选项"; sleep 1 ;;
        esac
    done
}


