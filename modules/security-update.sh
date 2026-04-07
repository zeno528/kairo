#!/bin/bash
# security-update 模块 - 安全更新

_detect_pkg_mgr() {
    if command -v apt &>/dev/null; then
        echo "apt"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v apk &>/dev/null; then
        echo "apk"
    else
        echo ""
    fi
}

PKG_MGR=$(_detect_pkg_mgr)

do_check() {
    echo ""
    case "$PKG_MGR" in
        apt)
            echo -e "  ${C_BOLD}可更新的包${C_RESET}"
            apt list --upgradable 2>/dev/null | grep -v "^Listing" | head -20 | sed 's/^/  /'
            local total
            total=$(apt list --upgradable 2>/dev/null | grep -c '/')
            echo ""
            info "共 $total 个包可更新"
            ;;
        yum)
            echo -e "  ${C_BOLD}检查更新中...${C_RESET}"
            sudo yum check-update 2>/dev/null | tail -n +3 | head -20 | sed 's/^/  /'
            ;;
        dnf)
            echo -e "  ${C_BOLD}检查更新中...${C_RESET}"
            sudo dnf check-update 2>/dev/null | tail -n +3 | head -20 | sed 's/^/  /'
            ;;
        apk)
            echo -e "  ${C_BOLD}检查更新中...${C_RESET}"
            apk version -l '<' 2>/dev/null | head -20 | sed 's/^/  /'
            ;;
        *)
            error "未检测到包管理器 (apt/yum/dnf/apk)"
            ;;
    esac
}

do_security_update() {
    echo ""
    case "$PKG_MGR" in
        apt)
            echo -e "  ${C_BOLD}执行安全更新...${C_RESET}"
            echo ""
            read -p "  确认执行安全更新? [y/N]: " confirm
            [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
            sudo apt update && sudo apt upgrade -y 2>/dev/null && success "安全更新完成"
            ;;
        yum)
            echo -e "  ${C_BOLD}执行安全更新...${C_RESET}"
            echo ""
            read -p "  确认执行安全更新? [y/N]: " confirm
            [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
            sudo yum update --security -y 2>/dev/null && success "安全更新完成"
            ;;
        dnf)
            echo -e "  ${C_BOLD}执行安全更新...${C_RESET}"
            echo ""
            read -p "  确认执行安全更新? [y/N]: " confirm
            [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
            sudo dnf upgrade --security -y 2>/dev/null && success "安全更新完成"
            ;;
        apk)
            echo -e "  ${C_BOLD}执行安全更新...${C_RESET}"
            echo ""
            read -p "  确认执行安全更新? [y/N]: " confirm
            [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
            sudo apk update && sudo apk upgrade 2>/dev/null && success "安全更新完成"
            ;;
        *)
            error "未检测到包管理器"
            ;;
    esac
}

do_full_update() {
    echo ""
    warn "完整更新包含所有包，不仅仅是安全更新"
    echo ""
    read -p "  确认执行完整更新? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    case "$PKG_MGR" in
        apt)
            sudo apt update && sudo apt full-upgrade -y 2>/dev/null && success "完整更新完成"
            ;;
        yum)
            sudo yum update -y 2>/dev/null && success "完整更新完成"
            ;;
        dnf)
            sudo dnf upgrade -y 2>/dev/null && success "完整更新完成"
            ;;
        apk)
            sudo apk update && sudo apk upgrade 2>/dev/null && success "完整更新完成"
            ;;
        *)
            error "未检测到包管理器"
            ;;
    esac
}

do_cleanup() {
    echo ""
    case "$PKG_MGR" in
        apt)
            echo -e "  ${C_BOLD}清理缓存和不需要的包...${C_RESET}"
            sudo apt autoremove -y 2>/dev/null && sudo apt clean 2>/dev/null && success "清理完成"
            ;;
        yum)
            sudo yum autoremove -y 2>/dev/null && sudo yum clean all 2>/dev/null && success "清理完成"
            ;;
        dnf)
            sudo dnf autoremove -y 2>/dev/null && sudo dnf clean all 2>/dev/null && success "清理完成"
            ;;
        apk)
            sudo apk cache clean 2>/dev/null && success "清理完成"
            ;;
        *)
            error "未检测到包管理器"
            ;;
    esac
}

menu() {
    while true; do
        title "🛡 安全更新"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 检查可更新包"
        echo -e "  ${C_BOLD}[2]${C_RESET} 执行安全更新"
        echo -e "  ${C_BOLD}[3]${C_RESET} 执行完整更新"
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
