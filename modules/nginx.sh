#!/bin/bash
# nginx 模块 - Nginx 反向代理管理（Debian/Ubuntu）
# 安装源: nginx 官方 apt 源（https://nginx.org/en/linux_packages.html）
# 证书: certbot + Let's Encrypt

NGINX_SITES_AVAIL="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF_D="/etc/nginx/conf.d"
LE_LIVE_DIR="/etc/letsencrypt/live"
# Nginx 发布日期本地缓存：安装/升级/检查官方更新时写入，状态总览离线读取。
NGINX_RELEASE_CACHE="/var/cache/kairo/nginx-release.info"
# 以下路径用 ${VAR:-default} 形式，便于测试环境覆盖。
NGINX_CONF_FILE="${NGINX_CONF_FILE:-/etc/nginx/nginx.conf}"
NGINX_LOG_DIR="${NGINX_LOG_DIR:-/var/log/nginx}"
NGINX_SNAPSHOT_DIR="${NGINX_SNAPSHOT_DIR:-/var/cache/kairo/nginx-snapshots}"
NGINX_SNAPSHOT_KEEP="${NGINX_SNAPSHOT_KEEP:-5}"
NGINX_ETC_DIR="${NGINX_ETC_DIR:-/etc/nginx}"

# ─── 前置检查 ────────────────────────────────────────────────

_check_nginx() {
    if ! command -v nginx &>/dev/null; then
        error "未安装 Nginx，请先执行 [1] 安装"
        return 1
    fi
}

# ─── 安装 / 升级 ─────────────────────────────────────────────

# 返回已安装的 Debian 包版本；未安装时返回空。
_get_nginx_installed_version() {
    dpkg-query -W -f='${Version}' nginx 2>/dev/null || true
}

# 返回当前 apt 候选版本。
_get_nginx_candidate_version() {
    apt-cache policy nginx 2>/dev/null | awk '/Candidate:/{print $2; exit}'
}

_get_nginx_release_date() {
    command -v curl &>/dev/null || return
    local last_modified
    last_modified=$(curl --connect-timeout 3 --max-time 5 -fsSI \
        "https://nginx.org/download/nginx-${1}.tar.gz" 2>/dev/null | \
        awk -F': ' 'tolower($1) == "last-modified" { print $2; exit }')
    [ -n "$last_modified" ] && date -d "$last_modified" '+%F' 2>/dev/null
}

# 读取本地缓存的发布日期；无匹配返回空。供 do_status 离线显示，不联网。
_nginx_cached_release_date() {
    [ -f "$NGINX_RELEASE_CACHE" ] || return
    awk -v v="$1" '$1 == v { print $2; exit }' "$NGINX_RELEASE_CACHE" 2>/dev/null
}

# 把 ver→date 写入本地缓存（覆盖同版本旧记录）。调用方需具备 sudo 权限。
_nginx_store_release_date() {
    local ver="$1" date="$2" cache_dir tmp_file
    [ -n "$ver" ] && [ -n "$date" ] || return
    cache_dir=$(dirname "$NGINX_RELEASE_CACHE")
    sudo mkdir -p "$cache_dir" || return 1
    tmp_file=$(mktemp) || return 1
    if [ -f "$NGINX_RELEASE_CACHE" ]; then
        awk -v v="$ver" '$1 != v' "$NGINX_RELEASE_CACHE" > "$tmp_file" || {
            rm -f -- "$tmp_file"
            return 1
        }
    fi
    printf '%s %s\n' "$ver" "$date" >> "$tmp_file"
    sudo install -m 0644 "$tmp_file" "$NGINX_RELEASE_CACHE"
    local rc=$?
    rm -f -- "$tmp_file"
    return "$rc"
}

# 使用 Debian 版本规则比较，避免 nginx -v 与 apt 包版本格式不同造成误判。
_nginx_version_is_at_least() {
    dpkg --compare-versions "$1" ge "$2"
}

# 按 nginx.org 官方文档配置 stable apt 源，并刷新 apt 索引。
_configure_nginx_official_repo() {
    local distro="$1"
    local codename="$2"
    local keyring_package

    case "$distro" in
        ubuntu) keyring_package="ubuntu-keyring" ;;
        debian) keyring_package="debian-archive-keyring" ;;
        *)
            error "不支持的发行版: ${distro}"
            return 1
            ;;
    esac

    info "配置 nginx 官方 apt 源..."

    if ! sudo apt-get install -y curl gnupg2 ca-certificates lsb-release "$keyring_package"; then
        error "安装 nginx 官方源依赖失败"
        return 1
    fi

    if [ ! -f /usr/share/keyrings/nginx-archive-keyring.gpg ]; then
        _start_spinner "正在下载 nginx 官方签名 key"
        if ! curl -fsSL "https://nginx.org/keys/nginx_signing.key?t=$(date +%s)" | \
            gpg --dearmor | \
            sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null; then
            _stop_spinner
            error "导入 nginx 官方签名 key 失败"
            return 1
        fi
        _stop_spinner
        success "已导入 nginx 官方签名 key"
    fi

    if [ ! -f /etc/apt/sources.list.d/nginx.list ]; then
        printf '%s\n' "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/${distro} ${codename} nginx" | \
            sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null || return 1
        success "已添加 nginx 官方源（stable / ${codename}）"
    fi

    printf '%s\n' "Package: *" "Pin: origin nginx.org" "Pin-Priority: 900" | \
        sudo tee /etc/apt/preferences.d/99nginx >/dev/null || return 1

    info "首次刷新软件源可能需要 1–2 分钟，请勿中断..."
    if ! sudo apt-get update; then
        error "刷新 apt 索引失败，无法获取 nginx 官方版本"
        return 1
    fi
}

# 检测发行版，结果写入 NGINX_DISTRO / NGINX_CODENAME；仅支持 Ubuntu/Debian。
_detect_distro() {
    NGINX_DISTRO="" NGINX_CODENAME=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        NGINX_DISTRO="$ID"
        NGINX_CODENAME="$VERSION_CODENAME"
    fi
    case "$NGINX_DISTRO" in
        ubuntu|debian) return 0 ;;
        *)
            error "当前系统 ${NGINX_DISTRO:-未知} 不在支持列表（仅 Ubuntu/Debian）"
            return 1
            ;;
    esac
}

