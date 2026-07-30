#!/bin/bash
# docker 模块 - Docker 管理

_check_docker() {
    if ! command -v docker &>/dev/null; then
        error "未安装 Docker"
        return 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        error "Docker 服务未运行或当前用户无权限"
        return 1
    fi
}

do_list_containers() {
    _check_docker || return
    echo ""
    echo -e "  ${C_BOLD}运行中的容器${C_RESET}"
    docker ps --format "table  {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | sed 's/^/  /'
    echo ""
    echo -e "  ${C_BOLD}所有容器${C_RESET}"
    docker ps -a --format "table  {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null | sed 's/^/  /'
}

do_start() {
    _check_docker || return
    local name="${1:-}"
    [ -n "$name" ] || { echo ""; read -p "  输入容器名或 ID: " name; }
    [ -z "$name" ] && info "已取消" && return
    if _with_spinner "正在启动容器 $name" docker start "$name"; then
        success "容器 $name 已启动"
    else
        error "启动失败"
        return 1
    fi
}

do_stop() {
    _check_docker || return
    local name="${1:-}"
    [ -n "$name" ] || { echo ""; read -p "  输入容器名或 ID: " name; }
    [ -z "$name" ] && info "已取消" && return
    echo ""
    read -p "  确认停止容器 $name? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    if _with_spinner "正在停止容器 $name" docker stop "$name"; then
        success "容器 $name 已停止"
    else
        error "停止失败"
        return 1
    fi
}

do_restart() {
    _check_docker || return
    local name="${1:-}"
    [ -n "$name" ] || { echo ""; read -p "  输入容器名或 ID: " name; }
    [ -z "$name" ] && info "已取消" && return
    if _with_spinner "正在重启容器 $name" docker restart "$name"; then
        success "容器 $name 已重启"
    else
        error "重启失败"
        return 1
    fi
}

do_logs() {
    _check_docker || return
    local name="${1:-}"
    [ -n "$name" ] || { echo ""; read -p "  输入容器名或 ID: " name; }
    [ -z "$name" ] && info "已取消" && return
    echo ""
    read -p "  查看行数 (默认 50): " lines
    lines=${lines:-50}
    kairo_is_positive_integer "$lines" || { error "行数必须是正整数"; return 1; }
    docker logs --tail "$lines" "$name" 2>&1
}

do_images() {
    _check_docker || return
    echo ""
    echo -e "  ${C_BOLD}镜像列表${C_RESET}"
    docker images --format "table  {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" 2>/dev/null | sed 's/^/  /'
    echo ""
    echo -e "  ${C_BOLD}磁盘占用${C_RESET}"
    docker system df 2>/dev/null | sed 's/^/  /'
    echo ""
    read -p "  清理未使用的镜像? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        if docker image prune -f; then
            success "清理完成"
        else
            error "清理失败"
            return 1
        fi
    fi
}

menu() {
    local choice name
    while true; do
        clear
        title "🐳 Docker 管理"
        _check_docker || { kairo_pause "按 Enter 返回上级..."; return; }
        mapfile -t DOCKER_CONTAINERS < <(docker ps -a --format '{{.Names}}' 2>/dev/null)
        echo ""
        echo -e "  ${C_BOLD}容器列表${C_RESET}"
        docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null |
            awk -F '\t' '{printf "  [%d] %s  %s  %s\n", NR, $1, $2, $3}'
        [ ${#DOCKER_CONTAINERS[@]} -eq 0 ] && info "当前没有容器"
        divider
        echo -e "  ${C_BOLD}[编号]${C_RESET} 选择容器    ${C_BOLD}[I]${C_RESET} 镜像管理"
        echo -e "  ${C_BOLD}[0]${C_RESET}  返回主菜单"
        divider
        echo ""
        read -p "  选择容器或操作: " choice
        case "$choice" in
            0) return ;;
            [Ii]) do_images; echo ""; kairo_pause "按 Enter 返回容器列表..."; continue ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#DOCKER_CONTAINERS[@]} ]; then
                    name="${DOCKER_CONTAINERS[$((choice - 1))]}"
                else
                    error "无效选项"; sleep 1; continue
                fi
                ;;
        esac
        echo ""
        echo "  ${C_BOLD}${name}${C_RESET}"
        echo "  [1] 启动  [2] 停止  [3] 重启  [4] 查看日志  [0] 返回上级"
        read -p "  选择操作: " choice
        case "$choice" in
            1) do_start "$name" ;;
            2) do_stop "$name" ;;
            3) do_restart "$name" ;;
            4) do_logs "$name" ;;
            0) continue ;;
            *) error "无效选项"; sleep 1; continue ;;
        esac
        echo ""; kairo_pause "按 Enter 返回容器列表..."
    done
}
