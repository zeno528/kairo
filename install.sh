#!/usr/bin/env bash
# KAIRO 安装/卸载脚本
# 安装: curl -fsSL https://raw.githubusercontent.com/zeno528/kairo/main/install.sh | bash
# 卸载: curl -fsSL https://raw.githubusercontent.com/zeno528/kairo/main/install.sh | bash -s -- uninstall

set -Eeuo pipefail

BIN_DIR="${KAIRO_BIN_DIR:-/usr/local/bin}"
LIB_DIR="${KAIRO_LIB_DIR:-/usr/local/lib/kairo}"
VERSION_FILE="${LIB_DIR}/VERSION"
REPO="${KAIRO_REPO:-zeno528/kairo}"
KAIRO_BRANCH="${KAIRO_BRANCH:-main}"
API_URL="https://api.github.com/repos/${REPO}"
RAW_URL="https://raw.githubusercontent.com/${REPO}"
MANIFEST_PATH="manifest.txt"
STAGE_DIR=""
DOWNLOAD_JOBS=4
DOWNLOAD_PIDS=()
DOWNLOAD_PATHS=()
KAIRO_NEEDS_SUDO=0

cleanup_stage() {
    if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
        rm -rf -- "$STAGE_DIR"
    fi
}
trap cleanup_stage EXIT

validate_install_paths() {
    local path
    for path in "$BIN_DIR" "$LIB_DIR"; do
        case "$path" in
            /*) ;;
            *)
                echo ">>> 安装路径必须是绝对路径: $path" >&2
                exit 1
                ;;
        esac
        case "${path%/}" in
            ""|/|/usr|/usr/local|/etc|/var|/opt|/home)
                echo ">>> 拒绝使用过宽的安装路径: $path" >&2
                exit 1
                ;;
        esac
    done
}

require_install_permissions() {
    local bin_parent lib_parent
    [ "$(id -u)" -eq 0 ] && return 0
    bin_parent=$(dirname "$BIN_DIR")
    lib_parent=$(dirname "$LIB_DIR")
    if ! { [ -e "$BIN_DIR" ] && [ -w "$BIN_DIR" ]; } &&
       ! { [ ! -e "$BIN_DIR" ] && [ -w "$bin_parent" ]; } ||
       [ ! -w "$lib_parent" ]; then
        KAIRO_NEEDS_SUDO=1
    fi
    [ "$KAIRO_NEEDS_SUDO" -eq 0 ] && return 0
    sudo -v || {
        echo ">>> 安装需要 sudo 权限" >&2
        exit 1
    }
}

run_privileged() {
    if [ "$KAIRO_NEEDS_SUDO" -eq 1 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

validate_install_paths

resolve_release_sha() {
    local sha="${KAIRO_RELEASE_SHA:-}"
    if [ -z "$sha" ]; then
        sha=$(curl --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 1 \
            -fsSL "${API_URL}/commits/${KAIRO_BRANCH}?t=$(date +%s)" |
            sed -n 's/^[[:space:]]*"sha": "\([0-9a-f]\{40\}\)",/\1/p' |
            awk 'NR == 1 { first=$0 } END { print first }')
    fi
    if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
        echo ">>> 无法解析发布提交，已取消安装" >&2
        return 1
    fi
    printf '%s' "$sha"
}

fetch_remote_file() {
    local path="$1" ref="$2"
    curl --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 \
        -fsSL "${RAW_URL}/${ref}/${path}"
}

download_remote_file() {
    local path="$1" destination="$2" ref="$3"
    local tmp_file
    mkdir -p "$(dirname "$destination")"
    tmp_file=$(mktemp "${destination}.tmp.XXXXXX")
    if ! fetch_remote_file "$path" "$ref" > "$tmp_file"; then
        rm -f -- "$tmp_file"
        return 1
    fi
    mv -- "$tmp_file" "$destination"
}

wait_download_batch() {
    local index failed=0

    for index in "${!DOWNLOAD_PIDS[@]}"; do
        if wait "${DOWNLOAD_PIDS[$index]}"; then
            COUNT=$((COUNT + 1))
            printf "\r  下载: %-25s [%d/%d]" "${DOWNLOAD_PATHS[$index]}" "$COUNT" "$TOTAL"
        else
            echo ""
            echo ">>> 下载失败: ${DOWNLOAD_PATHS[$index]}，未修改现有安装" >&2
            failed=1
        fi
    done
    DOWNLOAD_PIDS=()
    DOWNLOAD_PATHS=()
    return "$failed"
}

get_local_version() {
    if [ -s "$VERSION_FILE" ]; then
        tr -d '[:space:]' < "$VERSION_FILE"
    else
        echo "未安装"
    fi
}

normalize_manifest() {
    sed 's/\r$//;/^[[:space:]]*#/d;/^[[:space:]]*$/d'
}

validate_manifest_path() {
    local path="$1"
    case "$path" in
        *..*|/*|*//*|*[!a-zA-Z0-9._/-]*) return 1 ;;
        kairo.sh|VERSION|lib/*.sh|modules/*.sh) return 0 ;;
        *) return 1 ;;
    esac
}

validate_staged_release() {
    local runtime_dir="$1" bin_file="$2" path
    local manifest_modules="${STAGE_DIR}/manifest.modules"
    local registry_modules="${STAGE_DIR}/registry.modules"
    [ -s "$bin_file" ] || return 1
    [ -s "${runtime_dir}/VERSION" ] || return 1
    [ -s "${runtime_dir}/lib/core.sh" ] || return 1
    [ -s "${runtime_dir}/modules/registry.sh" ] || return 1

    if sort "${STAGE_DIR}/manifest.normalized" | uniq -d | grep -q .; then
        echo ">>> 安装清单包含重复路径" >&2
        return 1
    fi
    sed -n 's#^modules/\([^/]*\)\.sh$#\1#p' "${STAGE_DIR}/manifest.normalized" |
        sed '/^registry$/d' |
        sort > "$manifest_modules"
    sed -n 's/^kairo_register_module \([^[:space:]]*\).*/\1/p' \
        "${runtime_dir}/modules/registry.sh" |
        sort > "$registry_modules"
    if ! diff -u "$registry_modules" "$manifest_modules" >/dev/null; then
        echo ">>> 安装清单与模块注册表不一致" >&2
        return 1
    fi

    bash -n "$bin_file" || return 1
    while IFS= read -r path; do
        case "$path" in
            *.sh)
                if [ "$path" = "kairo.sh" ]; then
                    bash -n "$bin_file" || return 1
                else
                    bash -n "${runtime_dir}/${path}" || return 1
                fi
                ;;
        esac
    done < "${STAGE_DIR}/manifest.normalized"
}

