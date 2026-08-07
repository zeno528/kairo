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
    printf "  ${C_DIM}%s %s %s %s${C_RESET}\n" \
        "$(_pad_right "编号" 6)" "$(_pad_right "端口" 8)" "$(_pad_right "PID" 8)" "进程"
    while IFS= read -r line; do
        read -r -a ss_fields <<< "$line"
        addr="${ss_fields[3]:-}"
        port=${addr##*:}
        [ -n "$port_filter" ] && [ "$port" != "$port_filter" ] && continue
        if [[ "$line" =~ pid=([0-9]+) ]]; then
            pid="${BASH_REMATCH[1]}"
        else
            pid=""
        fi
        if [ -z "$pid" ]; then
            printf "  ${C_DIM}%s %s %s %s${C_RESET}\n" \
                "$(_pad_right "[--]" 6)" "$(_pad_right "$port" 8)" "$(_pad_right "-" 8)" "（无权限读取进程）"
            continue
        fi
        if [[ -z "${process_names[$pid]+x}" ]]; then
            process_names["$pid"]=$(ps -p "$pid" -o comm= 2>/dev/null)
        fi
        name="${process_names[$pid]}"
        [ -n "$name_filter" ] && [[ "${name,,}" != *"${name_filter,,}"* ]] && continue
        i=$((i + 1))
        PORT_PROCESS_PIDS+=("$pid")
        printf "  %s %s %s %s\n" \
            "$(_pad_right "[$i]" 6)" "$(_pad_right "$port" 8)" "$(_pad_right "$pid" 8)" "${name:-（无权限读取）}"
    done < <(ss -H -ltnp 2>/dev/null)
    [ "$i" -eq 0 ] && warn "未找到匹配的监听进程"
}

do_find_by_port() {
    echo ""
    read -r -p "  输入端口号: " port
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
    read -r -p "  输入进程名称: " name
    [ -z "$name" ] && info "已取消" && return
    echo ""
    ps aux | grep -i "$name" | grep -v grep || warn "未找到进程: $name"
}

do_list_memory() {
    local limit="${1:-15}" output line pid user rss pmem name memory_mib i=0
    local mem_total mem_available mem_used mem_percent
    PORT_PROCESS_PIDS=()
    kairo_is_positive_integer "$limit" || { error "显示数量必须是正整数"; return 1; }
    command -v ps &>/dev/null || { error "未找到 ps 命令"; return 1; }

    if [ -r /proc/meminfo ]; then
        read -r mem_total mem_available < <(awk '
            /^MemTotal:/ { total = $2 }
            /^MemAvailable:/ { available = $2 }
            END { print total, available }
        ' /proc/meminfo)
        if [[ "$mem_total" =~ ^[0-9]+$ && "$mem_available" =~ ^[0-9]+$ ]] && [ "$mem_total" -gt 0 ]; then
            mem_used=$((mem_total - mem_available))
            mem_percent=$((mem_used * 100 / mem_total))
            echo ""
            printf "  ${C_BOLD}系统内存总览${C_RESET}  总计: %s MiB  已用: %s MiB (%s%%)  可用: %s MiB\n" \
                "$((mem_total / 1024))" "$((mem_used / 1024))" "$mem_percent" "$((mem_available / 1024))"
        fi
    fi

    if ! output=$(ps -eo pid=,user=,rss=,pmem=,comm= --sort=-rss 2>/dev/null); then
        error "无法读取进程内存占用"
        return 1
    fi

    echo ""
    echo -e "  ${C_BOLD}内存占用 Top ${limit}${C_RESET}"
    printf "  ${C_DIM}%s %s %s %s %s %s${C_RESET}\n" \
        "$(_pad_right "编号" 6)" "$(_pad_right "PID" 8)" "$(_pad_right "内存" 10)" \
        "$(_pad_right "占比" 8)" "$(_pad_right "用户" 12)" "进程"
    while IFS= read -r line; do
        read -r pid user rss pmem name <<< "$line"
        [[ "$pid" =~ ^[0-9]+$ && "$rss" =~ ^[0-9]+$ ]] || continue
        memory_mib=$((rss / 1024))
        i=$((i + 1))
        PORT_PROCESS_PIDS+=("$pid")
        printf "  %s %s %s %s %s %s\n" \
            "$(_pad_right "[$i]" 6)" "$(_pad_right "$pid" 8)" "$(_pad_right "${memory_mib} MiB" 10)" \
            "$(_pad_right "${pmem}%" 8)" "$(_pad_right "$user" 12)" "$name"
        [ "$i" -ge "$limit" ] && break
    done <<< "$output"
    [ "$i" -eq 0 ] && warn "未找到可读取内存的进程"
}

do_kill_process() {
    local pid="${1:-}" default_yes="${2:-no}"
    echo ""
    [ -n "$pid" ] || read -r -p "  输入 PID: " pid
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
    if [ "$default_yes" = "yes" ]; then
        read -r -p "  确认终止? [Y/n]: " confirm
        [[ "$confirm" =~ ^[Nn]$ ]] && { info "已取消"; return; }
    else
        read -r -p "  确认终止? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return; }
    fi
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
}

# 进程操作子菜单；返回 2 表示返回主菜单，其余返回 0
_process_action_menu() {
    local pid="$1" choice
    echo ""
    _menu_actions 20 "[1] 查看进程详情"
    _menu_actions 20 "[2] 终止进程"
    _menu_actions 20 "[0] 返回上级"
    _menu_actions 20 "[00] 返回主菜单"
    read -r -p "  选择操作: " choice
    case "$choice" in
        1) ps -p "$pid" -o pid,ppid,user,stat,comm,args ;;
        2) do_kill_process "$pid" ;;
        00) return 2 ;;
        0) ;;
        *) error "无效选项" ;;
    esac
    return 0
}

