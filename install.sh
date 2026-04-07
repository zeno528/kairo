#!/bin/bash
# OPSTOOL 安装/卸载脚本
# 安装: curl -fsSL https://raw.githubusercontent.com/Ekko7778/opstool/main/install.sh | bash
# 卸载: curl -fsSL https://raw.githubusercontent.com/Ekko7778/opstool/main/install.sh | bash -s -- uninstall

set -e

BIN_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/opstool"
VERSION_FILE="${LIB_DIR}/VERSION"
REPO="Ekko7778/opstool"
BASE_URL="https://raw.githubusercontent.com/${REPO}/main"

# 获取远程版本号
get_remote_version() {
    curl -fsSL "${BASE_URL}/VERSION?t=$(date +%s)" 2>/dev/null | tr -d '[:space:]'
}

# 获取本地版本号
get_local_version() {
    cat "$VERSION_FILE" 2>/dev/null | tr -d '[:space:]' || echo "未安装"
}

# 卸载
if [ "$1" = "uninstall" ]; then
    local_ver=$(get_local_version)
    echo ">>> 卸载 OPSTOOL v${local_ver}..."
    for f in "$LIB_DIR/modules"/*.sh; do
        [ -f "$f" ] || continue
        alias_name=$(grep -oP 'alias:\s*\K\S+' "$f" 2>/dev/null) || true
        [ -n "$alias_name" ] && rm -f "${BIN_DIR}/${alias_name}"
    done
    rm -f "${BIN_DIR}/ot"
    rm -rf "$LIB_DIR"
    echo ">>> 卸载完成"
    exit 0
fi

# 版本检查
remote_ver=$(get_remote_version)
local_ver=$(get_local_version)

if [ "$local_ver" = "未安装" ]; then
    echo ">>> 首次安装 OPSTOOL v${remote_ver}..."
elif [ "$local_ver" = "$remote_ver" ]; then
    echo ">>> OPSTOOL 已是最新版本 v${remote_ver}"
    exit 0
else
    echo ">>> 更新 OPSTOOL v${local_ver} → v${remote_ver}..."
fi

mkdir -p "$LIB_DIR/modules"

# 下载主入口
curl -fsSL "${BASE_URL}/opstool.sh?t=$(date +%s)" -o "${BIN_DIR}/ot"
chmod +x "${BIN_DIR}/ot"
echo "  安装: ot (主菜单)"

# 动态获取远程模块列表
MODULES=$(curl -fsSL "https://api.github.com/repos/${REPO}/contents/modules" | grep -oP '"name":\s*"\K[^"]+\.sh')
if [ -z "$MODULES" ]; then
    echo "  警告: 无法获取模块列表，跳过模块安装"
else
    for mod_name in $MODULES; do
        mod_path="modules/${mod_name}"
        curl -fsSL "${BASE_URL}/${mod_path}?t=$(date +%s)" -o "${LIB_DIR}/${mod_path}"
        chmod +x "${LIB_DIR}/${mod_path}"
        echo "  安装: ${mod_name}"
    done
fi

# 保存版本号
echo "$remote_ver" > "$VERSION_FILE"

echo ">>> 完成！OPSTOOL v${remote_ver}"
echo ""
echo "  主菜单: ot"
