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

_docker_installed() {
    command -v docker &>/dev/null
}

# 添加当前用户到 docker 组，免 sudo
_docker_join_group() {
    if id -nG "$USER" 2>/dev/null | grep -qw docker; then
        return 0
    fi
    if getent group docker &>/dev/null; then
        sudo usermod -aG docker "$USER"
        info "已将 $USER 加入 docker 组（重新登录后免 sudo）"
    fi
}

do_install() {
    echo ""
    if _docker_installed; then
        success "Docker 已安装"
        docker --version 2>/dev/null
        return 0
    fi
    command -v apt-get >/dev/null 2>&1 || { error "仅支持 Debian/Ubuntu"; return 1; }
    sudo -v || { error "安装需要 sudo 权限"; return 1; }

    info "使用 Docker 官方 apt 源安装"
    _start_spinner "正在添加 Docker GPG key 和 apt 源"
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    _stop_spinner

    _start_spinner "正在安装 Docker Engine + Compose"
    if sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        _stop_spinner
        sudo systemctl enable --now docker 2>/dev/null || true
        _docker_join_group
        success "Docker 安装完成"
        docker --version 2>/dev/null
        docker compose version 2>/dev/null
        info "如果 docker 命令需要 sudo，请重新登录以刷新 docker 组权限"
    else
        _stop_spinner
        error "Docker 安装失败"
        return 1
    fi
}

do_status() {
    echo ""
    if ! _docker_installed; then
        warn "Docker 未安装"
        return 1
    fi
    docker --version 2>/dev/null
    if docker compose version &>/dev/null; then
        docker compose version 2>/dev/null | head -1
    fi
    echo ""
    if ! docker info &>/dev/null 2>&1; then
        warn "Docker 服务未运行或当前用户无权限"
        return 1
    fi
    local containers images
    containers=$(docker ps -aq 2>/dev/null | wc -l)
    images=$(docker images -q 2>/dev/null | wc -l)
    printf '  容器数    %s\n' "$containers"
    printf '  镜像数    %s\n' "$images"
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

do_remove() {
    _check_docker || return
    local name="${1:-}"
    [ -n "$name" ] || { echo ""; read -p "  输入容器名或 ID: " name; }
    [ -z "$name" ] && info "已取消" && return
    echo ""
    read -p "  确认删除容器 $name? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    if docker rm -f "$name" 2>/dev/null; then
        success "容器 $name 已删除"
    else
        error "删除失败"
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

do_exec() {
    _check_docker || return
    local name="${1:-}"
    [ -n "$name" ] || { echo ""; read -p "  输入容器名或 ID: " name; }
    [ -z "$name" ] && info "已取消" && return
    local shell
    # 先试 bash，没有就退回 sh
    if docker exec "$name" test -x /bin/bash 2>/dev/null; then
        shell="/bin/bash"
    else
        shell="/bin/sh"
    fi
    info "进入 $name ($shell)，输入 exit 退出"
    docker exec -it "$name" "$shell"
}

do_stats() {
    _check_docker || return
    echo ""
    echo -e "  ${C_BOLD}容器资源占用（单次快照）${C_RESET}"
    docker stats --no-stream --format "table  {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null | sed 's/^/  /'
}

do_compose() {
    _check_docker || return
    command -v docker compose &>/dev/null || { error "未安装 docker compose 插件"; return 1; }
    local compose_dir compose_file current_img
    echo ""
    read -r -p "  输入 compose 项目目录（默认当前目录）: " compose_dir
    compose_dir="${compose_dir:-.}"
    [ -d "$compose_dir" ] || { error "目录不存在: $compose_dir"; return 1; }

    # 自动发现 compose 文件
    if [ -f "$compose_dir/docker-compose.yml" ]; then
        compose_file="$compose_dir/docker-compose.yml"
    elif [ -f "$compose_dir/compose.yaml" ]; then
        compose_file="$compose_dir/compose.yaml"
    else
        error "未找到 docker-compose.yml 或 compose.yaml"; return 1
    fi

    # 展示当前镜像信息
    current_img=$(grep -oP '^\s+image:\s*\K\S+' "$compose_file" 2>/dev/null | head -1)
    echo ""
    if [ -n "$current_img" ]; then
        echo -e "  ${C_BOLD}当前镜像${C_RESET}: $current_img"
    fi

    while true; do
        divider
        _menu_actions 24 "${C_BOLD}[1]${C_RESET} 启动/更新 (up -d)"
        _menu_actions 24 "${C_BOLD}[2]${C_RESET} 停止并移除 (down)"
        _menu_actions 24 "${C_BOLD}[3]${C_RESET} 重启 (restart)"
        _menu_actions 24 "${C_BOLD}[4]${C_RESET} 查看日志 (logs --tail 50)"
        _menu_actions 24 "${C_BOLD}[5]${C_RESET} 拉取新镜像 (pull)"
        _menu_actions 24 "${C_BOLD}[6]${C_RESET} 切换镜像版本"
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回"
        divider
        echo ""
        read -r -p "  选择操作: " sub
        case "$sub" in
            1) (cd "$compose_dir" && docker compose up -d) 2>&1 ;;
            2) read -r -p "  同时删除卷? [y/N]: " rmv; [[ "$rmv" =~ ^[Yy]$ ]] && (cd "$compose_dir" && docker compose down -v) 2>&1 || (cd "$compose_dir" && docker compose down) 2>&1 ;;
            3) (cd "$compose_dir" && docker compose restart) 2>&1 ;;
            4) (cd "$compose_dir" && docker compose logs --tail 50) 2>&1 ;;
            5) (cd "$compose_dir" && docker compose pull) 2>&1 ;;
            6)
                if [ -z "$current_img" ]; then
                    error "无法解析 compose 文件中的镜像配置"; kairo_pause; continue
                fi
                _compose_switch_version "$compose_file" "$compose_dir" "$current_img"
                kairo_pause
                ;;
            0) break ;;
            *) error "无效选项"; sleep 1 ;;
        esac
        [ "$sub" != "0" ] && [ "$sub" != "6" ] && { echo ""; kairo_pause; }
    done
}

