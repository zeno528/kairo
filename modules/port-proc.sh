#!/bin/bash
# port-proc 模块 - 端口/进程管理

PORT_PROCESS_PIDS=()

do_listen_ports() {
    local port_filter="${1:-}" name_filter="${2:-}" line addr port pid name i=0
    local -a ss_fields=()
    local -A process_names=()
    PORT_PROCESS_PIDS=()
    command -v ss &>/dev/null || { error "未找到 ss 命令"; return 1; }

    echo ""
    echo -e "  ${C_BOLD}监听端口 / 进程${C_RESET}"
    printf "  ${C_DIM}%-4s %-7s %-8s %s${C_RESET}\n" "编号" "端口" "PID" "进程"
    while IFS= read -r line; do
        read -r -a ss_fields <<< "$line"
        addr="${ss_fields[4]:-}"
        port=${addr##*:}
        [ -n "$port_filter" ] && [ "$port" != "$port_filter" ] && continue
        if [[ "$line" =~ pid=([0-9]+) ]]; then
            pid="${BASH_REMATCH[1]}"
        else
            pid=""
        fi
        if [ -z "$pid" ]; then
            printf "  ${C_DIM}[--]  %-7s %-8s %s${C_RESET}\n" "$port" "-" "（无权限读取进程）"
            continue
        fi
        if [[ -z "${process_names[$pid]+x}" ]]; then
            process_names["$pid"]=$(ps -p "$pid" -o comm= 2>/dev/null)
        fi
        name="${process_names[$pid]}"
        [ -n "$name_filter" ] && [[ "${name,,}" != *"${name_filter,,}"* ]] && continue
        i=$((i + 1))
        PORT_PROCESS_PIDS+=("$pid")
        printf "  [%d]  %-7s %-8s %s\n" "$i" "$port" "$pid" "${name:-（无权限读取）}"
    done < <(ss -H -ltnp 2>/dev/null)
    [ "$i" -eq 0 ] && warn "未找到匹配的监听进程"
}

do_find_by_port() {
    echo ""
    read -p "  输入端口号: " port
    [ -z "$port" ] && info "已取消" && return
    kairo_is_port "$port" || { error "端口必须是 1-65535"; return 1; }
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
        return 1
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
    local pid="${1:-}"
    echo ""
    [ -n "$pid" ] || read -p "  输入 PID: " pid
    [ -z "$pid" ] && info "已取消" && return
    kairo_is_positive_integer "$pid" || { error "PID 必须是正整数"; return 1; }

    if ! kill -0 "$pid" 2>/dev/null; then
        error "进程 $pid 不存在"
        return 1
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
                if kill -9 "$pid" 2>/dev/null; then
                    success "已强制终止"
                else
                    error "强制终止失败"
                    return 1
                fi
            fi
        else
            error "无法终止进程 $pid（权限不足？）"
            return 1
        fi
    else
        info "已取消"
    fi
}

menu() {
    local choice port_filter="" name_filter="" pid
    while true; do
        clear
        title "📡 端口/进程管理"
        do_listen_ports "$port_filter" "$name_filter"
        divider
        echo -e "  ${C_BOLD}[编号]${C_RESET} 选择进程    ${C_BOLD}[P]${C_RESET} 按端口筛选    ${C_BOLD}[N]${C_RESET} 按名称筛选"
        echo -e "  ${C_BOLD}[R]${C_RESET} 清除筛选"
        echo -e "  ${C_BOLD}[0]${C_RESET}  返回主菜单"
        divider
        echo ""
        read -p "  选择进程或操作: " choice
        case "$choice" in
            [Pp]) read -p "  输入端口号: " port_filter; kairo_is_port "$port_filter" || { error "端口必须是 1-65535"; port_filter=""; sleep 1; }; name_filter="" ;;
            [Nn]) read -p "  输入进程名称: " name_filter; port_filter="" ;;
            [Rr]) port_filter=""; name_filter="" ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#PORT_PROCESS_PIDS[@]} ]; then
                    pid="${PORT_PROCESS_PIDS[$((choice - 1))]}"
                    echo ""
                    echo "  [1] 查看进程详情  [2] 终止进程  [0] 返回上级"
                    read -p "  选择操作: " choice
                    case "$choice" in
                        1) ps -p "$pid" -o pid,ppid,user,stat,comm,args ;;
                        2) do_kill_process "$pid" ;;
                    esac
                    echo ""; kairo_pause "按 Enter 返回进程列表..."
                elif [ "$choice" = "0" ]; then
                    return
                else
                    error "无效选项"; sleep 1
                fi
                ;;
        esac
    done
}
