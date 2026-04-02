#!/bin/bash
# ssh-passwd 模块 - SSH 密码登录管理
# alias: sp
# 用法: sp [on|off|status]

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
        return 1
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

# 二级菜单（被 vps 主菜单调用）
menu() {
    while true; do
        show_logo
        do_status
        echo '
  [1] 开启密码登录
  [2] 关闭密码登录
  [0] 返回上级

请输入选项: '
        read -p "" choice
        case "$choice" in
            1) do_on; echo; read -p "按回车键继续..." ;;
            2) do_off; echo; read -p "按回车键继续..." ;;
            0) return ;;
            *) echo "无效选项"; sleep 1 ;;
        esac
    done
}

# 独立运行模式（被 sp 命令直接调用）
if [ "${EKKOBOX_MODE}" != "module" ]; then
    if [ -n "$1" ]; then
        show_logo
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