# 三级页面：监听端口列表
port_menu() {
    local choice port_filter="" name_filter="" pid rc
    while true; do
        clear
        title "🔌 监听端口"
        do_listen_ports "$port_filter" "$name_filter"
        divider
        _menu_actions 20 "${C_BOLD}$(kairo_menu_range "${#PORT_PROCESS_PIDS[@]}" "选择进程")${C_RESET}"
        _menu_actions 20 "${C_BOLD}[P]${C_RESET} 按端口筛选"
        _menu_actions 20 "${C_BOLD}[N]${C_RESET} 按名称筛选"
        _menu_actions 20 "${C_BOLD}[R]${C_RESET} 清除筛选"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回任务管理器"
        _menu_actions 20 "${C_BOLD}[00]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  选择进程或操作: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#PORT_PROCESS_PIDS[@]} ]; then
            pid="${PORT_PROCESS_PIDS[$((choice - 1))]}"
            _process_action_menu "$pid"
            rc=$?
            echo ""; kairo_pause "按 Enter 返回端口列表..."
            [ "$rc" = 2 ] && return
        else
            case "$choice" in
                [Pp]) read -r -p "  输入端口号: " port_filter; kairo_is_port "$port_filter" || { error "端口必须是 1-65535"; port_filter=""; sleep 1; }; name_filter="" ;;
                [Nn]) read -r -p "  输入进程名称: " name_filter; port_filter="" ;;
                [Rr]) port_filter=""; name_filter="" ;;
                00) return 2 ;;
                0) return ;;
                *) error "无效选项"; sleep 1 ;;
            esac
        fi
    done
}

# 二级页面：进入模块默认显示任务管理器（内存占用排行）
menu() {
    local choice pid rc
    while true; do
        clear
        title "📊 任务管理器"
        do_list_memory
        divider
        _menu_actions 20 "${C_BOLD}$(kairo_menu_range "${#PORT_PROCESS_PIDS[@]}" "选择进程")${C_RESET}"
        _menu_actions 20 "${C_BOLD}[P]${C_RESET} 监听端口列表"
        _menu_actions 20 "${C_BOLD}[R]${C_RESET} 刷新排行"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  选择进程或操作: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#PORT_PROCESS_PIDS[@]} ]; then
            pid="${PORT_PROCESS_PIDS[$((choice - 1))]}"
            _process_action_menu "$pid"
            rc=$?
            echo ""; kairo_pause "按 Enter 返回任务管理器..."
            [ "$rc" = 2 ] && return
        else
            case "$choice" in
                [Pp]) port_menu; rc=$?; [ "$rc" = 2 ] && return ;;
                [Rr]) ;;
                0) return ;;
                *) error "无效选项"; sleep 1 ;;
            esac
        fi
    done
}
