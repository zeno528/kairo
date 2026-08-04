#!/bin/bash
# docker 模块 - Docker 管理

# 子菜单退出时置 1 表示需要一路返回主菜单（跨三级菜单的信号）
DOCKER_GO_HOME=0

# sudo 默认丢弃 http_proxy 等环境变量；WSL2 需保留本机代理才能访问 Docker 官方源
_docker_sudo_net() {
    local -a proxy=()
    [ -n "${http_proxy:-}" ] && proxy+=(http_proxy="$http_proxy")
    [ -n "${https_proxy:-}" ] && proxy+=(https_proxy="$https_proxy")
    [ -n "${HTTP_PROXY:-}" ] && proxy+=(HTTP_PROXY="$HTTP_PROXY")
    [ -n "${HTTPS_PROXY:-}" ] && proxy+=(HTTPS_PROXY="$HTTPS_PROXY")
    sudo env "${proxy[@]}" "$@"
}

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

_docker_image_display() {
    local image="$1" container="${2:-}" repository version
    [ "${image##*:}" = "latest" ] || { printf '%s\n' "$image"; return; }

    repository=${image%:latest}
    version=$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$image" 2>/dev/null)
    if [ -z "$version" ] || [ "$version" = "<no value>" ]; then
        case "$repository" in
            ghcr.io/nezhahq/nezha)
                [ -n "$container" ] && version=$(docker exec "$container" /dashboard/app -v 2>/dev/null | head -n 1)
                ;;
        esac
    fi
    case "$version" in
        ""|"<no value>") printf '%s\n' "$image" ;;
        *) printf '%s:%s\n' "$repository" "$version" ;;
    esac
}

_docker_duration_zh() {
    local duration="$1"
    duration=${duration/About an hour/约 1 小时}
    duration=${duration/Less than a second/少于 1 秒}
    duration=${duration/ seconds ago/ 秒前}
    duration=${duration/ minutes ago/ 分钟前}
    duration=${duration/ hours ago/ 小时前}
    duration=${duration/ days ago/ 天前}
    duration=${duration/ weeks ago/ 周前}
    duration=${duration/ months ago/ 个月前}
    duration=${duration/ years ago/ 年前}
    duration=${duration/ second ago/ 秒前}
    duration=${duration/ minute ago/ 分钟前}
    duration=${duration/ hour ago/ 小时前}
    duration=${duration/ day ago/ 天前}
    duration=${duration/ seconds/ 秒}
    duration=${duration/ minutes/ 分钟}
    duration=${duration/ hours/ 小时}
    duration=${duration/ days/ 天}
    duration=${duration/ weeks/ 周}
    duration=${duration/ months/ 个月}
    duration=${duration/ years/ 年}
    duration=${duration/ second/ 秒}
    duration=${duration/ minute/ 分钟}
    duration=${duration/ hour/ 小时}
    duration=${duration/ day/ 天}
    duration=${duration/ ago/前}
    printf '%s\n' "$duration"
}

_docker_status_display() {
    local status="$1" duration
    case "$status" in
        Up\ *)
            duration=${status#Up }
            duration=${duration%% \(*}
            printf '运行中 · 已运行 %s\n' "$(_docker_duration_zh "$duration")"
            ;;
        Exited\ *)
            duration=${status#*) }
            printf '已退出 · %s\n' "$(_docker_duration_zh "$duration")"
            ;;
        Created) printf '已创建\n' ;;
        Paused*) printf '已暂停\n' ;;
        Restarting*) printf '正在重启\n' ;;
        Dead*) printf '已停止\n' ;;
        *) printf '%s\n' "$status" ;;
    esac
}

