#!/bin/bash
# swap 模块 - 虚拟内存管理（zram / disk swap）

# ── 状态查看 ────────────────────────────────────────────────

do_status() {
    echo ""
    local has_swap=0

    # zram 设备
    if lsblk 2>/dev/null | grep -q zram; then
        has_swap=1
        echo -e "  ${C_BOLD}虚拟内存状态${C_RESET}"
        echo ""
        local zram_dev zram_size
        zram_dev=$(zramctl -n 2>/dev/null | head -1 | awk '{print $1}')
        zram_size=$(zramctl -n 2>/dev/null | head -1 | awk '{print $4}')
        echo -e "  $(_pad_right "类型:" 6) ${C_GREEN}zram 内存压缩${C_RESET}"
        echo -e "  $(_pad_right "设备:" 6) $zram_dev"
        echo -e "  $(_pad_right "大小:" 6) $zram_size"
        echo ""
    fi

    # 磁盘 swap
    if swapon --show --noheadings 2>/dev/null | grep -qv zram; then
        [ "$has_swap" -eq 0 ] && { echo -e "  ${C_BOLD}虚拟内存状态${C_RESET}"; echo ""; }
        has_swap=1
        local label_w=6
        while IFS= read -r line; do
            [[ "$line" == *zram* ]] && continue
            local name type size used
            read -r name type size used _ <<< "$line"
            echo -e "  $(_pad_right "类型:" $label_w) ${C_CYAN}磁盘${C_RESET}（${type}）"
            echo -e "  $(_pad_right "路径:" $label_w) ${C_DIM}${name}${C_RESET}"
            echo -e "  $(_pad_right "大小:" $label_w) ${size}B"
            echo -e "  $(_pad_right "已用:" $label_w) ${used}B"
            echo ""
        done < <(swapon --show --noheadings 2>/dev/null)
    fi

    # 汇总行
    if [ "$has_swap" -eq 1 ]; then
        local swap_total swap_used auto_label
        swap_total=$(free -h | awk '/Swap:/{print $2}')
        swap_used=$(free -h | awk '/Swap:/{print $3}')
        # 检查开机自启
        if crontab -l 2>/dev/null | grep -q 'ka swap zram'; then
            auto_label="${C_GREEN}是${C_RESET}（@reboot cron）"
        elif grep -q '^/swapfile ' /etc/fstab 2>/dev/null; then
            auto_label="${C_GREEN}是${C_RESET}（fstab）"
        else
            auto_label="${C_DIM}否${C_RESET}"
        fi
        divider
        echo -e "  $(_pad_right "总计:" 6) ${swap_total}  /  已用 ${swap_used}"
        echo -e "  $(_pad_right "自启:" 6) $auto_label"
    else
        warn "当前未启用任何虚拟内存"
        echo ""
        echo -e "  ${C_GREEN}zram${C_RESET}  —  内存压缩，速度快，适合小内存 VPS"
        echo -e "  ${C_DIM}disk${C_RESET}  —  传统磁盘交换文件，速度较慢但容量大"
    fi
}

# ── zram 管理 ────────────────────────────────────────────────

_zram_loaded() {
    lsmod 2>/dev/null | grep -q zram
}

_zram_enabled() {
    lsblk 2>/dev/null | grep -q zram
}

