#!/usr/bin/env bash
# Kairo 模块注册表：菜单、帮助和 CLI action 以此为唯一模块来源。

declare -a KAIRO_GROUP_IDS=()
declare -a KAIRO_MODULE_IDS=()
# shellcheck disable=SC2034 # 由主入口读取。
declare -A KAIRO_GROUP_LABELS=()
# shellcheck disable=SC2034 # 由主入口读取。
declare -A KAIRO_GROUP_LAYOUTS=()
# shellcheck disable=SC2034 # 由主入口读取。
declare -A KAIRO_MODULE_GROUPS=()
# shellcheck disable=SC2034 # 由主入口读取。
declare -A KAIRO_MODULE_LABELS=()
# shellcheck disable=SC2034 # 由主入口读取。
declare -A KAIRO_MODULE_DESCRIPTIONS=()
# 每个模块显式暴露给 CLI 的 action，避免调用入口或其他模块的同名函数。
declare -A KAIRO_MODULE_ACTIONS=()

kairo_register_group() {
    local id="$1" label="$2" layout="${3:-stack}"
    KAIRO_GROUP_IDS+=("$id")
    # shellcheck disable=SC2034 # 由主入口读取。
    KAIRO_GROUP_LABELS["$id"]="$label"
    # shellcheck disable=SC2034 # 由主入口读取。
    KAIRO_GROUP_LAYOUTS["$id"]="$layout"
}

kairo_register_module() {
    local id="$1" group="$2" label="$3" actions="$4" description="${5:-}"
    if [[ -z "${KAIRO_GROUP_LABELS[$group]+x}" ]]; then
        printf 'Kairo 注册表错误: 模块 %s 引用了未知分组 %s\n' "$id" "$group" >&2
        return 1
    fi
    if [[ -n "${KAIRO_MODULE_LABELS[$id]+x}" ]]; then
        printf 'Kairo 注册表错误: 模块重复注册: %s\n' "$id" >&2
        return 1
    fi
    KAIRO_MODULE_IDS+=("$id")
    # shellcheck disable=SC2034 # 由主入口读取。
    KAIRO_MODULE_GROUPS["$id"]="$group"
    KAIRO_MODULE_LABELS["$id"]="$label"
    # shellcheck disable=SC2034 # 由主入口读取。
    KAIRO_MODULE_DESCRIPTIONS["$id"]="$description"
    KAIRO_MODULE_ACTIONS["$id"]="$actions"
}

kairo_module_registered() {
    [[ -n "${KAIRO_MODULE_LABELS[$1]+x}" ]]
}

kairo_module_supports_action() {
    local module="$1" expected="$2" action
    kairo_module_registered "$module" || return 1
    for action in ${KAIRO_MODULE_ACTIONS[$module]}; do
        [ "$action" = "$expected" ] && return 0
    done
    return 1
}

kairo_register_group ssh "🔒 SSH"
kairo_register_group system "💻 系统"
kairo_register_group network "🌐 网络"
kairo_register_group proxy "🚀 代理"
kairo_register_group tools "🧰 工具"
kairo_register_group agents "🤖 AI Agent" "right_column"

kairo_register_module ssh-passwd ssh "密码登录管理" "on off status"
kairo_register_module ssh-keys ssh "公钥管理" "list add remove view rename"
kairo_register_module fail2ban ssh "fail2ban 防暴破" "status install bans uninstall"
kairo_register_module sys-info system "系统信息查看✨" "overview cpu memory disk network"
kairo_register_module port-proc system "端口/进程管理" "listen_ports find_by_port find_by_name kill_process"
kairo_register_module firewall system "防火墙管理" "status install open_port close_port allow_ip block_ip enable disable"
kairo_register_module services system "系统服务管理" "list status start stop restart toggle_enable reboot"
kairo_register_module crontab system "定时任务⏰" "list add"
kairo_register_module docker system "Docker 管理✨" "list_containers start stop restart remove logs exec stats images compose cleanup status install upgrade"
kairo_register_module nezha-agent system "哪吒监控 Agent✨" "status start stop remove logs mgmt"
kairo_register_module swap system "虚拟内存💾" "status zram swap disable autostart"
kairo_register_module network-test network "网络测试" "speedtest backtrace ping_test ip_quality streaming node_quality ecs_test"
kairo_register_module ssl-check network "SSL 证书检查" "local_check remote_check batch_check verify_chain"
kairo_register_module optimize network "网络与BBR内核优化" "status apply restore launch bbrv3"
kairo_register_module security-update network "软件更新" "check security_update full_update full_update_preview cleanup"
kairo_register_module nginx proxy "Nginx 管理" "install uninstall status start stop restart reload toggle_enable test_conf list_sites view_conf add_proxy del_proxy cert cert_list logs security_scan enable_site disable_site snapshot restore log_top"
kairo_register_module proxy-setup proxy "节点搭建✨" "3xui singbox_eooce singbox_yonggekkk"
kairo_register_module claude agents "Claude Code" "status install upgrade" "Anthropic AI 编程助手"
kairo_register_module kimi agents "Kimi Code" "status install upgrade" "Kimi AI 编程助手"
kairo_register_module github-cli tools "GitHub CLI" "status install upgrade" "GitHub 命令行工具"
kairo_register_module openclaw agents "OpenClaw" "status install upgrade" "AI Agent 网关"
kairo_register_module go tools "Go" "status install upgrade" "Go 语言工具链"
kairo_register_module jq tools "jq" "status install upgrade" "JSON 命令行处理器"
kairo_register_module sqlite3 tools "SQLite3" "status install upgrade" "轻量数据库命令行工具"
kairo_register_module basics tools "基础工具✨" "status install upgrade" "运维常用工具合集"
kairo_register_module codex agents "Codex CLI" "status install upgrade" "OpenAI AI 编程助手"