# 刷新 nginx 官方 apt 源并打印本地/上游版本对比。
# 有可用更新时返回 0，并把候选版本写入 NGINX_CANDIDATE_VER；
# 未安装 / 获取失败 / 已是最新时返回非零。
_nginx_refresh_upstream() {
    local distro="$1" codename="$2"
    local local_ver candidate_ver upstream_ver release_date

    local_ver=$(_get_nginx_installed_version)
    [ -n "$local_ver" ] || { error "未检测到已安装的 Nginx"; return 1; }

    _configure_nginx_official_repo "$distro" "$codename" || return 1
    candidate_ver=$(_get_nginx_candidate_version)
    if [ -z "$candidate_ver" ] || [ "$candidate_ver" = "(none)" ]; then
        error "未能获取 nginx 官方候选版本"
        return 1
    fi

    upstream_ver="${local_ver%%-*}"
    release_date=$(_get_nginx_release_date "$upstream_ver")
    [ -n "$release_date" ] && _nginx_store_release_date "$upstream_ver" "$release_date"

    echo ""
    info "当前版本:     v${local_ver}${release_date:+ （${release_date} 发布）}"
    info "官方候选版本: v${candidate_ver}"
    if _nginx_version_is_at_least "$local_ver" "$candidate_ver"; then
        success "当前 Nginx 已是官方最新版本或更高"
        return 1
    fi
    warn "检测到可更新版本"
    NGINX_CANDIDATE_VER="$candidate_ver"
    return 0
}

do_install() {
    if ! sudo -n true &>/dev/null; then
        error "此操作需要 sudo 权限"
        return
    fi

    echo ""

    # 检测发行版（只支持 Ubuntu/Debian）
    _detect_distro || return
    local distro="$NGINX_DISTRO" codename="$NGINX_CODENAME"

    local local_ver candidate_ver repo_configured=0
    local_ver=$(_get_nginx_installed_version)

    # 情况 1: 未安装 → 先确认，再添加官方源并安装。
    if [ -z "$local_ver" ]; then
        info "未检测到 Nginx，将从 nginx 官方源（stable / ${codename}）安装"
        echo ""
        read -p "  确认安装? [Y/n]: " confirm
        if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
            info "已取消"
            return
        fi
    else
        # 已安装时刷新官方候选版本，判断是否需要升级。
        repo_configured=1
        if ! _nginx_refresh_upstream "$distro" "$codename"; then
            return
        fi
        candidate_ver="$NGINX_CANDIDATE_VER"
        echo ""
        read -p "  是否升级到 v${candidate_ver}? [Y/n]: " confirm
        if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
            info "已取消"
            return
        fi
    fi

    # 首次安装在确认后配置官方源；升级路径已刷新过，无需重复 apt-get update。
    if [ "$repo_configured" -eq 0 ]; then
        _configure_nginx_official_repo "$distro" "$codename" || return
        candidate_ver=$(_get_nginx_candidate_version)
    fi
    if [ -z "$candidate_ver" ] || [ "$candidate_ver" = "(none)" ]; then
        error "未能获取 nginx 官方候选版本"
        return
    fi

    info "检测到已有 Nginx 配置时将保留现有文件，不覆盖站点配置"
    if sudo env DEBIAN_FRONTEND=noninteractive \
        apt-get -o Dpkg::Options::=--force-confold install -y nginx; then
        sudo systemctl enable --now nginx &>/dev/null
        local new_ver
        new_ver=$(nginx -v 2>&1 | sed 's|.*nginx/||')
        # 缓存新版本发布日期，供状态总览离线显示
        _start_spinner "正在记录版本发布日期"
        local new_date
        new_date=$(_get_nginx_release_date "$new_ver")
        _stop_spinner
        [ -n "$new_date" ] && _nginx_store_release_date "$new_ver" "$new_date"
        success "Nginx 安装/升级完成，当前版本 v${new_ver}"
        info "服务已启用并启动，监听 80 端口"
    else
        error "apt 安装失败，请检查 apt 日志"
        return
    fi
}

# ─── 卸载 ────────────────────────────────────────────────────

do_uninstall() {
    if ! sudo -n true &>/dev/null; then
        error "此操作需要 sudo 权限"
        return
    fi
    _check_nginx || return
    echo ""
    warn "即将卸载 Nginx:"
    echo -e "  ${C_GRAY}apt-get purge nginx nginx-common${C_RESET}"
    echo -e "  ${C_GRAY}配置 / 站点 conf / 日志 不会被自动删除${C_RESET}"
    echo ""
    read -p "  确认卸载? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
    sudo systemctl stop nginx 2>/dev/null
    if sudo apt-get purge -y nginx nginx-common; then
        success "已卸载 Nginx"
    else
        error "卸载 Nginx 失败"
        return 1
    fi
    info "如需彻底清理: rm -rf /etc/nginx /var/log/nginx /var/lib/nginx"
}

# ─── 状态 ────────────────────────────────────────────────────

