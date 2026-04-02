#!/bin/bash
# ssh-passwd.sh - 通用 SSH 密码登录开关
# 支持: Debian/Ubuntu/CentOS/AlmaLinux/Arch
# 用法: ssh-passwd [on|off|status] 或直接运行进入交互菜单

SSHD_CONFIG="/etc/ssh/sshd_config"

show_logo() {
    echo '
███████╗███████╗███╗   ██╗████████╗███████╗██████╗
██╔════╝██╔════╝████╗  ██║╚══██╔══╝██╔════╝██╔══██╗
█████╗  ███████╗██╔██╗ ██║   ██║   █████╗  ██║  ██║
██╔══╝  ╚════██║██║╚██╗██║   ██║   ██╔══╝  ██║  ██║
███████╗███████║██║ ╚████║   ██║   ███████╗██████╔╝
╚══════╝╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═════╝
'
}

restart_ssh() {
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "SSH 服务已重启"
    else
        echo "错误: 无法重启 SSH 服务" >&2
        exit 1
    fi
}

do_on() {
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    restart_ssh
    echo "密码登录: 已开启"
}

do_off() {
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
    restart_ssh
    echo "密码登录: 已关闭"
}

do_status() {
    current=$(grep -Ei '^#?\s*PasswordAuthentication' "$SSHD_CONFIG" | tail -1 | grep -oiP '(yes|no)')
    if [ "$current" = "no" ]; then
        echo "密码登录: 关闭"
    elif [ "$current" = "yes" ]; then
        echo "密码登录: 开启"
    else
        echo "密码登录: 未配置（默认开启）"
    fi
}

# 命令行参数模式
if [ -n "$1" ]; then
    show_logo
    case "$1" in
        on)   do_on ;;
        off)  do_off ;;
        status) do_status ;;
        *)    echo "用法: ssh-passwd [on|off|status]"; exit 1 ;;
    esac
    exit 0
fi

# 交互式菜单模式
while true; do
    show_logo
    do_status
    echo '
  [1] 开启密码登录
  [2] 关闭密码登录
  [0] 退出
'
    read -p "请输入选项: " choice
    case "$choice" in
        1) do_on; echo; read -p "按回车键继续..." ;;
        2) do_off; echo; read -p "按回车键继续..." ;;
        0) echo "再见！"; exit 0 ;;
        *) echo "无效选项"; sleep 1 ;;
    esac
done
