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
    local status
    status=$(ufw status | head -1 | sed 's/Status: //')
    if [ "$status" = "active" ]; then
        status="${C_GREEN}●${C_RESET} $status"
    fi
    echo -e "  ${C_BOLD}防火墙状态${C_RESET}  $status"
    if [ "$status" = "inactive" ]; then
        warn "防火墙未启用；放行规则会保存，但暂不会拦截流量"
        info "开启时会自动放行 SSH 监听端口；未放行的端口将被拒绝，再选择 [E] 开启防火墙"
    fi
    echo ""
    local -A allowed_ports=() listener_names=()
    local key name line num pp rest action from proc
    local w_num w_pp w_action w_from cell_width i col_gap="   "
    local -a unallowed=() rows_num=() rows_pp=() rows_action=() rows_from=() rows_proc=()
    w_num=$(_str_width "编号")
    w_pp=$(_str_width "端口/协议")
    w_action=$(_str_width "动作")
    w_from=$(_str_width "来源")
    while read -r key name; do
        [ -n "$key" ] && listener_names["$key"]="$name"
    done < <(_fw_listeners | sort -u)
    while read -r key; do
        [ -n "$key" ] && allowed_ports["$key"]=1
    done < <(ufw status numbered 2>/dev/null | grep -oE '[0-9]+/(tcp|udp)' | sort -u)
    while IFS= read -r line; do
        [[ "$line" =~ ^\[[[:space:]]*([0-9]+)\][[:space:]]+([0-9]+/(tcp|udp))(.*)$ ]] || continue
        num=${BASH_REMATCH[1]}
        pp=${BASH_REMATCH[2]}
        rest=${BASH_REMATCH[4]}
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
        if [ -n "${listener_names[${pp%% *}]:-}" ]; then
            proc="(${listener_names[${pp%% *}]})"
        fi
        rows_num+=("[$num]")
        rows_pp+=("$pp")
        rows_action+=("$action")
        rows_from+=("$from")
        rows_proc+=("$proc")
        cell_width=$(_str_width "[$num]")
        (( cell_width > w_num )) && w_num=$cell_width
        cell_width=$(_str_width "$pp")
        (( cell_width > w_pp )) && w_pp=$cell_width
        cell_width=$(_str_width "$action")
        (( cell_width > w_action )) && w_action=$cell_width
        cell_width=$(_str_width "$from")
        (( cell_width > w_from )) && w_from=$cell_width
    done < <(ufw status numbered 2>/dev/null | tail -n +4)
    if [ "${#rows_num[@]}" -gt 0 ]; then
        printf "  %s%s%s%s%s%s%s%s%s\n" \
            "$(_pad_right "编号" "$w_num")" "$col_gap" \
            "$(_pad_right "端口/协议" "$w_pp")" "$col_gap" \
            "$(_pad_right "动作" "$w_action")" "$col_gap" \
            "$(_pad_right "来源" "$w_from")" "$col_gap" "进程"
        for i in "${!rows_num[@]}"; do
            printf "  %s%s%s%s%s%s%s%s%s\n" \
                "$(_pad_right "${rows_num[$i]}" "$w_num")" "$col_gap" \
                "$(_pad_right "${rows_pp[$i]}" "$w_pp")" "$col_gap" \
                "$(_pad_right "${rows_action[$i]}" "$w_action")" "$col_gap" \
                "$(_pad_right "${rows_from[$i]}" "$w_from")" "$col_gap" "${rows_proc[$i]}"
        done
    fi
    for key in "${!listener_names[@]}"; do
        [ -z "${allowed_ports[$key]:-}" ] && unallowed+=("$key (${listener_names[$key]})")
    done
    if [ "${#unallowed[@]}" -gt 0 ]; then
        echo ""
        warn "以下端口在监听但未放行:"
        while IFS= read -r item; do
            echo "    - $item"
        done < <(printf '%s\n' "${unallowed[@]}" | sort -V)
    fi
}

