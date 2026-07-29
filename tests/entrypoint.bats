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

@test "all 12 个 modules bash 语法正确" {
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

@test "安装清单完整覆盖运行时文件" {
    while IFS= read -r path; do
        [[ -z "$path" || "$path" == \#* ]] && continue
        [ -f "$PWD/$path" ]
    done < "$PWD/manifest.txt"
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
