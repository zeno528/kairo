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
    echo ""
    docker ps -a --format "{{.ID}} {{.Names}} {{.Status}}" 2>/dev/null | grep -v "Up" | sed 's/^/  /'
    echo ""
    read -p "  输入容器名或 ID: " name
    [ -z "$name" ] && info "已取消" && return
    docker start "$name" 2>/dev/null && success "容器 $name 已启动" || error "启动失败"
}

do_stop() {
    _check_docker || return
    echo ""
    docker ps --format "{{.ID}} {{.Names}} {{.Status}}" 2>/dev/null | sed 's/^/  /'
    echo ""
    read -p "  输入容器名或 ID: " name
    [ -z "$name" ] && info "已取消" && return
    echo ""
    read -p "  确认停止容器 $name? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    docker stop "$name" 2>/dev/null && success "容器 $name 已停止" || error "停止失败"
}

do_restart() {
    _check_docker || return
    echo ""
    docker ps --format "{{.ID}} {{.Names}} {{.Status}}" 2>/dev/null | sed 's/^/  /'
    echo ""
    read -p "  输入容器名或 ID: " name
    [ -z "$name" ] && info "已取消" && return
    docker restart "$name" 2>/dev/null && success "容器 $name 已重启" || error "重启失败"
}

do_logs() {
    _check_docker || return
    echo ""
    docker ps --format "{{.ID}} {{.Names}}" 2>/dev/null | sed 's/^/  /'
    echo ""
    read -p "  输入容器名或 ID: " name
    [ -z "$name" ] && info "已取消" && return
    echo ""
    read -p "  查看行数 (默认 50): " lines
    lines=${lines:-50}
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
        docker image prune -f 2>/dev/null && success "清理完成"
    fi
}

menu() {
    while true; do
        title "🐳 Docker 管理"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 查看容器列表"
        echo -e "  ${C_BOLD}[2]${C_RESET} 启动容器"
        echo -e "  ${C_BOLD}[3]${C_RESET} 停止容器"
        echo -e "  ${C_BOLD}[4]${C_RESET} 重启容器"
        echo -e "  ${C_BOLD}[5]${C_RESET} 查看容器日志"
        echo -e "  ${C_BOLD}[6]${C_RESET} 镜像管理"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_list_containers; echo ""; read -p "  按回车键继续..." ;;
            2) do_start; echo ""; read -p "  按回车键继续..." ;;
            3) do_stop; echo ""; read -p "  按回车键继续..." ;;
            4) do_restart; echo ""; read -p "  按回车键继续..." ;;
            5) do_logs; echo ""; read -p "  按回车键继续..." ;;
            6) do_images; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
