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

@test "iptables 关闭端口删除对应 ACCEPT 规则" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        FW=iptables
        sudo() { "$@"; }
        iptables() { printf "iptables %s\\n" "$*"; }
        printf "%s\\n" 8080 tcp y | do_close_port
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"iptables -D INPUT -p tcp --dport 8080 -j ACCEPT"* ]]
    [[ "$output" == *"已移除 8080/tcp 的放行规则"* ]]
}

@test "iptables 全局启停返回失败而非伪成功" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/firewall.sh"
        FW=iptables
        do_enable
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"不支持全局开启"* ]]
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

@test "完整升级预演只执行 apt 模拟命令" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/security-update.sh"
        sudo() { printf "sudo %s\\n" "$*"; }
        do_full_update_preview
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt -s full-upgrade"* ]]
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

@test "系统网络信息按接口 flags 显示状态" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/sys-info.sh"
        ip() {
            case "$1" in
                -4) printf "    inet 192.0.2.10/24\\n" ;;
                -o) printf "2: eth0@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT\\n" ;;
            esac
        }
        do_network
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "eth0             UP" ]]
}

# ─── _with_spinner ──────────────────────────────────────────

@test "公共库定义了 _with_spinner 函数" {
    grep -q '^_with_spinner()' "$PWD/lib/core.sh"
}

@test "_with_spinner 非终端模式透传命令输出" {
    run bash -c '
        C_CYAN=""; C_RESET=""
        eval "$(sed -n "/^_with_spinner()/,/^}/p" "'"$PWD"'"/lib/core.sh)"
        _with_spinner "test" echo "hello world"
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "hello world" ]]
}

@test "_with_spinner 非终端模式透传退出码" {
    run bash -c '
        C_CYAN=""; C_RESET=""
        eval "$(sed -n "/^_with_spinner()/,/^}/p" "'"$PWD"'"/lib/core.sh)"
        _with_spinner "test" false
    '
    [ "$status" -eq 1 ]
}

@test "_with_spinner 非终端模式透传多行输出" {
    run bash -c '
        C_CYAN=""; C_RESET=""
        eval "$(sed -n "/^_with_spinner()/,/^}/p" "'"$PWD"'"/lib/core.sh)"
        _with_spinner "test" printf "a\nb\nc\n"
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "a" ]]
    [[ "$output" =~ "b" ]]
    [[ "$output" =~ "c" ]]
}