# 切换 compose 项目的镜像版本：列出本地可用 tag，改 compose 文件后 up -d
_compose_switch_version() {
    local compose_file="$1" compose_dir="$2" current_img="$3"
    local repo tags=() choice new_img

    repo="${current_img%%:*}"
    mapfile -t tags < <(docker images --format '{{.Tag}}' "$repo" 2>/dev/null | sort -V)

    if [ "${#tags[@]}" -le 1 ]; then
        info "只有当前版本 $current_img，无法切换"; return
    fi

    echo ""
    echo -e "  ${C_BOLD}当前：${C_RESET}$current_img"
    echo ""
    echo -e "  ${C_BOLD}本地可用版本${C_RESET}"
    local i=1 tag
    for tag in "${tags[@]}"; do
        if [ "$repo:$tag" = "$current_img" ]; then
            printf '  [%d] %-45s ${C_GREEN}当前${C_RESET}\n' "$i" "$repo:$tag"
        else
            printf '  [%d] %s\n' "$i" "$repo:$tag"
        fi
        ((i++))
    done
    echo ""
    read -r -p "  选择版本（输入编号，0 取消）: " choice

    [ "$choice" = "0" ] && { info "已取消"; return; }
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#tags[@]}" ]; then
        error "无效选项"; return 1
    fi

    new_img="$repo:${tags[$((choice - 1))]}"
    if [ "$new_img" = "$current_img" ]; then
        info "$current_img 已是当前版本"; return
    fi

    echo ""
    warn "将镜像从 $current_img 切换至 $new_img"
    info "compose 文件将被修改，数据卷不会丢失"
    read -r -p "  确认切换? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return; }

    # 修改 compose 文件
    sed -i "s|image: ${current_img}|image: ${new_img}|" "$compose_file" 2>/dev/null || {
        error "修改 compose 文件失败"; return 1
    }

    # 重建容器
    _start_spinner "正在更新容器"
    if (cd "$compose_dir" && docker compose up -d) >/dev/null 2>&1; then
        _stop_spinner
        success "已切换至 $new_img"
    else
        _stop_spinner
        error "切换失败，正在回滚 compose 文件"
        sed -i "s|image: ${new_img}|image: ${current_img}|" "$compose_file"
        return 1
    fi
}

