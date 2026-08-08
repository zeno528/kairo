#!/usr/bin/env bats
# 测试目标: kairo.sh + install.sh
# 覆盖: 语法、模块注册表和关键入口函数

setup() {
    # Bats 子进程 PATH 残缺
    export PATH="/usr/bin:/bin:/usr/local/bin:/usr/libexec:/c/Windows/System32:$PATH"
    cd "$BATS_TEST_DIRNAME/.." || return 1
}

# ─── 语法 ──────────────────────────────────────────────────────

@test "kairo.sh bash 语法正确" {
    run /usr/bin/bash -n "$PWD/kairo.sh"
    [ "$status" -eq 0 ]
}

@test "install.sh bash 语法正确" {
    run /usr/bin/bash -n "$PWD/install.sh"
    [ "$status" -eq 0 ]
}

@test "全部 modules bash 语法正确" {
    for f in "$PWD"/modules/*.sh; do
        run /usr/bin/bash -n "$f"
        [ "$status" -eq 0 ] || { echo "$f 语法失败"; return 1; }
    done
}

# ─── kairo.sh 入口 ────────────────────────────────────────────

@test "kairo.sh help 输出含注册表中的全部模块" {
    run /usr/bin/bash "$PWD/kairo.sh" help
    [ "$status" -eq 0 ]
    source "$PWD/lib/core.sh"
    source "$PWD/modules/registry.sh"
    for module in "${KAIRO_MODULE_IDS[@]}"; do
        [[ "$output" =~ "$module" ]]
    done
}

@test "kairo.sh help 输出含 update / uninstall" {
    run /usr/bin/bash "$PWD/kairo.sh" help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "update" ]]
    [[ "$output" =~ "uninstall" ]]
}

@test "kairo.sh --help 与 help 等价" {
    run /usr/bin/bash "$PWD/kairo.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ssh-passwd" ]]
}

@test "kairo.sh 错误模块名报错退出码非 0" {
    run /usr/bin/bash "$PWD/kairo.sh" nonexistent-module-xyz
    [ "$status" -ne 0 ]
    [[ "$output" =~ "模块不存在" ]]
}

@test "模块不能调用未在注册表声明的入口 action" {
    run /usr/bin/bash "$PWD/kairo.sh" sys-info update
    [ "$status" -ne 0 ]
    [[ "$output" =~ "不支持操作" ]]
}

@test "注册表声明的 action 均有对应模块函数" {
    source "$PWD/lib/core.sh"
    source "$PWD/modules/registry.sh"
    for module in "${KAIRO_MODULE_IDS[@]}"; do
        # shellcheck disable=SC1090
        source "$PWD/modules/${module}.sh"
        for action in ${KAIRO_MODULE_ACTIONS[$module]}; do
            type "do_${action}" >/dev/null
        done
    done
}

@test "注册表拒绝重复模块和未知分组" {
    source "$PWD/modules/registry.sh"
    run kairo_register_module sys-info system "重复模块" "overview"
    [ "$status" -ne 0 ]
    run kairo_register_module invalid missing-group "错误分组" "status"
    [ "$status" -ne 0 ]
}

@test "AI Agent 分组与工具分组独立注册" {
    source "$PWD/modules/registry.sh"
    [ "${KAIRO_GROUP_LAYOUTS[tools]}" = "stack" ]
    [ "${KAIRO_GROUP_LAYOUTS[agents]}" = "right_column" ]
    [ "${KAIRO_MODULE_GROUPS[claude]}" = "agents" ]
    [ "${KAIRO_MODULE_GROUPS[codex]}" = "agents" ]
    [ "${KAIRO_MODULE_GROUPS[kimi]}" = "agents" ]
    [ "${KAIRO_MODULE_GROUPS[openclaw]}" = "agents" ]
}

@test "更新安装器以当前用户身份运行" {
    run bash -c '
        source <(sed -n "/^kairo_run_installer()/,/^}/p" "'"$PWD"'/kairo.sh")
        fetch_remote_file() { printf "true\n"; }
        sudo() { return 1; }
        kairo_run_installer
    '
    [ "$status" -eq 0 ]
}

@test "更新后输入 ka 重新进入主菜单，回车返回命令行" {
    run bash -c '
        source <(sed -n "/^kairo_update_next_action()/,/^}/p" "'$PWD'/kairo.sh")
        BIN_DIR=$(mktemp -d)
        printf "#!/usr/bin/env bash\\nprintf MENU\\n" > "${BIN_DIR}/ka"
        chmod +x "${BIN_DIR}/ka"
        printf "ka\\n" | (kairo_update_next_action)
        printf "\\n" | kairo_update_next_action
        printf RETURN
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"MENU"* ]]
    [[ "$output" == *"RETURN"* ]]
}

# ─── install.sh 关键函数 ──────────────────────────────────────

@test "install.sh 语法 + 不实际执行（-n）" {
    run /usr/bin/bash -n "$PWD/install.sh"
    [ "$status" -eq 0 ]
}

# ─── VERSION / CHANGELOG 一致性 ─────────────────────────────

@test "VERSION 文件存在且非空" {
    [ -s "$PWD/VERSION" ]
}

@test "VERSION 与 CHANGELOG 头部版本号一致" {
    local ver
    ver=$(cat "$PWD/VERSION" | tr -d '[:space:]')
    local head_ver
    head_ver=$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$PWD/CHANGELOG.md" | head -1 | tr -d 'v')
    [ "$ver" = "$head_ver" ]
}

@test "VERSION 格式符合 semver" {
    local ver
    ver=$(cat "$PWD/VERSION" | tr -d '[:space:]')
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "模块注册表中的文件均存在，且没有未注册模块" {
    source "$PWD/lib/core.sh"
    source "$PWD/modules/registry.sh"
    for module in "${KAIRO_MODULE_IDS[@]}"; do
        [ -f "$PWD/modules/${module}.sh" ]
    done
    for file in "$PWD"/modules/*.sh; do
        module=$(basename "$file" .sh)
        [ "$module" = "registry" ] || kairo_module_registered "$module"
    done
}

@test "工具模块不包含代理检测或代理参数" {
    run grep -Ein 'proxy|v2ray|127\.0\.0\.1|ensure_proxy|with_proxy' \
        "$PWD/modules/claude.sh" "$PWD/modules/codex.sh" "$PWD/modules/kimi.sh" \
        "$PWD/modules/github-cli.sh" "$PWD/modules/openclaw.sh" \
        "$PWD/modules/go.sh" "$PWD/modules/jq.sh" "$PWD/modules/sqlite3.sh" \
        "$PWD/modules/basics.sh"
    [ "$status" -eq 1 ]
}

@test "工具模块不包装官方流程的 spinner" {
    run grep -En '_with_spinner' \
        "$PWD/modules/claude.sh" "$PWD/modules/codex.sh" "$PWD/modules/kimi.sh" \
        "$PWD/modules/github-cli.sh" "$PWD/modules/openclaw.sh" \
        "$PWD/modules/go.sh" "$PWD/modules/jq.sh" "$PWD/modules/sqlite3.sh" \
        "$PWD/modules/basics.sh"
    [ "$status" -eq 1 ]
}

@test "Claude Code、Codex CLI 与 OpenClaw 不由 Kairo 直接调用 npm 管理" {
    run grep -Ein '\<npm\>' "$PWD/modules/claude.sh" "$PWD/modules/codex.sh" "$PWD/modules/openclaw.sh"
    [ "$status" -eq 1 ]
}

@test "工具模块的升级操作默认回车继续" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/claude.sh"
        claude() { [ "$1" = "--version" ] && echo 1.0.0 || echo upgraded; }
        _claude_detect_channel() { CLAUDE_CHANNEL=official_installer; CLAUDE_BINARY=claude; }
        _claude_latest_version() { echo 1.1.0; }
        printf "\n" | do_upgrade
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已升级至 1.0.0" ]]
}

@test "Codex 缓存版本相同时不进入升级确认" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/codex.sh"
        _codex_detect_channel() { CODEX_CHANNEL=official_standalone; CODEX_BINARY=codex; }
        _codex_version() { echo 0.146.0; }
        _codex_cached_latest_version() { echo 0.146.0; }
        codex() { echo SHOULD_NOT_UPDATE; }
        do_upgrade
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已是最新版本 (0.146.0)" ]]
    [[ ! "$output" =~ "SHOULD_NOT_UPDATE" ]]
}

@test "OpenClaw 无更新时不进入升级确认" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/openclaw.sh"
        _openclaw_exists() { OPENCLAW_BINARY=openclaw; }
        _openclaw_version() { echo 2026.7.1-2; }
        timeout() { shift; "$@"; }
        openclaw() {
            if [ "$1" = "update" ] && [ "$2" = "status" ]; then
                printf "%s\n" "{\"availability\":{\"available\":false}}"
            else
                echo SHOULD_NOT_UPDATE
            fi
        }
        do_upgrade
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已是最新版本 (2026.7.1-2)" ]]
    [[ ! "$output" =~ "SHOULD_NOT_UPDATE" ]]
}

@test "安装清单与全部运行时文件双向一致" {
    local expected actual
    expected=$(mktemp)
    actual=$(mktemp)
    {
        printf '%s\n' kairo.sh VERSION lib/core.sh modules/registry.sh
        for file in "$PWD"/modules/*.sh; do
            printf 'modules/%s\n' "$(basename "$file")"
        done
    } | sort -u > "$expected"
    sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$PWD/manifest.txt" | sort -u > "$actual"
    run diff -u "$expected" "$actual"
    [ "$status" -eq 0 ]
    rm -f "$expected" "$actual"
}

@test "SSH 公钥添加保留字段分隔并拒绝重复 key" {
    local test_home
    test_home=$(mktemp -d)
    run env HOME="$test_home" bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/ssh-keys.sh"
        printf "%s\n" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest user@example.com" | do_add
        cat "$AUTHORIZED_KEYS"
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest user@example.com" ]]

    run env HOME="$test_home" bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/ssh-keys.sh"
        printf "%s\n" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest changed-comment" | do_add
    '
    [ "$status" -ne 0 ]
    [[ "$output" =~ "已存在" ]]
    rm -rf "$test_home"
}

@test "SSH 公钥重命名保留反斜杠和 sed 特殊字符" {
    local test_home
    test_home=$(mktemp -d)
    run env HOME="$test_home" bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/ssh-keys.sh"
        mkdir -p "$HOME/.ssh"
        printf "%s\\n" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest old" > "$AUTHORIZED_KEYS"
        printf "%s\\n" 1 "build\\\\cache/&" | do_rename
        cat "$AUTHORIZED_KEYS"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *$'build\\cache/&'* ]]
    rm -rf "$test_home"
}

@test "SSH 密码登录切换需要明确确认" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/ssh-passwd.sh"
        set_password_auth() { printf "CHANGED\\n"; }
        restart_ssh() { printf "RESTARTED\\n"; }
        printf "%s\\n" n | do_on
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已取消" ]]
    [[ ! "$output" =~ "CHANGED" ]]
    [[ ! "$output" =~ "RESTARTED" ]]
}

@test "ufw 关闭端口调用 delete allow" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        sudo() { "$@"; }
        ufw() { printf "ufw %s\n" "$*"; }
        printf "%s\n" 8080 tcp y | do_close_port
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ufw delete allow 8080/tcp"* ]]
}

@test "ufw 开启防火墙自动放行实际 SSH 端口" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        sudo() { "$@"; }
        ufw() { printf "ufw %s\n" "$*"; }
        _fw_ssh_ports() { printf "2222\n"; }
        printf "%s\n" y | do_enable
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ufw allow 2222/tcp"* ]]
    [[ "$output" == *"ufw --force enable"* ]]
}

@test "检测不到 SSH 监听端口时拒绝开启防火墙" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        _fw_ssh_ports() { :; }
        printf "%s\n" y | do_enable
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"未检测到 SSH 监听端口"* ]]
}

@test "防火墙未启用时开放端口提示规则暂不生效" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        sudo() { "$@"; }
        ufw() { printf "ufw %s\n" "$*"; }
        printf "%s\n" 8080 tcp y | do_open_port
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ufw allow 8080/tcp"* ]]
    [[ "$output" == *"规则已保存但暂不生效"* ]]
}

@test "防火墙状态用中文表头标注进程并提示未放行监听端口" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        ufw() {
            if [ "$1" = "status" ] && [ $# -eq 1 ]; then printf "Status: active\n"; return; fi
            if [ "$1" = "status" ] && [ "$2" = "numbered" ]; then
                printf "Status: active\n\n     To                         Action      From\n     --                         ------      ----\n[ 1] 22/tcp                     ALLOW IN    Anywhere\n[ 2] 1.2.3.4                     DENY IN     Anywhere\n"
                return
            fi
            return 1
        }
        ss() {
            printf "%s\n" \
                "tcp LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:((\"sshd\",pid=1,fd=3))" \
                "tcp LISTEN 0 4096 0.0.0.0:8080 0.0.0.0:* users:((\"nginx\",pid=2,fd=6))" \
                "LISTEN 0 4096 0.0.0.0:9000 0.0.0.0:* users:((\"app\",pid=5,fd=9))" \
                "tcp LISTEN 0 4096 127.0.0.1:62789 0.0.0.0:* users:((\"x-ui\",pid=3,fd=4))"
        }
        do_status
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"●"* ]]
    [[ "$output" == *"编号"* ]]
    [[ "$output" == *"端口/协议"* ]]
    [[ "$output" == *"动作"* ]]
    [[ "$output" == *"来源"* ]]
    [[ "$output" == *"进程"* ]]
    [[ "$output" == *"ALLOW"* ]]
    [[ "$output" == *"Anywhere"* ]]
    [[ "$output" == *"(sshd)"* ]]
    [[ "$output" == *"8080/tcp"* ]]
    [[ "$output" == *"(nginx)"* ]]
    [[ "$output" == *"9000/tcp"* ]]
    [[ "$output" == *"(app)"* ]]
    [[ "$output" == *"1.2.3.4"* ]]
    [[ "$output" == *"状态"* ]]
    [[ "$output" == *"已放行"* ]]
    [[ "$output" == *"未放行"* ]]
    [[ ! "$output" == *"以下端口在监听但未放行"* ]]
    [[ ! "$output" == *"62789"* ]]
}

@test "批量放行未放行监听端口支持编号和范围" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        sudo() { "$@"; }
        ufw() {
            if [ "$1" = "status" ] && [ $# -eq 1 ]; then printf "Status: active\n"; return; fi
            if [ "$1" = "status" ] && [ "$2" = "numbered" ]; then
                printf "Status: active\n\n     To                         Action      From\n     --                         ------      ----\n[ 1] 22/tcp                     ALLOW IN    Anywhere\n"
                return
            fi
            printf "ufw %s\n" "$*"
        }
        ss() {
            printf "%s\n" \
                "tcp LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:((\"sshd\",pid=1,fd=3))" \
                "tcp LISTEN 0 4096 0.0.0.0:8080 0.0.0.0:* users:((\"nginx\",pid=2,fd=6))" \
                "udp UNCONN 0 0 0.0.0.0:8443 0.0.0.0:* users:((\"xray-linux-amd64\",pid=3,fd=7))"
        }
        printf "%s\n" "1-2" | do_allow_listeners
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ufw allow 8080/tcp"* ]]
    [[ "$output" == *"ufw allow 8443/udp"* ]]
}

@test "批量放行时防火墙未启用提示暂不生效" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        sudo() { "$@"; }
        ufw() {
            if [ "$1" = "status" ] && [ $# -eq 1 ]; then printf "Status: inactive\n"; return; fi
            if [ "$1" = "status" ] && [ "$2" = "numbered" ]; then
                printf "Status: inactive\n\n     To                         Action      From\n     --                         ------      ----\n"
                return
            fi
            printf "ufw %s\n" "$*"
        }
        ss() {
            printf "%s\n" \
                "tcp LISTEN 0 4096 0.0.0.0:8080 0.0.0.0:* users:((\"nginx\",pid=1,fd=3))"
        }
        printf "%s\n" 1 y | do_allow_listeners
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"规则已保存但暂不生效"* ]]
}

@test "防火墙菜单 active 时只显示关闭防火墙" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        ufw() { [ "$1" = "status" ] && printf "Status: active\n"; }
        clear() { :; }
        title() { :; }
        do_status() { :; }
        divider() { :; }
        _menu_actions() { printf "%s\n" "$2"; }
        printf "0\n" | menu
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"关闭防火墙"* ]]
    [[ ! "$output" == *"开启防火墙"* ]]
    [[ ! "$output" == *"安装 ufw"* ]]
    [[ ! "$output" == *"删除规则"* ]]
}

@test "防火墙菜单 inactive 时只显示开启防火墙" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        ufw() { [ "$1" = "status" ] && printf "Status: inactive\n"; }
        clear() { :; }
        title() { :; }
        do_status() { :; }
        divider() { :; }
        _menu_actions() { printf "%s\n" "$2"; }
        printf "0\n" | menu
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"开启防火墙"* ]]
    [[ ! "$output" == *"关闭防火墙"* ]]
    [[ ! "$output" == *"安装 ufw"* ]]
}

@test "防火墙菜单未安装 ufw 时只显示安装入口" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 1; builtin command "$@"; }
        ufw() { :; }
        clear() { :; }
        title() { :; }
        do_status() { :; }
        divider() { :; }
        _menu_actions() { printf "%s\n" "$2"; }
        printf "0\n" | menu
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"安装 ufw"* ]]
    [[ ! "$output" == *"开启防火墙"* ]]
    [[ ! "$output" == *"关闭防火墙"* ]]
}

@test "防火墙菜单有规则时显示删除规则编号" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        ufw() {
            if [ "$1" = "status" ] && [ $# -eq 1 ]; then printf "Status: active\n"; return; fi
            if [ "$1" = "status" ] && [ "$2" = "numbered" ]; then
                printf "Status: active\n\n     To                         Action      From\n     --                         ------      ----\n[ 1] 22/tcp                     ALLOW IN    Anywhere\n"
                return
            fi
            return 1
        }
        clear() { :; }
        title() { :; }
        do_status() { FIREWALL_RULE_COUNT=1; }
        divider() { :; }
        _menu_actions() { printf "%s\n" "$2"; }
        printf "0\n" | menu
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"[1-1] 删除规则"* ]]
}

@test "防火墙 inactive 状态显示红点" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        ufw() {
            if [ "$1" = "status" ] && [ $# -eq 1 ]; then printf "Status: inactive\n"; return; fi
            if [ "$1" = "show" ] && [ "$2" = "added" ]; then
                printf "ufw allow 8080/tcp\n"
                return
            fi
            return 1
        }
        ss() { :; }
        do_status
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"●"* ]]
    [[ "$output" == *"inactive"* ]]
    [[ "$output" == *"防火墙未启用；放行规则会保存"* ]]
    [[ "$output" == *"已保存 1 条放行规则"* ]]
    [[ "$output" == *"8080/tcp"* ]]
}

@test "IP 白名单子菜单预览并删除" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        sudo() { "$@"; }
        ufw() {
            if [ "$1" = "status" ] && [ $# -eq 1 ]; then printf "Status: active\n"; return; fi
            if [ "$1" = "status" ] && [ "$2" = "numbered" ]; then
                printf "Status: active\n\n     To                         Action      From\n     --                         ------      ----\n[ 1] 1.2.3.4                     ALLOW IN    Anywhere\n"
                return
            fi
            printf "ufw %s\n" "$*"
        }
        ss() { :; }
        printf "%s\n" 2 1 y 0 | _fw_ip_submenu allow
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"1.2.3.4"* ]]
    [[ "$output" == *"ufw delete allow from 1.2.3.4"* ]]
}

@test "批量删除规则按编号倒序执行" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        sudo() { "$@"; }
        ufw() {
            if [ "$1" = "status" ] && [ $# -eq 1 ]; then printf "Status: active\n"; return; fi
            if [ "$1" = "status" ] && [ "$2" = "numbered" ]; then
                printf "Status: active\n\n     To                         Action      From\n     --                         ------      ----\n[ 1] 80/tcp                      ALLOW IN    Anywhere\n[ 2] 22/tcp                      ALLOW IN    Anywhere\n[ 3] 443/tcp                     ALLOW IN    Anywhere\n[ 4] 8080/tcp                    ALLOW IN    Anywhere\n"
                return
            fi
            printf "ufw %s\n" "$*"
        }
        printf "y\n" | do_delete_rule "1-4"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ufw --force delete allow 8080/tcp"*"ufw --force delete allow 443/tcp"*"ufw --force delete allow 80/tcp"* ]]
    [[ ! "$output" == *"ufw --force delete allow 22/tcp"* ]]
    [[ "$output" == *"已跳过 SSH 端口 22/tcp"* ]]
}

@test "批量删除对 v4/v6 同端口只执行一次" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        sudo() { "$@"; }
        ufw() {
            if [ "$1" = "status" ] && [ $# -eq 1 ]; then printf "Status: active\n"; return; fi
            if [ "$1" = "status" ] && [ "$2" = "numbered" ]; then
                printf "Status: active\n\n     To                         Action      From\n     --                         ------      ----\n[ 1] 80/tcp                      ALLOW IN    Anywhere\n[ 2] 80/tcp (v6)                 ALLOW IN    Anywhere (v6)\n"
                return
            fi
            printf "ufw %s\n" "$*"
        }
        printf "y\n" | do_delete_rule "1-2"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ufw --force delete allow 80/tcp"* ]]
    [[ ! "$output" == *"ufw --force delete allow 80/tcp"*"ufw --force delete allow 80/tcp"* ]]
}

@test "只选 SSH 端口时跳过删除" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 0; builtin command "$@"; }
        sudo() { "$@"; }
        ufw() {
            if [ "$1" = "status" ] && [ $# -eq 1 ]; then printf "Status: active\n"; return; fi
            if [ "$1" = "status" ] && [ "$2" = "numbered" ]; then
                printf "Status: active\n\n     To                         Action      From\n     --                         ------      ----\n[ 1] 80/tcp                      ALLOW IN    Anywhere\n[ 2] 22/tcp                      ALLOW IN    Anywhere\n"
                return
            fi
            printf "ufw %s\n" "$*"
        }
        printf "y\n" | do_delete_rule "2"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"不可删除"* ]]
    [[ ! "$output" == *"ufw --force delete allow 22/tcp"* ]]
}

@test "IP 黑名单拒绝非法格式" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        sudo() { "$@"; }
        ufw() { printf "ufw %s\n" "$*"; }
        printf "%s\n" 999.999.999.999 y | do_block_ip
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"格式无效"* ]]
    [[ ! "$output" == *"ufw deny from"* ]]
}

@test "无 ufw 时操作引导安装并可取消" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "ufw" ] && return 1; builtin command "$@"; }
        printf "%s\n" n | do_open_port
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"未检测到 ufw"* ]]
    [[ "$output" == *"已取消"* ]]
}

@test "软件源刷新失败时常规升级中止" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/security-update.sh"
        sudo() { return 42; }
        printf "%s\\n" y | do_security_update
    '
    [ "$status" -eq 42 ]
    [[ "$output" == *"刷新软件源列表失败，已取消升级"* ]]
}

@test "可更新包扫描只查询一次" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/security-update.sh"
        count_file=$(mktemp)
        apt-get() { printf x >> "$count_file"; printf "Inst foo [0] (1 stable [amd64])\\n"; }
        do_check
        [ "$(wc -c < "$count_file")" -eq 1 ]
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"共 1 个包可更新"* ]]
}

@test "软件更新的 apt 流程直接输出，不套 spinner" {
    run bash -c '
        source "'"$PWD"'/modules/security-update.sh"
        ! grep -q "_with_spinner" "'"$PWD"'/modules/security-update.sh"
        ! grep -q "_start_spinner.*更新软件源" "'"$PWD"'/modules/security-update.sh"
    '
    [ "$status" -eq 0 ]
}

@test "持续输出的安装、测速和证书流程不套 spinner" {
    run grep -E '_with_spinner.*(apt |snap |certbot|docker image prune)' \
        "$PWD/modules/nginx.sh" "$PWD/modules/docker.sh"
    [ "$status" -eq 1 ]
    run grep -q '_with_spinner' "$PWD/modules/network-test.sh"
    [ "$status" -eq 1 ]
}

@test "清理前展示孤立包和缓存占用，并要求确认" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/security-update.sh"
        sudo() {
            [ "$1" = "-v" ] && return 0
            "$@"
        }
        apt-get() {
            case "$1 $2" in
                "-s autoremove") printf "Remv unused-lib [1.0]\n" ;;
                "autoremove -y"|"clean ") printf "apt-get %s %s\n" "$1" "$2" ;;
            esac
        }
        du() { printf "24M /var/cache/apt/archives\n"; }
        journalctl() {
            case "$1" in
                "--disk-usage") printf "Archived and active journal takes 50M in the file system.\n" ;;
                "--vacuum-size") : ;;
            esac
        }
        printf "y\n" | do_cleanup
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"unused-lib"* ]]
    [[ "$output" == *"安装缓存占用: 24M"* ]]
    [[ "$output" == *"系统日志占用: 50M"* ]]
    [[ "$output" == *"孤立包、安装缓存和旧日志已清理"* ]]
}

@test "完整升级预演只执行 apt 模拟命令" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/security-update.sh"
        sudo() { printf "sudo %s\\n" "$*"; }
        do_full_update_preview
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt-get -s full-upgrade"* ]]
}

@test "services 拒绝可能改变 shell 语义的服务名" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/services.sh"
        printf "%s\n" "\"; printf INJECTED; #" | do_status
    '
    [ "$status" -ne 0 ]
    [[ "$output" =~ "服务名格式不合法" ]]
    [[ ! "$output" =~ "INJECTED" ]]
}

@test "服务列表单次查询同时获得状态和总数" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/services.sh"
        count_file=$(mktemp)
        systemctl() {
            printf x >> "$count_file"
            printf "%s\n" \
                "alpha.service loaded active running Alpha" \
                "beta.service loaded failed failed Beta"
        }
        do_list
        [ "$(wc -c < "$count_file")" -eq 1 ]
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "alpha.service" ]]
    [[ "$output" =~ "failed" ]]
    [[ "$output" =~ "共 2 个已加载服务" ]]
}

@test "服务启动失败返回非零" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/services.sh"
        systemctl() { return 42; }
        sudo() { "$@"; }
        do_start demo.service
    '
    [ "$status" -ne 0 ]
    [[ "$output" =~ "启动失败" ]]
}

@test "Docker 启动失败返回非零" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/docker.sh"
        docker() {
            [ "$1" = "info" ] && return 0
            return 42
        }
        do_start demo
    '
    [ "$status" -ne 0 ]
    [[ "$output" =~ "启动失败" ]]
}

@test "进程强制终止失败返回非零" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/port-proc.sh"
        ps() { printf "123 demo process\n"; }
        sleep() { :; }
        kill() {
            case "$1" in
                -0) return 0 ;;
                -9) return 42 ;;
                *) return 0 ;;
            esac
        }
        printf "%s\n" y | do_kill_process 123
    '
    [ "$status" -ne 0 ]
    [[ "$output" =~ "强制终止失败" ]]
}

@test "内存排行终止进程默认回车确认" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/port-proc.sh"
        check_count=0
        ps() { printf "123 demo process\\n"; }
        sleep() { :; }
        kill() {
            if [ "$1" = -0 ]; then
                check_count=$((check_count + 1))
                [ "$check_count" -eq 1 ]
            else
                return 0
            fi
        }
        printf "\\n" | do_kill_process 123 yes
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已发送 SIGTERM" ]]
}

@test "端口列表缓存同一 PID 的进程名" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/port-proc.sh"
        count_file=$(mktemp)
        ss() {
            printf "%s\n" \
                "LISTEN 0 4096 0.0.0.0:8080 0.0.0.0:* users:((\"nginx\",pid=123,fd=6))" \
                "LISTEN 0 4096 0.0.0.0:8081 0.0.0.0:* users:((\"nginx\",pid=123,fd=7))" \
                "LISTEN 0 4096 0.0.0.0:9000 0.0.0.0:* users:((\"app\",pid=456,fd=8))"
        }
        ps() {
            printf x >> "$count_file"
            printf "process"
        }
        do_listen_ports
        [ "$(wc -c < "$count_file")" -eq 2 ]
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "8080" ]]
    [[ "$output" =~ "9000" ]]
}

@test "内存排行按条目缓存 PID 并限制显示数量" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/port-proc.sh"
        ps() {
            printf "%s\\n" \
                "101 root 4096 0.1 init" \
                "202 app 2097152 25.0 api"
        }
        do_list_memory 1
        [ "${#PORT_PROCESS_PIDS[@]}" -eq 1 ]
        [ "${PORT_PROCESS_PIDS[0]}" = 101 ]
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "系统内存总览" ]]
    [[ "$output" =~ "内存占用 Top 1" ]]
    [[ "$output" =~ "4 MiB" ]]
    [[ ! "$output" =~ "api" ]]
}

@test "CPU 排行按条目缓存 PID 并限制显示数量" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/port-proc.sh"
        ps() {
            printf "%s\\n" \
                "101 root 4096 0.1 init 1.2" \
                "202 app 2097152 25.0 api 88.3"
        }
        do_list_cpu 1
        [ "${#PORT_PROCESS_PIDS[@]}" -eq 1 ]
        [ "${PORT_PROCESS_PIDS[0]}" = 101 ]
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "CPU 占用 Top 1" ]]
    [[ "$output" =~ "1.2%" ]]
    [[ ! "$output" =~ "api" ]]
}

@test "内存排行可在页面内刷新" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/port-proc.sh"
        count_file=$(mktemp)
        clear() { :; }
        title() { :; }
        divider() { :; }
        _menu_actions() { printf "%s\\n" "$2"; }
        ss() { :; }
        ps() {
            printf x >> "$count_file"
            printf "%s\\n" "101 root 4096 0.1 init"
        }
        printf "r\\n0\\n" | menu
        [ "$(wc -c < "$count_file")" -eq 2 ]
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "刷新排行" ]]
}

@test "CPU 信息只调用一次 lscpu" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/sys-info.sh"
        count_file=$(mktemp)
        lscpu() {
            printf x >> "$count_file"
            printf "%s\n" "Model name: Test CPU" "CPU(s): 8" "Thread(s) per core: 2"
        }
        top() { printf "%s\n" one two three four five; }
        do_cpu
        [ "$(wc -c < "$count_file")" -eq 1 ]
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Test CPU" ]]
    [[ "$output" =~ "线程" ]]
}

@test "Ping 测试并发收集节点并清理临时目录" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/network-test.sh"
        test_tmp=$(mktemp -d)
        TMPDIR="$test_tmp"
        curl() {
            case "$*" in
                *telecom*) operator="Telecom" ;;
                *unicom*) operator="Unicom" ;;
                *) operator="Mobile" ;;
            esac
            printf "%s\n" "id,a,b,c,d,host,g,h,city,j,operator,l"
            printf "1,2,3,4,5,198.51.100.1:443,7,8,Beijing,10,%s,12\n" "$operator"
        }
        ping() { printf "%s\n" "rtt min/avg/max/mdev = 1.000/2.500/3.000/0.000 ms"; }
        do_ping_test
        [ -z "$(find "$test_tmp" -mindepth 1 -maxdepth 1 -name "kairo-ping.*" -print -quit)" ]
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Telecom" ]]
    [[ "$output" =~ "2.500 ms" ]]
}

@test "网络测速在专用临时目录运行并清理" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/network-test.sh"
        test_tmp=$(mktemp -d)
        trap "rm -rf -- \"\$test_tmp\"" EXIT
        TMPDIR="$test_tmp"
        original_dir=$PWD
        curl() {
            while [ "$#" -gt 0 ]; do
                if [ "$1" = "-o" ]; then
                    printf "%s\\n" "touch speedtest-artifact" "echo MARKER" > "$2"
                    return
                fi
                shift
            done
            return 1
        }
        export -f curl
        do_speedtest
        [ ! -e "$original_dir/speedtest-artifact" ]
        [ -z "$(find "$test_tmp" -mindepth 1 -maxdepth 1 -name "kairo-speedtest.*" -print -quit)" ]
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"MARKER"* ]]
}

@test "回程路由在专用临时目录运行并清理" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/network-test.sh"
        test_tmp=$(mktemp -d)
        trap "rm -rf -- \"\$test_tmp\"" EXIT
        TMPDIR="$test_tmp"
        export test_tmp
        mkdir "$test_tmp/payload"
        printf "%s\\n" "#!/usr/bin/env bash" "exit 0" > "$test_tmp/payload/backtrace"
        chmod +x "$test_tmp/payload/backtrace"
        tar -czf "$test_tmp/backtrace.tar.gz" -C "$test_tmp/payload" backtrace
        curl() {
            while [ "$#" -gt 0 ]; do
                if [ "$1" = "-o" ]; then
                    cp "$test_tmp/backtrace.tar.gz" "$2"
                    return
                fi
                shift
            done
            return 1
        }
        export -f curl
        do_backtrace
        [ -z "$(find "$test_tmp" -mindepth 1 -maxdepth 1 -name "kairo-backtrace.*" -print -quit)" ]
    '
    [ "$status" -eq 0 ]
}

@test "系统网络信息按接口 flags 显示状态" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/sys-info.sh"
        ip() {
            case "$1" in
                -o) case "$2" in
                        -4) printf "2: eth0    inet 192.0.2.10/24 scope global eth0\\n" ;;
                        -6) printf "2: eth0    inet6 2001:db8::10/64 scope global\\n" ;;
                        link) printf "2: eth0@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT\\n" ;;
                    esac ;;
            esac
        }
        do_network
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "IPv4 地址" ]]
    [[ "$output" =~ "192.0.2.10" ]]
    [[ "$output" =~ "IPv6 地址" ]]
    [[ "$output" =~ "2001:db8::10" ]]
    [[ "$output" =~ "eth0             UP" ]]
}

@test "编号菜单范围按可选项数量显示" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        [ "$(kairo_menu_range 3 "管理容器")" = "[1-3] 管理容器" ]
        [ "$(kairo_menu_range 0 "管理容器")" = "[--] 管理容器" ]
    '

    [ "$status" -eq 0 ]
}