_docker_print_ports() {
    local ports="$1" indent="${2:-     }" width first rest label
    label=$(_pad_right "端口" 8)
    width=$(tput cols 2>/dev/null || echo 80)
    if [ "$width" -ge $(( ${#ports} + 18 )) ] || [[ "$ports" != *,* ]]; then
        printf '%s%s %s\n' "$indent" "$label" "$ports"
        return
    fi
    IFS=',' read -r first rest <<< "$ports"
    printf '%s%s %s\n' "$indent" "$label" "$first"
    printf '%*s%s\n' "$(( $(_str_width "$indent") + 9 ))" '' "${rest# }"
}

_docker_container_running() {
    [ "$(docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

_docker_apt_source() (
    # shellcheck disable=SC1090,SC1091 # 运行时由系统提供。
    . "${DOCKER_OS_RELEASE:-/etc/os-release}" || exit 1
    case "$ID" in
        ubuntu) printf 'ubuntu\t%s\n' "${UBUNTU_CODENAME:-$VERSION_CODENAME}" ;;
        debian) printf 'debian\t%s\n' "$VERSION_CODENAME" ;;
        *) exit 1 ;;
    esac
)

# 添加当前用户到 docker 组，免 sudo
_docker_join_group() {
    if id -nG "$USER" 2>/dev/null | grep -qw docker; then
        return 0
    fi
    if getent group docker &>/dev/null; then
        sudo usermod -aG docker "$USER"
        info "已将 $USER 加入 docker 组"
    fi
}

do_install() {
    local source_distro source_codename
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
    if ! IFS=$'\t' read -r source_distro source_codename < <(_docker_apt_source); then
        error "仅支持 Debian/Ubuntu"
        return 1
    fi

    info "使用 Docker 官方 apt 源安装"
    _start_spinner "正在添加 Docker GPG key 和 apt 源"

    # 移除旧版源文件（防止冲突）
    sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources 2>/dev/null

    if ! (
        _docker_sudo_net apt-get update -qq &&
        _docker_sudo_net apt-get install -y -qq ca-certificates curl &&
        sudo install -m 0755 -d /etc/apt/keyrings &&
        _docker_sudo_net curl -fsSL "https://download.docker.com/linux/${source_distro}/gpg" -o /etc/apt/keyrings/docker.asc &&
        sudo chmod a+r /etc/apt/keyrings/docker.asc &&
        sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF &&
Types: deb
URIs: https://download.docker.com/linux/${source_distro}
Suites: ${source_codename}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
        _docker_sudo_net apt-get update -qq
    ); then
        _stop_spinner
        error "Docker 官方 apt 源配置失败"
        return 1
    fi
    _stop_spinner

    info "正在安装 Docker Engine + Compose"
    if _docker_sudo_net apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        if [ -d /run/systemd/system ]; then
            if ! sudo systemctl enable --now docker; then
                error "Docker 已安装，但服务启动失败"
                return 1
            fi
        elif ! sudo service docker start; then
            error "Docker 已安装，但当前环境未启用 systemd 且无法启动服务；WSL2 请启用 systemd 或使用 Docker Desktop 集成"
            return 1
        fi
        if ! sudo docker info > /dev/null 2>&1; then
            error "Docker 已安装，但 daemon 未就绪"
            return 1
        fi
        _docker_join_group
        if ! id -nG | grep -qw docker; then
            warn "当前终端 docker 组权限尚未生效，请重新登录或执行 newgrp docker"
        fi
        success "Docker 安装完成"
        docker --version 2>/dev/null
        docker compose version 2>/dev/null
    else
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
    _docker_sudo_net apt-get update -qq
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

    info "正在升级 Docker"
    if _docker_sudo_net apt-get install -y --only-upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        success "Docker 升级完成"
        docker --version 2>/dev/null
    else
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

# 扫描常见目录，发现含 compose 文件的项目
_compose_find_projects() {
    local base
    for base in /opt "$HOME" .; do
        [ -d "$base" ] || continue
        find "$base" -maxdepth 2 \
            \( -name "docker-compose.yml" -o -name "compose.yaml" \) \
            2>/dev/null | while IFS= read -r f; do dirname "$f"; done
    done | sort -u | head -20
}

do_compose() {
    _check_docker || return
    command -v docker compose &>/dev/null || { error "未安装 docker compose 插件"; return 1; }
    local compose_dir compose_file current_img choice
    local -a projects=()
    echo ""

    mapfile -t projects < <(_compose_find_projects)
    if [ "${#projects[@]}" -gt 0 ]; then
        echo -e "  ${C_BOLD}发现的 Compose 项目${C_RESET}"
        local i=1
        for compose_dir in "${projects[@]}"; do
            printf '  [%d] %s\n' "$i" "$compose_dir"
            ((i++))
        done
        echo ""
        _menu_actions 24 "${C_BOLD}$(kairo_menu_range "${#projects[@]}" "选择项目")${C_RESET}"
        _menu_actions 24 "${C_BOLD}[M]${C_RESET} 手动输入目录"
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回上级"
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            0) return 0 ;;
            [Mm]) read -r -p "  输入 compose 项目目录: " compose_dir ;;
            *)
                if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#projects[@]}" ]; then
                    compose_dir="${projects[$((choice - 1))]}"
                else
                    error "无效选项"; return 1
                fi
                ;;
        esac
    else
        read -r -p "  输入 compose 项目目录（默认当前目录）: " compose_dir
        compose_dir="${compose_dir:-.}"
    fi

    [ -n "$compose_dir" ] || { info "已取消"; return 0; }
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
        _menu_actions 24 "${C_BOLD}[00]${C_RESET} 返回主菜单"
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
            00) DOCKER_GO_HOME=1; break ;;
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
    local choice imgs=() img_ids=() img_displays=() img_sizes=() img_created=() img_id repo_tag repo_tag_display size created i container image_id name_width index_width display_width status_cell
    local -A USED_IMAGES IMAGE_CONTAINER
    while true; do
        # 收集正在被容器使用的镜像
        USED_IMAGES=()
        IMAGE_CONTAINER=()
        while IFS= read -r container; do
            [ -n "$container" ] || continue
            image_id=$(docker inspect --format '{{.Image}}' "$container" 2>/dev/null) || continue
            USED_IMAGES["$image_id"]=1
            IMAGE_CONTAINER["$image_id"]="$container"
        done < <(docker ps --format '{{.Names}}' 2>/dev/null)

        imgs=()
        img_ids=()
        img_displays=()
        img_sizes=()
        img_created=()
        name_width=24
        while IFS=$'\t' read -r repo_tag image_id size created; do
            imgs+=("$repo_tag")
            img_ids+=("$image_id")
            created="${created#"${created%%[![:space:]]*}"}"
            repo_tag_display=$(_docker_image_display "$repo_tag" "${IMAGE_CONTAINER[$image_id]:-}")
            img_displays+=("$repo_tag_display")
            img_sizes+=("$size")
            img_created+=("$created")
            display_width=$(_str_width "$repo_tag_display")
            [ "$display_width" -gt "$name_width" ] && name_width="$display_width"
        done < <(docker images --no-trunc --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}' 2>/dev/null)

        if [ "${#imgs[@]}" -eq 0 ]; then
            info "当前没有镜像"
            kairo_pause
            return
        fi

        name_width=$((name_width + 2))
        index_width=$(_str_width "[${#imgs[@]}]")
        [ "$index_width" -lt 4 ] && index_width=4
        echo ""
        echo -e "  ${C_BOLD}镜像列表${C_RESET}"
        printf '  %s  %s  %s  %s  %s\n' \
            "$(_pad_right "${C_BOLD}状态${C_RESET}" 4)" \
            "$(_pad_right "${C_BOLD}编号${C_RESET}" "$index_width")" \
            "$(_pad_right "${C_BOLD}镜像名称${C_RESET}" "$name_width")" \
            "$(_pad_right "${C_BOLD}大小${C_RESET}" 8)" \
            "${C_BOLD}创建时间${C_RESET}"
        for i in "${!imgs[@]}"; do
            repo_tag="${imgs[$i]}"
            repo_tag_display="${img_displays[$i]}"
            size="${img_sizes[$i]}"
            created="${img_created[$i]}"
            if [ -n "${USED_IMAGES[${img_ids[$i]}]:-}" ]; then
                status_cell=$(_pad_right " ${C_GREEN}●${C_RESET}" 4)
            else
                status_cell="    "
            fi
            printf '  %s  %s  %s  %s  %s\n' \
                "$status_cell" \
                "$(_pad_right "[$((i + 1))]" "$index_width")" \
                "$(_pad_right "$repo_tag_display" "$name_width")" \
                "$(_pad_right "$size" 8)" \
                "$created"
        done
        echo ""
        echo -e "  ${C_GREEN}●${C_RESET} = 运行中"
        divider
        _menu_actions 20 "${C_BOLD}$(kairo_menu_range "${#imgs[@]}" "删除镜像")${C_RESET}"
        _menu_actions 20 "${C_BOLD}[p]${C_RESET} 清理未使用的镜像"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回上级"
        _menu_actions 20 "${C_BOLD}[00]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            00) DOCKER_GO_HOME=1; return ;;
            0) return ;;
            [Pp])
                if docker image prune -a -f 2>&1; then
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

# 删除所有容器、镜像、卷和网络（reset 和 uninstall 共用）
# 结果写入 DOCKER_WIPE_SUMMARY 供调用方输出
_docker_wipe_all() {
    local running_containers total_containers total_images total_volumes
    running_containers=$(docker ps -q 2>/dev/null | wc -l)
    total_containers=$(docker ps -aq 2>/dev/null | wc -l)
    total_images=$(docker images -q 2>/dev/null | wc -l)
    total_volumes=$(docker volume ls -q 2>/dev/null | wc -l)

    if [ "$running_containers" -gt 0 ]; then
        _start_spinner "正在停止 $running_containers 个运行中的容器"
        docker ps -q | xargs -r docker stop 2>/dev/null || true
        _stop_spinner
    fi

    if [ "$total_containers" -gt 0 ]; then
        _start_spinner "正在删除 $total_containers 个容器"
        docker ps -aq | xargs -r docker rm -f 2>/dev/null || true
        _stop_spinner
    fi

    if [ "$total_images" -gt 0 ]; then
        _start_spinner "正在删除 $total_images 个镜像"
        docker images -q | xargs -r docker rmi -f 2>/dev/null || true
        _stop_spinner
    fi

    if [ "$total_volumes" -gt 0 ]; then
        _start_spinner "正在删除 $total_volumes 个卷"
        docker volume ls -q | xargs -r docker volume rm 2>/dev/null || true
        _stop_spinner
    fi

    _start_spinner "正在清理网络和构建缓存"
    docker system prune -a -f --volumes 2>/dev/null || true
    _stop_spinner

    DOCKER_WIPE_SUMMARY="已清理: $total_containers 个容器, $total_images 个镜像, $total_volumes 个卷"
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

    _docker_wipe_all

    # 停止并禁用 Docker 服务
    _start_spinner "正在停止 Docker 服务"
    sudo systemctl stop docker docker.socket 2>/dev/null || true
    sudo systemctl disable docker docker.socket 2>/dev/null || true
    _stop_spinner

    # apt purge 卸载所有 Docker 包
    info "正在卸载 Docker 软件包"
    _docker_sudo_net apt-get purge -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin \
        docker-ce-rootless-extras || true
    _docker_sudo_net apt-get autoremove -y --purge || true

    # 清理 Docker 数据目录
    _start_spinner "正在清理 Docker 数据目录"
    sudo rm -rf /var/lib/docker /var/lib/containerd 2>/dev/null || true
    _stop_spinner

    # 清理 Docker apt 源和 GPG key
    _start_spinner "正在清理 Docker apt 源"
    sudo rm -f /etc/apt/sources.list.d/docker.list \
        /etc/apt/sources.list.d/docker.sources 2>/dev/null || true
    sudo rm -f /etc/apt/keyrings/docker.asc 2>/dev/null || true
    _docker_sudo_net apt-get update -qq 2>/dev/null || true
    _stop_spinner

    echo ""
    success "Docker 已完全卸载"
    info "$DOCKER_WIPE_SUMMARY"
    hash -r
}

do_reset() {
    echo ""
    warn "此操作将删除所有 Docker 容器、镜像、卷和网络，但保留 Docker Engine 本身"
    echo ""
    read -r -p "  确认重置? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }

    _docker_wipe_all

    echo ""
    success "Docker 环境已重置"
    info "$DOCKER_WIPE_SUMMARY"
}

do_overview() {
    _check_docker || return
    local choice i
    local -A CT_META      # container_name → "status|image|idx"
    local -A IMG_SIZE IMG_ID IMG_USED IMG_HAS_CT
    local CONTAINER_LIST=() IMAGE_LIST=() ORPHAN_CONTAINERS=()
    local -A img_seen

    while true; do
        clear
        title "🐳 Docker 资源总览"

        # 刷新数据
        CT_META=()
        IMG_SIZE=()
        IMG_ID=()
        IMG_USED=()
        IMG_HAS_CT=()
        img_seen=()
        CONTAINER_LIST=()
        IMAGE_LIST=()
        ORPHAN_CONTAINERS=()
        i=1

        while IFS=$'\t' read -r c_name c_status c_ports; do
            [ -z "$c_name" ] && continue
            c_img=$(docker inspect --format '{{.Image}}' "$c_name" 2>/dev/null) || continue
            CONTAINER_LIST+=("$c_name")
            CT_META["$c_name"]="${c_status}|${c_img}|${i}|${c_ports}"
            ((i++))
        done < <(docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null)

        # 镜像 ID 是容器和标签之间唯一可靠的关联键。
        while IFS=$'\t' read -r img_tag img_id img_size; do
            IMG_SIZE["$img_tag"]="$img_size"
            IMG_ID["$img_tag"]="$img_id"
        done < <(docker images --no-trunc --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' 2>/dev/null)

        for c_name in "${CONTAINER_LIST[@]}"; do
            IFS='|' read -r c_status c_img _ _ <<< "${CT_META[$c_name]}"
            local matched=0
            for img_tag in "${!IMG_ID[@]}"; do
                [ "${IMG_ID[$img_tag]}" = "$c_img" ] || continue
                IMG_HAS_CT["$img_tag"]=1
                [[ "$c_status" =~ ^Up ]] && IMG_USED["$img_tag"]=1
                matched=1
            done
            [ "$matched" -eq 1 ] || ORPHAN_CONTAINERS+=("$c_name")
        done

        for img_tag in "${!IMG_SIZE[@]}"; do
            if [ -n "${IMG_HAS_CT[$img_tag]:-}" ]; then
                IMAGE_LIST+=("$img_tag")
                img_seen["$img_tag"]=1
            fi
        done
        for img_tag in "${!IMG_SIZE[@]}"; do
            [ -z "${img_seen[$img_tag]:-}" ] && IMAGE_LIST+=("$img_tag")
        done

        local img_tag img_size img_display img_container c_mark i_mark c_status c_img c_idx c_ports label

        if [ "${#IMAGE_LIST[@]}" -eq 0 ]; then
            echo -e "  ${C_DIM}(无镜像)${C_RESET}"
        fi

        for img_tag in "${IMAGE_LIST[@]}"; do
            img_size="${IMG_SIZE[$img_tag]:-}"
            img_container=""
            for c_name in "${CONTAINER_LIST[@]}"; do
                IFS='|' read -r _ c_img _ _ <<< "${CT_META[$c_name]}"
                [ "$c_img" = "${IMG_ID[$img_tag]}" ] && { img_container="$c_name"; break; }
            done
            img_display=$(_docker_image_display "$img_tag" "$img_container")
            if [ -n "${IMG_USED[$img_tag]:-}" ]; then
                i_mark="${C_GREEN}●${C_RESET} "
            else
                i_mark="  "
            fi
            label=$(_pad_right "${C_BOLD}镜像${C_RESET}" 8)
            printf "    📦 %s%s%s ${C_DIM}(%s)${C_RESET}\n" "$label" "$i_mark" "$img_display" "$img_size"

            # 显示该镜像下的容器
            for c_name in "${CONTAINER_LIST[@]}"; do
                [ "${CT_META[$c_name]}" = "" ] && continue
                IFS='|' read -r c_status c_img c_idx c_ports <<< "${CT_META[$c_name]}"
                [ "$c_img" != "${IMG_ID[$img_tag]}" ] && continue
                if [[ "$c_status" =~ ^Up ]]; then
                    c_mark="${C_GREEN}●${C_RESET}"
                else
                    c_mark="${C_GRAY}○${C_RESET}"
                fi
                label=$(_pad_right "${C_BOLD}容器${c_idx}${C_RESET}" 8)
                printf '         %s %s %s\n' "$label" "$c_mark" "$c_name"
                label=$(_pad_right "状态" 8)
                printf '         %s %s\n' "$label" "$(_docker_status_display "$c_status")"
                [ -n "$c_ports" ] && _docker_print_ports "$c_ports" '         '
            done
            echo ""
        done

        if [ "${#ORPHAN_CONTAINERS[@]}" -gt 0 ]; then
            echo -e "  ${C_YELLOW}⚠ 未关联镜像（原镜像标签已删除或已更新）${C_RESET}"
            for c_name in "${ORPHAN_CONTAINERS[@]}"; do
                IFS='|' read -r c_status _ c_idx c_ports <<< "${CT_META[$c_name]}"
                if [[ "$c_status" =~ ^Up ]]; then c_mark="${C_GREEN}●${C_RESET}"; else c_mark="${C_GRAY}○${C_RESET}"; fi
                label=$(_pad_right "${C_BOLD}容器${c_idx}${C_RESET}" 8)
                printf '         %s %s %s\n' "$label" "$c_mark" "$c_name"
                label=$(_pad_right "状态" 8)
                printf '         %s %s\n' "$label" "$(_docker_status_display "$c_status")"
                [ -n "$c_ports" ] && _docker_print_ports "$c_ports" '         '
            done
            echo ""
        fi

        divider
        _menu_actions 24 "${C_BOLD}$(kairo_menu_range "${#CONTAINER_LIST[@]}" "管理容器")${C_RESET}"
        _menu_actions 24 "${C_BOLD}[I]${C_RESET} 镜像管理"
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回"
        divider
        echo ""
        read -r -p "  请选择: " choice

        case "$choice" in
            0) return ;;
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
        _menu_actions 24 "${C_BOLD}[1]${C_RESET} 资源总览" "${C_BOLD}[4]${C_RESET} 资源监控"
        _menu_actions 24 "${C_BOLD}[2]${C_RESET} Compose 项目" "${C_BOLD}[R]${C_RESET} 刷新状态"
        _menu_actions 24 "${C_BOLD}[3]${C_RESET} 系统清理" "${C_BOLD}[X]${C_RESET} 重置环境"
        divider
        _menu_actions 19 "${C_BOLD}[U]${C_RESET} 检查升级" "${C_BOLD}[D]${C_RESET} 卸载 Docker" "${C_BOLD}[0]${C_RESET} 返回主菜单"
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            0) return ;;
            1) do_overview; [ "$DOCKER_GO_HOME" -eq 1 ] && return ;;
            2) do_compose; [ "$DOCKER_GO_HOME" -eq 1 ] && return ;;
            3) do_cleanup; status_cache=""; echo ""; kairo_pause ;;
            4) do_stats; echo ""; kairo_pause ;;
            [Uu]) do_upgrade; status_cache=""; kairo_pause ;;
            [Rr]) status_cache=""; continue ;;
            [Xx]) do_reset; status_cache=""; kairo_pause ;;
            [Dd]) do_uninstall; status_cache=""; kairo_pause ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}

