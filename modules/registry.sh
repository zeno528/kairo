#!/usr/bin/env bash
# Kairo 模块注册表：菜单、帮助和安装清单以此为唯一模块来源。

declare -a KAIRO_GROUP_IDS=()
declare -a KAIRO_MODULE_IDS=()
# shellcheck disable=SC2034 # 由主入口读取。
declare -A KAIRO_GROUP_LABELS=()
# shellcheck disable=SC2034 # 由主入口读取。
declare -A KAIRO_MODULE_GROUPS=()
# shellcheck disable=SC2034 # 由主入口读取。
declare -A KAIRO_MODULE_LABELS=()

kairo_register_group() {
    local id="$1" label="$2"
    KAIRO_GROUP_IDS+=("$id")
    # shellcheck disable=SC2034 # 由主入口读取。
    KAIRO_GROUP_LABELS["$id"]="$label"
}

kairo_register_module() {
    local id="$1" group="$2" label="$3"
    KAIRO_MODULE_IDS+=("$id")
    # shellcheck disable=SC2034 # 由主入口读取。
    KAIRO_MODULE_GROUPS["$id"]="$group"
    KAIRO_MODULE_LABELS["$id"]="$label"
}

kairo_module_registered() {
    [[ -n "${KAIRO_MODULE_LABELS[$1]+x}" ]]
}

kairo_register_group ssh "🔒 SSH"
kairo_register_group system "🖥  系统"
kairo_register_group proxy "🌐  反代"

kairo_register_module ssh-passwd ssh "密码登录管理"
kairo_register_module ssh-keys ssh "公钥管理"
kairo_register_module sys-info system "系统信息查看"
kairo_register_module port-proc system "端口/进程管理"
kairo_register_module firewall system "防火墙管理"
kairo_register_module services system "系统服务管理"
kairo_register_module crontab system "定时任务"
kairo_register_module ssl-check system "SSL 证书检查"
kairo_register_module security-update system "安全更新"
kairo_register_module network-test system "网络测试"
kairo_register_module docker system "Docker 管理"
kairo_register_module nginx proxy "Nginx 管理"
