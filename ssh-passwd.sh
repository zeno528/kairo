#!/bin/bash
# ssh-passwd.sh - 通用 SSH 密码登录开关
# 支持: Debian/Ubuntu/CentOS/AlmaLinux/Arch
# 用法: ssh-passwd [on|off|status]

echo '
███████╗███████╗███╗   ██╗████████╗███████╗██████╗
██╔════╝██╔════╝████╗  ██║╚══██╔══╝██╔════╝██╔══██╗
█████╗  ███████╗██╔██╗ ██║   ██║   █████╗  ██║  ██║
██╔══╝  ╚════██║██║╚██╗██║   ██║   ██╔══╝  ██║  ██║
███████╗███████║██║ ╚████║   ██║   ███████╗██████╔╝
╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═════╝
'

SSHD_CONFIG="/etc/ssh/sshd_config"

restart_ssh() {
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "SSH 服务已重启"
    else
        echo "错误: 无法重启 SSH 服务" >&2
        exit 1
    fi
}

case "$1" in
    on)
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
        restart_ssh
        echo "密码登录: 已开启"
        ;;
    off)
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
        restart_ssh
        echo "密码登录: 已关闭"
        ;;
    status)
        current=$(grep -Ei '^#?\s*PasswordAuthentication' "$SSHD_CONFIG" | tail -1 | grep -oiP '(yes|no)')
        if [ "$current" = "no" ]; then
            echo "密码登录: 关闭"
        elif [ "$current" = "yes" ]; then
            echo "密码登录: 开启"
        else
            echo "密码登录: 未配置（默认开启）"
        fi
        ;;
    *)
        echo "用法: ssh-passwd [on|off|status]"
        exit 1
        ;;
esac
