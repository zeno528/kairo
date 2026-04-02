#!/bin/bash
# EKKOBOX 安装/卸载脚本
# 安装: curl -fsSL https://raw.githubusercontent.com/Ekko7778/ekkobox/main/install.sh | bash
# 卸载: curl -fsSL https://raw.githubusercontent.com/Ekko7778/ekkobox/main/install.sh | bash -s -- uninstall

set -e

BIN_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/ekkobox"
VERSION_FILE="${LIB_DIR}/VERSION"
REPO="Ekko7778/ekkobox"
BASE_URL="https://raw.githubusercontent.com/${REPO}/main"

# 获取远程版本号
get_remote_version() {
    curl -fsSL "${BASE_URL}/VERSION" 2>/dev/null | tr -d '[:space:]'
}

# 获取本地版本号
get_local_version() {
    cat "$VERSION_FILE" 2>/dev/null | tr -d '[:space:]' || echo "未安装"
}

# 卸载
if [ "$1" = "uninstall" ]; then
    local_ver=$(get_local_version)
    echo ">>> 卸载 EKKOBOX v${local_ver}..."
    for f in "$LIB_DIR/modules"/*.sh; do
        [ -f "$f" ] || continue
        alias_name=$(grep -oP '(?<=alias:\s*)\S+' "$f" || true)
        [ -n "$alias_name" ] && rm -f "${BIN_DIR}/${alias_name}"
    done
    rm -f "${BIN_DIR}/eb"
    rm -rf "$LIB_DIR"
    echo ">>> 卸载完成"
    exit 0
fi

# 版本检查
remote_ver=$(get_remote_version)
local_ver=$(get_local_version)

if [ "$local_ver" = "未安装" ]; then
    echo ">>> 首次安装 EKKOBOX v${remote_ver}..."
elif [ "$local_ver" = "$remote_ver" ]; then
    echo ">>> EKKOBOX 已是最新版本 v${remote_ver}"
    exit 0
else
    echo ">>> 更新 EKKOBOX v${local_ver} → v${remote_ver}..."
fi

mkdir -p "$LIB_DIR/modules"

# 下载主入口
curl -fsSL "${BASE_URL}/ekkobox.sh" -o "${BIN_DIR}/eb"
chmod +x "${BIN_DIR}/eb"
echo "  安装: eb (主菜单)"

# 下载模块
MODULES=("modules/ssh-passwd.sh")
for mod_path in "${MODULES[@]}"; do
    mod_file=$(basename "$mod_path")
    curl -fsSL "${BASE_URL}/${mod_path}" -o "${LIB_DIR}/${mod_path}"
    chmod +x "${LIB_DIR}/${mod_path}"
    alias_name=$(grep -oP '(?<=alias:\s*)\S+' "${LIB_DIR}/${mod_path}" || true)
    if [ -n "$alias_name" ]; then
        ln -sf "${LIB_DIR}/${mod_path}" "${BIN_DIR}/${alias_name}"
        echo "  安装: ${alias_name}"
    fi
done

# 保存版本号
echo "$remote_ver" > "$VERSION_FILE"

echo ">>> 完成！EKKOBOX v${remote_ver}"
echo ""
echo "  主菜单: eb"
echo "  快捷命令:"
for f in "$LIB_DIR/modules"/*.sh; do
    [ -f "$f" ] || continue
    alias_name=$(grep -oP '(?<=alias:\s*)\S+' "$f" || true)
    [ -n "$alias_name" ] && echo "    ${alias_name}"
done
