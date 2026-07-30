#!/bin/bash
# ecs-test - ECS 综合性能测试 (spiritysdx/za)

do_run() (
    echo ""
    local tmp_dir
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/kairo-ecs.XXXXXX") || {
        error "无法创建临时目录"
        return 1
    }
    trap 'rm -rf -- "$tmp_dir"' EXIT
    cd -- "$tmp_dir" || return 1
    bash -c \
        'curl --connect-timeout 10 --max-time 300 --retry 2 -fsSL "$0" | bash' \
        "https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh"
)

menu() {
    local choice
    while true; do
        clear
        title "📋 ECS 综合测试"
        echo ""
        info "全面体检 VPS：CPU、内存、磁盘、网络、虚拟化、流媒体解锁"
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