do_open_port() {
    _ensure_ufw || return 1
    echo ""
    read -r -p "  输入端口号: " port
    [ -z "$port" ] && info "已取消" && return
    kairo_is_port "$port" || { error "端口必须是 1-65535"; return 1; }
    read -r -p "  协议 (tcp/udp，默认 tcp；网页/SSH 用 tcp，Hysteria2 用 udp): " proto
    proto=${proto:-tcp}
    [[ "$proto" =~ ^(tcp|udp)$ ]] || { error "协议只能是 tcp 或 udp"; return 1; }
    warn "即将放行入站端口 $port/$proto"
    read -r -p "  确认放行? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    if sudo ufw allow "$port/$proto"; then
        success "已开放 $port/$proto"
        [[ "$(ufw status | head -1)" =~ active ]] || info "防火墙未启用，规则已保存但暂不生效"
    fi
}

do_close_port() {
    _ensure_ufw || return 1
    echo ""
    read -r -p "  输入端口号: " port
    [ -z "$port" ] && info "已取消" && return
    kairo_is_port "$port" || { error "端口必须是 1-65535"; return 1; }
    read -r -p "  协议 (tcp/udp，默认 tcp；网页/SSH 用 tcp，Hysteria2 用 udp): " proto
    proto=${proto:-tcp}
    [[ "$proto" =~ ^(tcp|udp)$ ]] || { error "协议只能是 tcp 或 udp"; return 1; }
    warn "即将关闭 $port/$proto，可能中断现有服务"
    read -r -p "  确认关闭? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    sudo ufw delete allow "$port/$proto" && success "已关闭 $port/$proto"
}

do_delete_rule() {
    local rule="$1"
    [[ "$rule" =~ ^[1-9][0-9]*$ ]] || { error "规则编号无效"; return 1; }
    warn "即将删除 ufw 规则 #$rule"
    read -r -p "  确认删除? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消"; return 0; }
    sudo ufw --force delete "$rule" && success "已删除规则 #$rule"
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
        [[ "$(ufw status | head -1)" =~ active ]] || info "防火墙未启用，规则已保存但暂不生效"
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
    local choice
    while true; do
        clear
        title "🛡 防火墙管理"
        do_status
        divider
        _menu_actions 20 "${C_BOLD}$(kairo_menu_range "$(ufw status numbered 2>/dev/null | awk '/^\[[[:space:]]*[0-9]+\]/ { count++ } END { print count + 0 }')" "删除规则")${C_RESET}"
        _menu_actions 20 "${C_BOLD}[O]${C_RESET} 开放端口"
        _menu_actions 20 "${C_BOLD}[C]${C_RESET} 按端口关闭"
        _menu_actions 20 "${C_BOLD}[A]${C_RESET} IP 白名单"
        _menu_actions 20 "${C_BOLD}[B]${C_RESET} IP 黑名单"
        _menu_actions 20 "${C_BOLD}[E]${C_RESET} 开启防火墙"
        _menu_actions 20 "${C_BOLD}[D]${C_RESET} 关闭防火墙"
        _menu_actions 20 "${C_BOLD}[I]${C_RESET} 安装 ufw"
        _menu_actions 20 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  选择规则或操作: " choice
        case "$choice" in
            [Oo]) do_open_port; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Cc]) do_close_port; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Aa]) do_allow_ip; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Bb]) do_block_ip; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Ee]) do_enable; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Dd]) do_disable; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            [Ii]) do_install; echo ""; kairo_pause "按 Enter 返回防火墙规则..." ;;
            0) return ;;
            *)
                if [[ "$choice" =~ ^[1-9][0-9]*$ ]]; then
                    do_delete_rule "$choice"
                    echo ""; kairo_pause "按 Enter 返回防火墙规则..."
                else
                    error "无效选项"; sleep 1
                fi
                ;;
        esac
    done
}
