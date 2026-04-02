#!/bin/bash
# install.sh - 一键安装 vps-toolkit 脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/Ekko7778/vps-toolkit/main/install.sh | bash

set -e

BIN_DIR="/usr/local/bin"
REPO="Ekko7778/vps-toolkit"
BASE_URL="https://raw.githubusercontent.com/${REPO}/main"

scripts=("ssh-passwd.sh")

echo ">>> 安装 vps-toolkit..."

for script in "${scripts[@]}"; do
    name="${script%.sh}"
    echo "  安装: ${name}"
    curl -fsSL "${BASE_URL}/${script}" -o "${BIN_DIR}/${name}"
    chmod +x "${BIN_DIR}/${name}"
done

echo ">>> 安装完成！可用命令:"
for script in "${scripts[@]}"; do
    name="${script%.sh}"
    echo "  ${name}"
done
