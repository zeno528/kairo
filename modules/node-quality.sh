#!/bin/bash
# node-quality - NodeQuality 节点质量综合测速

do_run() (
    echo ""
    bash -c \
        'curl --connect-timeout 10 --max-time 300 --retry 2 -fsSL "$0" | bash' \
        "https://run.NodeQuality.com"
)

menu() {
    local choice
    while true; do
        clear
        title "📊 NodeQuality 节点测速"
        echo ""
        info "综合测试延迟、丢包、流媒体解锁等节点质量指标"
        divider
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 开始测试"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_run; echo ""; kairo_pause ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
