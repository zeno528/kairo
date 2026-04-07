#!/bin/bash
# crontab 模块 - 定时任务管理

do_list() {
    echo ""
    if ! crontab -l 2>/dev/null | head -1 | read -r line; then
        warn "当前没有定时任务"
        return
    fi
    echo -e "  ${C_BOLD}当前定时任务${C_RESET}"
    echo -e "  ${C_GRAY}分  时  日  月  周  命令${C_RESET}"
    echo -e "  ${C_GRAY}── ── ── ── ── ──────────────────────${C_RESET}"
    local num=0
    crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | while IFS= read -r line; do
        num=$((num + 1))
        printf "  ${C_DIM}[%d]${C_RESET} %s\n" "$num" "$line"
    done
    echo ""
    # 显示注释行
    local has_comments=0
    crontab -l 2>/dev/null | grep '^#' | grep -v '^#\s*$' | while IFS= read -r line; do
        has_comments=1
        echo -e "  ${C_DIM}${line}${C_RESET}"
    done
}

do_add() {
    echo ""
    echo -e "  ${C_DIM}格式: 分 时 日 月 周 命令${C_RESET}"
    echo -e "  ${C_DIM}示例: */5 * * * * /path/to/script.sh${C_RESET}"
    echo -e "  ${C_DIM}在线生成: https://crontab.guru/${C_RESET}"
    echo ""
    read -p "  输入定时任务表达式: " expr
    [ -z "$expr" ] && info "已取消" && return
    read -p "  输入要执行的命令: " cmd
    [ -z "$cmd" ] && info "已取消" && return
    echo ""
    info "将添加: $expr $cmd"
    read -p "  确认? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    (crontab -l 2>/dev/null; echo "$expr $cmd") | crontab - && success "定时任务已添加"
}

do_remove() {
    echo ""
    local tasks
    tasks=$(crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$')
    if [ -z "$tasks" ]; then
        warn "当前没有定时任务"
        return
    fi
    do_list
    echo ""
    read -p "  输入要删除的编号: " num
    [ -z "$num" ] && info "已取消" && return
    [[ ! "$num" =~ ^[0-9]+$ ]] && error "请输入数字" && return

    # 构建新的 crontab，跳过指定行
    local skip=$num
    local current=0
    local new_crontab=""
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && {
            new_crontab="${new_crontab}${line}"$'\n'
            continue
        }
        current=$((current + 1))
        if [ "$current" -ne "$skip" ]; then
            new_crontab="${new_crontab}${line}"$'\n'
        fi
    done < <(crontab -l 2>/dev/null)

    if [ "$current" -lt "$skip" ]; then
        error "编号 $num 不存在"
        return
    fi
    echo "$new_crontab" | crontab - && success "已删除编号 $num"
}

do_edit() {
    echo ""
    info "将打开编辑器修改定时任务"
    read -p "  按回车键继续..."
    export EDITOR="${EDITOR:-vi}"
    crontab -e
    success "定时任务已保存"
}

menu() {
    while true; do
        title "⏰ 定时任务"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 查看当前定时任务"
        echo -e "  ${C_BOLD}[2]${C_RESET} 添加定时任务"
        echo -e "  ${C_BOLD}[3]${C_RESET} 删除定时任务"
        echo -e "  ${C_BOLD}[4]${C_RESET} 编辑定时任务"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_list; echo ""; read -p "  按回车键继续..." ;;
            2) do_add; echo ""; read -p "  按回车键继续..." ;;
            3) do_remove; echo ""; read -p "  按回车键继续..." ;;
            4) do_edit; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
