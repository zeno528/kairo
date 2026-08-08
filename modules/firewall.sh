#!/bin/bash
# firewall 模块 - 防火墙管理（ufw，Debian/Ubuntu）
# ufw 自带持久化（/etc/ufw/user.rules + systemd 单元），规则重启后保留，
# 因此不再维护裸 iptables fallback——那套需要手写 save/restore 且旧实现不持久化。

# 校验 IPv4 或 IPv4/CIDR（ufw allow/deny from 的入参格式）
_fw_is_ip() {
    local input="$1" addr prefix o
    local -a oct
    addr=${input%%/*}
    IFS=. read -ra oct <<< "$addr"
    [ "${#oct[@]}" -eq 4 ] || return 1
    for o in "${oct[@]}"; do
        [[ "$o" =~ ^[0-9]+$ ]] || return 1
        (( 10#$o >= 0 && 10#$o <= 255 )) || return 1
    done
    [[ "$input" == */* ]] || return 0
    prefix=${input#*/}
    [[ "$prefix" =~ ^[0-9]+$ ]] && (( 10#$prefix >= 0 && 10#$prefix <= 32 ))
}

# 确保 ufw 可用；未安装时引导安装（不每次进菜单都弹，仅在执行操作时触发）
_ensure_ufw() {
    command -v ufw &>/dev/null && return 0
    echo ""
    warn "未检测到 ufw"
    read -r -p "  是否安装 ufw? [Y/n]: " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && { info "已取消"; return 1; }
    kairo_apt_install ufw && return 0
    error "ufw 安装失败"
    return 1
}

# 实际监听中的 SSH 端口（以 ss 为准，避免 sshd_config 含 include 时解析遗漏）
_fw_ssh_ports() {
    sudo ss -tlnpH 2>/dev/null | awk '/sshd/ {
        split($4, a, ":")
        print a[length(a)]
    }' | sort -un
}

# 对外监听（非 127.0.0.1）的端口 -> 进程名，供状态区标注
_fw_listeners() {
    command -v ss &>/dev/null || return 0
    local line addr port proto name state field
    local -a fields=()
    while IFS= read -r line; do
        read -r -a fields <<< "$line"
        addr=""
        proto=""
        state=""
        for field in "${fields[@]}"; do
            case "$field" in
                tcp|udp) proto=$field ;;
                LISTEN|UNCONN) state=$field ;;
                *:*) [[ "$field" =~ ^(\*|0\.0\.0\.0|\[::\]|::):[0-9]+$ ]] && addr=$field ;;
            esac
        done
        [ -n "$addr" ] || continue
        [ -n "$state" ] || continue
        if [ -z "$proto" ]; then
            if [ "$state" = UNCONN ]; then proto=udp; else proto=tcp; fi
        fi
        port=${addr##*:}
        if [[ "$line" == *'users:(("'* ]]; then
            name=${line#*'users:(("'}
            name=${name%%'"'*}
        else
            name="?"
        fi
        printf '%s/%s %s\n' "$port" "$proto" "$name"
    done < <(ss -H -ltunp 2>/dev/null)
}

# 正在对外监听但未放行的端口，输出 "port/proto 进程名"
_fw_unallowed_listeners() {
    local -A allowed=()
    local key name
    while read -r key; do
        [ -n "$key" ] && allowed["$key"]=1
    done < <(_fw_rule_lines | grep -oE '[0-9]+/(tcp|udp)' | sort -u)
    while read -r key name; do
        [ -z "${allowed[$key]:-}" ] && printf '%s %s\n' "$key" "$name"
    done < <(_fw_listeners | sort -u)
}

# inactive 时 ufw status 不显示规则，改用 show added 渲染成统一格式
_fw_show_added_rules() {
    local line action target i=0
    while IFS= read -r line; do
        [[ "$line" == ufw\ * ]] || continue
        line=${line#ufw }
        if [[ "$line" =~ ^(allow|deny)[[:space:]]+from[[:space:]]+([^[:space:]]+) ]]; then
            action=${BASH_REMATCH[1]}
            target=${BASH_REMATCH[2]}
        elif [[ "$line" =~ ^(allow|deny)[[:space:]]+([^[:space:]]+) ]]; then
            action=${BASH_REMATCH[1]}
            target=${BASH_REMATCH[2]}
        else
            continue
        fi
        if [ "$action" = "allow" ]; then action="ALLOW"; else action="DENY"; fi
        i=$((i + 1))
        printf '[%s] %s %s IN Anywhere\n' "$i" "$target" "$action"
    done < <(ufw show added 2>/dev/null)
}

# 统一规则来源：active 用 status numbered（含 v6），inactive 用 show added
_fw_rule_lines() {
    if ufw status 2>/dev/null | head -1 | grep -q '^Status: active'; then
        ufw status numbered 2>/dev/null | tail -n +4
    else
        _fw_show_added_rules
    fi
}

do_install() {
    command -v ufw &>/dev/null && { info "ufw 已安装"; return 0; }
    _ensure_ufw
}

do_status() {
    echo ""
    if ! command -v ufw &>/dev/null; then
        error "未检测到 ufw"
        info "选择 [I] 安装 ufw，或任意操作也会引导安装"
        return
    fi
    local status status_raw
    status=$(ufw status | head -1 | sed 's/Status: //')
    status_raw=$status
    if [ "$status" = "active" ]; then
        status="${C_GREEN}●${C_RESET} $status"
    elif [ "$status" = "inactive" ]; then
        status="${C_RED}●${C_RESET} $status"
    fi
    echo -e "  ${C_BOLD}防火墙状态${C_RESET}  $status"
    if [ "$status_raw" = "inactive" ]; then
        warn "防火墙未启用；放行规则会保存，但暂不会拦截流量"
        info "开启时会自动放行 SSH 监听端口；未放行的端口将被拒绝，再选择 [E] 开启防火墙"
    fi
    echo ""
    local -A listener_names=()
    local key name line num pp rest action from proc status_text
    local w_num w_pp w_action w_from w_proc w_status cell_width i col_gap="   " saved_count=0 status_cell
    local -a rows_num=() rows_pp=() rows_action=() rows_from=() rows_proc=() rows_status=()
    w_num=$(_str_width "编号")
    w_pp=$(_str_width "端口/协议")
    w_action=$(_str_width "动作")
    w_from=$(_str_width "来源")
    w_proc=$(_str_width "进程")
    w_status=$(_str_width "状态")
    while read -r key name; do
        [ -n "$key" ] && listener_names["$key"]="$name"
    done < <(_fw_listeners | sort -u)
    while IFS= read -r line; do
        [[ "$line" =~ ^\[[[:space:]]*([0-9]+)\][[:space:]]+([^[:space:]]+)(.*)$ ]] || continue
        num=${BASH_REMATCH[1]}
        pp=${BASH_REMATCH[2]}
        rest=${BASH_REMATCH[3]}
        [[ "$rest" == *"(v6)"* ]] && pp="$pp (v6)"
        rest=$(sed -E 's/^[[:space:]]*\(v6\)//; s/^[[:space:]]+//; s/[[:space:]]+$//' <<< "$rest")
        if [[ "$rest" =~ ^([A-Z]+)[[:space:]]+IN[[:space:]]+(.*)$ ]]; then
            action="${BASH_REMATCH[1]} IN"
            from=${BASH_REMATCH[2]}
        else
            action=$rest
            from=""
        fi
        proc=""
        if [[ "${pp%% *}" =~ ^[0-9]+/(tcp|udp)$ ]] && [ -n "${listener_names[${pp%% *}]:-}" ]; then
            proc="(${listener_names[${pp%% *}]})"
        fi
        rows_num+=("[$num]")
        rows_pp+=("$pp")
        rows_action+=("$action")
        rows_from+=("$from")
        rows_proc+=("$proc")
        if [ "$status_raw" = "inactive" ]; then status_text="已保存"; else status_text="已放行"; fi
        rows_status+=("$status_text")
        saved_count=$((saved_count + 1))
        cell_width=$(_str_width "[$num]")
        (( cell_width > w_num )) && w_num=$cell_width
        cell_width=$(_str_width "$pp")
        (( cell_width > w_pp )) && w_pp=$cell_width
        cell_width=$(_str_width "$action")
        (( cell_width > w_action )) && w_action=$cell_width
        cell_width=$(_str_width "$from")
        (( cell_width > w_from )) && w_from=$cell_width
        cell_width=$(_str_width "$proc")
        (( cell_width > w_proc )) && w_proc=$cell_width
        cell_width=$(_str_width "$status_text")
        (( cell_width > w_status )) && w_status=$cell_width
    done < <(_fw_rule_lines)
    while read -r key name; do
        rows_num+=("-")
        rows_pp+=("$key")
        rows_action+=("-")
        rows_from+=("-")
        rows_proc+=("($name)")
        rows_status+=("未放行")
        cell_width=$(_str_width "$key")
        (( cell_width > w_pp )) && w_pp=$cell_width
        cell_width=$(_str_width "($name)")
        (( cell_width > w_proc )) && w_proc=$cell_width
        cell_width=$(_str_width "未放行")
        (( cell_width > w_status )) && w_status=$cell_width
    done < <(_fw_unallowed_listeners)
    if [ "${#rows_num[@]}" -gt 0 ]; then
        printf "  %s%s%s%s%s%s%s%s%s%s%s\n" \
            "$(_pad_right "编号" "$w_num")" "$col_gap" \
            "$(_pad_right "端口/协议" "$w_pp")" "$col_gap" \
            "$(_pad_right "动作" "$w_action")" "$col_gap" \
            "$(_pad_right "来源" "$w_from")" "$col_gap" \
            "$(_pad_right "进程" "$w_proc")" "$col_gap" "状态"
        for i in "${!rows_num[@]}"; do
            status_cell=$(_pad_right "${rows_status[$i]}" "$w_status")
            if [ "${rows_status[$i]}" = "未放行" ]; then
                status_cell="${C_RED}${status_cell}${C_RESET}"
            elif [ "${rows_status[$i]}" = "已保存" ]; then
                status_cell="${C_YELLOW}${status_cell}${C_RESET}"
            else
                status_cell="${C_GREEN}${status_cell}${C_RESET}"
            fi
            printf "  %s%s%s%s%s%s%s%s%s%s%s\n" \
                "$(_pad_right "${rows_num[$i]}" "$w_num")" "$col_gap" \
                "$(_pad_right "${rows_pp[$i]}" "$w_pp")" "$col_gap" \
                "$(_pad_right "${rows_action[$i]}" "$w_action")" "$col_gap" \
                "$(_pad_right "${rows_from[$i]}" "$w_from")" "$col_gap" \
                "$(_pad_right "${rows_proc[$i]}" "$w_proc")" "$col_gap" "$status_cell"
        done
    fi
    if [ "$status_raw" = "inactive" ] && [ "$saved_count" -gt 0 ]; then
        info "已保存 $saved_count 条放行规则，开启防火墙后生效"
    fi
}

do_open_port() {
    _ensure_ufw || return 1
    echo ""
    read -r -p "  输入端口号: " port
    [ -z "$port" ] && info "已取消" && return
    kairo_is_port "$port" || { error "端口必须是 1-65535"; return 1; }
    echo "  协议选项: tcp（网页/SSH/面板）  udp（Hysteria2）"
    read -r -p "  协议（默认 tcp，直接回车）: " proto
    proto=${proto:-tcp}
    [[ "$proto" =~ ^(tcp|udp)$ ]] || { error "协议只能是 tcp 或 udp"; return 1; }
    warn "即将放行入站端口 $port/$proto"
    read -r -p "  确认放行? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    if sudo ufw allow "$port/$proto"; then
        success "已开放 $port/$proto"
        [[ "$(ufw status | head -1)" == "Status: active" ]] || info "防火墙未启用，规则已保存但暂不生效"
    fi
}

do_close_port() {
    _ensure_ufw || return 1
    echo ""
    read -r -p "  输入端口号: " port
    [ -z "$port" ] && info "已取消" && return
    kairo_is_port "$port" || { error "端口必须是 1-65535"; return 1; }
    echo "  协议选项: tcp（网页/SSH/面板）  udp（Hysteria2）"
    read -r -p "  协议（默认 tcp，直接回车）: " proto
    proto=${proto:-tcp}
    [[ "$proto" =~ ^(tcp|udp)$ ]] || { error "协议只能是 tcp 或 udp"; return 1; }
    warn "即将关闭 $port/$proto，可能中断现有服务"
    read -r -p "  确认关闭? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    sudo ufw delete allow "$port/$proto" && success "已关闭 $port/$proto"
}

_fw_ufw_delete() {
    local action="$1" target="$2"
    if _fw_is_ip "$target"; then
        sudo ufw --force delete "$action" from "$target"
    else
        sudo ufw --force delete "$action" "$target"
    fi
}

do_delete_rule() {
    local choice="$1" token start end i n rule_count line target action key
    local -a nums=() rule_lines=() delete_actions=() delete_targets=()
    local -A pick=() seen=()
    rule_count=$(_fw_rule_lines | awk '/^\[/ { c++ } END { print c + 0 }')
    [ "$rule_count" -gt 0 ] || { error "没有规则可删除"; return 1; }
    mapfile -t rule_lines < <(_fw_rule_lines | grep '^\[')
    for token in ${choice//,/ }; do
        if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start=${BASH_REMATCH[1]}
            end=${BASH_REMATCH[2]}
            for ((i = start; i <= end; i++)); do
                (( i >= 1 && i <= rule_count )) && pick[$i]=1
            done
        elif [[ "$token" =~ ^[0-9]+$ ]] && (( token >= 1 && token <= rule_count )); then
            pick[$token]=1
        fi
    done
    if [ "${#pick[@]}" -eq 0 ]; then
        error "规则编号无效"
        return 1
    fi
    for n in "${!pick[@]}"; do nums+=("$n"); done
    mapfile -t nums < <(printf '%s\n' "${nums[@]}" | sort -nr)
    # ponytail: 只保护固定 22/tcp；若 SSH 改到其他端口需同步此保护
    for n in "${nums[@]}"; do
        line=${rule_lines[$((n - 1))]:-}
        [[ "$line" =~ ^\[[[:space:]]*[0-9]+\][[:space:]]+([^[:space:]]+)([[:space:]]+\(v6\))?[[:space:]]+(ALLOW|DENY)[[:space:]]+IN ]] || continue
        target=${BASH_REMATCH[1]}
        action=${BASH_REMATCH[3]}
        if [ "$target" = "22/tcp" ]; then
            error "规则 #$n 是 SSH 端口 (22/tcp)，禁止删除"
            return 1
        fi
        key="$action $target"
        [ -n "${seen[$key]:-}" ] && continue
        seen[$key]=1
        delete_actions+=("${action,,}")
        delete_targets+=("$target")
    done
    if [ "${#delete_targets[@]}" -eq 0 ]; then
        error "规则编号无效"
        return 1
    fi
    warn "即将删除规则:"
    for target in "${delete_targets[@]}"; do
        echo "    - $target"
    done
    read -r -p "  确认删除? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    for i in "${!delete_actions[@]}"; do
        _fw_ufw_delete "${delete_actions[$i]}" "${delete_targets[$i]}" || { error "删除 ${delete_targets[$i]} 失败"; return 1; }
    done
    success "已删除规则: ${delete_targets[*]}"
}

do_allow_ip() {
    _ensure_ufw || return 1
    echo ""
    read -r -p "  输入要放行的 IP 或 IP 段 (如 1.2.3.4 或 10.0.0.0/24): " ip
    [ -z "$ip" ] && info "已取消" && return
    _fw_is_ip "$ip" || { error "格式无效（需 IPv4 或 CIDR，如 1.2.3.4 或 10.0.0.0/24）"; return 1; }
    warn "即将放行来自 $ip 的所有入站连接"
    read -r -p "  确认放行? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    if sudo ufw allow from "$ip"; then
        success "已放行 IP $ip"
        [[ "$(ufw status | head -1)" == "Status: active" ]] || info "防火墙未启用，规则已保存但暂不生效"
    fi
}

do_block_ip() {
    _ensure_ufw || return 1
    echo ""
    read -r -p "  输入要封锁的 IP 或 IP 段: " ip
    [ -z "$ip" ] && info "已取消" && return
    _fw_is_ip "$ip" || { error "格式无效（需 IPv4 或 CIDR，如 1.2.3.4 或 10.0.0.0/24）"; return 1; }
    warn "即将封锁来自 $ip 的所有入站连接"
    read -r -p "  确认封锁? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    sudo ufw deny from "$ip" && success "已封锁 IP $ip"
}

# 列出 ALLOW/DENY 的 IP 规则，输出 "ufw编号 IP"
_fw_ip_list() {
    local action="$1" line num target
    while IFS= read -r line; do
        [[ "$line" =~ ^\[[[:space:]]*([0-9]+)\][[:space:]]+([^[:space:]]+)[[:space:]]+(ALLOW|DENY)[[:space:]]+IN(.*)$ ]] || continue
        [ "${BASH_REMATCH[3]}" = "$action" ] || continue
        num=${BASH_REMATCH[1]}
        target=${BASH_REMATCH[2]}
        _fw_is_ip "$target" || continue
        printf '%s %s\n' "$num" "$target"
    done < <(_fw_rule_lines)
}

# 白/黑名单子菜单：先预览现有规则，再选择添加或删除
_fw_ip_submenu() {
    local mode="$1" label action_cmd
    local -a nums=() ips=()
    local choice num ip i confirm
    if [ "$mode" = allow ]; then
        label="IP 白名单"
        action_cmd="allow from"
    else
        label="IP 黑名单"
        action_cmd="deny from"
    fi
    while true; do
        echo ""
        title "$label"
        nums=()
        ips=()
        while read -r num ip; do
            nums+=("$num")
            ips+=("$ip")
        done < <(_fw_ip_list "$([ "$mode" = allow ] && echo ALLOW || echo DENY)")
        echo ""
        if [ "${#ips[@]}" -eq 0 ]; then
            info "当前没有${label#IP }记录"
        else
            for i in "${!ips[@]}"; do
                echo "  [$((i + 1))] ${ips[$i]}"
            done
        fi
        echo ""
        _menu_actions 20 "${C_BOLD}[1]${C_RESET} 添加"
        [ "${#ips[@]}" -gt 0 ] && _menu_actions 20 "${C_BOLD}[2]${C_RESET} 删除"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回"
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1)
                if [ "$mode" = allow ]; then do_allow_ip; else do_block_ip; fi
                ;;
            2)
                if [ "${#ips[@]}" -eq 0 ]; then
                    error "没有可删除的 $label"
                    sleep 1
                    continue
                fi
                read -r -p "  输入要删除的编号: " num
                if ! [[ "$num" =~ ^[1-9][0-9]*$ ]] || (( num > ${#ips[@]} )); then
                    error "编号无效"
                    sleep 1
                    continue
                fi
                ip=${ips[$((num - 1))]}
                warn "即将删除 $label: $ip"
                read -r -p "  确认删除? [y/N]: " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; continue; }
                sudo ufw delete "$action_cmd" "$ip" && success "已删除 $ip"
                ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}

do_allow_listeners() {
    local -a ports=() items=() to_allow=() idx=()
    local key name line token start end i confirm port_proto choice
    while read -r key name; do
        ports+=("$key")
        items+=("$key ($name)")
    done < <(_fw_unallowed_listeners)
    echo ""
    if [ "${#ports[@]}" -eq 0 ]; then
        info "没有需要放行的监听端口"
        return 0
    fi
    for i in "${!ports[@]}"; do
        echo "  $((i + 1))) ${items[$i]}"
    done
    echo ""
    read -r -p "  选择编号（如 1 3 或 1-3；全部放行输入 a）: " choice
    [ -z "$choice" ] && info "已取消" && return 0
    local -A pick=()
    for token in ${choice//,/ }; do
        if [[ "$token" =~ ^[Aa](ll)?$ ]]; then
            for i in "${!ports[@]}"; do pick[$i]=1; done
        elif [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start=${BASH_REMATCH[1]}
            end=${BASH_REMATCH[2]}
            for ((i = start; i <= end; i++)); do
                (( i >= 1 && i <= ${#ports[@]} )) && pick[$((i - 1))]=1
            done
        elif [[ "$token" =~ ^[0-9]+$ ]] && (( token >= 1 && token <= ${#ports[@]} )); then
            pick[$((token - 1))]=1
        fi
    done
    if [ "${#pick[@]}" -eq 0 ]; then
        info "没有有效的编号，已取消"
        return 0
    fi
    for i in "${!pick[@]}"; do idx+=("$i"); done
    mapfile -t idx < <(printf '%s\n' "${idx[@]}" | sort -n)
    for i in "${idx[@]}"; do to_allow+=("${ports[$i]}"); done
    warn "即将放行:"
    for port_proto in "${to_allow[@]}"; do
        echo "    - $port_proto"
    done
    read -r -p "  确认放行? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    for port_proto in "${to_allow[@]}"; do
        sudo ufw allow "$port_proto" || { error "放行 $port_proto 失败"; return 1; }
    done
    success "已放行: ${to_allow[*]}"
    [[ "$(ufw status | head -1)" == "Status: active" ]] || info "防火墙未启用，规则已保存但暂不生效"
}

do_enable() {
    _ensure_ufw || return 1
    echo ""
    local -a ssh_ports
    local port_list=""
    mapfile -t ssh_ports < <(_fw_ssh_ports)
    if [ "${#ssh_ports[@]}" -eq 0 ]; then
        error "未检测到 SSH 监听端口，已取消开启（防止把自己锁在门外）"
        return 1
    fi
    printf -v port_list '%s ' "${ssh_ports[@]}"
    port_list=${port_list% }
    warn "开启后，未明确放行的入站连接将被阻止"
    warn "将自动放行 SSH 监听端口: $port_list"
    read -r -p "  确认开启? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    for port in "${ssh_ports[@]}"; do
        sudo ufw allow "$port/tcp" || { error "放行 SSH 端口 $port/tcp 失败，已取消开启"; return 1; }
    done
    sudo ufw --force enable && success "防火墙已开启，已放行 SSH 端口 $port_list"
}

do_disable() {
    _ensure_ufw || return 1
    echo ""
    warn "关闭防火墙后所有入站限制将失效"
    read -r -p "  确认关闭? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    sudo ufw disable && success "防火墙已关闭"
}

menu() {
    local choice fw_status rule_count
    while true; do
        clear
        title "🛡 防火墙管理"
        do_status
        divider
        rule_count=$(_fw_rule_lines | awk '/^\[[[:space:]]*[0-9]+\]/ { count++ } END { print count + 0 }')
        if [ "$rule_count" -gt 0 ]; then
            _menu_actions 20 "${C_BOLD}$(kairo_menu_range "$rule_count" "删除规则")${C_RESET}"
        fi
        _menu_actions 20 "${C_BOLD}[O]${C_RESET} 开放端口"
        _menu_actions 20 "${C_BOLD}[U]${C_RESET} 放行未放行端口"
        _menu_actions 20 "${C_BOLD}[C]${C_RESET} 按端口关闭"
        _menu_actions 20 "${C_BOLD}[A]${C_RESET} IP 白名单"
        _menu_actions 20 "${C_BOLD}[B]${C_RESET} IP 黑名单"
        fw_status=$(ufw status 2>/dev/null | head -1 | sed 's/Status: //')
        if ! command -v ufw &>/dev/null; then
            _menu_actions 20 "${C_BOLD}[I]${C_RESET} 安装 ufw"
        elif [ "$fw_status" = "active" ]; then
            _menu_actions 20 "${C_RED}${C_BOLD}[D]${C_RESET}${C_RED} 关闭防火墙${C_RESET}"
        else
            _menu_actions 20 "${C_GREEN}${C_BOLD}[E]${C_RESET}${C_GREEN} 开启防火墙${C_RESET}"
        fi
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  选择规则或操作: " choice
        case "$choice" in
            [Oo]) do_open_port; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Uu]) do_allow_listeners; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Cc]) do_close_port; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Aa]) _fw_ip_submenu allow ;;
            [Bb]) _fw_ip_submenu block ;;
            [Ee]) do_enable; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Dd]) do_disable; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Ii]) do_install; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            0) return ;;
            *)
                if [[ "$choice" =~ ^[0-9]+([[:space:],-]+[0-9]+)*$ ]]; then
                    do_delete_rule "$choice"
                    echo ""; kairo_pause "按 Enter 返回防火墙规则..."
                else
                    error "无效选项"; sleep 1
                fi
                ;;
        esac
    done
}
