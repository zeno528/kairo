#!/usr/bin/env bash
# Kimi Code 安装与升级。

KIMI_CHANNEL=""
KIMI_BINARY=""

_kimi_detect_channel() {
    KIMI_CHANNEL=""
    KIMI_BINARY=$(command -v kimi 2>/dev/null) || return 1
    if [ "$(readlink -f "$KIMI_BINARY")" = "$HOME/.kimi-code/bin/kimi" ]; then
        KIMI_CHANNEL="official_installer"
    else
        KIMI_CHANNEL="other"
    fi
}

_kimi_version() {
    "$KIMI_BINARY" --version 2>/dev/null | head -n 1 | sed 's/^v//'
}

_kimi_latest_version() {
    curl --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 1 -fsSL \
        "https://code.kimi.com/kimi-code/latest" | tr -d '[:space:]'
}

_kimi_run_installer() {
    local version="$1" installer rc
    installer=$(mktemp) || return 1
    if ! curl --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 1 -fsSL \
        "https://code.kimi.com/kimi-code/install.sh" -o "$installer"; then
        rm -f -- "$installer"
        return 1
    fi
    KIMI_VERSION="$version" bash "$installer"
    rc=$?
    rm -f -- "$installer"
    return "$rc"
}

do_status() {
    title "当前状态"
    if ! _kimi_detect_channel; then
        warn "未安装"
        return 1
    fi
    printf '  版本    %s\n' "$(_kimi_version)"
    printf '  路径    %s\n' "$KIMI_BINARY"
    if [ "$KIMI_CHANNEL" = "official_installer" ]; then
        printf '  方式    Kimi Code 官方安装器\n'
    else
        printf '  方式    未识别的安装渠道\n'
    fi
    printf '  来源    https://github.com/MoonshotAI/kimi-code/releases\n'
}

do_install() {
    local latest
    latest=$(_kimi_latest_version)
    [ -n "$latest" ] || { error "无法获取 Kimi Code 最新版本"; return 1; }
    if _kimi_run_installer "$latest"; then
        export PATH="$HOME/.kimi-code/bin:$PATH"
        success "Kimi Code 安装完成: $(_kimi_version)"
    else
        error "Kimi Code 安装失败"
        return 1
    fi
}

do_upgrade() {
    local current latest confirm
    _kimi_detect_channel || { do_install; return $?; }
    if [ "$KIMI_CHANNEL" != "official_installer" ]; then
        error "未识别 Kimi Code 的安装渠道，未自动升级: $KIMI_BINARY"
        return 1
    fi
    current=$(_kimi_version)
    latest=$(_kimi_latest_version)
    [ -n "$latest" ] || { error "无法获取 Kimi Code 最新版本"; return 1; }
    if ! kairo_version_is_newer "$latest" "$current"; then
        success "已是最新版本 ($current)"
        return 0
    fi
    info "$current → $latest"
    read -r -p "  升级 Kimi Code? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    if _kimi_run_installer "$latest"; then
        export PATH="$HOME/.kimi-code/bin:$PATH"
        success "Kimi Code 已升级至 $(_kimi_version)"
    else
        error "Kimi Code 升级失败"
        return 1
    fi
}

menu() {
    local choice
    while true; do
        clear
        title "🤖 Kimi Code"
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