deploy_staged_release() {
    local runtime_dir="$1" bin_file="$2" lib_parent
    local new_runtime backup_runtime new_bin backup_bin had_runtime=0 had_bin=0

    lib_parent=$(dirname "$LIB_DIR")
    run_privileged mkdir -p "$BIN_DIR" "$lib_parent"
    new_runtime=$(run_privileged mktemp -d "${lib_parent}/.kairo-runtime.XXXXXX") || return 1
    new_bin=$(run_privileged mktemp "${BIN_DIR}/.ka.new.XXXXXX") || {
        run_privileged rm -rf -- "$new_runtime"
        return 1
    }
    run_privileged cp -a "${runtime_dir}/." "$new_runtime/" || return 1
    run_privileged install -m 755 "$bin_file" "$new_bin" || return 1

    if [ -e "${BIN_DIR}/ka" ]; then
        backup_bin=$(run_privileged mktemp "${BIN_DIR}/.ka.backup.XXXXXX") || return 1
        run_privileged cp -p -- "${BIN_DIR}/ka" "$backup_bin" || return 1
        had_bin=1
    fi
    if [ -e "$LIB_DIR" ]; then
        backup_runtime=$(run_privileged mktemp -d "${lib_parent}/.kairo-backup.XXXXXX") || return 1
        run_privileged rmdir "$backup_runtime" || return 1
        run_privileged mv -- "$LIB_DIR" "$backup_runtime" || return 1
        had_runtime=1
    fi

    if ! run_privileged mv -- "$new_runtime" "$LIB_DIR" || ! run_privileged mv -- "$new_bin" "${BIN_DIR}/ka"; then
        echo ">>> 部署失败，正在恢复上一版本" >&2
        run_privileged rm -rf -- "$LIB_DIR"
        [ "$had_runtime" -eq 1 ] && run_privileged mv -- "$backup_runtime" "$LIB_DIR"
        if [ "$had_bin" -eq 1 ]; then
            run_privileged cp -p -- "$backup_bin" "${BIN_DIR}/ka"
        else
            run_privileged rm -f -- "${BIN_DIR}/ka"
        fi
        run_privileged rm -f -- "$new_bin"
        return 1
    fi
    [ "$had_runtime" -eq 1 ] && run_privileged rm -rf -- "$backup_runtime"
    [ "$had_bin" -eq 1 ] && run_privileged rm -f -- "$backup_bin"
    return 0
}

