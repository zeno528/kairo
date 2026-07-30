#!/usr/bin/env bash
# OpenClaw 安装与升级。

_openclaw_exists() {
    command -v openclaw >/dev/null 2>&1
}

_openclaw_version() {
    openclaw --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){1,2}(-[0-9]+)?' | head -n 1
}

_openclaw_latest_version() {
    timeout 30 npm view openclaw version 2>/dev/null | tr -d '[:space:]'
}

_openclaw_restart_gateway() {
    if ! systemctl --user stop openclaw-gateway 2>/dev/null; then
        warn "Gateway 未运行或无法停止"
    fi
    if ! systemctl --user start openclaw-gateway 2>/dev/null; then
        warn "Gateway 未启动，请检查用户级 systemd 服务"
    fi
}

_openclaw_install_version() {
    npm install -g "openclaw@$1"
}

do_status() {
    title "当前状态"
    if ! _openclaw_exists; then
        warn "未安装"
        return 1
    fi
    printf '  版本    %s\n' "$(_openclaw_version)"
    printf '  路径    %s\n' "$(command -v openclaw)"
    printf '  来源    '
    kairo_link "https://www.npmjs.com/package/openclaw" "https://www.npmjs.com/package/openclaw"
    printf '\n'
}

do_install() {
    local latest
    if _openclaw_exists; then
        info "OpenClaw 已安装: $(_openclaw_version)"
        return 0
    fi
    command -v npm >/dev/null 2>&1 || { error "需要 npm，请先安装 Node.js"; return 1; }
    latest=$(_openclaw_latest_version)
    [ -n "$latest" ] || { error "无法获取 OpenClaw 最新版本"; return 1; }
    if _with_spinner "正在安装 OpenClaw" _openclaw_install_version "$latest"; then
        success "OpenClaw 安装完成: $(_openclaw_version)"
    else
        error "OpenClaw 安装失败"
        return 1
    fi
}

do_upgrade() {
    local current latest confirm method
    _openclaw_exists || { do_install; return $?; }
    command -v npm >/dev/null 2>&1 || { error "需要 npm"; return 1; }
    current=$(_openclaw_version)
    latest=$(_openclaw_latest_version)
    [ -n "$latest" ] || { error "无法获取 OpenClaw 最新版本"; return 1; }
    if ! kairo_version_is_newer "$latest" "$current"; then
        success "已是最新版本 ($current)"
        return 0
    fi
    info "$current → $latest"
    read -r -p "  升级 OpenClaw? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    echo "  [1] openclaw update（官方命令）"
    echo "  [2] npm install -g（适用于 update 失败）"
    read -r -p "  请选择升级方式 [1/2，默认 1]: " method
    case "${method:-1}" in
        1) _with_spinner "正在升级 OpenClaw" openclaw update ;;
        2) _with_spinner "正在升级 OpenClaw" _openclaw_install_version "$latest" ;;
        *) error "无效选项"; return 1 ;;
    esac || { error "OpenClaw 升级失败"; return 1; }
    _openclaw_restart_gateway
    openclaw doctor --fix || warn "doctor 检查有警告"
    if [ "$(_openclaw_version)" = "$latest" ]; then
        success "OpenClaw 已升级至 $latest"
    else
        warn "升级完成，但当前版本与目标版本不一致: $(_openclaw_version)"
    fi
}

menu() {
    local choice
    while true; do
        title "🦞 OpenClaw"
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
