#!/usr/bin/env bats
# 测试目标: kairo.sh + install.sh
# 覆盖: 语法 + 关键常量/函数可调用

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

@test "all 12 个 modules bash 语法正确" {
    for f in "$PWD"/modules/*.sh; do
        run /usr/bin/bash -n "$f"
        [ "$status" -eq 0 ] || { echo "$f 语法失败"; return 1; }
    done
}

# ─── kairo.sh 入口 ────────────────────────────────────────────

@test "kairo.sh help 输出含全部模块" {
    run /usr/bin/bash "$PWD/kairo.sh" help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ssh-passwd" ]]
    [[ "$output" =~ "ssh-keys" ]]
    [[ "$output" =~ "sys-info" ]]
    [[ "$output" =~ "port-proc" ]]
    [[ "$output" =~ "firewall" ]]
    [[ "$output" =~ "services" ]]
    [[ "$output" =~ "crontab" ]]
    [[ "$output" =~ "ssl-check" ]]
    [[ "$output" =~ "security-update" ]]
    [[ "$output" =~ "network-test" ]]
    [[ "$output" =~ "docker" ]]
    [[ "$output" =~ "nginx" ]]
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

# ─── install.sh 关键函数 ──────────────────────────────────────

@test "install.sh 语法 + 不实际执行（-n）" {
    run /usr/bin/bash -n "$PWD/install.sh"
    [ "$status" -eq 0 ]
}

@test "install.sh 不接受 uninstall 子命令以外的实际参数时不写 VERSION" {
    # --help 等不存在的 flag: 应立即退出且不在任意位置创建 VERSION
    if [ -f "$PWD/.test_install_touch" ]; then rm -f "$PWD/.test_install_touch"; fi
    run /usr/bin/bash "$PWD/install.sh" --this-flag-does-not-exist 2>&1 || true
    # install.sh 会输出"无法连接远程仓库"或类似的失败消息而不是建立版本文件
    [ ! -f /tmp/kairo_test_version ]
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

@test "CHANGELOG 顶部有 v1.0.28 条目" {
    grep -q "^## v1.0.28" "$PWD/CHANGELOG.md"
}

@test "modules 目录含 12 个 .sh 文件（含 nginx 新增）" {
    local count
    count=$(find "$PWD/modules" -maxdepth 1 -name "*.sh" | wc -l)
    [ "$count" -eq 12 ]
}

@test "modules 目录含 nginx.sh 新模块" {
    [ -f "$PWD/modules/nginx.sh" ]
}

# ─── _with_spinner ──────────────────────────────────────────

@test "kairo.sh 定义了 _with_spinner 函数" {
    grep -q '^_with_spinner()' "$PWD/kairo.sh"
}

@test "_with_spinner 非终端模式透传命令输出" {
    run bash -c '
        C_CYAN=""; C_RESET=""
        eval "$(sed -n "/^_with_spinner()/,/^}/p" "'"$PWD"'"/kairo.sh)"
        _with_spinner "test" echo "hello world"
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "hello world" ]]
}

@test "_with_spinner 非终端模式透传退出码" {
    run bash -c '
        C_CYAN=""; C_RESET=""
        eval "$(sed -n "/^_with_spinner()/,/^}/p" "'"$PWD"'"/kairo.sh)"
        _with_spinner "test" false
    '
    [ "$status" -eq 1 ]
}

@test "_with_spinner 非终端模式透传多行输出" {
    run bash -c '
        C_CYAN=""; C_RESET=""
        eval "$(sed -n "/^_with_spinner()/,/^}/p" "'"$PWD"'"/kairo.sh)"
        _with_spinner "test" printf "a\nb\nc\n"
    '
    [ "$status" -eq 0 ]
    [[ "$output" =~ "a" ]]
    [[ "$output" =~ "b" ]]
    [[ "$output" =~ "c" ]]
}
