#!/bin/bash
# install.sh - 一键安装 vps-toolkit 脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/Ekko7778/vps-toolkit/main/install.sh | bash

set -e

BIN_DIR="/usr/local/bin"
REPO="Ekko7778/vps-toolkit"
BASE_URL="https://raw.githubusercontent.com/${REPO}/main"

declare -A aliases=(
    ["ssh-passwd.sh"]="sp"
)

echo ">>> 安装 vps-toolkit..."

for script in "${!aliases[@]}"; do
    cmd="${aliases[$script]}"
    echo "  安装: ${cmd}"
    curl -fsSL "${BASE_URL}/${script}" -o "${BIN_DIR}/${cmd}"
    chmod +x "${BIN_DIR}/${cmd}"
done

echo ">>> 安装完成！可用命令:"
for cmd in "${aliases[@]}"; do
    echo "  ${cmd}"
done