do_zram() {
    echo ""
    if _zram_enabled; then
        local zram_dev zram_size zram_algo label_w=6
        zram_dev=$(zramctl -n 2>/dev/null | head -1 | awk '{print $1}')
        zram_size=$(zramctl -n 2>/dev/null | head -1 | awk '{print $4}')
        zram_algo=$(zramctl -n 2>/dev/null | head -1 | awk '{print $2}')
        echo -e "  $(_pad_right "设备:" $label_w) ${C_GREEN}${zram_dev}${C_RESET}"
        echo -e "  $(_pad_right "大小:" $label_w) $zram_size"
        echo -e "  $(_pad_right "算法:" $label_w) ${C_DIM}${zram_algo}${C_RESET}"
        echo ""
        read -r -p "  重新配置大小? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || return 0
        do_disable
    fi

    local choice size
    echo ""
    echo -e "  ${C_BOLD}选择 zram 大小${C_RESET}"
    echo ""
    _menu_actions 24 "${C_BOLD}[1]${C_RESET} 512M （推荐 1-2G 内存 VPS）"
    _menu_actions 24 "${C_BOLD}[2]${C_RESET} 1G"
    _menu_actions 24 "${C_BOLD}[3]${C_RESET} 自定义大小"
    _menu_actions 24 "${C_BOLD}[0]${C_RESET} 取消"
    divider
    echo ""
    read -r -p "  (1-3): " choice

    case "$choice" in
        1) size="512M" ;;
        2) size="1G" ;;
        3)
            echo ""
            echo -e "  ${C_DIM}格式: 数字+M 或 数字+G，如 768M、3G${C_RESET}"
            read -r -p "  输入大小: " size
            if ! [[ "$size" =~ ^[1-9][0-9]*[mMgG]$ ]]; then
                error "格式无效，请输入如 768M 或 3G"
                return 1
            fi
            # 统一转大写
            size="${size^^}"
            ;;
        0|"") info "已取消"; return 0 ;;
        *) error "无效选项"; return 1 ;;
    esac

    # 加载模块
    if ! _zram_loaded; then
        _start_spinner "正在加载 zram 模块"
        if ! sudo modprobe zram 2>/dev/null; then
            _stop_spinner
            error "zram 模块加载失败（内核不支持？）"
            return 1
        fi
        _stop_spinner
    fi

    # 配置设备
    _start_spinner "正在配置 zram ($size)"
    if ! sudo zramctl -f -s "$size" 2>/dev/null; then
        _stop_spinner
        error "zram 设备创建失败"
        return 1
    fi

    # 获取设备名
    local zram_dev
    zram_dev=$(zramctl -n 2>/dev/null | tail -1 | awk '{print $1}')
    [ -z "$zram_dev" ] && { _stop_spinner; error "无法获取 zram 设备名"; return 1; }

    if ! sudo mkswap "$zram_dev" >/dev/null 2>&1; then
        _stop_spinner
        error "mkswap $zram_dev 失败"
        return 1
    fi

    if ! sudo swapon "$zram_dev" 2>/dev/null; then
        _stop_spinner
        error "swapon $zram_dev 失败"
        return 1
    fi
    _stop_spinner

    echo ""
    success "zram 已启用 ($size)，立即生效"
    local zram_dev zram_size zram_algo
    zram_dev=$(zramctl -n 2>/dev/null | tail -1 | awk '{print $1}')
    zram_size=$(zramctl -n 2>/dev/null | tail -1 | awk '{print $4}')
    zram_algo=$(zramctl -n 2>/dev/null | tail -1 | awk '{print $2}')
    echo -e "  $(_pad_right "设备:" 6) $zram_dev"
    echo -e "  $(_pad_right "大小:" 6) $zram_size"
    echo -e "  $(_pad_right "算法:" 6) ${C_DIM}${zram_algo}${C_RESET}"
    info "重启后不会自动启用，菜单 [3] 可设开机自启"
}

# ── 磁盘 Swap ────────────────────────────────────────────────

do_swap() {
    echo ""
    if swapon --show 2>/dev/null | grep -qv zram; then
        local existing
        existing=$(swapon --show 2>/dev/null | grep -v zram | awk 'NR>1{print $1}')
        info "已有磁盘 swap: $existing"
        echo ""
        read -r -p "  重新配置? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || return 0
        do_disable
    fi

    local choice size swapfile="/swapfile"
    echo ""
    echo -e "  ${C_BOLD}选择 Swap 文件大小${C_RESET}"
    echo ""
    _menu_actions 24 "${C_BOLD}[1]${C_RESET} 512M"
    _menu_actions 24 "${C_BOLD}[2]${C_RESET} 1G"
    _menu_actions 24 "${C_BOLD}[3]${C_RESET} 2G"
    _menu_actions 24 "${C_BOLD}[4]${C_RESET} 4G"
    _menu_actions 24 "${C_BOLD}[0]${C_RESET} 取消"
    divider
    echo ""
    read -r -p "  (1-4): " choice

    case "$choice" in
        1) size="512M" ;;
        2) size="1G" ;;
        3) size="2G" ;;
        4) size="4G" ;;
        0|"") info "已取消"; return 0 ;;
        *) error "无效选项"; return 1 ;;
    esac

    _start_spinner "正在创建 swap 文件 ($size)"
    if [ -f "$swapfile" ]; then
        sudo swapoff "$swapfile" 2>/dev/null || true
        sudo rm -f "$swapfile"
    fi

    if ! sudo fallocate -l "$size" "$swapfile" 2>/dev/null; then
        # fallocate 可能不支持某些文件系统，fallback 到 dd
        local blocks=$(( ${size%[MG]} * 1024 ))
        [ "${size: -1}" = "M" ] && blocks=$(( ${size%M} ))
        sudo dd if=/dev/zero of="$swapfile" bs=1M count="$blocks" status=none 2>/dev/null || {
            _stop_spinner
            error "创建 swap 文件失败"
            return 1
        }
    fi

    sudo chmod 600 "$swapfile"
    sudo mkswap "$swapfile" >/dev/null 2>&1 || { _stop_spinner; error "mkswap 失败"; return 1; }
    sudo swapon "$swapfile" 2>/dev/null || { _stop_spinner; error "swapon 失败"; return 1; }
    _stop_spinner

    # 持久化到 fstab
    if ! grep -q "^$swapfile " /etc/fstab 2>/dev/null; then
        echo "$swapfile none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
    fi

    echo ""
    success "Swap 已启用 ($size)"
    local swap_total
    swap_total=$(free -h | awk '/Swap:/{print $2}')
    echo -e "  $(_pad_right "路径:" 6) ${C_DIM}/swapfile${C_RESET}"
    echo -e "  $(_pad_right "大小:" 6) ${swap_total}"
    info "已写入 /etc/fstab，重启后自动生效"
}

