#!/bin/bash
# EKKOBOX - 运维工具箱主入口
# 用法: eb

LIB_DIR="/usr/local/lib/ekkobox"
MODULES_DIR="${LIB_DIR}/modules"
VERSION=$(cat "${LIB_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

show_banner() {
    echo '
███████╗██╗  ██╗██╗  ██╗ ██████╗
██╔════╝██║ ██╔╝██║ ██╔╝██╔════╝
███████╗█████╔╝█████╔╝██║
██╔══██║██╔═██╗██╔═██╗██║
██║  ██║██║  ██╗██║  ██╗╚██████╗
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝
                 B O X       v'"$VERSION"'
'
}

load_modules() {
    local mods=()
    for f in "$MODULES_DIR"/*.sh; do
        [ -f "$f" ] && mods+=("$f")
    done
    echo "${mods[@]}"
}

get_module_name() {
    local file="$1"
    grep -oP '模块\s*-\s*\K.+|(?<=#\s).*模块' "$file" | head -1 || basename "$file" .sh
}

do_update() {
    echo ""
    echo ">>> 正在更新 EKKOBOX..."
    curl -fsSL https://raw.githubusercontent.com/Ekko7778/ekkobox/main/install.sh | bash
}

do_uninstall() {
    echo ""
    echo ">>> 即将卸载 EKKOBOX，以下文件将被删除:"
    echo "  /usr/local/bin/eb"
    echo "  ${LIB_DIR}/"
    for f in "$MODULES_DIR"/*.sh; do
        [ -f "$f" ] || continue
        alias_name=$(grep -oP 'alias:\s*\K\S+' "$f" 2>/dev/null) || true
        [ -n "$alias_name" ] && echo "  /usr/local/bin/${alias_name}"
    done
    echo ""
    read -p "  确认卸载? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        for f in "$MODULES_DIR"/*.sh; do
            [ -f "$f" ] || continue
            alias_name=$(grep -oP 'alias:\s*\K\S+' "$f" 2>/dev/null) || true
            [ -n "$alias_name" ] && rm -f "/usr/local/bin/${alias_name}"
        done
        rm -f /usr/local/bin/eb
        rm -rf "$LIB_DIR"
        echo ">>> 卸载完成"
        exit 0
    else
        echo "已取消"
    fi
}

# 主菜单
while true; do
    show_banner

    modules=($(load_modules))
    module_count=${#modules[@]}

    echo "  [1] SSH 密码登录管理"

    # 更新和卸载的序号跟在模块后面
    update_num=$((module_count + 2))
    uninstall_num=$((module_count + 3))

    echo "  [$((module_count + 2))] 检查更新"
    echo "  [$((module_count + 3))] 卸载 EKKOBOX"
    echo "  [0] 退出"
    echo ""
    read -p "  请输入选项: " choice

    case "$choice" in
        1)
            export EKKOBOX_MODE="module"
            source "${MODULES_DIR}/ssh-passwd.sh"
            unset EKKOBOX_MODE
            if type menu &>/dev/null; then
                menu
            fi
            ;;
        $update_num)
            do_update
            echo ""; read -p "  按回车键继续..."
            ;;
        $uninstall_num)
            do_uninstall
            echo ""; read -p "  按回车键继续..."
            ;;
        0)
            echo "再见！"; exit 0
            ;;
        *)
            echo "  无效选项"; sleep 1
            ;;
    esac
done
