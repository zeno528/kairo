#!/usr/bin/env bash
# Go 官方发行包安装与升级。

_go_root="/usr/local/go"

_go_managed() {
    [ -x "${_go_root}/bin/go" ]
}

_go_exists() {
    command -v go >/dev/null 2>&1 || _go_managed
}

_go_binary() {
    if _go_managed; then
        printf '%s/bin/go' "$_go_root"
    else
        command -v go
    fi
}

_go_version() {
    "$(_go_binary)" version 2>/dev/null | sed -n 's/^go version go\([^ ]*\).*/\1/p'
}

_go_latest_version() {
    curl --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 1 -fsSL \
        "https://go.dev/VERSION?m=text" | head -n 1 | sed 's/^go//'
}

_go_architecture() {
    case "$(uname -m)" in
        x86_64) printf 'amd64' ;;
        aarch64) printf 'arm64' ;;
        *) return 1 ;;
    esac
}

_go_install_release() {
    local version="$1" architecture="$2" archive_url stage backup rc=0
    archive_url="https://go.dev/dl/go${version}.linux-${architecture}.tar.gz"
    stage=$(mktemp -d) || return 1
    trap 'rm -rf -- "$stage"; trap - RETURN' RETURN
    if ! curl --connect-timeout 10 --max-time 300 --retry 2 --retry-delay 1 -fsSL \
        "$archive_url" -o "$stage/go.tar.gz" \
        || ! tar -tzf "$stage/go.tar.gz" >/dev/null \
        || ! tar -C "$stage" -xzf "$stage/go.tar.gz" \
        || [ ! -x "$stage/go/bin/go" ]; then
        return 1
    fi
    if _go_managed; then
        backup=$(sudo mktemp -d /usr/local/.kairo-go-backup.XXXXXX) || return 1
        if ! sudo mv "$_go_root" "$backup/go" || ! sudo mv "$stage/go" "$_go_root"; then
            if [ -e "$backup/go" ] && ! sudo mv "$backup/go" "$_go_root"; then
                printf 'Go 回滚失败，备份仍位于 %s\n' "$backup/go" >&2
            fi
            return 1
        fi
        sudo rmdir "$backup" || rc=1
    else
        sudo mv "$stage/go" "$_go_root" || return 1
    fi
    return "$rc"
}

do_status() {
    title "当前状态"
    if ! _go_exists; then
        warn "未安装"
        return 1
    fi
    printf '  版本    %s\n' "$(_go_version)"
    printf '  路径    %s\n' "$(_go_binary)"
    if _go_managed; then
        printf '  方式    Go 官方发行包\n'
    else
        printf '  方式    非 Kairo 管理\n'
    fi
    printf '  来源    '
    kairo_link "https://go.dev/dl/" "https://go.dev/dl/"
    printf '\n'
}

do_install() {
    local latest architecture
    if _go_managed; then
        info "Go 已安装: $(_go_version)"
        return 0
    fi
    if command -v go >/dev/null 2>&1; then
        error "检测到非 Kairo 管理的 Go，未自动覆盖: $(command -v go)"
        return 1
    fi
    latest=$(_go_latest_version)
    architecture=$(_go_architecture) || { error "不支持的架构: $(uname -m)"; return 1; }
    [ -n "$latest" ] || { error "无法获取 Go 最新版本"; return 1; }
    sudo -v || { error "安装需要 sudo 权限"; return 1; }
    if _with_spinner "正在安装 Go ${latest}" _go_install_release "$latest" "$architecture"; then
        success "Go 安装完成: $(_go_version)"
    else
        error "Go 安装失败"
        return 1
    fi
}

do_upgrade() {
    local current latest architecture confirm
    _go_managed || { do_install; return $?; }
    current=$(_go_version)
    latest=$(_go_latest_version)
    architecture=$(_go_architecture) || { error "不支持的架构: $(uname -m)"; return 1; }
    [ -n "$latest" ] || { error "无法获取 Go 最新版本"; return 1; }
    if ! kairo_version_is_newer "$latest" "$current"; then
        success "已是最新版本 ($current)"
        return 0
    fi
    info "$current → $latest"
    read -r -p "  将替换 ${_go_root}，确认升级 Go? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    sudo -v || { error "升级需要 sudo 权限"; return 1; }
    if _with_spinner "正在升级 Go ${latest}" _go_install_release "$latest" "$architecture"; then
        success "Go 已升级至 $(_go_version)"
    else
        error "Go 升级失败，已尝试恢复原版本"
        return 1
    fi
}

menu() {
    local choice
    while true; do
        title "🐹 Go"
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
