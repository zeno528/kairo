#!/bin/bash
# install.sh - vps-toolkit 安装/卸载脚本
# 安装: curl -fsSL https://raw.githubusercontent.com/Ekko7778/vps-toolkit/main/install.sh | bash
# 卸载: curl -fsSL https://raw.githubusercontent.com/Ekko7778/vps-toolkit/main/install.sh | bash -s -- uninstall

set -e

BIN_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/vps-toolkit"
REPO="Ekko7778/vps-toolkit"
BASE_URL="https://raw.githubusercontent.com/${REPO}/main"

# 卸载
if [ "$1" = "uninstall" ]; then
    echo ">>> 卸载 vps-toolkit..."
    # 删除模块快捷命令
    for f in "$LIB_DIR/modules"/*.sh; do
        [ -f "$f" ] || continue
        alias_name=$(grep -oP '(?<=alias:\s*)\S+' "$f" || true)
        [ -n "$alias_name" ] && rm -f "${BIN_DIR}/${alias_name}"
    done
    rm -f "${BIN_DIR}/vps"
    rm -rf "$LIB_DIR"
    echo ">>> 卸载完成"
    exit 0
fi

# 安装/更新
echo ">>> 安装 vps-toolkit..."
mkdir -p "$LIB_DIR/modules"

# 下载主入口
curl -fsSL "${BASE_URL}/vps-toolkit.sh" -o "${BIN_DIR}/vps"
chmod +x "${BIN_DIR}/vps"
echo "  安装: vps (主菜单)"

# 下载模块
for f in $(curl -fsSL "${BASE_URL}/modules/" 2>/dev/null | grep -oP '(?<=href=")[^"]+\.sh(?=")' || true); do
    curl -fsSL "${BASE_URL}/modules/${f}" -o "${LIB_DIR/modules}/${f}"
    chmod +x "${LIB_DIR/modules}/${f}"
    # 从模块文件中提取别名并创建快捷命令
    alias_name=$(grep -oP '(?<=alias:\s*)\S+' "${LIB_DIR/modules}/${f}" || true)
    if [ -n "$alias_name" ]; then
        ln -sf "${LIB_DIR/modules}/${f}" "${BIN_DIR}/${alias_name}"
        echo "  安装: ${alias_name}"
    fi
done

echo ">>> 安装完成！"
echo ""
echo "  主菜单: vps"
echo "  快捷命令:"
for f in "$LIB_DIR/modules"/*.sh; do
    [ -f "$f" ] || continue
    alias_name=$(grep -oP '(?<=alias:\s*)\S+' "$f" || true)
    [ -n "$alias_name" ] && echo "    ${alias_name}"
done
