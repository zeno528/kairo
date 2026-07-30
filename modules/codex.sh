#!/usr/bin/env bash
# Codex CLI 使用官方 standalone 安装器与内置 update 命令安装和升级。

CODEX_CHANNEL=""
CODEX_BINARY=""

_codex_detect_channel() {
    local resolved
    CODEX_CHANNEL=""
    CODEX_BINARY=$(command -v codex 2>/dev/null) || return 1
    resolved=$(readlink -f "$CODEX_BINARY") || return 1
    if [ "$CODEX_BINARY" = "$HOME/.local/bin/codex" ] \
        && [[ "$resolved" = "$HOME/.codex/packages/standalone/"* ]]; then
        CODEX_CHANNEL="official_standalone"
    else
        CODEX_CHANNEL="other"
    fi
}

_codex_version() {
    "$CODEX_BINARY" --version 2>/dev/null | awk 'NR == 1 { print $2; exit }' | sed 's/^v//'
}

_codex_run_installer() {
    local installer rc
    installer=$(mktemp) || return 1
    if ! curl --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 1 -fsSL \
        "https://chatgpt.com/codex/install.sh" -o "$installer"; then
        rm -f -- "$installer"
        return 1
    fi
    sh "$installer"
    rc=$?
    rm -f -- "$installer"
    return "$rc"
}

do_status() {
    title "当前状态"
    if ! _codex_detect_channel; then
        warn "未安装"
        return 1
    fi
    printf '  版本    %s\n' "$(_codex_version)"
    printf '  路径    %s\n' "$CODEX_BINARY"
    if [ "$CODEX_CHANNEL" = "official_standalone" ]; then
        printf '  方式    Codex 官方 standalone 安装器\n'
    else
        printf '  方式    未识别的安装渠道\n'
    fi
    printf '  来源    https://github.com/openai/codex/releases\n'
}

do_install() {
    command -v curl >/dev/null 2>&1 || { error "需要 curl"; return 1; }
    if _codex_run_installer; then
        export PATH="$HOME/.local/bin:$PATH"
        _codex_detect_channel
        success "Codex CLI 安装完成: $(_codex_version)"
    else
        error "Codex CLI 安装失败"
        return 1
    fi
}

do_upgrade() {
    local current confirm
    _codex_detect_channel || { do_install; return $?; }
    if [ "$CODEX_CHANNEL" != "official_standalone" ]; then
        error "未识别 Codex CLI 的安装渠道，未自动升级: $CODEX_BINARY"
        return 1
    fi
    current=$(_codex_version)
    info "当前版本: $current"
    read -r -p "  使用 Codex 官方更新器检查并升级? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    if "$CODEX_BINARY" update; then
        _codex_detect_channel
        if [ "$(_codex_version)" = "$current" ]; then
            success "已是最新版本 ($current)"
        else
            success "Codex CLI 已升级至 $(_codex_version)"
        fi
    else
        error "Codex CLI 升级失败"
        return 1
    fi
}

menu() {
    local choice
    while true; do
        title "🤖 Codex CLI"
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
