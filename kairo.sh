#!/usr/bin/env bash
# KAIRO - 运维工具箱主入口
# 用法: ka                    # 交互菜单
#       ka <模块> [操作] [参数]  # CLI 调用

BIN_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/kairo"
LEGACY_LIB_DIR="/usr/local/lib/opstool"
REPO="zeno528/kairo"
# shellcheck disable=SC2034 # 由 lib/core.sh 的 fetch_remote_file 使用。
KAIRO_BRANCH="main"
# shellcheck disable=SC2034 # 由 lib/core.sh 的 fetch_remote_file 使用。
CONTENTS_URL="https://api.github.com/repos/${REPO}/contents"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 从仓库直接运行时优先使用当前源码；安装后则使用运行时目录。
if [ -f "${SCRIPT_DIR}/lib/core.sh" ]; then
    KAIRO_ROOT="$SCRIPT_DIR"
elif [ -f "${LIB_DIR}/lib/core.sh" ]; then
    KAIRO_ROOT="$LIB_DIR"
else
    echo "Kairo 运行时文件不完整，请重新安装。" >&2
    exit 1
fi

# shellcheck disable=SC1091
source "${KAIRO_ROOT}/lib/core.sh"
# shellcheck disable=SC1091
source "${KAIRO_ROOT}/modules/registry.sh"

