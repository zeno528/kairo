#!/bin/bash
# port-proc 模块 - 端口/进程管理

do_listen_ports() {
    echo ""
    if command -v ss &>/dev/null; then
        echo "  监听端口:"
        ss -tlnp 2>/dev/null | awk '
        NR>1 {
            state=$1; local_addr=$4; process=$7
            split(local_addr, a, ":")
            port=a[length(a)]
            if (process ~ /\*$/ || process == "") process="-"
            printf "    %-6s %-22s %s\n", port, state, process
        }'
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | awk 'NR>2'
    else
        echo "  错误: 未找到 ss 或 netstat 命令"
    fi
}

do_find_by_port() {
    echo ""
    read -p "  输入端口号: " port
    [ -z "$port" ] && echo "  已取消" && return
    echo ""
    if command -v ss &>/dev/null; then
        result=$(ss -tlnp "sport = :$port" 2>/dev/null)
        if [ -n "$result" ]; then
            echo "$result"
        else
            echo "  未找到监听端口 $port"
        fi
    elif command -v lsof &>/dev/null; then
        lsof -i ":$port" 2>/dev/null || echo "  未找到端口 $port"
    else
        echo "  错误: 未找到 ss 或 lsof 命令"
    fi
}

do_find_by_name() {
    echo ""
    read -p "  输入进程名称: " name
    [ -z "$name" ] && echo "  已取消" && return
    echo ""
    ps aux | grep -i "$name" | grep -v grep || echo "  未找到进程: $name"
}

do_kill_process() {
    echo ""
    read -p "  输入 PID: " pid
    [ -z "$pid" ] && echo "  已取消" && return

    # 检查 PID 是否存在
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "  错误: 进程 $pid 不存在"
        return
    fi

    # 显示进程信息
    proc_info=$(ps -p "$pid" -o pid,comm,args --no-headers 2>/dev/null)
    echo ""
    echo "  进程信息: $proc_info"
    echo ""
    read -p "  确认终止? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        if kill "$pid" 2>/dev/null; then
            echo "  已发送 SIGTERM 到进程 $pid"
            # 等待 3 秒，如果还在就 SIGKILL
            sleep 3
            if kill -0 "$pid" 2>/dev/null; then
                echo "  进程未退出，发送 SIGKILL..."
                kill -9 "$pid" 2>/dev/null && echo "  已强制终止" || echo "  强制终止失败"
            fi
        else
            echo "  错误: 无法终止进程 $pid（权限不足？）"
        fi
    else
        echo "  已取消"
    fi
}

menu() {
    while true; do
        echo ""
        echo "  [1] 查看监听端口"
        echo "  [2] 按端口查找进程"
        echo "  [3] 按名称查找进程"
        echo "  [4] 终止进程"
        echo "  [0] 返回上级"
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_listen_ports; echo ""; read -p "  按回车键继续..." ;;
            2) do_find_by_port; echo ""; read -p "  按回车键继续..." ;;
            3) do_find_by_name; echo ""; read -p "  按回车键继续..." ;;
            4) do_kill_process; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) echo "  无效选项"; sleep 1 ;;
        esac
    done
}
