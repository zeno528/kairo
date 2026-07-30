#!/bin/bash
# security-update 模块 - 软件更新（Debian/Ubuntu）

# 检查失效源并提示，不阻断更新
_apt_update_smart() {
    local update_log update_output update_status
    update_log=$(mktemp) || {
        error "无法创建软件源更新日志"
        return 1
    }
    sudo apt-get update 2>&1 | tee "$update_log"
    update_status=${PIPESTATUS[0]}
    update_output=$(<"$update_log")
    rm -f -- "$update_log"

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
    local packages total
    echo ""
    echo -e "  ${C_BOLD}可更新的包${C_RESET}"
    _start_spinner "正在扫描可更新的软件包"
    packages=$(LC_ALL=C apt-get -s upgrade 2>/dev/null | awk '/^Inst / { print $2 }')
    _stop_spinner
    [ -n "$packages" ] && printf '%s\n' "$packages" | head -20 | sed 's/^/  /'
    total=$(printf '%s\n' "$packages" | sed '/^$/d' | wc -l)
    echo ""
    info "共 $total 个包可更新"
}

do_security_update() {
    echo ""
    echo -e "  ${C_BOLD}执行常规升级...${C_RESET}"
    echo ""
    read -p "  确认执行常规升级? [Y/n]: " confirm
    [ "$confirm" = "n" ] || [ "$confirm" = "N" ] && info "已取消" && return
    _apt_update_smart || return
    if sudo apt-get upgrade -y; then
        success "常规升级完成"
    else
        error "常规升级失败"
        return 1
    fi
}

do_full_update() {
    echo ""
    warn "完整升级可能安装新包或移除冲突包"
    echo ""
    read -p "  确认执行完整升级? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    _apt_update_smart || return
    if sudo apt-get full-upgrade -y; then
        success "完整更新完成"
    else
        error "完整更新失败"
        return 1
    fi
}

do_full_update_preview() {
    echo ""
    info "以下仅为预演，不会修改系统"
    sudo apt-get -s full-upgrade
}

do_cleanup() {
    echo ""
    echo -e "  ${C_BOLD}清理缓存和不需要的包...${C_RESET}"
    if sudo apt-get autoremove -y && sudo apt-get clean; then
        success "清理完成"
    else
        error "清理失败"
        return 1
    fi
}

menu() {
    while true; do
        title "🛡 软件更新"
        do_check
        divider
        echo -e "  ${C_BOLD}[U]${C_RESET} 常规升级（不删除已安装软件包）"
        echo -e "  ${C_BOLD}[F]${C_RESET} 完整升级（可能安装或删除软件包）"
        echo -e "  ${C_BOLD}[P]${C_RESET} 预演完整升级（不修改系统）"
        echo -e "  ${C_BOLD}[C]${C_RESET} 清理缓存        ${C_BOLD}[R]${C_RESET} 刷新列表"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  选择操作: " choice
        case "$choice" in
            [Uu]) do_security_update; echo ""; kairo_pause "按 Enter 返回更新列表..." ;;
            [Ff]) do_full_update; echo ""; kairo_pause "按 Enter 返回更新列表..." ;;
            [Pp]) do_full_update_preview; echo ""; kairo_pause "按 Enter 返回更新列表..." ;;
            [Cc]) do_cleanup; echo ""; kairo_pause "按 Enter 返回更新列表..." ;;
            [Rr]) continue ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
