#!/bin/bash
# EKKOBOX - 运维工具箱主入口
# 用法: eb 或 eb [update|uninstall]

LIB_DIR="/usr/local/lib/ekkobox"
MODULES_DIR="${LIB_DIR}/modules"
VERSION=$(cat "${LIB_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

show_banner() {
    echo '
 ██████╗ ██╗   ██╗███████╗███████╗████████╗
 ██╔══██╗██║   ██║██╔════╝██╔════╝╚══██╔══╝
 ██████╔╝██║   ██║█████╗  ███████╗   ██║
 ██╔══██╗██║   ██║██╔══╝  ╚════██║   ██║
 ██║   ██║╚██████╔╝███████╗███████║   ██║
 ╚═╝   ╚═╝ ╚═════╝ ╚══════╝╚══════╝   ╚═╝
                   B O X           v'"$VERSION"'
'
}

load_modules() {
    local modules=()
    for f in "$MODULES_DIR"/*.sh; do
        [ -f "$f" ] && modules+=("$f")
    done
    echo "${modules[@]}"
}

get_module_name() {
    local file="$1"
    grep -oP '(?<=模块\s*-\s*)\K.+|(?<=#\s).*模块' "$file" | head -1 || basename "$file" .sh
}

do_update() {
    echo ">>> 正在更新 EKKOBOX..."
    curl -fsSL https://raw.githubusercontent.com/Ekko7778/ekkobox/main/install.sh | bash
}

do_uninstall() {
    echo ">>> 即将卸载 EKKOBOX，以下文件将被删除:"
    echo "  /usr/local/bin/eb"
    echo "  ${LIB_DIR}/"
    for f in "$MODULES_DIR"/*.sh; do
        [ -f "$f" ] || continue
        local alias
        alias=$(grep -oP '(?<=alias:\s*)\S+' "$f" || true)
        [ -n "$alias" ] && echo "  /usr/local/bin/${alias}"
    done
    read -p "确认卸载? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        for f in "$MODULES_DIR"/*.sh; do
            [ -f "$f" ] || continue
            local alias
            alias=$(grep -oP '(?<=alias:\s*)\S+' "$f" || true)
            [ -n "$alias" ] && rm -f "/usr/local/bin/${alias}"
        done
        rm -f /usr/local/bin/eb
        rm -rf "$LIB_DIR"
        echo ">>> 卸载完成"
    else
        echo "已取消"
    fi
    exit 0
}

# 命令行参数
case "$1" in
    update)     show_banner; do_update; exit 0 ;;
    uninstall)  show_banner; do_uninstall; exit 0 ;;
    version|-v) echo "ekkobox v${VERSION}"; exit 0 ;;
esac

# 一级菜单
while true; do
    show_banner

    modules=($(load_modules))
    echo "  可用模块:"
    n=1
    for mod in "${modules[@]}"; do
        name=$(get_module_name "$mod")
        alias=$(grep -oP '(?<=alias:\s*)\S+' "$mod" || true)
        if [ -n "$alias" ]; then
            printf "  [%d] %-20s (%s)\n" "$n" "$name" "$alias"
        else
            printf "  [%d] %s\n" "$n" "$name"
        fi
        ((n++))
    done
    echo '
  [U] 检查更新
  [0] 退出
'
    read -p "请输入选项: " choice

    case "$choice" in
        [Uu]) do_update; echo; read -p "按回车键继续..." ;;
        0)    echo "再见！"; exit 0 ;;
        *)
            idx=$((choice - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#modules[@]}" ]; then
                export EKKOBOX_MODE="module"
                source "${modules[$idx]}"
                unset EKKOBOX_MODE
                if type menu &>/dev/null; then
                    menu
                fi
                echo; read -p "按回车键返回..."
            else
                echo "无效选项"; sleep 1
            fi
            ;;
    esac
done
