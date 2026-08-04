#!/usr/bin/env bats
# 测试目标: install.sh 的固定提交下载、修复安装、清理和失败保护。

setup() {
    export TEST_TMP
    TEST_TMP=$(mktemp -d)
    export KAIRO_BIN_DIR="${TEST_TMP}/bin"
    export KAIRO_LIB_DIR="${TEST_TMP}/lib/kairo"
    export KAIRO_RELEASE_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    export MOCK_REPO_ROOT="$PWD"
    mkdir -p "$KAIRO_BIN_DIR" "${TEST_TMP}/lib" "${TEST_TMP}/mock-bin"

    cat > "${TEST_TMP}/mock-bin/curl" <<'MOCK'
#!/usr/bin/env bash
url="${*: -1}"
[[ "$url" == *"raw.githubusercontent.com/"* ]] || exit 22
path="${url#*${KAIRO_RELEASE_SHA}/}"
if [ -n "${MOCK_FAIL_PATH:-}" ] && [ "$path" = "$MOCK_FAIL_PATH" ]; then
    exit 22
fi
if [ -n "${MOCK_CORRUPT_PATH:-}" ] && [ "$path" = "$MOCK_CORRUPT_PATH" ]; then
    printf 'this is not valid bash (\n'
    exit 0
fi
if [ "$path" = "VERSION" ] && [ -n "${MOCK_REMOTE_VERSION:-}" ]; then
    printf '%s\n' "$MOCK_REMOTE_VERSION"
    exit 0
fi
cat "${MOCK_REPO_ROOT}/${path}"
MOCK
    chmod +x "${TEST_TMP}/mock-bin/curl"
    export PATH="${TEST_TMP}/mock-bin:/usr/bin:/bin"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "安装器从同一提交完成 staging 部署" {
    run bash "$PWD/install.sh"
    [ "$status" -eq 0 ]
    [ -x "${KAIRO_BIN_DIR}/ka" ]
    [ -s "${KAIRO_LIB_DIR}/VERSION" ]
    [ -s "${KAIRO_LIB_DIR}/lib/core.sh" ]
    [ -s "${KAIRO_LIB_DIR}/modules/registry.sh" ]
}

@test "同版本安装会修复缺失文件并清理旧模块" {
    run bash "$PWD/install.sh"
    [ "$status" -eq 0 ]
    rm -f "${KAIRO_LIB_DIR}/lib/core.sh"
    touch "${KAIRO_LIB_DIR}/modules/removed-module.sh"

    run bash "$PWD/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "校验并修复" ]]
    [ -s "${KAIRO_LIB_DIR}/lib/core.sh" ]
    [ ! -e "${KAIRO_LIB_DIR}/modules/removed-module.sh" ]
}

@test "可写的自定义安装目录不请求 sudo" {
    export SUDO_LOG="${TEST_TMP}/sudo.log"
    cat > "${TEST_TMP}/mock-bin/id" <<'MOCK'
#!/usr/bin/env bash
printf '1000\n'
MOCK
    cat > "${TEST_TMP}/mock-bin/sudo" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SUDO_LOG"
[ "${1:-}" = "-v" ] && exit 0
exec "$@"
MOCK
    chmod +x "${TEST_TMP}/mock-bin/id" "${TEST_TMP}/mock-bin/sudo"

    run bash "$PWD/install.sh"

    [ "$status" -eq 0 ]
    [ ! -s "$SUDO_LOG" ]
}

@test "升级完成提示新版本并提示 ka 命令" {
    mkdir -p "$KAIRO_LIB_DIR"
    printf '1.1.30\n' > "${KAIRO_LIB_DIR}/VERSION"
    export MOCK_REMOTE_VERSION="1.1.31"

    run bash "$PWD/install.sh"

    [ "$status" -eq 0 ]
    plain_output=$(printf '%s' "$output" | sed -E $'s/\x1B\\[[0-9;]*m//g')
    [[ "$plain_output" =~ "升级完成！v1.1.31" ]]
    [[ "$plain_output" =~ "进入主菜单" ]]
    [[ "$plain_output" =~ $'  >>> 下载' ]]
    [[ "$plain_output" =~ $'  >>> 🎉 Kairo' ]]
    [ "$(tr -d '[:space:]' < "${KAIRO_LIB_DIR}/VERSION")" = "1.1.31" ]
}

@test "下载中途失败时保留现有安装" {
    mkdir -p "${KAIRO_LIB_DIR}/lib"
    printf 'old-runtime\n' > "${KAIRO_LIB_DIR}/lib/core.sh"
    printf 'old-bin\n' > "${KAIRO_BIN_DIR}/ka"
    export MOCK_FAIL_PATH="modules/docker.sh"

    run bash "$PWD/install.sh"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "未修改现有安装" ]]
    [ "$(cat "${KAIRO_LIB_DIR}/lib/core.sh")" = "old-runtime" ]
    [ "$(cat "${KAIRO_BIN_DIR}/ka")" = "old-bin" ]
}

@test "暂存文件语法校验失败时保留现有安装" {
    mkdir -p "${KAIRO_LIB_DIR}/lib"
    printf 'old-runtime\n' > "${KAIRO_LIB_DIR}/lib/core.sh"
    printf 'old-bin\n' > "${KAIRO_BIN_DIR}/ka"
    export MOCK_CORRUPT_PATH="modules/docker.sh"

    run bash "$PWD/install.sh"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "校验失败" ]]
    [ "$(cat "${KAIRO_LIB_DIR}/lib/core.sh")" = "old-runtime" ]
    [ "$(cat "${KAIRO_BIN_DIR}/ka")" = "old-bin" ]
}

@test "远程卸载清理运行时" {
    mkdir -p "$KAIRO_LIB_DIR"
    touch "${KAIRO_BIN_DIR}/ka"
    printf '1.1.3\n' > "${KAIRO_LIB_DIR}/VERSION"

    run bash "$PWD/install.sh" uninstall
    [ "$status" -eq 0 ]
    [[ "$output" =~ "运行文件已全部清理" ]]
    [ ! -e "${KAIRO_BIN_DIR}/ka" ]
    [ ! -e "$KAIRO_LIB_DIR" ]
}