do_status() {
    kairo_require_systemctl || return

    # 版本 + 本地缓存的发布日期（零联网；缓存由安装/升级/检查官方更新时写入）
    local ver release_date
    if command -v nginx &>/dev/null; then
        ver=$(nginx -v 2>&1 | sed 's|.*nginx/||')
        release_date=$(_nginx_cached_release_date "$ver")
    else
        ver="未安装"
    fi

    # 服务状态
    local svc_state
    svc_state=$(systemctl is-active nginx 2>/dev/null)
    svc_state=${svc_state:-未运行}
    local en_state
    en_state=$(systemctl is-enabled nginx 2>/dev/null)
    en_state=${en_state:-未启用}

    # 监听端口
    local listen
    listen=$(ss -tlnp 2>/dev/null | awk '
        $4 ~ /:(80|443)$/ {
            addresses = addresses (addresses ? ", " : "") $4
        }
        END { print addresses }
    ')

    # 站点统计
    local site_count conf_count cert_count
    [ -d "$NGINX_SITES_ENABLED" ] && site_count=$(find "$NGINX_SITES_ENABLED" -maxdepth 1 -type l 2>/dev/null | wc -l)
    [ -d "$NGINX_CONF_D" ] && conf_count=$(find "$NGINX_CONF_D" -maxdepth 1 -name "*.conf" 2>/dev/null | wc -l)
    [ -d "$LE_LIVE_DIR" ] && cert_count=$(find "$LE_LIVE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

    echo ""
    echo -e "  ${C_BOLD}Nginx 状态${C_RESET}"
    if [ "$ver" = "未安装" ]; then
        echo -e "  版本:     ${C_YELLOW}${ver}${C_RESET}"
    else
        echo -e "  版本:     ${C_CYAN}v${ver}${C_RESET}${release_date:+ （${release_date} 发布）}"
    fi
    if [ "$svc_state" = "active" ]; then
        echo -e "  服务:     ${C_GREEN}${svc_state}${C_RESET} （${en_state} 开机自启）"
    else
        echo -e "  服务:     ${C_RED}${svc_state}${C_RESET}"
    fi
    echo -e "  监听:     ${listen:-(无 80/443)}"
    echo -e "  反代站点: ${site_count:-0} 个（sites-enabled）"
    echo -e "  conf.d:   ${conf_count:-0} 个"
    echo -e "  证书:     ${cert_count:-0} 个（letsencrypt/live）"
}

# ─── 启停 / 重载 / 测试 ──────────────────────────────────────

do_start() {
    _check_nginx || return
    kairo_require_systemctl || return
    if _with_spinner "正在启动 Nginx" sudo systemctl start nginx; then
        success "已启动"
    else
        error "启动失败"
        return 1
    fi
}

do_stop() {
    _check_nginx || return
    kairo_require_systemctl || return
    if _with_spinner "正在停止 Nginx" sudo systemctl stop nginx; then
        success "已停止"
    else
        error "停止失败"
        return 1
    fi
}

do_restart() {
    _check_nginx || return
    kairo_require_systemctl || return
    if _with_spinner "正在重启 Nginx" sudo systemctl restart nginx; then
        success "已重启"
    else
        error "重启失败"
        return 1
    fi
}

do_reload() {
    _check_nginx || return
    kairo_require_systemctl || return
    echo ""
    if sudo nginx -t 2>&1 | sed 's/^/  /' && sudo systemctl reload nginx 2>/dev/null; then
        success "配置语法 OK，已重载"
    else
        error "重载失败，请检查 nginx -t 输出"
        return 1
    fi
}

do_test_conf() {
    _check_nginx || return
    echo ""
    local output rc
    output=$(sudo nginx -t 2>&1)
    rc=$?
    echo "$output" | sed 's/^/  /'
    if [ "$rc" -eq 0 ]; then
        success "配置语法正确"
    else
        error "配置语法检查失败"
        return 1
    fi
}

do_toggle_enable() {
    kairo_require_systemctl || return
    local is_enabled
    is_enabled=$(systemctl is-enabled nginx 2>/dev/null)
    if [ "$is_enabled" = "enabled" ]; then
        read -p "  关闭开机自启? [y/N]: " confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return
        if sudo systemctl disable nginx 2>/dev/null; then
            success "已关闭"
        else
            error "关闭开机自启失败"
            return 1
        fi
    else
        read -p "  开启开机自启? [Y/n]: " confirm
        [ "$confirm" = "n" ] || [ "$confirm" = "N" ] && info "已取消" && return
        if sudo systemctl enable nginx 2>/dev/null; then
            success "已开启"
        else
            error "开启开机自启失败"
            return 1
        fi
    fi
}

# ─── 站点管理 ────────────────────────────────────────────────

# 检查 domain 是否已有 LE 证书
_has_cert() {
    [ -f "${LE_LIVE_DIR}/$1/fullchain.pem" ]
}

do_list_sites() {
    _check_nginx || return
    echo ""
    echo -e "  ${C_BOLD}sites-enabled (完整站点)${C_RESET}"
    if [ -d "$NGINX_SITES_ENABLED" ] && [ -n "$(ls "$NGINX_SITES_ENABLED" 2>/dev/null)" ]; then
        local link
        for link in "$NGINX_SITES_ENABLED"/*; do
            [ -L "$link" ] || continue
            local target
            target=$(readlink "$link")
            local name
            name=$(basename "$link")
            if _has_cert "$name"; then
                echo -e "  ${C_GREEN}●${C_RESET} ${name} ${C_DIM}→ ${target}${C_RESET}"
            else
                echo -e "  ${C_YELLOW}○${C_RESET} ${name} ${C_DIM}→ ${target} (无证书)${C_RESET}"
            fi
        done
    else
        echo -e "  ${C_DIM}(空)${C_RESET}"
    fi

    echo ""
    echo -e "  ${C_BOLD}conf.d (单文件配置)${C_RESET}"
    if [ -d "$NGINX_CONF_D" ] && [ -n "$(ls "$NGINX_CONF_D" 2>/dev/null)" ]; then
        local f
        for f in "$NGINX_CONF_D"/*.conf; do
            [ -f "$f" ] || continue
            echo -e "  ${C_CYAN}●${C_RESET} $(basename "$f")"
        done
    else
        echo -e "  ${C_DIM}(空)${C_RESET}"
    fi
}

_list_manageable_sites() {
    local link name i=0
    NGINX_SITE_ITEMS=()
    echo ""
    echo -e "  ${C_BOLD}反代站点${C_RESET}"
    for link in "$NGINX_SITES_ENABLED"/*; do
        [ -L "$link" ] || continue
        name=$(basename "$link")
        [ -f "${NGINX_SITES_AVAIL}/${name}" ] || continue
        i=$((i + 1))
        NGINX_SITE_ITEMS+=("$name")
        if _has_cert "$name"; then
            echo -e "  [$i] $name ${C_GREEN}(有证书)${C_RESET}"
        else
            echo -e "  [$i] $name ${C_YELLOW}(无证书)${C_RESET}"
        fi
    done
    [ "$i" -eq 0 ] && info "无反代站点"
}

_select_enabled_site() {
    local sel
    _list_manageable_sites
    [ ${#NGINX_SITE_ITEMS[@]} -gt 0 ] || return 1
    _menu_actions 20 "[0] 返回上级"
    read -p "  选择站点编号（0 返回）: " sel
    [ -n "$sel" ] && [ "$sel" != "0" ] || { info "已返回"; return 1; }
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#NGINX_SITE_ITEMS[@]} ]; then
        error "无效选择"
        return 1
    fi
    NGINX_SELECTED_SITE="${NGINX_SITE_ITEMS[$((sel - 1))]}"
}

do_view_conf() {
    _check_nginx || return
    local target="${1:-}"
    [ -n "$target" ] || { _select_enabled_site || return 0; target="$NGINX_SELECTED_SITE"; }
    target="${NGINX_SITES_AVAIL}/${target}"
    [ -f "$target" ] || { error "站点配置不存在"; return 1; }
    echo ""
    echo -e "  ${C_DIM}──── $(basename "$target") ────${C_RESET}"
    cat "$target" 2>/dev/null || sudo cat "$target" 2>/dev/null
    echo -e "  ${C_DIM}──────────────────────────────────${C_RESET}"
}

# 确保 conf.d 下存在 WebSocket Connection 头映射（全局，仅创建一次）。
_ensure_ws_map() {
    local ws_conf="${NGINX_CONF_D}/kairo-ws-upgrade.conf"
    if [ ! -f "$ws_conf" ]; then
        info "创建 WebSocket 升级映射 ($ws_conf)"
        sudo mkdir -p "$NGINX_CONF_D" || return 1
        cat <<'WSMAP' | sudo tee "$ws_conf" >/dev/null
# 由 Kairo 生成 - WebSocket Connection 头映射
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
WSMAP
    fi
}

# 生成反代 conf（TLSv1.2/1.3 + WebSocket + HSTS + SSL 会话复用 + 完整 proxy_set_header）
_make_proxy_conf() {
    local domain="$1"
    local upstream_host="$2"
    local upstream_port="$3"
    local with_www="$4"
    local enable_tls="${5:-y}"

    local server_name="$domain"
    [ "$with_www" = "y" ] && server_name="$domain www.$domain"

    if [ "$enable_tls" != "y" ]; then
        cat <<EOF
# 由 Kairo 生成于 $(date +%Y-%m-%d)
server {
    listen 80;
    server_name ${server_name};

    location / {
        proxy_pass http://${upstream_host}:${upstream_port};
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        \$connection_upgrade;
        proxy_read_timeout 86400s;
    }
}
EOF
        return
    fi

    cat <<EOF
# 由 Kairo 生成于 $(date +%Y-%m-%d)
# 删除: rm ${NGINX_SITES_AVAIL}/${domain} && rm ${NGINX_SITES_ENABLED}/${domain}
server {
    listen 443 ssl http2;
    server_name ${server_name};

    ssl_certificate     ${LE_LIVE_DIR}/${domain}/fullchain.pem;
    ssl_certificate_key ${LE_LIVE_DIR}/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    # Mozilla Intermediate 兼容配置 (https://ssl-config.mozilla.org/)
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    client_max_body_size 20m;

    add_header Strict-Transport-Security "max-age=63072000" always;

    location / {
        proxy_pass http://${upstream_host}:${upstream_port};

        # WebSocket 需要 HTTP/1.1（nginx < 1.29.7 默认 1.0）
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        \$connection_upgrade;
        proxy_read_timeout 86400s;
    }
}

server {
    listen 80;
    server_name ${server_name};
    return 301 https://\$host\$request_uri;
}
EOF
}

do_add_proxy() {
    _check_nginx || return
    if ! sudo -n true &>/dev/null; then
        error "此操作需要 sudo 权限"
        return
    fi

    echo ""
    echo -e "  ${C_DIM}添加反代站点（域名 → 上游 host:port）${C_RESET}"
    echo ""

    read -p "  域名（如 example.com）: " domain
    [ -z "$domain" ] && info "已取消" && return

    # 域名格式粗校验
    if ! echo "$domain" | grep -qP '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$'; then
        error "域名格式不合法: $domain"
        return
    fi

    # 已存在检查
    if [ -L "${NGINX_SITES_ENABLED}/${domain}" ] || [ -f "${NGINX_SITES_AVAIL}/${domain}" ]; then
        error "反代站点已存在: $domain，请在站点列表中删除后再添加"
        return
    fi

    read -p "  上游 host (默认 127.0.0.1): " up_host
    up_host=${up_host:-127.0.0.1}
    if [[ ! "$up_host" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
        error "上游 host 格式不合法"
        return 1
    fi

    read -p "  上游 port (默认 8080): " up_port
    up_port=${up_port:-8080}
    if ! [[ "$up_port" =~ ^[0-9]+$ ]] || [ "$up_port" -lt 1 ] || [ "$up_port" -gt 65535 ]; then
        error "端口不合法"
        return
    fi

    read -p "  包含 www.${domain}? [Y/n]: " with_www
    [ "$with_www" = "n" ] || [ "$with_www" = "N" ] && with_www="n" || with_www="y"

    echo ""
    info "将写入: ${NGINX_SITES_AVAIL}/${domain}"
    echo -e "  ${C_DIM}反代: http://${up_host}:${up_port}${C_RESET}"
    echo -e "  ${C_DIM}域名: ${domain}$([ "$with_www" = "y" ] && echo " + www")${C_RESET}"
    echo ""
    read -p "  确认添加? [Y/n]: " confirm
    [ "$confirm" = "n" ] || [ "$confirm" = "N" ] && info "已取消" && return

    sudo mkdir -p "$NGINX_SITES_AVAIL" "$NGINX_SITES_ENABLED" || {
        error "无法创建 Nginx 站点目录"
        return 1
    }
    _ensure_ws_map || {
        error "无法创建 WebSocket 公共配置"
        return 1
    }

    local conf_file="${NGINX_SITES_AVAIL}/${domain}"
    local enable_tls="n"
    _has_cert "$domain" && enable_tls="y"
    _make_proxy_conf "$domain" "$up_host" "$up_port" "$with_www" "$enable_tls" | sudo tee "$conf_file" >/dev/null \
        || { error "写入失败"; return 1; }

    sudo ln -sf "$conf_file" "${NGINX_SITES_ENABLED}/${domain}" || {
        sudo rm -f -- "$conf_file"
        error "启用站点失败"
        return 1
    }
    sudo nginx -t 2>&1 | sed 's/^/  /'

    if ! sudo nginx -t &>/dev/null; then
        sudo rm -f -- "${NGINX_SITES_ENABLED}/${domain}" "$conf_file"
        error "配置语法检查失败，已移除新站点"
        return 1
    fi
    if ! sudo systemctl reload nginx 2>/dev/null; then
        sudo rm -f -- "${NGINX_SITES_ENABLED}/${domain}" "$conf_file"
        error "Nginx 重载失败，已移除新站点"
        return 1
    fi
    success "已添加: ${domain} → ${up_host}:${up_port}"

    # 提示申请证书
    echo ""
    if ! _has_cert "$domain"; then
        warn "未检测到 ${domain} 的 Let's Encrypt 证书"
        echo -e "  ${C_DIM}访问当前走 80→443 重定向，但 443 证书文件不存在，浏览器会报错${C_RESET}"
        read -p "  立即申请证书? [Y/n]: " do_cert_now
        if [ "$do_cert_now" != "n" ] && [ "$do_cert_now" != "N" ]; then
            _do_cert_for_domain "$domain" "$with_www"
        fi
    else
        success "检测到已有证书: ${LE_LIVE_DIR}/${domain}/"
    fi
}

do_del_proxy() {
    _check_nginx || return
    if ! sudo -n true &>/dev/null; then
        error "此操作需要 sudo 权限"
        return 1
    fi

    local target="${1:-}"
    [ -n "$target" ] || { _select_enabled_site || return 0; target="$NGINX_SELECTED_SITE"; }
    [ -L "${NGINX_SITES_ENABLED}/${target}" ] || { error "站点不存在: $target"; return 1; }

    echo ""
    warn "将删除: ${target}"
    echo -e "  ${C_GRAY}${NGINX_SITES_AVAIL}/${target}${C_RESET}"
    echo -e "  ${C_GRAY}${NGINX_SITES_ENABLED}/${target}${C_RESET}"
    if _has_cert "$target"; then
        echo -e "  ${C_CYAN}证书 ${LE_LIVE_DIR}/${target}/ 不动（保留）${C_RESET}"
    fi
    echo ""
    read -p "  确认删除? [y/N]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && info "已取消" && return

    if ! sudo rm -f "${NGINX_SITES_ENABLED}/${target}" ||
       ! sudo rm -f "${NGINX_SITES_AVAIL}/${target}"; then
        error "删除站点文件失败"
        return 1
    fi
    if sudo nginx -t &>/dev/null && sudo systemctl reload nginx 2>/dev/null; then
        success "已删除 ${target}，nginx 配置已重载"
    else
        error "重载失败，请检查配置"
        return 1
    fi
}

# 列出 sites-available 中尚未启用的站点，写进 NGINX_SITE_ITEMS。
_list_disabled_sites() {
    local f name i=0
    NGINX_SITE_ITEMS=()
    echo ""
    echo -e "  ${C_BOLD}未启用的站点配置 (sites-available)${C_RESET}"
    for f in "$NGINX_SITES_AVAIL"/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        [ -L "${NGINX_SITES_ENABLED}/${name}" ] && continue
        i=$((i + 1))
        NGINX_SITE_ITEMS+=("$name")
        echo -e "  [$i] $name"
    done
    [ "$i" -eq 0 ] && info "无未启用的站点"
}

_select_disabled_site() {
    local sel
    _list_disabled_sites
    [ ${#NGINX_SITE_ITEMS[@]} -gt 0 ] || return 1
    _menu_actions 20 "[0] 返回上级"
    read -p "  选择要启用的站点编号（0 返回）: " sel
    [ -n "$sel" ] && [ "$sel" != "0" ] || { info "已返回"; return 1; }
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#NGINX_SITE_ITEMS[@]} ]; then
        error "无效选择"
        return 1
    fi
    NGINX_SELECTED_SITE="${NGINX_SITE_ITEMS[$((sel - 1))]}"
}

# 禁用站点：移除 sites-enabled 软链（保留 available 配置与证书）。
# shellcheck disable=SC2120 # CLI 可传站点名；菜单入口会交互选择。
do_disable_site() {
    _check_nginx || return
    if ! sudo -n true &>/dev/null; then
        error "此操作需要 sudo 权限"
        return 1
    fi
    local target="${1:-}"
    [ -n "$target" ] || { _select_enabled_site || return 0; target="$NGINX_SELECTED_SITE"; }
    [ -f "${NGINX_SITES_AVAIL}/${target}" ] || { error "站点配置缺失: $target"; return 1; }
    [ -L "${NGINX_SITES_ENABLED}/${target}" ] || { error "站点未启用: $target"; return 1; }

    echo ""
    warn "禁用站点（保留配置与证书）: ${target}"
    read -p "  确认禁用? [y/N]: " confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || { info "已取消"; return; }

    sudo rm -f "${NGINX_SITES_ENABLED}/${target}" || { error "禁用失败"; return 1; }
    if sudo nginx -t &>/dev/null && sudo systemctl reload nginx 2>/dev/null; then
        success "已禁用 ${target}（配置保留在 sites-available）"
    else
        sudo ln -sf "${NGINX_SITES_AVAIL}/${target}" "${NGINX_SITES_ENABLED}/${target}"
        error "重载失败，已恢复启用状态"
        return 1
    fi
}

# 启用站点：为 sites-available 配置建立 sites-enabled 软链。
# shellcheck disable=SC2120 # CLI 可传站点名；菜单入口会交互选择。
do_enable_site() {
    _check_nginx || return
    if ! sudo -n true &>/dev/null; then
        error "此操作需要 sudo 权限"
        return 1
    fi
    local target="${1:-}"
    [ -n "$target" ] || { _select_disabled_site || return 0; target="$NGINX_SELECTED_SITE"; }
    [ -f "${NGINX_SITES_AVAIL}/${target}" ] || { error "站点配置不存在: $target"; return 1; }
    [ -L "${NGINX_SITES_ENABLED}/${target}" ] && { info "站点已启用: $target"; return; }

    sudo mkdir -p "$NGINX_SITES_ENABLED"
    sudo ln -sf "${NGINX_SITES_AVAIL}/${target}" "${NGINX_SITES_ENABLED}/${target}" || { error "启用失败"; return 1; }
    if sudo nginx -t &>/dev/null && sudo systemctl reload nginx 2>/dev/null; then
        success "已启用 ${target}"
    else
        sudo rm -f "${NGINX_SITES_ENABLED}/${target}"
        error "配置校验/重载失败，已撤销启用（请检查 ${NGINX_SITES_AVAIL}/${target}）"
        return 1
    fi
}

# ─── 证书 ────────────────────────────────────────────────────

_check_certbot() {
    if command -v certbot &>/dev/null; then
        return 0
    fi
    warn "未检测到 certbot"
    if ! command -v snap &>/dev/null && [ "$(id -u)" -ne 0 ]; then
        error "安装 certbot 需要 root 权限"
        return 1
    fi
    read -p "  安装 certbot? [Y/n]: " confirm
    [ "$confirm" = "n" ] || [ "$confirm" = "N" ] && return 1

    if command -v snap &>/dev/null; then
        info "使用 snap 安装 certbot（官方推荐路径）"
        if ! sudo snap install --classic certbot; then
            error "certbot 安装失败"
            return 1
        fi
        if ! sudo ln -sf /snap/bin/certbot /usr/local/bin/certbot 2>/dev/null; then
            error "无法创建 certbot 命令链接"
            return 1
        fi
    else
        info "snap 不可用，使用 apt 安装 python3-certbot-nginx"
        if ! sudo apt-get install -y python3-certbot-nginx; then
            error "certbot 安装失败"
            return 1
        fi
    fi

    if command -v certbot &>/dev/null; then
        success "certbot 已安装"
    else
        error "certbot 安装失败"
        return 1
    fi
}

# 为单个域名申请证书（内部函数，nginx 模块内复用）
_do_cert_for_domain() {
    local domain="$1"
    local with_www="$2"

    _check_certbot || return

    info "开始为 ${domain} 申请 Let's Encrypt 证书..."

    local args=(--nginx --agree-tos --non-interactive --redirect)
    args+=(-m "admin@${domain}")
    args+=(-d "$domain")
    [ "$with_www" = "y" ] && args+=(-d "www.${domain}")

    if sudo certbot "${args[@]}"; then
        success "证书申请/续期完成"
    else
        error "证书申请失败，请检查:"
        echo -e "  ${C_DIM}- 域名 ${domain} 已解析到本机 IP${C_RESET}"
        echo -e "  ${C_DIM}- 80 端口未开放 / 未被防火墙拦截${C_RESET}"
        echo -e "  ${C_DIM}- LE 未对该域名颁发达到 rate limit${C_RESET}"
    fi
}

do_cert() {
    _check_nginx || return
    if ! sudo -n true &>/dev/null; then
        error "此操作需要 sudo 权限"
        return
    fi

    local target="${1:-}" with_www="n"
    [ -n "$target" ] || { _select_enabled_site || return 0; target="$NGINX_SELECTED_SITE"; }
    [ -L "${NGINX_SITES_ENABLED}/${target}" ] || { error "站点不存在: $target"; return 1; }
    grep -q "www.${target}" "${NGINX_SITES_AVAIL}/${target}" 2>/dev/null && with_www="y"
    _do_cert_for_domain "$target" "$with_www"
}

do_cert_list() {
    if ! command -v certbot &>/dev/null; then
        error "未安装 certbot，可在站点操作中申请证书时自动安装"
        return
    fi
    echo ""
    sudo certbot certificates
}

# ─── 日志 ────────────────────────────────────────────────────

do_logs() {
    _check_nginx || return
    echo ""
    _menu_actions 30 "[1] 访问日志 (tail)"
    _menu_actions 30 "[2] 错误日志 (tail)"
    _menu_actions 30 "[3] 访问日志 Top 分析 (今天)"
    _menu_actions 30 "[0] 返回上级"
    read -p "  选择: " log_type
    case "$log_type" in
        1) sudo tail -f "${NGINX_LOG_DIR}/access.log" ;;
        2) sudo tail -f "${NGINX_LOG_DIR}/error.log" ;;
        3) do_log_top; echo ""; kairo_pause "按 Enter 返回日志菜单..." ;;
        *) info "已取消"; return ;;
    esac
}

# 把字节数转为人类可读（B/KB/MB/GB）。
_human_bytes() {
    local b="${1:-0}"
    awk -v b="$b" 'BEGIN{
        if (b>=1073741824) printf "%.2f GB", b/1073741824
        else if (b>=1048576) printf "%.2f MB", b/1048576
        else if (b>=1024) printf "%.2f KB", b/1024
        else printf "%d B", b
    }'
}

# 访问日志 Top 分析（默认今天）：Top IP / URL / 状态码 / 总流量。
# nginx combined: IP - - [date] "METHOD URL PROTO" status bytes "ref" "ua"
do_log_top() {
    _check_nginx || return
    local log="${NGINX_LOG_DIR}/access.log"
    if ! sudo test -r "$log"; then
        error "访问日志不存在或不可读: $log"
        return 1
    fi

    local today data total
    today=$(date '+%d/%b/%Y')
    data=$(sudo awk -v d="$today" '$0 ~ d' "$log")
    if [ -z "$data" ]; then
        echo ""
        info "今天（${today}）暂无访问记录"
        return
    fi
    total=$(printf '%s\n' "$data" | wc -l)
    echo ""
    info "访问日志分析（${today}，共 ${total} 条）"

    echo ""
    echo -e "  ${C_BOLD}Top 10 IP${C_RESET}"
    printf '%s\n' "$data" | awk '{print $1}' | sort | uniq -c | sort -rn | head -n 10 | \
        awk '{printf "  %8d  %s\n", $1, $2}'

    echo ""
    echo -e "  ${C_BOLD}Top 10 URL${C_RESET}"
    printf '%s\n' "$data" | awk -F'"' '{print $2}' | awk '{print $2}' | sort | uniq -c | sort -rn | head -n 10 | \
        awk '{printf "  %8d  %s\n", $1, $2}'

    echo ""
    echo -e "  ${C_BOLD}状态码分布${C_RESET}"
    printf '%s\n' "$data" | awk -F'"' '{gsub(/^ /,"",$3); split($3,a," "); print a[1]}' | sort | uniq -c | sort -rn | \
        awk '{printf "  %8d  %s\n", $1, $2}'

    local bytes
    bytes=$(printf '%s\n' "$data" | awk -F'"' '{gsub(/^ /,"",$3); split($3,a," "); sum+=a[2]} END{print sum+0}')
    echo ""
    info "总流量: $(_human_bytes "$bytes")"
}

# ─── 安全加固扫描 ────────────────────────────────────────────

# 安全加固扫描（只读）：检查全局 server_tokens 与各站点的安全配置项。
do_security_scan() {
    _check_nginx || return
    echo ""
    title "🔒 安全加固扫描"

    # 全局：server_tokens（nginx.conf + conf.d）
    echo ""
    echo -e "  ${C_BOLD}全局${C_RESET}"
    local gconf=""
    [ -f "$NGINX_CONF_FILE" ] && gconf=$(sudo cat "$NGINX_CONF_FILE" 2>/dev/null)
    if [ -d "$NGINX_CONF_D" ]; then
        local gf
        for gf in "$NGINX_CONF_D"/*.conf; do
            [ -f "$gf" ] && gconf="${gconf}
$(sudo cat "$gf" 2>/dev/null)"
        done
    fi
    if printf '%s\n' "$gconf" | grep -qE '^[[:space:]]*server_tokens[[:space:]]+off[[:space:]]*;'; then
        printf "  %-28s ${C_GREEN}%s${C_RESET}\n" "server_tokens off" "✔"
    else
        printf "  %-28s ${C_YELLOW}%s${C_RESET}\n" "server_tokens off" "⚠ 未关闭（暴露版本号）"
    fi

    # 逐站点
    echo ""
    echo -e "  ${C_BOLD}站点（sites-enabled）${C_RESET}"
    # "站点" 是两个双宽字符；printf 按 UTF-8 字节而非终端显示宽度计数，
    # 因此这里用 28（而非数据行的 26）让后续列与 ASCII 站点名对齐。
    printf "  ${C_DIM}%-28s %-4s %-5s %-8s %-7s %-6s %s${C_RESET}\n" \
        "站点" "TLS" "HSTS" "NoSniff" "Frame" "Body" "证书"
    printf "  ${C_DIM}%-26s %-4s %-5s %-8s %-7s %-6s %s${C_RESET}\n" \
        "──────────────────────────" "────" "─────" "────────" "───────" "──────" "────"
    local any=0 link name c tls hsts nosniff frame body cert
    for link in "$NGINX_SITES_ENABLED"/*; do
        [ -L "$link" ] || continue
        name=$(basename "$link")
        [ -f "${NGINX_SITES_AVAIL}/${name}" ] || continue
        any=1
        c=$(sudo cat "${NGINX_SITES_AVAIL}/${name}" 2>/dev/null)
        printf '%s\n' "$c" | grep -qE 'ssl_protocols[^\n]*TLSv1\.[23]' && tls="${C_GREEN}✔" || tls="${C_YELLOW}-"
        printf '%s\n' "$c" | grep -qi 'Strict-Transport-Security' && hsts="${C_GREEN}✔" || hsts="${C_YELLOW}-"
        printf '%s\n' "$c" | grep -qi 'X-Content-Type-Options' && nosniff="${C_GREEN}✔" || nosniff="${C_YELLOW}-"
        printf '%s\n' "$c" | grep -qEi 'X-Frame-Options|frame-ancestors' && frame="${C_GREEN}✔" || frame="${C_YELLOW}-"
        printf '%s\n' "$c" | grep -q 'client_max_body_size' && body="${C_GREEN}✔" || body="${C_YELLOW}-"
        if _has_cert "$name"; then cert="${C_GREEN}有"; else cert="${C_YELLOW}无"; fi
        printf "  %-26s %s${C_RESET}    %s${C_RESET}     %s${C_RESET}        %s${C_RESET}       %s${C_RESET}      %s${C_RESET}\n" \
            "$name" "$tls" "$hsts" "$nosniff" "$frame" "$body" "$cert"
    done
    if [ "$any" -eq 0 ]; then
        echo -e "  ${C_DIM}(无启用站点)${C_RESET}"
    else
        echo ""
        echo -e "  ${C_DIM}列: TLS≥1.2 / HSTS / NoSniff / Frame / Body 限制 / 证书    ✔=已配置  -=缺失${C_RESET}"
    fi
}

# ─── 配置快照 / 回滚 ────────────────────────────────────────

# 创建配置快照（整目录 /etc/nginx），只保留最近 NGINX_SNAPSHOT_KEEP 个。
do_snapshot() {
    _check_nginx || return
    if ! sudo -n true &>/dev/null; then
        error "此操作需要 sudo 权限"
        return 1
    fi
    [ -d "$NGINX_ETC_DIR" ] || { error "Nginx 配置目录不存在"; return 1; }

    sudo mkdir -p "$NGINX_SNAPSHOT_DIR" || { error "无法创建快照目录"; return 1; }
    local stamp snap
    stamp=$(date '+%Y%m%d-%H%M%S')
    snap="${NGINX_SNAPSHOT_DIR}/nginx-${stamp}"
    if _with_spinner "正在创建快照 nginx-${stamp}" sudo cp -a "$NGINX_ETC_DIR" "$snap"; then
        success "已创建快照: $snap"
    else
        error "创建快照失败"
        return 1
    fi

    # 清理：只保留最近 NGINX_SNAPSHOT_KEEP 个
    local i=0 d
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        i=$((i + 1))
        [ "$i" -gt "$NGINX_SNAPSHOT_KEEP" ] && sudo rm -rf -- "$d"
    done < <(sudo ls -1dt "${NGINX_SNAPSHOT_DIR}"/*/ 2>/dev/null | sed 's#/$##')
    [ "$i" -gt "$NGINX_SNAPSHOT_KEEP" ] && info "已清理旧快照，保留最近 ${NGINX_SNAPSHOT_KEEP} 个"
}

# 列出快照（按时间倒序），写 NGINX_SNAPSHOT_ITEMS 数组。
_list_snapshots() {
    local d i=0
    NGINX_SNAPSHOT_ITEMS=()
    echo ""
    echo -e "  ${C_BOLD}配置快照（${NGINX_SNAPSHOT_DIR}）${C_RESET}"
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        i=$((i + 1))
        NGINX_SNAPSHOT_ITEMS+=("$d")
        echo -e "  [$i] $(basename "$d")"
    done < <(sudo ls -1dt "${NGINX_SNAPSHOT_DIR}"/*/ 2>/dev/null | sed 's#/$##')
    [ "$i" -eq 0 ] && info "无快照（先选择 [1] 创建快照）"
}

# 从快照恢复 /etc/nginx：二次确认 + 恢复前自动 pre-restore 保险 + nginx -t 兜底。
do_restore() {
    _check_nginx || return
    if ! sudo -n true &>/dev/null; then
        error "此操作需要 sudo 权限"
        return 1
    fi
    _list_snapshots
    [ ${#NGINX_SNAPSHOT_ITEMS[@]} -gt 0 ] || return 0
    _menu_actions 20 "[0] 返回上级"
    local sel
    read -p "  选择要恢复的快照（0 返回）: " sel
    [ -n "$sel" ] && [ "$sel" != "0" ] || { info "已返回"; return; }
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#NGINX_SNAPSHOT_ITEMS[@]} ]; then
        error "无效选择"
        return 1
    fi
    local snap="${NGINX_SNAPSHOT_ITEMS[$((sel - 1))]}"

    echo ""
    warn "将用快照 $(basename "$snap") 覆盖整个 /etc/nginx"
    echo -e "  ${C_GRAY}当前配置会先自动备份为 pre-restore 快照${C_RESET}"
    read -p "  确认恢复? [y/N]: " confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || { info "已取消"; return; }

    local pre
    pre="${NGINX_SNAPSHOT_DIR}/pre-restore-$(date '+%Y%m%d-%H%M%S')"
    sudo cp -a "$NGINX_ETC_DIR" "$pre" || { error "恢复前的备份失败，已中止"; return 1; }

    if ! sudo cp -a "${snap}/." "${NGINX_ETC_DIR}/"; then
        error "恢复失败，当前配置未受影响（pre-restore 备份: $pre）"
        return 1
    fi

    if sudo nginx -t &>/dev/null; then
        sudo systemctl reload nginx 2>/dev/null
        success "已从 $(basename "$snap") 恢复并重载"
        info "恢复前的备份: $pre"
    else
        sudo cp -a "${pre}/." "${NGINX_ETC_DIR}/" 2>/dev/null
        error "快照配置校验失败，已自动回滚到恢复前状态"
        return 1
    fi
}

# ─── 菜单 ────────────────────────────────────────────────────

menu() {
    while true; do
        clear
        title "🌐 Nginx 管理"
        do_status 2>/dev/null
        divider
        _menu_actions 24 "${C_BOLD}[1]${C_RESET} 安装 / 升级 Nginx (官方源)"
        _menu_actions 24 "${C_BOLD}[2]${C_RESET} 服务管理"
        _menu_actions 24 "${C_BOLD}[3]${C_RESET} 反代站点管理"
        _menu_actions 24 "${C_BOLD}[4]${C_RESET} 日志 (tail / Top 分析)"
        _menu_actions 24 "${C_BOLD}[5]${C_RESET} 安全加固扫描"
        _menu_actions 24 "${C_BOLD}[6]${C_RESET} 配置快照 / 回滚"
        _menu_actions 24 "${C_BOLD}[7]${C_RESET} 卸载 Nginx"
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_install; ;;
            2)
                echo ""
                _menu_actions 20 "[1] 启动" "[2] 停止"
                _menu_actions 20 "[3] 重启" "[4] 重载配置"
                _menu_actions 20 "[5] 开关开机自启" "[6] 测试配置语法"
                _menu_actions 20 "[0] 返回上级"
                read -p "  选择服务操作: " sub
                case "$sub" in
                    1) do_start ;;
                    2) do_stop ;;
                    3) do_restart ;;
                    4) do_reload ;;
                    5) do_toggle_enable ;;
                    6) do_test_conf ;;
                    0) continue ;;
                    *) error "无效选项"; sleep 1; continue ;;
                esac
                echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            3)
                _list_manageable_sites
                echo ""
                _menu_actions 18 "[编号] 选择站点" "[A] 添加" "[D] 禁用站点"
                _menu_actions 18 "[E] 启用站点" "[C] 证书概览" "[0] 返回上级"
                read -p "  选择站点或操作: " sub
                case "$sub" in
                    [Aa]) do_add_proxy; echo ""; kairo_pause "按 Enter 返回站点列表..."; continue ;;
                    [Dd]) do_disable_site; echo ""; kairo_pause "按 Enter 返回站点列表..."; continue ;;
                    [Ee]) do_enable_site; echo ""; kairo_pause "按 Enter 返回站点列表..."; continue ;;
                    [Cc]) do_cert_list; echo ""; kairo_pause "按 Enter 返回站点列表..."; continue ;;
                    0) continue ;;
                    *)
                        if [[ "$sub" =~ ^[0-9]+$ ]] && [ "$sub" -ge 1 ] && [ "$sub" -le ${#NGINX_SITE_ITEMS[@]} ]; then
                            local site="${NGINX_SITE_ITEMS[$((sub - 1))]}"
                            echo ""
                            echo "  ${C_BOLD}${site}${C_RESET}"
                            _menu_actions 22 "[1] 查看配置" "[2] 申请 / 续期证书" "[3] 删除站点" "[0] 返回上级"
                            read -p "  选择操作: " sub
                            case "$sub" in
                                1) do_view_conf "$site" ;;
                                2) do_cert "$site" ;;
                                3) do_del_proxy "$site" ;;
                                0) continue ;;
                                *) error "无效选项"; sleep 1; continue ;;
                            esac
                        else
                            error "无效选项"; sleep 1; continue
                        fi
                        ;;
                esac
                echo ""; kairo_pause "按 Enter 返回站点列表..." ;;
            4) do_logs ;;
            5) do_security_scan; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            6)
                echo ""
                _menu_actions 20 "[1] 创建快照" "[2] 从快照恢复" "[0] 返回上级"
                read -p "  选择: " sub
                case "$sub" in
                    1) do_snapshot ;;
                    2) do_restore ;;
                    0) continue ;;
                    *) error "无效选项"; sleep 1; continue ;;
                esac
                echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            7) do_uninstall; ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
