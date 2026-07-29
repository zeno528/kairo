#!/bin/bash
# security-update 模块 - 软件更新（Debian/Ubuntu）

# 检查失效源并提示，不阻断更新
_apt_update_smart() {
    local update_output update_status
    _start_spinner "正在更新软件源列表"
    update_output=$(sudo apt update 2>&1)
    update_status=$?
    _stop_spinner

    # 提取失效源地址
    local broken
    broken=$(echo "$update_output" | grep -E "Err:.*404|Err:.*does not have a Release file" | grep -oP 'https?://[^ ]+' | sort -u)

    if [ -n "$broken" ]; then
        echo ""
        warn "检测到失效软件源:"
        echo "$broken" | while read -r repo; do
            echo -e "    ${C_RED}${repo}${C_RESET}"
        done
        echo ""
        echo -e "  ${C_DIM}失效源不影响系统官方源的正常更新${C_RESET}"
        echo -e "  ${C_DIM}清理方法: sudo rm /etc/apt/sources.list.d/对应文件.list${C_RESET}"
        echo ""
    fi

    if [ "$update_status" -ne 0 ]; then
        error "刷新软件源列表失败，已取消升级"
        return "$update_status"
    fi
}

do_check() {
    echo ""
    echo -e "  ${C_BOLD}可更新的包${C_RESET}"
    apt list --upgradable 2>/dev/null | grep -v "^Listing" | head -20 | sed 's/^/  /'
    local total
    total=$(apt list --upgradable 2>/dev/null | grep -c '/')
    echo ""
    info "共 $total 个包可更新"
}

do_security_update() {
    echo ""
    echo -e "  ${C_BOLD}执行常规升级...${C_RESET}"
    echo ""
    read -p "  确认执行常规升级? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    _apt_update_smart || return
    _with_spinner "正在升级软件包" sudo apt upgrade -y && success "常规升级完成"
}

do_full_update() {
    echo ""
    warn "完整升级可能安装新包或移除冲突包"
    echo ""
    read -p "  确认执行完整升级? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    _apt_update_smart || return
    _with_spinner "正在升级软件包" sudo apt full-upgrade -y && success "完整更新完成"
}

do_cleanup() {
    echo ""
    echo -e "  ${C_BOLD}清理缓存和不需要的包...${C_RESET}"
    _with_spinner "正在清理缓存和不需要的包" bash -c 'sudo apt autoremove -y && sudo apt clean' && success "清理完成"
}

menu() {
    while true; do
        title "🛡 软件更新"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 检查可更新包"
        echo -e "  ${C_BOLD}[2]${C_RESET} 执行常规升级"
        echo -e "  ${C_BOLD}[3]${C_RESET} 执行完整升级"
        echo -e "  ${C_BOLD}[4]${C_RESET} 清理缓存"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_check; echo ""; read -p "  按回车键继续..." ;;
            2) do_security_update; echo ""; read -p "  按回车键继续..." ;;
            3) do_full_update; echo ""; read -p "  按回车键继续..." ;;
            4) do_cleanup; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
