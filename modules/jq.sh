#!/usr/bin/env bash
# jq 按 Debian/Ubuntu apt 或官方 Releases 二进制安装渠道升级。

_jq_target="/usr/local/bin/jq"
JQ_CHANNEL=""
JQ_PACKAGE=""
JQ_BINARY=""

_jq_detect_channel() {
    local binary
    JQ_CHANNEL=""
    JQ_PACKAGE=""
    JQ_BINARY=""
    binary=$(command -v jq 2>/dev/null) || return 1
    JQ_BINARY="$binary"
    JQ_PACKAGE=$(kairo_deb_package_for_path "$binary") || {
        if [ "$(readlink -f "$binary")" = "$_jq_target" ]; then
            JQ_CHANNEL="official_release"
        else
            JQ_CHANNEL="other"
        fi
        return 0
    }
    JQ_CHANNEL="apt"
}

_jq_version() {
    "$JQ_BINARY" --version 2>/dev/null | sed 's/^jq-//'
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

_jq_upgrade_apt() {
    sudo apt update -qq && sudo apt install --only-upgrade -y "$JQ_PACKAGE"
}

do_status() {
    title "当前状态"
    if ! _jq_detect_channel; then
        warn "未安装"
        return 1
    fi
    printf '  版本    %s\n' "$(_jq_version)"
    printf '  路径    %s\n' "$JQ_BINARY"
    case "$JQ_CHANNEL" in
        apt) printf '  方式    apt 包: %s\n' "$JQ_PACKAGE" ;;
        official_release) printf '  方式    jq 官方 Releases 二进制\n' ;;
        *) printf '  方式    未识别的安装渠道\n' ;;
    esac
    printf '  来源    https://github.com/jqlang/jq/releases\n'
}

do_install() {
    command -v apt >/dev/null 2>&1 || { error "仅支持 Debian/Ubuntu 的 apt"; return 1; }
    sudo -v || { error "安装需要 sudo 权限"; return 1; }
    if _with_spinner "正在通过 apt 安装 jq" sudo apt update -qq && sudo apt install -y jq; then
        _jq_detect_channel
        success "jq 安装完成: $(_jq_version)"
    else
        error "jq 安装失败"
        return 1
    fi
}

do_upgrade() {
    local current latest asset confirm installed candidate
    _jq_detect_channel || { do_install; return $?; }
    case "$JQ_CHANNEL" in
        apt)
            sudo -v || { error "升级需要 sudo 权限"; return 1; }
            if ! _with_spinner "正在刷新 jq 软件源" sudo apt update -qq; then
                error "刷新软件源失败"
                return 1
            fi
            installed=$(dpkg-query -W -f='${Version}' "$JQ_PACKAGE")
            candidate=$(apt-cache policy "$JQ_PACKAGE" | awk '/Candidate:/ { print $2; exit }')
            [ -n "$candidate" ] && [ "$candidate" != "(none)" ] || { error "无法获取候选版本"; return 1; }
            if [ "$installed" = "$candidate" ]; then
                success "系统包已是最新版本 ($(_jq_version))"
                return 0
            fi
            info "$installed → $candidate"
            read -r -p "  通过 apt 升级 jq? [Y/n]: " confirm
            [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
            if _with_spinner "正在升级 jq" _jq_upgrade_apt; then
                _jq_detect_channel
                success "jq 已升级至 $(_jq_version)"
            else
                error "jq 升级失败"
                return 1
            fi
            ;;
        official_release)
            current=$(_jq_version)
            latest=$(_jq_latest_version)
            asset=$(_jq_asset_name) || { error "不支持的架构: $(uname -m)"; return 1; }
            [ -n "$latest" ] || { error "无法获取 jq 最新版本"; return 1; }
            if ! kairo_version_is_newer "$latest" "$current"; then
                success "已是最新版本 ($current)"
                return 0
            fi
            info "$current → $latest"
            read -r -p "  通过 jq 官方 Releases 升级? [Y/n]: " confirm
            [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
            sudo -v || { error "升级需要 sudo 权限"; return 1; }
            if _with_spinner "正在升级 jq ${latest}" _jq_install_release "$latest" "$asset"; then
                _jq_detect_channel
                success "jq 已升级至 $(_jq_version)"
            else
                error "jq 升级失败"
                return 1
            fi
            ;;
        *)
            error "未识别 jq 的安装渠道，未自动升级: $JQ_BINARY"
            return 1
            ;;
    esac
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
