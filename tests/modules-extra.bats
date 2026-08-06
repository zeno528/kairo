#!/usr/bin/env bats
# 覆盖无专项测试文件的模块：fail2ban / crontab / nezha-agent / swap / optimize / proxy-setup

@test "无专项测试模块均提供 menu 入口" {
    for mod in fail2ban crontab nezha-agent swap optimize proxy-setup; do
        run bash -c 'source "'"$PWD"'/modules/'"$mod"'.sh"; declare -F menu'
        [ "$status" -eq 0 ] || fail "$mod 缺少 menu 函数"
    done
}

@test "fail2ban 未安装时状态提示未安装" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/fail2ban.sh"
        command() { [ "$1" = "-v" ] && [ "$2" = "fail2ban-client" ] && return 1; builtin command "$@"; }
        do_status
    '
    [ "$status" -eq 1 ]
    [[ "$output" == *"未安装"* ]]
}

@test "fail2ban 运行中显示封禁数量" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/fail2ban.sh"
        fail2ban-client() { printf "%s\n" "Currently banned: 3"; }
        systemctl() { [ "$1" = "is-active" ] && return 0; }
        do_status
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"fail2ban 运行中"* ]]
    [[ "$output" == *"3"* ]]
}

@test "fail2ban 封禁查询失败返回非零" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/fail2ban.sh"
        fail2ban-client() { return 1; }
        sudo() { "$@"; }
        do_bans
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"无法获取"* ]]
}

@test "crontab 任务行识别排除注释与环境变量" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/crontab.sh"
        _is_task_line "*/5 * * * * echo hi"; printf "%s" "$?"; echo -n " "
        _is_task_line "SHELL=/bin/bash"; printf "%s" "$?"; echo -n " "
        _is_task_line "# comment"; printf "%s" "$?"; echo -n " "
        _is_task_line "#KAIRO_OFF# */5 * * * * echo hi"; printf "%s" "$?"; echo -n " "
        _is_task_line ""; printf "%s" "$?"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "0 1 1 0 1" ]]
}

@test "cron 表达式自然语言解释覆盖特殊调度" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/crontab.sh"
        _cron_explain @reboot "" "" "" ""; echo
        _cron_explain "*/5" "*" "*" "*" "*"; echo
        _cron_explain "30" "8" "*" "*" "*"; echo
        _cron_explain "0" "*" "*" "*" "1"; echo
        _cron_explain "*" "*/2" "*" "*" "*"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"系统启动时执行"* ]]
    [[ "$output" == *"每隔 5 分钟执行一次"* ]]
    [[ "$output" == *"每天 08:30 执行一次"* ]]
    [[ "$output" == *"每周一 00:00 执行一次"* ]]
    [[ "$output" == *"每隔 2 小时执行一次"* ]]
}

@test "crontab 批量编号解析支持范围并逆序去重" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/crontab.sh"
        _batch_parse_ids "3,1,5-7,3" && printf "%s\n" "${_BATCH_IDS[@]}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == $'7\n6\n5\n3\n1' ]]
}

@test "crontab 无任务时提示" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/crontab.sh"
        crontab() { return 1; }
        do_list
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"当前没有定时任务"* ]]
}

@test "nezha-agent 发现服务列表排除无关服务" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/nezha-agent.sh"
        systemctl() {
            if [ "$1" = "list-unit-files" ]; then
                printf "%s\n" "nezha-agent.service enabled" "nezha-agent-2.service enabled" "nginx.service enabled"
            else
                return 1
            fi
        }
        _find_agents
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"nezha-agent.service"* ]]
    [[ "$output" == *"nezha-agent-2.service"* ]]
    [[ ! "$output" == *"nginx.service"* ]]
}

@test "nezha-agent 从服务文件提取二进制路径" {
    local svc_file
    svc_file=$(mktemp)
    printf 'ExecStart=/opt/nezha/agent/nezha-agent -c /opt/nezha/agent/config.yml\n' > "$svc_file"
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/nezha-agent.sh"
        _agent_binary "'"$svc_file"'"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "/opt/nezha/agent/nezha-agent" ]]
    rm -f "$svc_file"
}

@test "nezha-agent 解析二进制版本号" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/nezha-agent.sh"
        agent_bin=$(mktemp)
        printf "#!/bin/sh\necho \"nezha-agent v0.20.3 linux/amd64\"\n" > "$agent_bin"
        chmod +x "$agent_bin"
        _agent_version "$agent_bin"
        rm -f "$agent_bin"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "v0.20.3" ]]
}

@test "nezha-agent 无服务时状态返回非零" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/nezha-agent.sh"
        systemctl() { return 1; }
        do_status
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"未发现 nezha-agent"* ]]
}

@test "swap 未启用时状态提示" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/swap.sh"
        lsblk() { return 1; }
        swapon() { return 1; }
        free() { printf "Swap: 0B 0B\n"; }
        crontab() { return 1; }
        do_status
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"当前未启用任何虚拟内存"* ]]
}

@test "swap 启用 zram 时状态显示设备" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/swap.sh"
        lsblk() { printf "zram0 252:0 0 512M 0 disk\n"; }
        zramctl() { printf "zram0 512M lz4\n"; }
        swapon() { return 1; }
        free() { printf "Swap: 512M 10M\n"; }
        crontab() { return 1; }
        do_status
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"zram 内存压缩"* ]]
    [[ "$output" == *"zram0"* ]]
}

@test "内核优化配置包含关键参数" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/optimize.sh"
        _kernel_tune_conf
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"net.core.default_qdisc = fq"* ]]
    [[ "$output" == *"net.ipv4.tcp_fastopen = 3"* ]]
    [[ "$output" == *"vm.swappiness = 10"* ]]
}

@test "内核优化未应用时状态提示" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/optimize.sh"
        sysctl() { printf "cubic\n"; }
        cat() { printf "cubic\n"; }
        do_status
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"当前拥塞算法"* ]]
    [[ "$output" == *"未应用 Kairo 优化"* ]]
}

@test "节点搭建取消时不执行外部脚本" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/proxy-setup.sh"
        bash() { printf "BASH_CALLED %s\n" "$*"; }
        printf "%s\n" n | do_3xui
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"已取消"* ]]
    [[ ! "$output" == *"BASH_CALLED"* ]]
}

@test "节点搭建确认时调用统一安装执行器并传入官方脚本地址" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/proxy-setup.sh"
        _tool_run_remote_installer() { printf "RUN %s\n" "$1"; }
        printf "%s\n" y | do_3xui
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUN https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"* ]]
}