do_images() {
    _check_docker || return
    local choice imgs=() img_id repo_tag size created i
    local -A USED_IMAGES
    while true; do
        # 收集正在被容器使用的镜像
        USED_IMAGES=()
        while IFS= read -r img; do
            [ -n "$img" ] && USED_IMAGES["$img"]=1
        done < <(docker ps --format '{{.Image}}' 2>/dev/null)

        imgs=()
        echo ""
        echo -e "  ${C_BOLD}镜像列表${C_RESET} （${C_GREEN}●${C_RESET} = 有容器在用）"
        i=1
        while IFS=$'\t' read -r repo_tag size created; do
            imgs+=("$repo_tag")
            created="${created#"${created%%[![:space:]]*}"}"
            if [ -n "${USED_IMAGES[$repo_tag]:-}" ]; then
                printf "  ${C_GREEN}●${C_RESET} [%2d] %-40s  %-8s  %s\n" "$i" "$repo_tag" "$size" "$created"
            else
                printf '    [%2d] %-40s  %-8s  %s\n' "$i" "$repo_tag" "$size" "$created"
            fi
            ((i++))
        done < <(docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' 2>/dev/null)

        if [ "${#imgs[@]}" -eq 0 ]; then
            info "当前没有镜像"
            kairo_pause
            return
        fi
        divider
        _menu_actions 20 "${C_BOLD}[编号]${C_RESET} 删除镜像"
        _menu_actions 20 "${C_BOLD}[p]${C_RESET} 清理未使用的镜像"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            0) return ;;
            [Pp])
                if docker image prune -f 2>&1; then
                    success "清理完成"
                else
                    error "清理失败"
                fi
                kairo_pause
                ;;
            *)
                if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#imgs[@]}" ]; then
                    img_id="${imgs[$((choice - 1))]}"
                    if [ -n "${USED_IMAGES[$img_id]:-}" ]; then
                        warn "$img_id 正被运行中的容器使用，无法删除"
                        info "若要更换版本，请先停止容器，再用新镜像重建"
                        kairo_pause
                        continue
                    fi
                    echo ""
                    read -r -p "  确认删除镜像 $img_id? [y/N]: " confirm
                    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; kairo_pause; continue; }
                    if docker rmi "$img_id" 2>&1; then
                        success "已删除 $img_id"
                    else
                        error "删除失败（可能被容器引用）"
                    fi
                else
                    error "无效选项"; sleep 1
                fi
                kairo_pause
                ;;
        esac
    done
}

do_cleanup() {
    _check_docker || return
    echo ""
    echo -e "  ${C_BOLD}当前磁盘占用${C_RESET}"
    docker system df 2>/dev/null | sed 's/^/  /'
    echo ""
    _menu_actions 24 "${C_BOLD}[1]${C_RESET} 基础清理（容器、网络、悬空镜像）"
    _menu_actions 24 "${C_BOLD}[2]${C_RESET} 深度清理（含所有未使用镜像和卷）"
    _menu_actions 24 "${C_BOLD}[0]${C_RESET} 取消"
    echo ""
    read -r -p "  请选择: " choice
    case "$choice" in
        1) docker system prune -f 2>&1 ;;
        2) docker system prune -a -f --volumes 2>&1 ;;
        0) info "已取消"; return 0 ;;
        *) error "无效选项"; return 1 ;;
    esac
    echo ""
    success "清理完成"
}

