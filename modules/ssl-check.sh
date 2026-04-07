#!/bin/bash
# ssl-check 模块 - SSL 证书检查

_check_openssl() {
    if ! command -v openssl &>/dev/null; then
        error "未安装 openssl"
        return 1
    fi
}

# 解析证书日期，返回剩余天数
_get_cert_days() {
    local host="$1"
    local port="${2:-443}"
    local end_date
    end_date=$(echo | openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null | \
        openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
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

# 显示证书详情
_show_cert_info() {
    local host="$1"
    local port="${2:-443}"
    echo ""
    echo | openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null | \
        openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null | \
        sed 's/^/  /'
}

do_local_check() {
    _check_openssl || return
    echo ""
    read -p "  输入证书文件路径 (如 /etc/ssl/certs/xxx.pem): " cert_path
    [ -z "$cert_path" ] && info "已取消" && return
    if [ ! -f "$cert_path" ]; then
        error "文件不存在: $cert_path"
        return
    fi
    echo ""
    openssl x509 -in "$cert_path" -noout -subject -issuer -dates 2>/dev/null | sed 's/^/  /'
    echo ""
    local end_date
    end_date=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
    local end_epoch
    end_epoch=$(date -d "$end_date" +%s 2>/dev/null)
    local now_epoch
    now_epoch=$(date +%s)
    local days=$(( (end_epoch - now_epoch) / 86400 ))
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
    echo ""
    read -p "  输入域名: " domain
    [ -z "$domain" ] && info "已取消" && return
    read -p "  端口号 (默认 443): " port
    port=${port:-443}
    _show_cert_info "$domain" "$port"
    echo ""
    local days
    days=$(_get_cert_days "$domain" "$port")
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
    echo ""
    echo -e "  ${C_DIM}输入域名列表，每行一个，输入空行结束${C_RESET}"
    echo ""
    local domains=()
    while true; do
        read -p "  域名: " domain
        [ -z "$domain" ] && break
        domains+=("$domain")
    done
    if [ ${#domains[@]} -eq 0 ]; then
        info "已取消"
        return
    fi
    echo ""
    echo -e "  ${C_BOLD}域名${C_RESET}                        ${C_BOLD}剩余天数${C_RESET}  ${C_BOLD}状态${C_RESET}"
    echo -e "  ${C_GRAY}────────────────────────── ─────── ──────${C_RESET}"
    for domain in "${domains[@]}"; do
        local days
        days=$(_get_cert_days "$domain")
        if [ "$days" -lt 0 ]; then
            printf "  %-26s ${C_RED}%6s  %s${C_RESET}\n" "$domain" "N/A" "连接失败/已过期"
        elif [ "$days" -lt 30 ]; then
            printf "  %-26s ${C_YELLOW}%6s  %s${C_RESET}\n" "$domain" "$days" "即将过期"
        else
            printf "  %-26s ${C_GREEN}%6s  %s${C_RESET}\n" "$domain" "$days" "正常"
        fi
    done
}

menu() {
    while true; do
        title "🔒 SSL 证书检查"
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 检查本机证书文件"
        echo -e "  ${C_BOLD}[2]${C_RESET} 检查远程域名证书"
        echo -e "  ${C_BOLD}[3]${C_RESET} 批量检查证书到期"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_local_check; echo ""; read -p "  按回车键继续..." ;;
            2) do_remote_check; echo ""; read -p "  按回车键继续..." ;;
            3) do_batch_check; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
