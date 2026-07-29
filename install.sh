#!/bin/bash
# KAIRO 安装/卸载脚本
# 安装: curl -fsSL -H 'Accept: application/vnd.github.raw+json' 'https://api.github.com/repos/zeno528/kairo/contents/install.sh?ref=main' | bash
# 卸载: curl -fsSL -H 'Accept: application/vnd.github.raw+json' 'https://api.github.com/repos/zeno528/kairo/contents/install.sh?ref=main' | bash -s -- uninstall

set -e

BIN_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/kairo"
LEGACY_LIB_DIR="/usr/local/lib/opstool"
VERSION_FILE="${LIB_DIR}/VERSION"
REPO="zeno528/kairo"
CONTENTS_URL="https://api.github.com/repos/${REPO}/contents"
MANIFEST_PATH="manifest.txt"

# 通过 GitHub Contents API 下载 main 分支文件，避免 raw CDN 返回陈旧缓存。
fetch_remote_file() {
    local path="$1"
    curl -fsSL -H "Accept: application/vnd.github.raw+json" \
        "${CONTENTS_URL}/${path}?ref=main&t=$(date +%s)"
}

download_remote_file() {
    local path="$1"
    local destination="$2"
    local tmp_file
    mkdir -p "$(dirname "$destination")"
    tmp_file=$(mktemp "${destination}.tmp.XXXXXX")
    if ! fetch_remote_file "$path" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    mv "$tmp_file" "$destination"
}

# 获取远程版本号
get_remote_version() {
    fetch_remote_file VERSION 2>/dev/null | tr -d '[:space:]'
}

# 获取本地版本号
get_local_version() {
    cat "$VERSION_FILE" 2>/dev/null | tr -d '[:space:]' || echo "未安装"
}

# 卸载
if [ "$1" = "uninstall" ]; then
    local_ver=$(get_local_version)
    echo ">>> 卸载 KAIRO v${local_ver}..."
    rm -f "${BIN_DIR}/ka"
    rm -rf "$LIB_DIR"
    rm -rf "$LEGACY_LIB_DIR"
    echo ">>> 卸载完成"
    exit 0
fi

# 版本检查
remote_ver=$(get_remote_version)
local_ver=$(get_local_version)

if [ "$local_ver" = "未安装" ]; then
    echo ">>> 首次安装 KAIRO v${remote_ver}..."
elif [ "$local_ver" = "$remote_ver" ]; then
    echo ">>> KAIRO 已是最新版本 v${remote_ver}"
    exit 0
else
    echo ">>> 更新 KAIRO v${local_ver} → v${remote_ver}..."
fi

manifest=$(fetch_remote_file "$MANIFEST_PATH")
if [ -z "$manifest" ]; then
    echo ">>> 无法获取安装清单，已取消安装" >&2
    exit 1
fi

TOTAL=$(printf '%s\n' "$manifest" | sed '/^#/d;/^[[:space:]]*$/d' | wc -l)
COUNT=0
while IFS= read -r path; do
    [ -z "$path" ] && continue
    case "$path" in
        \#*) continue ;;
        kairo.sh) destination="${BIN_DIR}/ka" ;;
        VERSION|lib/*.sh|modules/*.sh) destination="${LIB_DIR}/${path}" ;;
        *)
            echo ">>> 安装清单包含非法路径: $path" >&2
            exit 1
            ;;
    esac
    case "$path" in
        *..*|/*)
            echo ">>> 安装清单包含非法路径: $path" >&2
            exit 1
            ;;
    esac
    download_remote_file "$path" "$destination"
    chmod +x "$destination"
    COUNT=$((COUNT + 1))
    printf "\r  安装: %-25s [%d/%d]" "$path" "$COUNT" "$TOTAL"
done <<EOF
$manifest
EOF
echo ""

# 清理旧版本的快捷入口，避免同一工具保留两个命令。
rm -f "${BIN_DIR}/ot"

# 保存版本号
# 完成 Kairo 安装后再清理旧运行库，保证旧版本用户可平滑迁移。
rm -rf "$LEGACY_LIB_DIR"

echo -e "\033[1;32m>>> 🎉 完成！KAIRO v${remote_ver}\033[0m"
echo ""
echo "  主菜单: ka"
