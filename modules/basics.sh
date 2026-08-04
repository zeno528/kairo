#!/usr/bin/env bash
# basics — 运维常用工具合集：进菜单即看状态，按编号选装，或一键装齐/升级。
# 工具集经维护者审定；新增或移除工具只改 BASICS_TOOLS 一处。

declare -ra BASICS_TOOLS=(curl wget git vim nano unzip tar htop btop iftop ncdu fzf socat)

# 渲染一个编号单元格："[1] ✔ curl"。$1=编号 $2=工具名
_basics_cell() {
    local num="$1" tool="$2" mark
    if command -v "$tool" >/dev/null 2>&1; then
        mark="${C_GREEN}✔${C_RESET}"
    else
        mark="${C_RED}✘${C_RESET}"
    fi
    printf '%s[%s]%s %s %s' "${C_BOLD}" "$num" "${C_RESET}" "$mark" "$tool"
}

# 双列渲染带编号的状态面板（无标题，供 do_status 和 menu 复用）。
_basics_render() {
    local i left right col_w=24
    for ((i = 0; i < ${#BASICS_TOOLS[@]}; i += 2)); do
        left=$(_basics_cell $((i + 1)) "${BASICS_TOOLS[i]}")
        if (( i + 1 < ${#BASICS_TOOLS[@]} )); then
            right=$(_basics_cell $((i + 2)) "${BASICS_TOOLS[i + 1]}")
            printf '  %s%s\n' "$(_pad_right "$left" "$col_w")" "$right"
        else
            printf '  %s\n' "$left"
        fi
    done
}

do_status() {
    title "基础工具状态"
    _basics_render
}

# 装单个工具（菜单内部用，不暴露为 CLI action）。
_basics_install_one() {
    local tool="$1"
    command -v "$tool" >/dev/null 2>&1 && { info "$tool 已安装"; return 0; }
    info "将安装: $tool"
    sudo -v || { error "安装需要 sudo 权限"; return 1; }
    if kairo_apt_install "$tool"; then
        success "$tool 安装完成"
    else
        error "$tool 安装失败"
        return 1
    fi
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
    local choice max=${#BASICS_TOOLS[@]}
    while true; do
        clear
        title "🧰 基础工具"
        _basics_render
        divider
        _menu_actions 26 "${C_BOLD}$(kairo_menu_range "$max" "安装对应工具")${C_RESET}"
        _menu_actions 26 "${C_BOLD}[a]${C_RESET} 一键装齐缺失工具"
        _menu_actions 26 "${C_BOLD}[u]${C_RESET} 升级已装工具"
        _menu_actions 26 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            [aA]) do_install ;;
            [uU]) do_upgrade ;;
            0) return ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max )); then
                    _basics_install_one "${BASICS_TOOLS[choice - 1]}"
                else
                    error "无效选项"
                fi
                ;;
        esac
        kairo_pause
    done
}