menu() {
    local choice name status_cache=""
    while true; do
        clear
        title "🐳 Docker 管理"
        if ! _docker_installed; then
            echo ""
            warn "Docker 未安装"
            divider
            _menu_actions 20 "${C_BOLD}[1]${C_RESET} 安装 Docker"
            _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
            divider
            echo ""
            read -r -p "  请选择: " choice
            case "$choice" in
                1) do_install; status_cache=""; kairo_pause ;;
                0) return ;;
                *) error "无效选项"; sleep 1 ;;
            esac
            continue
        fi
        # 只在首次或操作后刷新状态，避免每次回到菜单都跑 docker info
        if [ -z "$status_cache" ]; then
            status_cache=$(_render_status_cache)
        fi
        echo "$status_cache"
        divider
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 容器列表"
        _menu_actions 20 "${C_BOLD}[2]${C_RESET} 资源监控"
        _menu_actions 20 "${C_BOLD}[3]${C_RESET} Compose 项目"
        _menu_actions 20 "${C_BOLD}[4]${C_RESET} 镜像列表"
        _menu_actions 20 "${C_BOLD}[5]${C_RESET} 系统清理"
        _menu_actions 20 "${C_BOLD}[R]${C_RESET} 刷新状态"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            0) return ;;
            [Rr]) status_cache=""; continue ;;
            1)
                _show_container_list
                _compose_container_menu
                ;;
            2) do_stats; echo ""; kairo_pause ;;
            3) do_compose ;;
            4) do_images ;;
            5) do_cleanup; status_cache=""; echo ""; kairo_pause ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}

# 缓存版状态渲染：收集输出为字符串，避免每次循环都查 docker info
_render_status_cache() {
    echo ""
    docker --version 2>/dev/null
    if docker compose version &>/dev/null; then
        docker compose version 2>/dev/null | head -1
    fi
    echo ""
    # 用 docker ps 做轻量 daemon 探活，比 docker info 快得多
    if ! docker ps &>/dev/null; then
        echo -e "  ${C_YELLOW}⚠ Docker 服务未运行或当前用户无权限${C_RESET}"
        return
    fi
    local containers images
    containers=$(docker ps -aq 2>/dev/null | wc -l)
    images=$(docker images -q 2>/dev/null | wc -l)
    printf '  容器数    %s\n' "$containers"
    printf '  镜像数    %s\n' "$images"
}

# 带编号的容器列表（供菜单选择用）
_show_container_list() {
    echo ""
    mapfile -t DOCKER_CONTAINERS < <(docker ps -a --format '{{.Names}}' 2>/dev/null)
    echo -e "  ${C_BOLD}容器列表${C_RESET}"
    docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null |
        awk -F '\t' '{printf "  [%2d] %-20s  %-14s  %s\n", NR, $1, $2, $3}'
    [ ${#DOCKER_CONTAINERS[@]} -eq 0 ] && info "当前没有容器"
}

# 容器列表后的选择+操作子菜单
_compose_container_menu() {
    local choice name
    while true; do
        _show_container_list
        divider
        _menu_actions 20 "${C_BOLD}[编号]${C_RESET} 选择容器"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -r -p "  选择容器或操作: " choice
        case "$choice" in
            0) return ;;
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
        _menu_actions 18 "[1] 启动"
        _menu_actions 18 "[2] 停止"
        _menu_actions 18 "[3] 重启"
        _menu_actions 18 "[4] 查看日志"
        _menu_actions 18 "[5] 进入终端"
        _menu_actions 18 "[6] 删除容器"
        _menu_actions 18 "[0] 返回上级"
        read -r -p "  选择操作: " choice
        case "$choice" in
            1) do_start "$name" ;;
            2) do_stop "$name" ;;
            3) do_restart "$name" ;;
            4) do_logs "$name" ;;
            5) do_exec "$name" ;;
            6) do_remove "$name" ;;
            0) continue ;;
            *) error "无效选项"; sleep 1; continue ;;
        esac
        echo ""; kairo_pause "按 Enter 返回容器列表..."
    done
}