# ── 关闭 ────────────────────────────────────────────────────

do_disable() {
    echo ""
    local has_any=0

    # 关闭所有 swap
    if swapon --show 2>/dev/null | grep -q .; then
        has_any=1
        _start_spinner "正在关闭所有 swap"
        sudo swapoff -a 2>/dev/null || true
        _stop_spinner
    fi

    # 移除 zram 设备
    if lsblk 2>/dev/null | grep -q zram; then
        has_any=1
        local zram_dev
        for zram_dev in $(lsblk -nro NAME 2>/dev/null | grep '^zram'); do
            sudo zramctl -r "/dev/$zram_dev" 2>/dev/null || true
        done
    fi

    # 删除 swap 文件
    if [ -f /swapfile ]; then
        has_any=1
        sudo rm -f /swapfile
        sudo sed -i '\|^/swapfile |d' /etc/fstab 2>/dev/null || true
    fi

    if [ "$has_any" -eq 0 ]; then
        info "未启用任何虚拟内存"
        return 0
    fi

    echo ""
    success "虚拟内存已关闭"
}

# ── 开机自启（zram）───────────────────────────────────────────

do_autostart() {
    echo ""
    if crontab -l 2>/dev/null | grep -q 'zram'; then
        local entry
        entry=$(crontab -l 2>/dev/null | grep 'zram')
        info "已有 @reboot 任务: $entry"
        echo ""
        read -r -p "  移除开机自启? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || return 0
        crontab -l 2>/dev/null | grep -v 'zram' | crontab - || true
        success "已移除开机自启"
        return 0
    fi

    if ! _zram_enabled; then
        warn "请先启用 zram"
        return 1
    fi

    local entry="@reboot sleep 10 && ka swap zram"
    echo ""
    info "将添加 @reboot cron 任务，开机 10 秒后自动启用 zram"
    read -r -p "  确认? [Y/n]: " confirm
    [[ "$confirm" =~ ^([Nn]|[Nn][Oo])$ ]] && { info "已取消"; return 0; }
    (crontab -l 2>/dev/null; echo "$entry") | crontab - && success "已添加开机自启"
}

# ── 菜单 ────────────────────────────────────────────────────

menu() {
    local choice
    while true; do
        clear
        title "💾 虚拟内存"
        do_status
        divider
        _menu_actions 24 "${C_BOLD}[1]${C_RESET} zram 内存压缩 ${C_GREEN}(推荐)${C_RESET}"
        _menu_actions 24 "${C_BOLD}[2]${C_RESET} 磁盘 Swap 文件"
        _menu_actions 24 "${C_BOLD}[3]${C_RESET} 开机自启 (zram)"
        _menu_actions 24 "${C_BOLD}[4]${C_RESET} 关闭虚拟内存"
        _menu_actions 24 "${C_BOLD}[0]${C_RESET} 返回主菜单"
        divider
        echo ""
        read -r -p "  请选择: " choice
        case "$choice" in
            1) do_zram; echo ""; kairo_pause ;;
            2) do_swap; echo ""; kairo_pause ;;
            3) do_autostart; echo ""; kairo_pause ;;
            4) do_disable; echo ""; kairo_pause ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
