#!/bin/bash
# OPSTOOL - 运维工具箱主入口
# 用法: ot

LIB_DIR="/usr/local/lib/opstool"
MODULES_DIR="${LIB_DIR}/modules"
VERSION=$(cat "${LIB_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
REPO_URL="https://raw.githubusercontent.com/Ekko7778/opstool/main"

show_banner() {
    echo '
 ██████╗ ██████╗ ████████╗
██╔════╝ ██╔══██╗╚══██╔══╝
██║  ███╗██████╔╝   ██║
██║   ██║██╔══██╗   ██║
╚██████╔╝██║  ██║   ██║
 ╚═════╝ ╚═╝  ╚═╝   ╚═╝
            T O O L          v'"$VERSION"'
'
}

do_update() {
    echo ""
    echo ">>> 正在检查更新..."
    # 加随机参数绕过 GitHub 缓存
    remote_ver=$(curl -fsSL "${REPO_URL}/VERSION?t=$(date +%s)" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$remote_ver" ]; then
        echo "  无法连接远程仓库"
        return
    fi
    if [ "$VERSION" = "$remote_ver" ]; then
        echo "  已是最新版本 v${VERSION}"
        return
    fi
    echo ">>> 发现新版本 v${VERSION} → v${remote_ver}"
    curl -fsSL "${REPO_URL}/install.sh?t=$(date +%s)" | bash
}

do_uninstall() {
    echo ""
    echo ">>> 即将卸载 OPSTOOL，以下文件将被删除:"
    echo "  /usr/local/bin/ot"
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
        rm -f /usr/local/bin/ot
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

    echo "  [1] SSH 密码登录管理"
    echo "  [2] 检查更新"
    echo "  [3] 卸载 OPSTOOL"
    echo "  [0] 退出"
    echo ""
    read -p "  请输入选项: " choice

    case "$choice" in
        1)
            export OPSTOOL_MODE="module"
            source "${MODULES_DIR}/ssh-passwd.sh"
            unset OPSTOOL_MODE
            if type menu &>/dev/null; then
                menu
            fi
            ;;
        2)
            do_update
            echo ""; read -p "  按回车键继续..."
            ;;
        3)
            do_uninstall
            echo ""; read -p "  按回车键继续..."
            ;;
        0)
            echo "👋 再见！"; exit 0
            ;;
        *)
            echo "  无效选项"; sleep 1
            ;;
    esac
done
