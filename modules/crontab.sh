#!/bin/bash
# crontab 模块 - 定时任务管理

# ── 内部辅助 ────────────────────────────────────────────────

_crontab_task_lines() {
    crontab -l 2>/dev/null | grep -vE '^[[:space:]]*$|^[A-Za-z_][A-Za-z0-9_]*=' | grep -E '^[^#]|^#KAIRO_OFF#'
}

_crontab_has_tasks() {
    _crontab_task_lines | grep -q .
}

_is_task_line() {
    [[ -n "$1" ]] || return 1
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && return 1
    [[ "$1" =~ ^# ]] && [[ ! "$1" =~ ^#KAIRO_OFF# ]] && return 1
    return 0
}

_crontab_get_task() {
    local target=$1 current=0 line
    while IFS= read -r line; do
        _is_task_line "$line" || continue
        current=$((current + 1))
        [ "$current" -eq "$target" ] && { printf '%s\n' "$line"; return 0; }
    done < <(crontab -l 2>/dev/null)
    return 1
}

_crontab_replace_task() {
    local target=$1 new_content=$2 current=0 line output=""
    while IFS= read -r line; do
        if _is_task_line "$line"; then
            current=$((current + 1))
            if [ "$current" -eq "$target" ]; then
                output="${output}${new_content}"$'\n'
                continue
            fi
        fi
        output="${output}${line}"$'\n'
    done < <(crontab -l 2>/dev/null)
    echo "$output" | crontab -
}

# ── 调度引导 ────────────────────────────────────────────────

# 引导用户选择执行周期，结果存入全局变量 KAIRO_CRON_SCHEDULE
_cron_pick_schedule() {
    local choice min hour day mon week min_n custom
    echo -e "  ${C_DIM}这个任务多久执行一次？${C_RESET}"
    echo ""
    _menu_actions 24 "${C_BOLD}[1]${C_RESET} 每分钟"
    _menu_actions 24 "${C_BOLD}[2]${C_RESET} 每隔 N 分钟"
    _menu_actions 24 "${C_BOLD}[3]${C_RESET} 每小时"
    _menu_actions 24 "${C_BOLD}[4]${C_RESET} 每天"
    _menu_actions 24 "${C_BOLD}[5]${C_RESET} 每周"
    _menu_actions 24 "${C_BOLD}[6]${C_RESET} 每月"
    _menu_actions 24 "${C_BOLD}[7]${C_RESET} 自定义 cron 表达式"
    echo ""
    read -r -p "  (1-7): " choice
    echo ""

    case "$choice" in
        1) min="*" hour="*" day="*" mon="*" week="*" ;;
        2)
            read -r -p "  每隔多少分钟 (1-59): " min_n
            kairo_is_positive_integer "$min_n" && [ "$min_n" -le 59 ] || { error "请输入 1-59 的数字"; return 1; }
            min="*/${min_n}" hour="*" day="*" mon="*" week="*"
            ;;
        3)
            echo -e "  ${C_DIM}每小时的第 N 分钟执行${C_RESET}"
            read -r -p "  第几分 (0-59): " min
            kairo_is_positive_integer "$min" && [ "$min" -le 59 ] || { error "请输入 0-59 的数字"; return 1; }
            hour="*" day="*" mon="*" week="*"
            ;;
        4)
            echo -e "  ${C_DIM}每天 HH:MM 执行${C_RESET}"
            read -r -p "  几点 (0-23): " hour
            kairo_is_positive_integer "$hour" && [ "$hour" -le 23 ] || { error "请输入 0-23 的数字"; return 1; }
            read -r -p "  几分 (0-59): " min
            kairo_is_positive_integer "$min" && [ "$min" -le 59 ] || { error "请输入 0-59 的数字"; return 1; }
            day="*" mon="*" week="*"
            ;;
        5)
            echo -e "  ${C_DIM}每周 星期几 HH:MM 执行${C_RESET}"
            echo ""
            echo -e "  ${C_DIM}  0 — 周日    1 — 周一    2 — 周二    3 — 周三${C_RESET}"
            echo -e "  ${C_DIM}  4 — 周四    5 — 周五    6 — 周六${C_RESET}"
            echo ""
            read -r -p "  星期几 (0-6): " week
            kairo_is_positive_integer "$week" && [ "$week" -le 6 ] || { error "请输入 0-6 的数字"; return 1; }
            read -r -p "  几点 (0-23): " hour
            kairo_is_positive_integer "$hour" && [ "$hour" -le 23 ] || { error "请输入 0-23 的数字"; return 1; }
            read -r -p "  几分 (0-59): " min
            kairo_is_positive_integer "$min" && [ "$min" -le 59 ] || { error "请输入 0-59 的数字"; return 1; }
            day="*" mon="*"
            ;;
        6)
            echo -e "  ${C_DIM}每月 几号 HH:MM 执行${C_RESET}"
            read -r -p "  几号 (1-31): " day
            kairo_is_positive_integer "$day" && [ "$day" -le 31 ] || { error "请输入 1-31 的数字"; return 1; }
            read -r -p "  几点 (0-23): " hour
            kairo_is_positive_integer "$hour" && [ "$hour" -le 23 ] || { error "请输入 0-23 的数字"; return 1; }
            read -r -p "  几分 (0-59): " min
            kairo_is_positive_integer "$min" && [ "$min" -le 59 ] || { error "请输入 0-59 的数字"; return 1; }
            mon="*" week="*"
            ;;
        7)
            echo -e "  ${C_DIM}直接输入 cron 表达式: 分 时 日 月 周${C_RESET}"
            echo -e "  ${C_DIM}参考 https://crontab.guru/${C_RESET}"
            echo ""
            read -r -p "  表达式: " custom
            [ -z "$custom" ] && return 1
            read -r min hour day mon week _ <<< "$custom"
            ;;
        *) return 1 ;;
    esac
    KAIRO_CRON_SCHEDULE="${min} ${hour} ${day} ${mon} ${week}"
    return 0
}