if [ "${1:-}" = "uninstall" ]; then
    require_install_permissions
    local_ver=$(get_local_version)
    echo ">>> 卸载 Kairo v${local_ver}..."
    run_privileged rm -f -- "${BIN_DIR}/ka" || {
        echo ">>> 删除命令入口失败" >&2
        exit 1
    }
    run_privileged rm -rf -- "$LIB_DIR" || {
        echo ">>> 删除运行库失败" >&2
        exit 1
    }
    # 清理 Kairo 运行时缓存（发布日期等；丢失会自动重建）
    run_privileged rm -rf -- /var/cache/kairo 2>/dev/null || true
    for target in "${BIN_DIR}/ka" "$LIB_DIR"; do
        if [ -e "$target" ] || [ -L "$target" ]; then
            echo ">>> 卸载后仍有残留: $target" >&2
            exit 1
        fi
    done
    echo ">>> 卸载完成，Kairo 运行文件已全部清理"
    echo ">>> Nginx、SSH、防火墙、证书等业务配置已保留"
    exit 0
fi

require_install_permissions
release_sha=$(resolve_release_sha)
local_ver=$(get_local_version)

STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kairo-stage.XXXXXX")
runtime_dir="${STAGE_DIR}/runtime"
bin_file="${STAGE_DIR}/ka"
mkdir -p "$runtime_dir"

fetch_remote_file "$MANIFEST_PATH" "$release_sha" | normalize_manifest > "${STAGE_DIR}/manifest.normalized"
if [ ! -s "${STAGE_DIR}/manifest.normalized" ]; then
    echo ">>> 无法获取有效安装清单，已取消安装" >&2
    exit 1
fi

TOTAL=$(wc -l < "${STAGE_DIR}/manifest.normalized")
COUNT=0
while IFS= read -r path; do
    if ! validate_manifest_path "$path"; then
        echo ">>> 安装清单包含非法路径: $path" >&2
        exit 1
    fi
    case "$path" in
        kairo.sh) destination="$bin_file" ;;
        *) destination="${runtime_dir}/${path}" ;;
    esac
    download_remote_file "$path" "$destination" "$release_sha" &
    DOWNLOAD_PIDS+=("$!")
    DOWNLOAD_PATHS+=("$path")
    if [ "${#DOWNLOAD_PIDS[@]}" -ge "$DOWNLOAD_JOBS" ]; then
        wait_download_batch || exit 1
    fi
done < "${STAGE_DIR}/manifest.normalized"
wait_download_batch || exit 1
echo ""

remote_ver=$(tr -d '[:space:]' < "${runtime_dir}/VERSION")
if [[ ! "$remote_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo ">>> 发布版本号无效，未修改现有安装" >&2
    exit 1
fi

if ! validate_staged_release "$runtime_dir" "$bin_file"; then
    echo ">>> 发布文件校验失败，未修改现有安装" >&2
    exit 1
fi

if [ "$local_ver" = "未安装" ]; then
    echo ">>> 首次安装 Kairo v${remote_ver}..."
elif [ "$local_ver" = "$remote_ver" ]; then
    echo ">>> 校验并修复 Kairo v${remote_ver}..."
fi

chmod 644 "${runtime_dir}/VERSION"
find "${runtime_dir}/lib" "${runtime_dir}/modules" -type f -name '*.sh' -exec chmod 755 {} +
deploy_staged_release "$runtime_dir" "$bin_file"

if [ "$local_ver" = "未安装" ]; then
    done_msg="安装完成"
elif [ "$local_ver" = "$remote_ver" ]; then
    done_msg="修复完成"
else
    done_msg="升级完成"
fi
echo -e ">>> 🎉 \033[1mKairo\033[0m ${done_msg}！\033[1;32mv${remote_ver} (${release_sha:0:7})\033[0m"
echo ""
echo -e "  \033[1m💡 输入 \033[1;36mka\033[0m\033[1m 进入主菜单\033[0m"
