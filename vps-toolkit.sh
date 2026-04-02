#!/bin/bash
# vps-toolkit - VPS 运维工具箱主入口
# 用法: vps 或 vps [update|uninstall]

VERSION="1.0.0"
MODULES_DIR="/usr/local/lib/vps-toolkit/modules"
CONFIG_FILE="/usr/local/lib/vps-toolkit/config"

show_banner() {
    echo '
███████╗███████╗███████╗███████╗███████╗███████╗███████╗
██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝
█████╗  █████╗  ███████╗█████╗  █████╗  ███████╗███████╗
██╔══╝  ██╔══╝  ╚════██║██╔══╝  ██╔══╝  ╚════██║██╔════╝
██║    ██║     ███████║██║    ██║     ███████║███████╗
╚═╝    ╚═╝     ╚══════╝╚═╝    ╚═╝     ╚══════╝╚══════╝
        ████████╗███████╗██████╗ ███╗   ███╗
        ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
           ██║   █████╗  ██████╔╝██╔████╔██║
           ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║
           ██║   ███████╗██║  ██║██║ ╚═╝ ██║
           ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝
                 VPS TOOLKIT v'"$VERSION"'
'
}

load_modules() {
    local modules=()
    for f in "$MODULES_DIR"/*.sh; do
        [ -f "$f" ] && modules+=("$f")
    done
    echo "${modules[@]}"
}

# 获取模块显示名（从文件注释中提取）
get_module_name() {
    local file="$1"
    head -1 "$file" | sed 's/#[[:space:]]*//' | cut -d'-' -f2 | sed 's/^[[:space:]]*//'
}

# 获取模块简短命令名
get_module_alias() {
    local file="$1"
    basename "$file" .sh | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1' | sed 's/ //g'
}

do_update() {
    echo ">>> 正在更新 vps-toolkit..."
    curl -fsSL https://raw.githubusercontent.com/Ekko7778/vps-toolkit/main/install.sh | bash
}

do_uninstall() {
    echo ">>> 即将卸载 vps-toolkit，以下文件将被删除:"
    echo "  /usr/local/bin/vps"
    echo "  /usr/local/lib/vps-toolkit/"
    # 列出所有快捷命令
    for f in "$MODULES_DIR"/*.sh; do
        [ -f "$f" ] || continue
        local alias
        alias=$(head -5 "$f" | grep -oP '(?<=别名:|alias:)\s*\K\S+' || true)
        [ -n "$alias" ] && echo "  /usr/local/bin/${alias}"
    done
    read -p "确认卸载? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # 删除快捷命令
        for f in "$MODULES_DIR"/*.sh; do
            [ -f "$f" ] || continue
            local alias
            alias=$(head -5 "$f" | grep -oP '(?<=别名:|alias:)\s*\K\S+' || true)
            [ -n "$alias" ] && rm -f "/usr/local/bin/${alias}"
        done
        rm -f /usr/local/bin/vps
        rm -rf /usr/local/lib/vps-toolkit
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
    version|-v) echo "vps-toolkit v${VERSION}"; exit 0 ;;
esac

# 一级菜单
while true; do
    show_banner

    modules=($(load_modules))
    echo "  可用模块:"
    local n=1
    for mod in "${modules[@]}"; do
        name=$(get_module_name "$mod")
        alias=$(head -5 "$mod" | grep -oP '(?<=别名:|alias:)\s*\K\S+' || true)
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
            # 选择模块 → 进入二级菜单
            idx=$((choice - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#modules[@]}" ]; then
                export VPS_TOOLKIT_MODE="module"
                source "${modules[$idx]}"
                unset VPS_TOOLKIT_MODE
                # 调用模块的菜单（约定函数名：menu）
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