# 缓存版状态渲染：收集输出为字符串，避免每次循环都查 docker info
_render_status_cache() {
    echo ""
    local docker_ver compose_ver compose_line=""
    docker_ver=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
    if docker compose version &>/dev/null; then
        compose_ver=$(docker compose version 2>/dev/null | sed 's/.*version v\?//; s/[ ,].*//')
        compose_line="${C_DIM}Compose ${compose_ver}${C_RESET}"
    fi

    local ps_err
    ps_err=$(docker ps 2>&1) || {
        if [[ "$ps_err" == *"permission denied"* ]]; then
            echo -e "  ${C_YELLOW}⚠ 当前用户无 Docker 权限；刚安装请重新登录（或 newgrp docker）${C_RESET}"
        else
            echo -e "  ${C_YELLOW}⚠ Docker 服务未运行${C_RESET}"
        fi
        return
    }
    local containers images
    containers=$(docker ps -aq 2>/dev/null | wc -l)
    images=$(docker images -q 2>/dev/null | wc -l)

    printf '  %s %s\n' \
        "$(_pad_right "容器 ${C_CYAN}${containers}${C_RESET}" 18)" \
        "镜像 ${C_CYAN}${images}${C_RESET}"
    printf '  %s %s\n' \
        "$(_pad_right "${C_DIM}Docker ${docker_ver}${C_RESET}" 18)" \
        "${compose_line}"
    echo ""
}

# 容器操作子菜单（可被总览视图复用）
_container_ops_menu() {
    local name="$1" choice action
    while true; do
        echo ""
        echo "  ${C_BOLD}${name}${C_RESET}"
        if _docker_container_running "$name"; then
            _menu_actions 18 "${C_RED}[1] 停止${C_RESET}"
            action=do_stop
        else
            _menu_actions 18 "${C_GREEN}[1] 启动${C_RESET}"
            action=do_start
        fi
        _menu_actions 18 "[2] 重启"
        _menu_actions 18 "[3] 查看日志"
        _menu_actions 18 "[4] 进入终端"
        _menu_actions 18 "[5] 删除容器"
        _menu_actions 18 "[0] 返回"
        _menu_actions 18 "[00] 返回主菜单"
        read -r -p "  选择操作: " choice
        case "$choice" in
            1) "$action" "$name"; kairo_pause ;;
            2) do_restart "$name"; kairo_pause ;;
            3) do_logs "$name"; kairo_pause ;;
            4) do_exec "$name" ;;
            5) do_remove "$name"; return ;;
            00) DOCKER_GO_HOME=1; return ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
