#!/usr/bin/env bash
# Claude Code 安装与升级。

_claude_exists() {
    command -v claude >/dev/null 2>&1
}

_claude_version() {
    claude --version 2>/dev/null | awk 'NR == 1 { print $1; exit }' | sed 's/^v//'
}

_claude_latest_version() {
    curl --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 1 -fsSL \
        "https://api.github.com/repos/anthropics/claude-code/releases/latest" \
        | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1
}

_claude_run_installer() {
    local installer rc
    installer=$(mktemp) || return 1
    if ! curl --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 1 -fsSL \
        "https://claude.ai/install.sh" -o "$installer"; then
        rm -f -- "$installer"
        return 1
    fi
    bash "$installer"
    rc=$?
    rm -f -- "$installer"
    return "$rc"
}

do_status() {
    title "当前状态"
    if ! _claude_exists; then
        warn "未安装"
        return 1
    fi
    printf '  版本    %s\n' "$(_claude_version)"
    printf '  路径    %s\n' "$(command -v claude)"
    printf '  来源    '
    kairo_link "https://github.com/anthropics/claude-code/releases" "https://github.com/anthropics/claude-code/releases"
    printf '\n'
}

do_install() {
    if _claude_exists; then
        info "Claude Code 已安装: $(_claude_version)"
        return 0
    fi
    command -v curl >/dev/null 2>&1 || { error "需要 curl"; return 1; }
    if _with_spinner "正在安装 Claude Code" _claude_run_installer; then
        success "Claude Code 安装完成: $(_claude_version)"
    else
        error "Claude Code 安装失败"
        return 1
    fi
}

do_upgrade() {
    local current latest confirm
    _claude_exists || { do_install; return $?; }
    current=$(_claude_version)
    latest=$(_claude_latest_version)
    [ -n "$latest" ] || { error "无法获取 GitHub Releases 最新版本"; return 1; }
    if ! kairo_version_is_newer "$latest" "$current"; then
        success "已是最新版本 ($current)"
        return 0
    fi
    info "$current → $latest"
    read -r -p "  升级 Claude Code? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    if _with_spinner "正在升级 Claude Code" claude update; then
        success "Claude Code 已升级至 $(_claude_version)"
    else
        error "Claude Code 升级失败"
        return 1
    fi
}

menu() {
    local choice
    while true; do
        title "🤖 Claude Code"
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
