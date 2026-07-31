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
    local package
    package=$(_sqlite3_package 2>/dev/null)
    if [ -n "$package" ]; then
        dpkg-query -W -f='${Version}' "$package" 2>/dev/null && return
    fi
    sqlite3 --version 2>/dev/null | awk 'NR == 1 { print $1; exit }'
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
    command -v apt-get >/dev/null 2>&1 || { error "仅支持 Debian/Ubuntu 的 apt"; return 1; }
    sudo -v || { error "安装需要 sudo 权限"; return 1; }
    if kairo_apt_install sqlite3; then
        success "SQLite3 安装完成: $(_sqlite3_version)"
    else
        error "SQLite3 安装失败"
        return 1
    fi
}

do_upgrade() {
    local package
    _sqlite3_exists || { do_install; return $?; }
    package=$(_sqlite3_package)
    [ -n "$package" ] || { error "未识别 SQLite3 的安装渠道，未自动升级"; return 1; }
    if _tool_apt_upgrade "$package" "SQLite3"; then
        success "SQLite3 已升级至 $(_sqlite3_version)"
    fi
}

menu() {
    _tool_menu "🗃️ SQLite3"
}
