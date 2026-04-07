#!/bin/bash
# port-proc 模块 - 端口/进程管理

do_listen_ports() {
    echo ""
    if command -v ss &>/dev/null; then
        echo -e "  ${C_BOLD}监听端口${C_RESET}"
        ss -tlnp 2>/dev/null | awk '
        NR>1 {
            state=$1; local_addr=$4; process=$7
            split(local_addr, a, ":")
            port=a[length(a)]
            if (process ~ /\*$/ || process == "") process="-"
            printf "  %-6s %-22s %s\n", port, state, process
        }'
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | awk 'NR>2'
    else
        error "未找到 ss 或 netstat 命令"
    fi
}

do_find_by_port() {
    echo ""
    read -p "  输入端口号: " port
    [ -z "$port" ] && info "已取消" && return
    echo ""
    if command -v ss &>/dev/null; then
        result=$(ss -tlnp "sport = :$port" 2>/dev/null)
        if [ -n "$result" ]; then
            echo "$result"
        else
            warn "未找到监听端口 $port"
        fi
    elif command -v lsof &>/dev/null; then
        lsof -i ":$port" 2>/dev/null || warn "未找到端口 $port"
    else
        error "未找到 ss 或 lsof 命令"
    fi
}

do_find_by_name() {
    echo ""
    read -p "  输入进程名称: " name
    [ -z "$name" ] && info "已取消" && return
    echo ""
    ps aux | grep -i "$name" | grep -v grep || warn "未找到进程: $name"
}

do_kill_process() {
    echo ""
    read -p "  输入 PID: " pid
    [ -z "$pid" ] && info "已取消" && return

    if ! kill -0 "$pid" 2>/dev/null; then
        error "进程 $pid 不存在"
        return
    fi

    proc_info=$(ps -p "$pid" -o pid,comm,args --no-headers 2>/dev/null)
    echo ""
    info "进程信息: $proc_info"
    echo ""
    read -p "  确认终止? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        if kill "$pid" 2>/dev/null; then
            success "已发送 SIGTERM 到进程 $pid"
            sleep 3
            if kill -0 "$pid" 2>/dev/null; then
                warn "进程未退出，发送 SIGKILL..."
                kill -9 "$pid" 2>/dev/null && success "已强制终止" || error "强制终止失败"
            fi
        else
            error "无法终止进程 $pid（权限不足？）"
        fi
    else
        info "已取消"
    fi
}

menu() {
    while true; do
        title "📡 端口/进程管理"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 查看监听端口"
        echo -e "  ${C_BOLD}[2]${C_RESET} 按端口查找进程"
        echo -e "  ${C_BOLD}[3]${C_RESET} 按名称查找进程"
        echo -e "  ${C_BOLD}[4]${C_RESET} 终止进程"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_listen_ports; echo ""; read -p "  按回车键继续..." ;;
            2) do_find_by_port; echo ""; read -p "  按回车键继续..." ;;
            3) do_find_by_name; echo ""; read -p "  按回车键继续..." ;;
            4) do_kill_process; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
