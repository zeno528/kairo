#!/usr/bin/env bash
# OpenClaw 使用官方安装器与官方 update 命令安装和升级。

OPENCLAW_BINARY=""

_openclaw_exists() {
    OPENCLAW_BINARY=$(command -v openclaw 2>/dev/null) || return 1
}

_openclaw_version() {
    "$OPENCLAW_BINARY" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){1,2}(-[0-9]+)?' | head -n 1
}

_openclaw_update_status() {
    timeout 30 "$OPENCLAW_BINARY" update status --json
}

_openclaw_run_installer() {
    _tool_run_remote_installer "https://openclaw.ai/install.sh"
}

do_status() {
    title "当前状态"
    if ! _openclaw_exists; then
        warn "未安装"
        return 1
    fi
    printf '  版本    %s\n' "$(_openclaw_version)"
    printf '  路径    %s\n' "$OPENCLAW_BINARY"
    printf '  方式    OpenClaw 官方更新器\n'
    printf '  来源    https://openclaw.ai/\n'
}

do_install() {
    command -v curl >/dev/null 2>&1 || { error "需要 curl"; return 1; }
    if _openclaw_run_installer; then
        _openclaw_exists
        success "OpenClaw 安装完成: $(_openclaw_version)"
    else
        error "OpenClaw 安装失败"
        return 1
    fi
}

do_upgrade() {
    local current status_json available latest confirm
    _openclaw_exists || { do_install; return $?; }
    current=$(_openclaw_version)
    status_json=$(_openclaw_update_status 2>/dev/null) || {
        error "无法检查 OpenClaw 更新状态"
        return 1
    }
    available=$(printf '%s\n' "$status_json" | sed -n 's/.*"available"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -n 1)
    case "$available" in
        false)
            success "已是最新版本 ($current)"
            return 0
            ;;
        true)
            latest=$(printf '%s\n' "$status_json" | sed -n 's/.*"latestVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
            if [ -n "$latest" ]; then
                info "$current → $latest"
            else
                info "发现可用更新"
            fi
            ;;
        *)
            error "无法解析 OpenClaw 更新状态"
            return 1
            ;;
    esac
    read -r -p "  使用 OpenClaw 官方更新器检查并升级? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    if "$OPENCLAW_BINARY" update; then
        _openclaw_exists
        if [ "$(_openclaw_version)" = "$current" ]; then
            success "已是最新版本 ($current)"
        else
            success "OpenClaw 已升级至 $(_openclaw_version)"
        fi
    else
        error "OpenClaw 升级失败"
        return 1
    fi
}

menu() {
    _tool_menu "🦞 OpenClaw"
}
