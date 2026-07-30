#!/usr/bin/env bash
# GitHub CLI（gh）通过 GitHub 官方 apt 源安装与升级。

_github_cli_exists() {
    command -v gh >/dev/null 2>&1
}

_github_cli_version() {
    if _github_cli_via_apt; then
        dpkg-query -W -f='${Version}' gh 2>/dev/null && return
    fi
    gh --version 2>/dev/null | sed -n '1s/^gh version \([^ ]*\).*/\1/p' | sed 's/^v//'
}

_github_cli_via_apt() {
    dpkg-query -W -f='${Status}' gh 2>/dev/null | grep -qx 'install ok installed'
}

_github_cli_add_repo() {
    local keyring sources_file architecture key_file
    keyring="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
    sources_file="/etc/apt/sources.list.d/github-cli.list"
    architecture=$(dpkg --print-architecture) || return 1
    if [ -f "$keyring" ] && [ -f "$sources_file" ]; then
        return 0
    fi
    key_file=$(mktemp) || return 1
    if ! curl --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 -fsSL \
        "https://cli.github.com/packages/githubcli-archive-keyring.gpg" -o "$key_file"; then
        rm -f -- "$key_file"
        return 1
    fi
    if ! sudo install -d -m 755 /etc/apt/keyrings \
        || ! sudo install -m 644 "$key_file" "$keyring" \
        || ! printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages stable main\n' \
            "$architecture" "$keyring" | sudo tee "$sources_file" >/dev/null; then
        rm -f -- "$key_file"
        return 1
    fi
    rm -f -- "$key_file"
}

_github_cli_install() {
    _github_cli_add_repo && kairo_apt_install gh
}

do_status() {
    title "当前状态"
    if ! _github_cli_exists; then
        warn "未安装"
        return 1
    fi
    printf '  版本    %s\n' "$(_github_cli_version)"
    printf '  路径    %s\n' "$(command -v gh)"
    if _github_cli_via_apt; then
        printf '  方式    GitHub 官方 apt 源\n'
    else
        printf '  方式    非 apt 安装\n'
    fi
    if gh auth status &>/dev/null; then
        printf "  认证    ${C_GREEN}已登录${C_RESET} (%s)\n" "$(gh auth status 2>&1 | head -1)"
    else
        printf "  认证    ${C_RED}未认证${C_RESET}，请运行 [A] 认证登录\n"
    fi
    printf '  来源    https://github.com/cli/cli/releases\n'
}

do_auth() {
    _github_cli_exists || { error "请先安装 gh"; return 1; }
    local masked_token
    _masked_read() {
        local char t=""
        stty -echo
        while IFS= read -r -s -n1 char; do
            [ -z "$char" ] && { echo ""; break; }
            t+="$char"
            printf '*'
        done
        stty echo
        printf '%s' "$t"
    }
    echo ""
    echo -e "  ${C_BOLD}选择认证方式${C_RESET}"
    echo ""
    _menu_actions 32 "${C_BOLD}[1]${C_RESET} 粘贴 Token（推荐）"
    _menu_actions 32 "${C_BOLD}[2]${C_RESET} 浏览器登录"
    _menu_actions 32 "${C_BOLD}[3]${C_RESET} 设备码登录（无浏览器）"
    _menu_actions 32 "${C_BOLD}[0]${C_RESET} 取消"
    echo ""
    read -r -p "  请选择: " choice
    case "$choice" in
        1)
            echo ""
            info "前往 https://github.com/settings/tokens 创建 Token（勾选 repo、workflow 权限）"
            printf "  粘贴 Token: "
            masked_token=$(_masked_read)
            echo ""
            [ -z "$masked_token" ] && { info "已取消"; return 0; }
            if echo "$masked_token" | gh auth login --with-token 2>&1; then
                success "认证成功"
            else
                error "认证失败，请检查 Token 是否正确"
            fi
            ;;
        2)
            if gh auth login --web 2>&1; then
                success "认证成功"
            else
                error "浏览器登录失败，请尝试其他方式"
            fi
            ;;
        3)
            if gh auth login 2>&1; then
                success "认证成功"
            else
                error "设备码登录失败"
            fi
            ;;
        0) info "已取消" ;;
        *) error "无效选项" ;;
    esac
}

do_install() {
    command -v curl >/dev/null 2>&1 || { error "需要 curl"; return 1; }
    command -v apt-get >/dev/null 2>&1 || { error "仅支持 Debian/Ubuntu 的 apt"; return 1; }
    sudo -v || { error "安装需要 sudo 权限"; return 1; }
    if _github_cli_install; then
        success "GitHub CLI 安装完成: $(_github_cli_version)"
    else
        error "GitHub CLI 安装失败"
        return 1
    fi
}

do_upgrade() {
    local installed candidate confirm
    _github_cli_exists || { do_install; return $?; }
    if ! _github_cli_via_apt; then
        error "当前 gh 并非由 apt 管理，未自动替换: $(command -v gh)"
        return 1
    fi
    sudo -v || { error "升级需要 sudo 权限"; return 1; }
    if ! kairo_apt_update; then
        error "刷新软件源失败"
        return 1
    fi
    installed=$(dpkg-query -W -f='${Version}' gh 2>/dev/null)
    candidate=$(apt-cache policy gh | awk '/Candidate:/ { print $2; exit }')
    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
        error "无法获取候选版本"
        return 1
    fi
    if [ "$installed" = "$candidate" ]; then
        success "已是最新版本 ($(_github_cli_version))"
        return 0
    fi
    info "$installed → $candidate"
    read -r -p "  升级 GitHub CLI? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    if sudo apt-get install --only-upgrade -y gh; then
        success "GitHub CLI 已升级至 $(_github_cli_version)"
    else
        error "GitHub CLI 升级失败"
        return 1
    fi
}

menu() {
    local choice
    while true; do
        clear
        title "🐙 GitHub CLI"
        do_status || true
        divider
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 安装"
        _menu_actions 20 "${C_BOLD}[2]${C_RESET} 检查并升级"
        _menu_actions 20 "${C_BOLD}[A]${C_RESET} 认证登录"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_install ;;
            2) do_upgrade ;;
            [Aa]) do_auth ;;
            0) return ;;
            *) error "无效选项" ;;
        esac
        kairo_pause
    done
}