# ── cron 表达式 → 自然语言 ──────────────────────────────────

_cron_explain() {
    local min="$1" hour="$2" day="$3" mon="$4" week="$5"

    # @ 特殊调度关键字
    case "$min" in
        @reboot) echo "系统启动时执行"; return 0 ;;
        @yearly|@annually) echo "每年执行一次"; return 0 ;;
        @monthly) echo "每月执行一次"; return 0 ;;
        @weekly) echo "每周执行一次"; return 0 ;;
        @daily) echo "每天执行一次"; return 0 ;;
        @hourly) echo "每小时执行一次"; return 0 ;;
    esac

    # 每分钟
    [ "$min" = "*" ] && [ "$hour" = "*" ] && [ "$day" = "*" ] && [ "$mon" = "*" ] && [ "$week" = "*" ] && \
        { echo "每分钟执行一次"; return 0; }

    # 每隔 N 分钟
    [[ "$min" =~ ^\*/[0-9]+$ ]] && { echo "每隔 ${min#\*/} 分钟执行一次"; return 0; }

    # 每隔 N 小时
    if [[ "$hour" =~ ^\*/[0-9]+$ ]] && [ "$day" = "*" ] && [ "$mon" = "*" ] && [ "$week" = "*" ]; then
        local h_interval="${hour#\*/}" h_desc=""
        if [ "$min" = "*" ]; then
            h_desc="每隔 ${h_interval} 小时执行一次"
        else
            h_desc="每隔 ${h_interval} 小时的第 ${min} 分执行一次"
        fi
        echo "$h_desc"; return 0
    fi

    # 判断是否为多值字段（含逗号）
    local multi=0
    [[ "$min" == *,* || "$hour" == *,* || "$day" == *,* ]] && multi=1

    # 构建时间描述
    local times=""
    if [ "$multi" -eq 1 ]; then
        # 多值：列出所有时间点
        local h m
        IFS=',' read -ra HOURS <<< "$hour"
        IFS=',' read -ra MINS <<< "$min"
        for h in "${HOURS[@]}"; do
            for m in "${MINS[@]}"; do
                [ -n "$times" ] && times+="、"
                printf -v t '%02d:%02d' "$h" "$m"
                times+="$t"
            done
        done
    else
        printf -v times '%02d:%02d' "$hour" "$min"
    fi

    # 按周期类型描述
    if [ "$week" != "*" ] && [ "$day" = "*" ]; then
        local dow_name="$week"
        case "$week" in
            0|7) dow_name="周日" ;; 1) dow_name="周一" ;;
            2) dow_name="周二" ;; 3) dow_name="周三" ;;
            4) dow_name="周四" ;; 5) dow_name="周五" ;;
            6) dow_name="周六" ;;
        esac
        [ "$multi" -eq 1 ] && echo "每${dow_name} ${times} 各执行一次" || echo "每${dow_name} ${times} 执行一次"
    elif [ "$day" != "*" ] && [ "$mon" = "*" ]; then
        echo "每月 ${day} 日 ${times} 执行一次"
    elif [ "$mon" != "*" ]; then
        echo "每年 ${mon} 月 ${times} 执行一次"
    elif [ "$hour" != "*" ] && [ "$day" = "*" ] && [ "$week" = "*" ]; then
        [ "$multi" -eq 1 ] && echo "每天 ${times} 各执行一次" || echo "每天 ${times} 执行一次"
    elif [ "$min" != "*" ] && [ "$hour" = "*" ] && [ "$day" = "*" ] && [ "$week" = "*" ]; then
        [ "$multi" -eq 1 ] && echo "每小时的第 ${times} 分各执行一次" || echo "每小时的第 ${min} 分执行一次"
    else
        echo "自定义调度"
    fi
}

