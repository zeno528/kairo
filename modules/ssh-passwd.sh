#!/bin/bash
# ssh-passwd 模块 - SSH 密码登录管理
# alias: sp
# 用法: sp [on|off|status]

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

# 统一设置所有配置文件中的 PasswordAuthentication
set_password_auth() {
    local value="$1"
    # 1. 修改主配置
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication '"$value"'/' "$SSHD_CONFIG"
    # 2. 修改 sshd_config.d 下的所有 conf 文件（优先级更高，必须一起改）
    if [ -d "$SSHD_CONFIG_D" ]; then
        for conf in "$SSHD_CONFIG_D"/*.conf; do
            [ -f "$conf" ] || continue
            if grep -qi 'PasswordAuthentication' "$conf"; then
                sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication '"$value"'/' "$conf"
                echo "  已更新: $conf"
            fi
        done
    fi
}

do_on() {
    set_password_auth "yes"
    restart_ssh
    echo "密码登录: 已开启"
}

do_off() {
    set_password_auth "no"
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
        echo "密码登录: 关闭"
    elif [ "$current" = "yes" ]; then
        echo "密码登录: 开启"
    else
        echo "密码登录: 未配置（默认开启）"
    fi
}

# 二级菜单（被 eb 主菜单调用）
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

# 独立运行模式（被 sp 命令直接调用）
if [ "${OPSTOOL_MODE}" != "module" ]; then
    if [ -n "$1" ]; then
        case "$1" in
            on)     do_on ;;
            off)    do_off ;;
            status) do_status ;;
            *)      echo "用法: sp [on|off|status]"; exit 1 ;;
        esac
        exit 0
    fi
    menu
fi
