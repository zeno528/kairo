#!/usr/bin/env bash
# SQLite3 使用 Debian/Ubuntu 官方 apt 包安装与升级。

_sqlite3_exists() {
    command -v sqlite3 >/dev/null 2>&1
}

_sqlite3_package() {
    local binary
    binary=$(command -v sqlite3 2>/dev/null) || return 1
    kairo_deb_package_for_path "$binary"
}

_sqlite3_version() {
    sqlite3 --version 2>/dev/null | awk 'NR == 1 { print $1; exit }'
}

_sqlite3_upgrade_apt() {
    sudo apt update -qq && sudo apt install --only-upgrade -y "$1"
}

do_status() {
    local package
    title "当前状态"
    if ! _sqlite3_exists; then
        warn "未安装"
        return 1
    fi
    package=$(_sqlite3_package)
    printf '  版本    %s\n' "$(_sqlite3_version)"
    printf '  路径    %s\n' "$(command -v sqlite3)"
    if [ -n "$package" ]; then
        printf '  方式    apt 包: %s\n' "$package"
    else
        printf '  方式    未识别的安装渠道\n'
    fi
    printf '  来源    https://www.sqlite.org/download.html\n'
}

do_install() {
    command -v apt >/dev/null 2>&1 || { error "仅支持 Debian/Ubuntu 的 apt"; return 1; }
    sudo -v || { error "安装需要 sudo 权限"; return 1; }
    if _with_spinner "正在通过 apt 安装 SQLite3" sudo apt update -qq && sudo apt install -y sqlite3; then
        success "SQLite3 安装完成: $(_sqlite3_version)"
    else
        error "SQLite3 安装失败"
        return 1
    fi
}

do_upgrade() {
    local package installed candidate confirm
    _sqlite3_exists || { do_install; return $?; }
    package=$(_sqlite3_package)
    [ -n "$package" ] || { error "未识别 SQLite3 的安装渠道，未自动升级"; return 1; }
    sudo -v || { error "升级需要 sudo 权限"; return 1; }
    if ! _with_spinner "正在刷新 SQLite3 软件源" sudo apt update -qq; then
        error "刷新软件源失败"
        return 1
    fi
    installed=$(dpkg-query -W -f='${Version}' "$package")
    candidate=$(apt-cache policy "$package" | awk '/Candidate:/ { print $2; exit }')
    [ -n "$candidate" ] && [ "$candidate" != "(none)" ] || { error "无法获取候选版本"; return 1; }
    if [ "$installed" = "$candidate" ]; then
        success "系统包已是最新版本 ($(_sqlite3_version))"
        return 0
    fi
    info "$installed → $candidate"
    read -r -p "  通过 apt 升级 SQLite3? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    if _with_spinner "正在升级 SQLite3" _sqlite3_upgrade_apt "$package"; then
        success "SQLite3 已升级至 $(_sqlite3_version)"
    else
        error "SQLite3 升级失败"
        return 1
    fi
}

menu() {
    local choice
    while true; do
        title "🗃️ SQLite3"
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