# ── 操作函数 ────────────────────────────────────────────────

do_list() {
    if ! _crontab_has_tasks; then
        echo ""
        warn "当前没有定时任务"
        return
    fi
    echo -e "  ${C_BOLD}当前定时任务${C_RESET}"

    # 第一遍：收集所有任务数据，计算各列最大宽度
    local -a tasks_num=() tasks_schedule=() tasks_cmd=() tasks_explain=() tasks_disabled=()
    local num=0 line min hour day mon week cmd schedule explain
    local max_num_w=4 max_sched_w=14

    while IFS= read -r line; do
        num=$((num + 1))
        local is_disabled=0
        if [[ "$line" =~ ^#KAIRO_OFF# ]]; then
            is_disabled=1
            line="${line#\#KAIRO_OFF# }"
        fi
        if [[ "$line" =~ ^@ ]]; then
            # @ 特殊调度关键字
            schedule="${line%% *}"
            cmd="${line#* }"
            explain=$(_cron_explain "$schedule" "" "" "" "")
        else
            read -r min hour day mon week cmd <<< "$line"
            schedule="${min} ${hour} ${day} ${mon} ${week}"
            explain=$(_cron_explain "$min" "$hour" "$day" "$mon" "$week")
        fi
        tasks_num+=("$num")
        tasks_schedule+=("$schedule")
        tasks_cmd+=("$cmd")
        tasks_explain+=("$explain")
        tasks_disabled+=("$is_disabled")
        [ "${#schedule}" -gt "$max_sched_w" ] && max_sched_w="${#schedule}"
        local num_str="[$num]"
        [ "${#num_str}" -gt "$max_num_w" ] && max_num_w="${#num_str}"
    done < <(_crontab_task_lines)

    # 第二遍：用计算好的列宽统一渲染
    local i
    for ((i = 0; i < ${#tasks_num[@]}; i++)); do
        if [ "${tasks_disabled[$i]}" -eq 1 ]; then
            printf "  %s ○ %s %s  ${C_DIM}—⏱  %s${C_RESET}\n" \
                "$(_pad_right "[${tasks_num[$i]}]" "$max_num_w")" \
                "$(_pad_right "${C_DIM}${tasks_schedule[$i]}${C_RESET}" "$max_sched_w")" \
                "${C_DIM}${tasks_cmd[$i]}${C_RESET}" \
                "${tasks_explain[$i]}"
        else
            printf "  %s ${C_GREEN}●${C_RESET} %s %s  ${C_DIM}—⏱  %s${C_RESET}\n" \
                "$(_pad_right "[${tasks_num[$i]}]" "$max_num_w")" \
                "$(_pad_right "${tasks_schedule[$i]}" "$max_sched_w")" \
                "${tasks_cmd[$i]}" \
                "${tasks_explain[$i]}"
        fi
    done
    echo ""
}

do_add() {
    echo ""
    echo -e "  ${C_BOLD}添加定时任务${C_RESET}"

    local min hour day mon week cmd explain

    # 第一步：多久执行一次
    echo ""
    _cron_pick_schedule || { info "已取消"; return 0; }
    read -r min hour day mon week _ <<< "$KAIRO_CRON_SCHEDULE"
    explain=$(_cron_explain "$min" "$hour" "$day" "$mon" "$week")

    # 第二步：输入命令
    echo ""
    echo -e "  ${C_DIM}第 2 步：输入要执行的命令${C_RESET}"
    echo -e "  ${C_DIM}将 ${C_GREEN}${explain}${C_DIM} 执行这个命令${C_RESET}"
    echo -e "  ${C_DIM}可以是一个脚本路径、一行命令、或系统指令${C_RESET}"
    echo -e "  ${C_DIM}示例: /root/scripts/backup.sh  或  echo hello >> /tmp/log  或  systemctl restart nginx${C_RESET}"
    echo ""
    while true; do
        read -r -p "  命令: " cmd
        [ -n "$cmd" ] && break
        echo -e "  ${C_YELLOW}⚠ 命令不能为空${C_RESET}"
    done

    # 确认
    echo ""
    echo -e "  ${C_GREEN}此任务将 ${explain}${C_RESET}"
    echo -e "  → ${cmd}"
    echo ""
    read -r -p "  确认添加? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }

    (crontab -l 2>/dev/null; echo "$KAIRO_CRON_SCHEDULE $cmd") | crontab - && success "定时任务已添加"
}

# ── 任务编辑子菜单 ──────────────────────────────────────────

_task_edit_schedule() {
    local num=$1 task cmd is_disabled=0 min hour day mon week
    task=$(_crontab_get_task "$num") || { error "任务不存在"; return 1; }
    if [[ "$task" =~ ^#KAIRO_OFF# ]]; then
        is_disabled=1
        task="${task#\#KAIRO_OFF# }"
    fi
    read -r _ _ _ _ _ cmd <<< "$task"

    echo ""
    echo -e "  ${C_BOLD}修改调度${C_RESET}"
    echo ""
    _cron_pick_schedule || { info "已取消"; return 0; }
    read -r min hour day mon week _ <<< "$KAIRO_CRON_SCHEDULE"

    local explain
    explain=$(_cron_explain "$min" "$hour" "$day" "$mon" "$week")
    echo ""
    echo -e "  ${C_GREEN}修改后：${explain}${C_RESET}"
    echo ""
    read -r -p "  确认修改? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }

    local new_line="${KAIRO_CRON_SCHEDULE} ${cmd}"
    [ "$is_disabled" -eq 1 ] && new_line="#KAIRO_OFF# ${new_line}"
    _crontab_replace_task "$num" "$new_line" && success "调度已更新"
}

_task_edit_command() {
    local num=$1 task min hour day mon week cmd
    task=$(_crontab_get_task "$num") || { error "任务不存在"; return 1; }
    local is_disabled=0
    if [[ "$task" =~ ^#KAIRO_OFF# ]]; then
        is_disabled=1
        task="${task#\#KAIRO_OFF# }"
    fi
    read -r min hour day mon week cmd <<< "$task"

    echo ""
    info "当前命令: ${C_BOLD}${cmd}${C_RESET}"
    echo -e "  ${C_DIM}可以是一个脚本路径、一行命令、或系统指令${C_RESET}"
    echo -e "  ${C_DIM}示例: /root/scripts/backup.sh  或  echo hello >> /tmp/log${C_RESET}"
    echo ""
    read -r -p "  新命令: " new_cmd
    [ -z "$new_cmd" ] && { info "已取消"; return 0; }
    echo ""
    read -r -p "  确认修改? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }

    local new_line="${min} ${hour} ${day} ${mon} ${week} ${new_cmd}"
    [ "$is_disabled" -eq 1 ] && new_line="#KAIRO_OFF# ${new_line}"
    _crontab_replace_task "$num" "$new_line" && success "命令已更新"
}

_task_toggle() {
    local num=$1 task
    task=$(_crontab_get_task "$num") || { error "任务不存在"; return 1; }
    local new_line
    if [[ "$task" =~ ^#KAIRO_OFF# ]]; then
        new_line="${task#\#KAIRO_OFF# }"
        _crontab_replace_task "$num" "$new_line" && success "已启用"
    else
        new_line="#KAIRO_OFF# ${task}"
        _crontab_replace_task "$num" "$new_line" && success "已禁用"
    fi
}

_task_remove() {
    local num=$1 task min hour day mon week cmd
    task=$(_crontab_get_task "$num") || { error "任务不存在"; return 1; }
    if [[ "$task" =~ ^#KAIRO_OFF# ]]; then
        task="${task#\#KAIRO_OFF# }"
    fi
    read -r min hour day mon week cmd <<< "$task"
    echo ""
    warn "将删除: ${min} ${hour} ${day} ${mon} ${week} ${cmd}"
    read -r -p "  确认删除? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    _crontab_replace_task "$num" "" && success "已删除"
}

_task_menu() {
    local num=$1 task min hour day mon week cmd
    task=$(_crontab_get_task "$num") || { error "任务不存在"; return 1; }
    local is_disabled=0
    if [[ "$task" =~ ^#KAIRO_OFF# ]]; then
        is_disabled=1
        task="${task#\#KAIRO_OFF# }"
    fi
    read -r min hour day mon week cmd <<< "$task"

    local choice toggle_label
    while true; do
        echo ""
        echo -e "  ${C_BOLD}[${num}]${C_RESET} 调度: ${C_BOLD}${min} ${hour} ${day} ${mon} ${week}${C_RESET}"
        echo -e "        命令: ${cmd}"
        if [ "$is_disabled" -eq 1 ]; then
            toggle_label="启用"
            echo -e "        状态: ${C_RED}已禁用${C_RESET}"
        else
            toggle_label="禁用"
            echo -e "        状态: ${C_GREEN}已启用${C_RESET}"
        fi
        divider
        _menu_actions 18 "${C_BOLD}[1]${C_RESET} 编辑调度"
        _menu_actions 18 "${C_BOLD}[2]${C_RESET} 编辑命令"
        _menu_actions 18 "${C_BOLD}[3]${C_RESET} ${toggle_label}"
        _menu_actions 18 "${C_BOLD}[4]${C_RESET} 删除"
        _menu_actions 18 "${C_BOLD}[0]${C_RESET} 返回"
        divider
        echo ""
        read -r -p "  选择操作: " choice
        case "$choice" in
            1) _task_edit_schedule "$num"; echo ""; kairo_pause "按 Enter 返回..." ;;
            2) _task_edit_command "$num"; echo ""; kairo_pause "按 Enter 返回..." ;;
            3)
                _task_toggle "$num"
                is_disabled=$((1 - is_disabled))
                task=$(_crontab_get_task "$num") || break
                if [[ "$task" =~ ^#KAIRO_OFF# ]]; then
                    is_disabled=1
                    task="${task#\#KAIRO_OFF# }"
                fi
                read -r min hour day mon week cmd <<< "$task"
                echo ""; kairo_pause "按 Enter 返回..."
                ;;
            4) _task_remove "$num" && break; echo ""; kairo_pause "按 Enter 返回..." ;;
            0) break ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}

# ── 批量操作 ────────────────────────────────────────────────

# 解析逗号分隔的编号列表，如 "1,3,5-7" → 返回到全局 _BATCH_IDS 数组
_batch_parse_ids() {
    local raw="$1" part start end i
    _BATCH_IDS=()
    IFS=',' read -ra parts <<< "$raw"
    for part in "${parts[@]}"; do
        part="${part## }"; part="${part%% }"
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
            [ "$start" -le "$end" ] || { error "范围无效: ${start}-${end}"; return 1; }
            for ((i = start; i <= end; i++)); do _BATCH_IDS+=("$i"); done
        elif kairo_is_positive_integer "$part"; then
            _BATCH_IDS+=("$part")
        else
            error "无效编号: ${part}"; return 1
        fi
    done
    # 去重并逆序排列，处理时从高到低避免编号偏移
    mapfile -t _BATCH_IDS < <(printf '%s\n' "${_BATCH_IDS[@]}" | sort -urn)
    return 0
}

_batch_delete() {
    local raw="$1" id
    _batch_parse_ids "$raw" || return 1
    [ "${#_BATCH_IDS[@]}" -eq 0 ] && { error "未指定编号"; return 1; }

    echo ""
    warn "将删除以下任务:"
    for id in "${_BATCH_IDS[@]}"; do
        local task min hour day mon week cmd
        task=$(_crontab_get_task "$id") || continue
        [[ "$task" =~ ^#KAIRO_OFF# ]] && task="${task#\#KAIRO_OFF# }"
        read -r min hour day mon week cmd <<< "$task"
        echo -e "  [${id}] ${min} ${hour} ${day} ${mon} ${week} ${cmd}"
    done
    echo ""
    read -r -p "  确认批量删除? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }

    # 逆序删除，避免编号偏移
    for id in "${_BATCH_IDS[@]}"; do
        _crontab_replace_task "$id" "" 2>/dev/null
    done
    success "已批量删除"
}

_batch_toggle() {
    local raw="$1" target_state="$2" id action_label
    _batch_parse_ids "$raw" || return 1
    [ "${#_BATCH_IDS[@]}" -eq 0 ] && { error "未指定编号"; return 1; }

    if [ "$target_state" = "disable" ]; then
        action_label="禁用"
    else
        action_label="启用"
    fi

    echo ""
    warn "将批量${action_label}以下任务:"
    for id in "${_BATCH_IDS[@]}"; do
        local task
        task=$(_crontab_get_task "$id") || continue
        local cur_state="启用"
        [[ "$task" =~ ^#KAIRO_OFF# ]] && cur_state="禁用"
        echo -e "  [${id}] ${cur_state} → ${action_label}"
    done
    echo ""
    read -r -p "  确认? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }

    for id in "${_BATCH_IDS[@]}"; do
        local task new_line
        task=$(_crontab_get_task "$id") || continue
        if [ "$target_state" = "disable" ]; then
            [[ "$task" =~ ^#KAIRO_OFF# ]] && continue
            new_line="#KAIRO_OFF# ${task}"
        else
            [[ "$task" =~ ^#KAIRO_OFF# ]] || continue
            new_line="${task#\#KAIRO_OFF# }"
        fi
        _crontab_replace_task "$id" "$new_line" 2>/dev/null
    done
    success "已批量${action_label}"
}

_batch_menu() {
    local choice
    while true; do
        echo ""
        echo -e "  ${C_BOLD}批量操作${C_RESET}"
        echo -e "  ${C_DIM}输入编号，用逗号分隔，如: 1,3,5  或  2-4${C_RESET}"
        divider
        _menu_actions 24 "${C_BOLD}[1]${C_RESET} 批量删除"
        _menu_actions 24 "${C_BOLD}[2]${C_RESET} 批量禁用"
        _menu_actions 24 "${C_BOLD}[3]${C_RESET} 批量启用"
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回"
        divider
        echo ""
        read -r -p "  选择操作: " choice
        case "$choice" in
            1)
                echo ""; read -r -p "  要删除的编号: " ids
                [ -z "$ids" ] && { info "已取消"; continue; }
                _batch_delete "$ids"
                echo ""; kairo_pause "按 Enter 返回..."
                ;;
            2)
                echo ""; read -r -p "  要禁用的编号: " ids
                [ -z "$ids" ] && { info "已取消"; continue; }
                _batch_toggle "$ids" "disable"
                echo ""; kairo_pause "按 Enter 返回..."
                ;;
            3)
                echo ""; read -r -p "  要启用的编号: " ids
                [ -z "$ids" ] && { info "已取消"; continue; }
                _batch_toggle "$ids" "enable"
                echo ""; kairo_pause "按 Enter 返回..."
                ;;
            0) break ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}

# ── 主菜单 ──────────────────────────────────────────────────

menu() {
    local choice task_count
    while true; do
        clear
        title "⏰ 定时任务"
        echo ""
        do_list
        divider
        task_count=$(_crontab_task_lines | wc -l)
        _menu_actions 20 "${C_BOLD}$(kairo_menu_range "$task_count" "管理任务")${C_RESET}"
        _menu_actions 20 "${C_BOLD}[D]${C_RESET} 批量操作"
        _menu_actions 20 "${C_BOLD}[A]${C_RESET} 添加任务"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  选择任务或操作: " choice
        case "$choice" in
            [Aa]) do_add; echo ""; kairo_pause "按 Enter 返回任务列表..." ;;
            [Dd]) _batch_menu ;;
            0) return ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]]; then
                    _task_menu "$choice"
                else
                    error "无效选项"; sleep 1
                fi
                ;;
        esac
    done
}
