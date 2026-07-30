#!/usr/bin/env bash
# jq 官方发行二进制安装与升级。

_jq_target="/usr/local/bin/jq"

_jq_managed() {
    [ -x "$_jq_target" ]
}

_jq_exists() {
    command -v jq >/dev/null 2>&1
}

_jq_version() {
    jq --version 2>/dev/null | sed 's/^jq-//'
}

_jq_latest_version() {
    curl --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 1 -fsSL \
        "https://api.github.com/repos/jqlang/jq/releases/latest" \
        | sed -n 's/.*"tag_name": *"jq-\{0,1\}\([^"]*\)".*/\1/p' | head -n 1
}

_jq_asset_name() {
    case "$(uname -m)" in
        x86_64) printf 'jq-linux-amd64' ;;
        aarch64) printf 'jq-linux-arm64' ;;
        *) return 1 ;;
    esac
}

_jq_install_release() {
    local version="$1" asset="$2" binary
    binary=$(mktemp) || return 1
    trap 'rm -f -- "$binary"; trap - RETURN' RETURN
    if ! curl --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 1 -fsSL \
        "https://github.com/jqlang/jq/releases/download/jq-${version}/${asset}" -o "$binary" \
        || ! chmod 755 "$binary" \
        || [ "$("$binary" --version 2>/dev/null | sed 's/^jq-//')" != "$version" ]; then
        return 1
    fi
    sudo install -m 755 "$binary" "$_jq_target"
}

do_status() {
    title "当前状态"
    if ! _jq_exists; then
        warn "未安装"
        return 1
    fi
    printf '  版本    %s\n' "$(_jq_version)"
    printf '  路径    %s\n' "$(command -v jq)"
    if _jq_managed; then
        printf '  方式    jq 官方发行二进制\n'
    else
        printf '  方式    非 Kairo 管理\n'
    fi
    printf '  来源    '
    kairo_link "https://github.com/jqlang/jq/releases" "https://github.com/jqlang/jq/releases"
    printf '\n'
}

do_install() {
    local latest asset
    if _jq_managed; then
        info "jq 已安装: $(_jq_version)"
        return 0
    fi
    if _jq_exists; then
        error "检测到非 Kairo 管理的 jq，未自动覆盖: $(command -v jq)"
        return 1
    fi
    latest=$(_jq_latest_version)
    asset=$(_jq_asset_name) || { error "不支持的架构: $(uname -m)"; return 1; }
    [ -n "$latest" ] || { error "无法获取 jq 最新版本"; return 1; }
    sudo -v || { error "安装需要 sudo 权限"; return 1; }
    if _with_spinner "正在安装 jq ${latest}" _jq_install_release "$latest" "$asset"; then
        success "jq 安装完成: $(_jq_version)"
    else
        error "jq 安装失败"
        return 1
    fi
}

do_upgrade() {
    local current latest asset confirm
    _jq_managed || { do_install; return $?; }
    current=$(_jq_version)
    latest=$(_jq_latest_version)
    asset=$(_jq_asset_name) || { error "不支持的架构: $(uname -m)"; return 1; }
    [ -n "$latest" ] || { error "无法获取 jq 最新版本"; return 1; }
    if ! kairo_version_is_newer "$latest" "$current"; then
        success "已是最新版本 ($current)"
        return 0
    fi
    info "$current → $latest"
    read -r -p "  将覆盖 ${_jq_target}，确认升级 jq? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    sudo -v || { error "升级需要 sudo 权限"; return 1; }
    if _with_spinner "正在升级 jq ${latest}" _jq_install_release "$latest" "$asset"; then
        success "jq 已升级至 $(_jq_version)"
    else
        error "jq 升级失败"
        return 1
    fi
}

menu() {
    local choice
    while true; do
        title "🔧 jq"
        do_status || true
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 安装    ${C_BOLD}[2]${C_RESET} 检查并升级    ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_install ;;
            2) do_upgrade ;;
            0) return ;;
            *) error "无效选项" ;;
        esac
        kairo_pause
    done
}
