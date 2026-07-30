#!/bin/bash
# docker 模块 - Docker 管理

# 子菜单退出时置 1 表示需要一路返回主菜单（跨三级菜单的信号）
DOCKER_GO_HOME=0

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
    local p
    p=$(command -v docker 2>/dev/null) && [ -x "$p" ]
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
        echo ""
        read -r -p "  是否检查并升级到最新版本? [Y/n]: " confirm
        [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && return 0
        do_upgrade
        return $?
    fi
    command -v apt-get >/dev/null 2>&1 || { error "仅支持 Debian/Ubuntu"; return 1; }
    sudo -v || { error "安装需要 sudo 权限"; return 1; }

    info "使用 Docker 官方 apt 源安装"
    _start_spinner "正在添加 Docker GPG key 和 apt 源"

    # 移除旧版源文件（防止冲突）
    sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources 2>/dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # 使用官方推荐的 deb822 .sources 格式
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF > /dev/null
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

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

do_upgrade() {
    echo ""
    if ! _docker_installed; then
        info "Docker 未安装，请先安装"; return 1
    fi
    sudo -v || { error "升级需要 sudo 权限"; return 1; }

    local current candidate candidate_ver
    current=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')

    _start_spinner "正在检查更新"
    sudo apt-get update -qq
    candidate=$(apt-cache policy docker-ce 2>/dev/null | awk '/Candidate:/ {print $2; exit}')
    _stop_spinner

    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
        error "无法获取 Docker 最新版本信息，请确认已添加 Docker 官方源"; return 1
    fi

    # 从 Debian 包版本中提取纯 Docker 引擎版本：5:29.6.2-1~debian.13~trixie → 29.6.2
    candidate_ver=$(echo "$candidate" | sed -E 's/^[0-9]+://; s/-.*//')

    echo ""
    info "当前版本: $current"
    info "最新版本: $candidate_ver (包: $candidate)"

    if [ "$current" = "$candidate_ver" ]; then
        success "已是最新版本"; return 0
    fi

    read -r -p "  确认升级? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }

    _start_spinner "正在升级 Docker"
    if sudo apt-get install -y --only-upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        _stop_spinner
        success "Docker 升级完成"
        docker --version 2>/dev/null
    else
        _stop_spinner
        error "升级失败"
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
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回上级"
        _menu_actions 24 "${C_BOLD}[H]${C_RESET} 返回主菜单"
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
            [Hh]) DOCKER_GO_HOME=1; break ;;
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
        echo -e "  ${C_BOLD}镜像列表${C_RESET} （${C_GREEN}●${C_RESET} = 当前使用容器）"
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
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回上级"
        _menu_actions 20 "${C_BOLD}[H]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            [Hh]) DOCKER_GO_HOME=1; return ;;
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

do_uninstall() {
    echo ""
    if ! _docker_installed; then
        info "Docker 未安装，无需卸载"
        return 0
    fi

    warn "此操作将删除所有 Docker 容器、镜像、卷和网络，并彻底卸载 Docker Engine"
    echo ""
    read -r -p "  确认卸载 Docker? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }

    # 收集统计信息用于最终报告
    local running_containers total_containers total_images total_volumes
    running_containers=$(docker ps -q 2>/dev/null | wc -l)
    total_containers=$(docker ps -aq 2>/dev/null | wc -l)
    total_images=$(docker images -q 2>/dev/null | wc -l)
    total_volumes=$(docker volume ls -q 2>/dev/null | wc -l)

    # 停止所有运行中的容器
    if [ "$running_containers" -gt 0 ]; then
        _start_spinner "正在停止 $running_containers 个运行中的容器"
        docker stop $(docker ps -q) 2>/dev/null || true
        _stop_spinner
    fi

    # 删除所有容器
    if [ "$total_containers" -gt 0 ]; then
        _start_spinner "正在删除 $total_containers 个容器"
        docker rm -f $(docker ps -aq) 2>/dev/null || true
        _stop_spinner
    fi

    # 删除所有镜像
    if [ "$total_images" -gt 0 ]; then
        _start_spinner "正在删除 $total_images 个镜像"
        docker rmi -f $(docker images -q) 2>/dev/null || true
        _stop_spinner
    fi

    # 删除所有卷
    if [ "$total_volumes" -gt 0 ]; then
        _start_spinner "正在删除 $total_volumes 个卷"
        docker volume rm $(docker volume ls -q) 2>/dev/null || true
        _stop_spinner
    fi

    # 清理剩余网络和构建缓存
    _start_spinner "正在清理网络和构建缓存"
    docker system prune -a -f --volumes 2>/dev/null || true
    _stop_spinner

    # 停止并禁用 Docker 服务
    _start_spinner "正在停止 Docker 服务"
    sudo systemctl stop docker docker.socket 2>/dev/null || true
    sudo systemctl disable docker docker.socket 2>/dev/null || true
    _stop_spinner

    # apt purge 卸载所有 Docker 包
    _start_spinner "正在卸载 Docker 软件包"
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin \
        docker-ce-rootless-extras 2>/dev/null || true
    sudo apt-get autoremove -y --purge 2>/dev/null || true
    _stop_spinner

    # 清理 Docker 数据目录
    _start_spinner "正在清理 Docker 数据目录"
    sudo rm -rf /var/lib/docker /var/lib/containerd 2>/dev/null || true
    _stop_spinner

    # 清理 Docker apt 源和 GPG key
    _start_spinner "正在清理 Docker apt 源"
    sudo rm -f /etc/apt/sources.list.d/docker.list \
        /etc/apt/sources.list.d/docker.sources 2>/dev/null || true
    sudo rm -f /etc/apt/keyrings/docker.asc 2>/dev/null || true
    sudo apt-get update -qq 2>/dev/null || true
    _stop_spinner

    echo ""
    success "Docker 已完全卸载"
    info "已清理: $total_containers 个容器, $total_images 个镜像, $total_volumes 个卷"
    hash -r
}

do_reset() {
    echo ""
    warn "此操作将删除所有 Docker 容器、镜像、卷和网络，但保留 Docker Engine 本身"
    echo ""
    read -r -p "  确认重置? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }

    local running_containers total_containers total_images total_volumes
    running_containers=$(docker ps -q 2>/dev/null | wc -l)
    total_containers=$(docker ps -aq 2>/dev/null | wc -l)
    total_images=$(docker images -q 2>/dev/null | wc -l)
    total_volumes=$(docker volume ls -q 2>/dev/null | wc -l)

    if [ "$running_containers" -gt 0 ]; then
        _start_spinner "正在停止 $running_containers 个运行中的容器"
        docker stop $(docker ps -q) 2>/dev/null || true
        _stop_spinner
    fi

    if [ "$total_containers" -gt 0 ]; then
        _start_spinner "正在删除 $total_containers 个容器"
        docker rm -f $(docker ps -aq) 2>/dev/null || true
        _stop_spinner
    fi

    if [ "$total_images" -gt 0 ]; then
        _start_spinner "正在删除 $total_images 个镜像"
        docker rmi -f $(docker images -q) 2>/dev/null || true
        _stop_spinner
    fi

    if [ "$total_volumes" -gt 0 ]; then
        _start_spinner "正在删除 $total_volumes 个卷"
        docker volume rm $(docker volume ls -q) 2>/dev/null || true
        _stop_spinner
    fi

    _start_spinner "正在清理网络和构建缓存"
    docker system prune -a -f --volumes 2>/dev/null || true
    _stop_spinner

    echo ""
    success "Docker 环境已重置"
    info "已清理: $total_containers 个容器, $total_images 个镜像, $total_volumes 个卷"
}

do_overview() {
    _check_docker || return
    local choice i
    local -A CT_META      # container_name → "status|image|idx"
    local -A IMG_SIZE     # image → size
    local -A IMG_USED     # image → 1 if has running container
    local CONTAINER_LIST=() IMAGE_LIST=()
    local -A IMG_HAS_CT   # image → 1 if has containers
    local -A img_seen

    while true; do
        clear
        title "🐳 Docker 资源总览"

        # 刷新数据
        CT_META=()
        IMG_SIZE=()
        IMG_USED=()
        IMG_HAS_CT=()
        img_seen=()
        CONTAINER_LIST=()
        IMAGE_LIST=()
        i=1

        while IFS=$'\t' read -r c_name c_img c_status c_ports; do
            [ -z "$c_name" ] && continue
            CONTAINER_LIST+=("$c_name")
            CT_META["$c_name"]="${c_status}|${c_img}|${i}|${c_ports}"
            IMG_HAS_CT["$c_img"]=1
            if [[ "$c_status" =~ ^Up ]]; then
                IMG_USED["$c_img"]=1
            fi
            ((i++))
        done < <(docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null)

        # 收集所有镜像，有容器的排前面
        while IFS=$'\t' read -r img_tag img_size; do
            IMG_SIZE["$img_tag"]="$img_size"
        done < <(docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' 2>/dev/null)

        for img_tag in "${!IMG_SIZE[@]}"; do
            if [ -n "${IMG_HAS_CT[$img_tag]:-}" ]; then
                IMAGE_LIST+=("$img_tag")
                img_seen["$img_tag"]=1
            fi
        done
        for img_tag in "${!IMG_SIZE[@]}"; do
            [ -z "${img_seen[$img_tag]:-}" ] && IMAGE_LIST+=("$img_tag")
        done

        echo ""
        local img_tag img_size c_mark i_mark name_col status_col c_status c_img c_idx c_ports

        if [ "${#IMAGE_LIST[@]}" -eq 0 ]; then
            echo -e "  ${C_DIM}(无镜像)${C_RESET}"
        fi

        # 列标题
        if [ "${#IMAGE_LIST[@]}" -gt 0 ]; then
            printf "  %s %s %s\n" "$(_pad_right "${C_BOLD}NAME${C_RESET}" 42)" "$(_pad_right "${C_BOLD}STATUS${C_RESET}" 18)" "${C_BOLD}PORTS${C_RESET}"
            echo ""
        fi

        for img_tag in "${IMAGE_LIST[@]}"; do
            img_size="${IMG_SIZE[$img_tag]:-}"
            if [ -n "${IMG_USED[$img_tag]:-}" ]; then
                i_mark="${C_GREEN}●${C_RESET}"
            else
                i_mark=" "
            fi
            printf "  %s  %s\n" "$(_pad_right "${i_mark} ${C_BOLD}${img_tag}${C_RESET}" 48)" "${img_size}"

            # 显示该镜像下的容器
            local has_ct=0 total_ct=0
            for c_name in "${CONTAINER_LIST[@]}"; do
                [ "${CT_META[$c_name]}" = "" ] && continue
                IFS='|' read -r c_status c_img c_idx _ <<< "${CT_META[$c_name]}"
                [ "$c_img" != "$img_tag" ] && continue
                ((total_ct++))
            done

            for c_name in "${CONTAINER_LIST[@]}"; do
                [ "${CT_META[$c_name]}" = "" ] && continue
                IFS='|' read -r c_status c_img c_idx c_ports <<< "${CT_META[$c_name]}"
                [ "$c_img" != "$img_tag" ] && continue
                has_ct=1
                if [[ "$c_status" =~ ^Up ]]; then
                    c_mark="${C_GREEN}●${C_RESET}"
                else
                    c_mark="${C_GRAY}○${C_RESET}"
                fi
                # 最后一个容器用 └─，前面的用 ├─
                if [ "$has_ct" -eq "$total_ct" ]; then
                    name_col="  ${C_DIM}└─${C_RESET} ${c_mark} ${C_BOLD}[${c_idx}]${C_RESET} ${c_name}"
                else
                    name_col="  ${C_DIM}├─${C_RESET} ${c_mark} ${C_BOLD}[${c_idx}]${C_RESET} ${c_name}"
                fi
                status_col="${C_DIM}${c_status:0:14}${C_RESET}"
                printf "  %s %s  %s\n" "$(_pad_right "$name_col" 42)" "$(_pad_right "$status_col" 18)" "${c_ports}"
            done
            [ "$has_ct" -eq 0 ] && echo -e "  ${C_DIM}  (无容器)${C_RESET}"
            echo ""
        done

        divider
        _menu_actions 24 "${C_BOLD}[1-${#CONTAINER_LIST[@]}]${C_RESET} 管理容器"
        _menu_actions 24 "${C_BOLD}[R]${C_RESET} 从镜像运行"
        _menu_actions 24 "${C_BOLD}[I]${C_RESET} 镜像管理"
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回"
        divider
        echo ""
        read -r -p "  请选择: " choice

        case "$choice" in
            0) return ;;
            [Rr])
                echo ""
                read -r -p "  镜像名: " img_tag
                [ -z "$img_tag" ] && { info "已取消"; sleep 1; continue; }
                docker image inspect "$img_tag" &>/dev/null || { error "镜像不存在: $img_tag"; sleep 1; continue; }
                read -r -p "  容器名 (回车随机): " c_name
                echo ""
                local run_args=(-d)
                [ -n "$c_name" ] && run_args+=(--name "$c_name")
                run_args+=("$img_tag")
                local c_id
                if c_id=$(docker run "${run_args[@]}" 2>/dev/null); then
                    success "容器已启动: ${c_name:-${c_id:0:12}}"
                else
                    error "启动失败"
                fi
                sleep 1
                ;;
            [Ii]) do_images; [ "$DOCKER_GO_HOME" -eq 1 ] && return ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#CONTAINER_LIST[@]}" ]; then
                    _container_ops_menu "${CONTAINER_LIST[$((choice-1))]}"
                    [ "$DOCKER_GO_HOME" -eq 1 ] && return
                else
                    error "无效选项"; sleep 1
                fi
                ;;
        esac
    done
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
        # 只在首次或操作后刷新状态，避免每次回到菜单都跑 docker ps
        if [ -z "$status_cache" ]; then
            status_cache=$(_render_status_cache)
        fi
        echo "$status_cache"
        divider
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 资源总览"
        _menu_actions 20 "${C_BOLD}[2]${C_RESET} 资源监控"
        _menu_actions 20 "${C_BOLD}[3]${C_RESET} Compose 项目"
        _menu_actions 20 "${C_BOLD}[4]${C_RESET} 系统清理"
        _menu_actions 20 "${C_BOLD}[X]${C_RESET} 重置环境"
        _menu_actions 20 "${C_BOLD}[U]${C_RESET} 检查升级"
        _menu_actions 20 "${C_BOLD}[D]${C_RESET} 卸载 Docker"
        _menu_actions 20 "${C_BOLD}[R]${C_RESET} 刷新状态"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            0) return ;;
            [Rr]) status_cache=""; continue ;;
            1) do_overview; [ "$DOCKER_GO_HOME" -eq 1 ] && return ;;
            2) do_stats; echo ""; kairo_pause ;;
            3) do_compose; [ "$DOCKER_GO_HOME" -eq 1 ] && return ;;
            4) do_cleanup; status_cache=""; echo ""; kairo_pause ;;
            [Xx]) do_reset; status_cache=""; kairo_pause ;;
            [Uu]) do_upgrade; status_cache=""; kairo_pause ;;
            [Dd]) do_uninstall; status_cache=""; kairo_pause ;;
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
        _container_ops_menu "$name"
        [ "$DOCKER_GO_HOME" -eq 1 ] && return
        echo ""; kairo_pause "按 Enter 返回容器列表..."
    done
}

# 容器操作子菜单（可被总览视图复用）
_container_ops_menu() {
    local name="$1" choice
    echo ""
    echo "  ${C_BOLD}${name}${C_RESET}"
    _menu_actions 18 "[1] 启动"
    _menu_actions 18 "[2] 停止"
    _menu_actions 18 "[3] 重启"
    _menu_actions 18 "[4] 查看日志"
    _menu_actions 18 "[5] 进入终端"
    _menu_actions 18 "[6] 删除容器"
    _menu_actions 18 "[0] 返回"
    _menu_actions 18 "[H] 返回主菜单"
    read -r -p "  选择操作: " choice
    case "$choice" in
        1) do_start "$name" ;;
        2) do_stop "$name" ;;
        3) do_restart "$name" ;;
        4) do_logs "$name" ;;
        5) do_exec "$name" ;;
        6) do_remove "$name" ;;
        [Hh]) DOCKER_GO_HOME=1; return ;;
        0) return ;;
        *) error "无效选项"; sleep 1 ;;
    esac
}
