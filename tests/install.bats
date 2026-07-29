#!/usr/bin/env bats
# 测试目标: install.sh 的固定提交下载、修复安装、清理和失败保护。

setup() {
    export TEST_TMP
    TEST_TMP=$(mktemp -d)
    export KAIRO_BIN_DIR="${TEST_TMP}/bin"
    export KAIRO_LIB_DIR="${TEST_TMP}/lib/kairo"
    export KAIRO_LEGACY_LIB_DIR="${TEST_TMP}/lib/opstool"
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

@test "远程卸载清理新旧运行时" {
    mkdir -p "$KAIRO_LIB_DIR" "$KAIRO_LEGACY_LIB_DIR"
    touch "${KAIRO_BIN_DIR}/ka" "${KAIRO_BIN_DIR}/ot"
    printf '1.1.3\n' > "${KAIRO_LIB_DIR}/VERSION"

    run bash "$PWD/install.sh" uninstall
    [ "$status" -eq 0 ]
    [[ "$output" =~ "运行文件已全部清理" ]]
    [ ! -e "${KAIRO_BIN_DIR}/ka" ]
    [ ! -e "${KAIRO_BIN_DIR}/ot" ]
    [ ! -e "$KAIRO_LIB_DIR" ]
    [ ! -e "$KAIRO_LEGACY_LIB_DIR" ]
}