VERSION=$(cat "${KAIRO_ROOT}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

kairo_cleanup() {
    _stop_spinner
}
trap kairo_cleanup EXIT
trap 'kairo_cleanup; exit 130' INT TERM

show_banner() {
    local width=42 header="─ Kairo "
    local version_line="  v${VERSION}"
    local repo_line="  https://github.com/zeno528/kairo"
    local i dash="" fill="" version_padding="" repo_padding=""

    for ((i=${#header}; i<width; i++)); do fill+="─"; done
    for ((i=0; i<width; i++)); do dash+="─"; done
    for ((i=${#version_line}; i<width; i++)); do version_padding+=" "; done
    for ((i=${#repo_line}; i<width; i++)); do repo_padding+=" "; done
    echo -e "  ${C_CYAN}╭${C_BOLD}${header}${C_RESET}${C_CYAN}${fill}╮${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}${C_BOLD}${C_CYAN}${version_line}${C_RESET}${version_padding}${C_CYAN}│${C_RESET}"
    echo -e "  ${C_CYAN}│${C_RESET}${C_DIM}${repo_line}${C_RESET}${repo_padding}${C_CYAN}│${C_RESET}"
    echo -e "  ${C_CYAN}╰${dash}╯${C_RESET}"
}

kairo_run_installer() {
    set -o pipefail
    if [ "$(id -u)" -eq 0 ]; then
        fetch_remote_file install.sh | bash
    else
        fetch_remote_file install.sh | sudo bash
    fi
}

do_update() {
    local remote_ver
    echo ""
    _start_spinner "正在检查更新"
    remote_ver=$(fetch_remote_file VERSION 2>/dev/null | tr -d '[:space:]')
    _stop_spinner
    if [ -z "$remote_ver" ]; then
        error "无法连接远程仓库"
        return 1
    fi
    if [ "$VERSION" = "$remote_ver" ]; then
        success "已是最新版本 v${VERSION}"
        return 0
    fi
    warn "发现新版本 v${VERSION} → v${remote_ver}"
    if [ "$(id -u)" -ne 0 ] && ! sudo -v; then
        error "更新需要 sudo 权限"
        return 1
    fi
    kairo_run_installer
}

do_uninstall() {
    local target failed=0
    local -a elevate=()

    echo ""
    warn "即将卸载 Kairo，以下文件将被删除:"
    echo -e "  ${C_GRAY}${BIN_DIR}/ka${C_RESET}"
    echo -e "  ${C_GRAY}${BIN_DIR}/ot（旧版入口，如存在）${C_RESET}"
    echo -e "  ${C_GRAY}${LIB_DIR}/${C_RESET}"
    echo -e "  ${C_GRAY}${LEGACY_LIB_DIR}/（旧版运行库，如存在）${C_RESET}"
    echo ""
    info "Nginx、SSH、防火墙、证书等业务配置不会被删除"
    echo ""
    read -r -p "  确认卸载? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return; }

    if [ "$(id -u)" -ne 0 ]; then
        sudo -v || { error "卸载需要 sudo 权限"; return 1; }
        elevate=(sudo)
    fi

    "${elevate[@]}" rm -f -- "${BIN_DIR}/ka" "${BIN_DIR}/ot" || failed=1
    "${elevate[@]}" rm -rf -- "$LIB_DIR" "$LEGACY_LIB_DIR" || failed=1

    for target in "${BIN_DIR}/ka" "${BIN_DIR}/ot" "$LIB_DIR" "$LEGACY_LIB_DIR"; do
        if [ -e "$target" ] || [ -L "$target" ]; then
            error "仍有残留: $target"
            failed=1
        fi
    done
    if [ "$failed" -ne 0 ]; then
        error "卸载失败"
        return 1
    fi

    success "卸载完成，Kairo 运行文件已全部清理"
    exit 0
}

kairo_module_file() {
    printf '%s/modules/%s.sh' "$KAIRO_ROOT" "$1"
}

_load_module() {
    local module="$1" module_file
    if ! kairo_module_registered "$module"; then
        error "模块不存在: $module"
        return 1
    fi
    module_file=$(kairo_module_file "$module")
    if [ ! -f "$module_file" ]; then
        error "模块文件缺失: $module"
        return 1
    fi
    unset -f menu 2>/dev/null || true
    # shellcheck disable=SC1090
    if ! source "$module_file"; then
        error "模块加载失败: $module"
        return 1
    fi
    if ! declare -F menu >/dev/null; then
        error "模块未提供 menu 函数: $module"
        return 1
    fi
    menu
}

show_help() {
    local group module
    echo "用法: ka                    # 交互菜单"
    echo "      ka <模块> [操作] [参数]  # CLI 调用"
    echo "      ka update               # 检查更新"
    echo "      ka uninstall            # 卸载"
    echo ""
    echo "模块:"
    for group in "${KAIRO_GROUP_IDS[@]}"; do
        printf '  %s:\n' "${KAIRO_GROUP_LABELS[$group]}"
        for module in "${KAIRO_MODULE_IDS[@]}"; do
            if [ "${KAIRO_MODULE_GROUPS[$module]}" = "$group" ]; then
                printf '    %-18s %s\n' "$module" "${KAIRO_MODULE_ACTIONS[$module]}"
            fi
        done
    done
}

run_module_action() {
    local module="$1" action="$2"
    shift 2
    if ! kairo_module_registered "$module"; then
        error "模块不存在: $module"
        return 1
    fi
    if ! kairo_module_supports_action "$module" "$action"; then
        error "模块 $module 不支持操作: $action"
        return 1
    fi
    local module_file
    module_file=$(kairo_module_file "$module")
    if [ ! -f "$module_file" ]; then
        error "模块文件缺失: $module"
        return 1
    fi
    local function_name="do_${action}"
    unset -f "$function_name" 2>/dev/null || true
    # shellcheck disable=SC1090
    if ! source "$module_file"; then
        error "模块加载失败: $module"
        return 1
    fi
    if declare -F "$function_name" >/dev/null; then
        "$function_name" "$@"
    else
        error "操作不存在: $action"
        return 1
    fi
}

if [ $# -gt 0 ]; then
    case "$1" in
        update) do_update; exit $? ;;
        uninstall) do_uninstall; exit $? ;;
        help|--help|-h) show_help; exit 0 ;;
        *)
            module="$1"
            shift
            if [ $# -eq 0 ]; then
                _load_module "$module"
            else
                action="$1"
                shift
                run_module_action "$module" "$action" "$@"
            fi
            exit $?
            ;;
    esac
fi

declare -A KAIRO_MENU_MODULES=()
show_main_menu() {
    local group module number=1
    KAIRO_MENU_MODULES=()
    show_banner
    divider
    echo -e "  ${C_BOLD}[U]${C_RESET} 检查更新    ${C_BOLD}[X]${C_RESET} 卸载 Kairo    ${C_BOLD}[0]${C_RESET} 退出"

    for group in "${KAIRO_GROUP_IDS[@]}"; do
        title "${KAIRO_GROUP_LABELS[$group]}"
        for module in "${KAIRO_MODULE_IDS[@]}"; do
            [ "${KAIRO_MODULE_GROUPS[$module]}" = "$group" ] || continue
            printf '   %b[%d]%b %s\n' "$C_BOLD" "$number" "$C_RESET" "${KAIRO_MODULE_LABELS[$module]}"
            KAIRO_MENU_MODULES["$number"]="$module"
            ((number++))
        done
    done
    divider
}

while true; do
    show_main_menu
    echo ""
    read -r -p "  请输入选项: " choice

    case "$choice" in
        [Uu])
            do_update
            read -r -p "  按回车键重启 Kairo..." _
            exec "$0"
            ;;
        [Xx]) do_uninstall; kairo_pause ;;
        0) echo -e "\n  👋 后会有期！\n"; exit 0 ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ -n "${KAIRO_MENU_MODULES[$choice]+x}" ]; then
                _load_module "${KAIRO_MENU_MODULES[$choice]}"
            else
                error "无效选项"
                sleep 1
            fi
            ;;
    esac
done
