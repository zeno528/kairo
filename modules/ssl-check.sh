#!/bin/bash
# ssl-check 模块 - SSL 证书检查

LE_LIVE_DIR="${LE_LIVE_DIR:-/etc/letsencrypt/live}"

_check_openssl() {
    if ! command -v openssl &>/dev/null; then
        error "未安装 openssl"
        return 1
    fi
}

_local_cert_files() {
    [ -d "$LE_LIVE_DIR" ] || return 0
    find "$LE_LIVE_DIR" -mindepth 2 -maxdepth 2 -type f -name fullchain.pem -print 2>/dev/null
}

_get_local_cert_days() {
    local end_date end_epoch
    end_date=$(openssl x509 -in "$1" -noout -enddate 2>/dev/null | cut -d= -f2)
    end_epoch=$(date -d "$end_date" +%s 2>/dev/null)
    [ -n "$end_epoch" ] || { echo "-1"; return; }
    echo $(( (end_epoch - $(date +%s)) / 86400 ))
}

# 在有限时间内完成一次 TLS 握手，输出供后续解析的证书数据。
_get_remote_cert() {
    local host="$1"
    local port="${2:-443}"

    timeout 15 openssl s_client -servername "$host" -connect "$host:$port" </dev/null 2>/dev/null
}

# 解析已获取的证书日期，返回剩余天数。
_get_cert_days() {
    local cert_data="$1"
    local end_date
    end_date=$(printf '%s\n' "$cert_data" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -z "$end_date" ]; then
        echo "-1"
        return
    fi
    local end_epoch
    end_epoch=$(date -d "$end_date" +%s 2>/dev/null)
    if [ -z "$end_epoch" ]; then
        echo "-1"
        return
    fi
    local now_epoch
    now_epoch=$(date +%s)
    echo $(( (end_epoch - now_epoch) / 86400 ))
}

# 显示已获取的证书详情。
_show_cert_info() {
    printf '%s\n' "$1" | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null | \
        sed 's/^/  /'
}

do_local_check() {
    _check_openssl || return
    local certs=() cert_path choice days
    mapfile -t certs < <(_local_cert_files)

    if [ "${#certs[@]}" -eq 0 ]; then
        info "未发现 Let's Encrypt 证书"
        read -p "  输入其他证书文件路径（直接回车取消）: " cert_path
        [ -z "$cert_path" ] && info "已取消" && return
    else
        echo ""
        echo -e "  ${C_BOLD}已发现的本机证书${C_RESET}"
        local i
        for i in "${!certs[@]}"; do
            printf "  [%d] %s\n" "$((i + 1))" "$(basename "$(dirname "${certs[$i]}")")"
        done
        echo "  [0] 手动输入其他路径"
        echo ""
        read -p "  选择证书编号（直接回车取消）: " choice
        [ -z "$choice" ] && info "已取消" && return
        if [ "$choice" = "0" ]; then
            read -p "  输入其他证书文件路径: " cert_path
        elif [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#certs[@]}" ]; then
            cert_path="${certs[$((choice - 1))]}"
        else
            error "编号无效"
            return 1
        fi
    fi
    [ -z "$cert_path" ] && info "已取消" && return
    if [ ! -f "$cert_path" ]; then
        error "文件不存在: $cert_path"
        return
    fi
    echo ""
    openssl x509 -in "$cert_path" -noout -subject -issuer -dates 2>/dev/null | sed 's/^/  /'
    echo ""
    days=$(_get_local_cert_days "$cert_path")
    if [ "$days" -lt 0 ]; then
        echo -e "  ${C_RED}证书已过期${C_RESET}"
    elif [ "$days" -lt 30 ]; then
        echo -e "  ${C_YELLOW}剩余 $days 天（即将过期）${C_RESET}"
    else
        echo -e "  ${C_GREEN}剩余 $days 天${C_RESET}"
    fi
}

do_remote_check() {
    _check_openssl || return
    local certs=() choice cert_data days
    mapfile -t certs < <(_local_cert_files)
    if [ "${#certs[@]}" -gt 0 ]; then
        echo ""
        echo -e "  ${C_BOLD}已发现的本机域名${C_RESET}"
        local i
        for i in "${!certs[@]}"; do
            printf "  [%d] %s\n" "$((i + 1))" "$(basename "$(dirname "${certs[$i]}")")"
        done
        echo "  [0] 输入其他域名"
        echo ""
        read -p "  选择域名编号（直接回车取消）: " choice
        [ -z "$choice" ] && info "已取消" && return
        if [ "$choice" = "0" ]; then
            read -p "  输入域名: " domain
        elif [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#certs[@]}" ]; then
            domain=$(basename "$(dirname "${certs[$((choice - 1))]}")")
        else
            error "编号无效"
            return 1
        fi
    else
        read -p "  输入域名: " domain
    fi
    [ -z "$domain" ] && info "已取消" && return
    kairo_is_host "$domain" || { error "域名或主机名格式不合法"; return 1; }
    read -p "  端口号 (默认 443): " port
    port=${port:-443}
    kairo_is_port "$port" || { error "端口必须是 1-65535"; return 1; }

    _start_spinner "正在获取 $domain 的证书"
    cert_data=$(_get_remote_cert "$domain" "$port")
    local fetch_status=$?
    _stop_spinner
    if [ "$fetch_status" -ne 0 ] || [ -z "$cert_data" ]; then
        error "无法在 15 秒内获取证书信息"
        return 1
    fi

    echo ""
    _show_cert_info "$cert_data"
    echo ""
    days=$(_get_cert_days "$cert_data")
    if [ "$days" -lt 0 ]; then
        echo -e "  ${C_RED}无法获取证书信息或证书已过期${C_RESET}"
    elif [ "$days" -lt 30 ]; then
        echo -e "  ${C_YELLOW}剩余 $days 天（即将过期）${C_RESET}"
    else
        echo -e "  ${C_GREEN}剩余 $days 天${C_RESET}"
    fi
}

do_batch_check() {
    _check_openssl || return
    local certs=()
    mapfile -t certs < <(_local_cert_files)
    if [ "${#certs[@]}" -eq 0 ]; then
        info "未发现 Let's Encrypt 证书"
        return
    fi
    echo ""
    info "检查 ${#certs[@]} 个本机证书的到期时间"
    echo -e "  ${C_BOLD}域名${C_RESET}                        ${C_BOLD}剩余天数${C_RESET}  ${C_BOLD}状态${C_RESET}"
    echo -e "  ${C_GRAY}────────────────────────── ─────── ──────${C_RESET}"
    local cert_path domain days
    for cert_path in "${certs[@]}"; do
        domain=$(basename "$(dirname "$cert_path")")
        days=$(_get_local_cert_days "$cert_path")
        if [ "$days" -lt 0 ]; then
            printf "  %-26s ${C_RED}%6s  %s${C_RESET}\n" "$domain" "N/A" "无法读取"
        elif [ "$days" -lt 30 ]; then
            printf "  %-26s ${C_YELLOW}%6s  %s${C_RESET}\n" "$domain" "$days" "即将过期"
        else
            printf "  %-26s ${C_GREEN}%6s  %s${C_RESET}\n" "$domain" "$days" "正常"
        fi
    done
}

menu() {
    while true; do
        clear
        title "🔒 SSL 证书检查"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 查看本机证书"
        echo -e "  ${C_BOLD}[2]${C_RESET} 检查远程域名证书"
        echo -e "  ${C_BOLD}[3]${C_RESET} 批量检查本机证书到期"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_local_check; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            2) do_remote_check; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            3) do_batch_check; echo ""; kairo_pause "按 Enter 返回当前菜单..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
