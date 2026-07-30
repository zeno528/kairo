#!/usr/bin/env bash
# basics — 运维常用工具合集：查看状态、一键装齐缺失、升级已装。
# 工具集经维护者审定；新增或移除工具只改 BASICS_TOOLS 一处。

declare -ra BASICS_TOOLS=(curl wget git vim nano unzip tar htop btop iftop ncdu fzf socat)

# 渲染状态面板的一个单元格："✔ curl" 或 "✘ ncdu"。
_basics_cell() {
    local tool="$1" mark
    if command -v "$tool" >/dev/null 2>&1; then
        mark="${C_GREEN}✔${C_RESET}"
    else
        mark="${C_RED}✘${C_RESET}"
    fi
    printf '%s %s' "$mark" "$tool"
}

do_status() {
    local i left right col_w=22
    title "基础工具状态"
    for ((i = 0; i < ${#BASICS_TOOLS[@]}; i += 2)); do
        left=$(_basics_cell "${BASICS_TOOLS[i]}")
        if (( i + 1 < ${#BASICS_TOOLS[@]} )); then
            right=$(_basics_cell "${BASICS_TOOLS[i + 1]}")
            printf '  %s%s\n' "$(_pad_right "$left" "$col_w")" "$right"
        else
            printf '  %s\n' "$left"
        fi
    done
}

do_install() {
    echo ""
    local missing=() tool
    for tool in "${BASICS_TOOLS[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if [ ${#missing[@]} -eq 0 ]; then
        success "基础工具已全部安装"
        return 0
    fi
    info "将安装: ${C_BOLD}${missing[*]}${C_RESET}"
    sudo -v || { error "安装需要 sudo 权限"; return 1; }
    if kairo_apt_install "${missing[@]}"; then
        success "基础工具安装完成"
    else
        error "基础工具安装失败"
        return 1
    fi
}

do_upgrade() {
    echo ""
    local installed=() tool
    for tool in "${BASICS_TOOLS[@]}"; do
        command -v "$tool" >/dev/null 2>&1 && installed+=("$tool")
    done
    if [ ${#installed[@]} -eq 0 ]; then
        info "尚无已安装的基础工具，请先执行安装"
        return 0
    fi
    sudo -v || { error "升级需要 sudo 权限"; return 1; }
    if kairo_apt_upgrade "${installed[@]}"; then
        success "基础工具升级完成"
    else
        error "基础工具升级失败"
        return 1
    fi
}

menu() {
    local choice
    while true; do
        clear
        title "🧰 基础工具"
        divider
        _menu_actions 24 "${C_BOLD}[1]${C_RESET} 查看状态"
        _menu_actions 24 "${C_BOLD}[2]${C_RESET} 一键装齐缺失工具"
        _menu_actions 24 "${C_BOLD}[3]${C_RESET} 升级已装工具"
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_status ;;
            2) do_install ;;
            3) do_upgrade ;;
            0) return ;;
            *) error "无效选项" ;;
        esac
        kairo_pause
    done
}
