#!/bin/bash
# ssh-keys 模块 - SSH 公钥管理

AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"

# 根据编号获取实际文件行号
_get_line_num() {
    local target_num=$1
    local line_num=0
    local file_line=0
    while IFS= read -r line; do
        file_line=$((file_line + 1))
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line_num=$((line_num + 1))
        if [ "$line_num" -eq "$target_num" ]; then
            echo "$file_line"
            return
        fi
    done < "$AUTHORIZED_KEYS"
    echo "0"
}

do_list() {
    echo ""
    if [ ! -f "$AUTHORIZED_KEYS" ]; then
        warn "未找到 authorized_keys 文件: $AUTHORIZED_KEYS"
        return
    fi

    local count=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        count=$((count + 1))
        local key_type
        local comment
        key_type=$(awk '{print $1}' <<< "$line")
        comment=$(awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' <<< "$line" | sed 's/[[:space:]]*$//')
        if [ ${#comment} -gt 50 ]; then
            comment="${comment:0:47}..."
        fi
        printf "  ${C_DIM}[%d]${C_RESET}  %-12s %s\n" "$count" "$key_type" "${comment:-（无注释）}"
    done < "$AUTHORIZED_KEYS"

    if [ "$count" -eq 0 ]; then
        warn "authorized_keys 为空"
    else
        echo ""
        info "共 $count 个公钥"
    fi
}

do_add() {
    echo ""
    read -r -p "  粘贴公钥内容（ssh-rsa / ssh-ed25519 开头）: " key
    key=${key%$'\r'}
    [ -z "$key" ] && info "已取消" && return

    local key_type key_data key_comment
    read -r key_type key_data key_comment <<< "$key"
    case "$key_type" in
        ssh-rsa|ssh-ed25519|ecdsa-sha2-*|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ;;
        *)
            error "公钥类型不受支持: $key_type"
            return 1
            ;;
    esac
    if [ -z "$key_data" ] || [[ ! "$key_data" =~ ^[A-Za-z0-9+/]+={0,3}$ ]]; then
        error "公钥格式不正确，应以 ssh-rsa / ssh-ed25519 等开头"
        return 1
    fi

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$AUTHORIZED_KEYS"
    if awk -v type="$key_type" -v data="$key_data" \
        '$1 == type && $2 == data { found=1 } END { exit !found }' "$AUTHORIZED_KEYS"; then
        warn "该公钥已存在"
        return 1
    fi
    if [ -n "$key_comment" ]; then
        printf '%s %s %s\n' "$key_type" "$key_data" "$key_comment" >> "$AUTHORIZED_KEYS"
    else
        printf '%s %s\n' "$key_type" "$key_data" >> "$AUTHORIZED_KEYS"
    fi
    chmod 600 "$AUTHORIZED_KEYS"
    success "公钥已添加"
}

do_remove() {
    local input="${1:-}"
    echo ""
    if [ ! -f "$AUTHORIZED_KEYS" ]; then
        warn "未找到 authorized_keys 文件"
        return
    fi

    if [ -z "$input" ]; then
        do_list
        echo ""
        read -p "  输入要删除的编号（空格分隔多个）: " input
    fi
    [ -z "$input" ] && info "已取消" && return

    # 解析编号并验证
    local nums=() invalid=""
    local input_nums=()
    read -r -a input_nums <<< "$input"
    for n in "${input_nums[@]}"; do
        [[ ! "$n" =~ ^[0-9]+$ ]] && invalid="$invalid $n" && continue
        local line
        line=$(_get_line_num "$n")
        if [ "$line" -eq 0 ]; then
            invalid="$invalid $n"
        else
            nums+=("$n")
        fi
    done
    [ -n "$invalid" ] && warn "跳过无效编号:$invalid"
    [ ${#nums[@]} -eq 0 ] && error "没有有效的编号" && return

    # 显示待删除列表
    echo ""
    for n in "${nums[@]}"; do
        local tl
        local kc
        tl=$(_get_line_num "$n")
        kc=$(sed -n "${tl}p" "$AUTHORIZED_KEYS" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//')
        warn "  [$n] ${kc:-（无注释）}"
    done

    read -p "  确认删除 ${#nums[@]} 个公钥? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # 从大到小排序，避免删除后行号偏移
        local sorted=()
        mapfile -t sorted < <(printf '%s\n' "${nums[@]}" | sort -rn)
        for n in "${sorted[@]}"; do
            local tl
            tl=$(_get_line_num "$n")
            [ "$tl" -gt 0 ] && sed -i "${tl}d" "$AUTHORIZED_KEYS"
        done
        success "已删除 ${#nums[@]} 个公钥"
    else
        info "已取消"
    fi
}

do_view() {
    local num="${1:-}"
    echo ""
    if [ ! -f "$AUTHORIZED_KEYS" ]; then
        warn "未找到 authorized_keys 文件"
        return
    fi

    if [ -z "$num" ]; then
        do_list
        echo ""
        read -p "  输入编号查看完整公钥: " num
    fi
    [ -z "$num" ] && info "已取消" && return
    [[ ! "$num" =~ ^[0-9]+$ ]] && error "请输入数字" && return

    local target_line
    target_line=$(_get_line_num "$num")
    if [ "$target_line" -eq 0 ]; then
        error "编号 $num 不存在"
        return
    fi

    echo ""
    sed -n "${target_line}p" "$AUTHORIZED_KEYS"
}

do_rename() {
    local num="${1:-}"
    echo ""
    if [ ! -f "$AUTHORIZED_KEYS" ]; then
        warn "未找到 authorized_keys 文件"
        return
    fi

    if [ -z "$num" ]; then
        do_list
        echo ""
        read -p "  输入编号: " num
    fi
    [ -z "$num" ] && info "已取消" && return
    [[ ! "$num" =~ ^[0-9]+$ ]] && error "请输入数字" && return

    local target_line
    target_line=$(_get_line_num "$num")
    if [ "$target_line" -eq 0 ]; then
        error "编号 $num 不存在"
        return
    fi

    local old_line
    local key_part
    local old_comment
    old_line=$(sed -n "${target_line}p" "$AUTHORIZED_KEYS")
    key_part=$(awk '{print $1, $2}' <<< "$old_line")
    old_comment=$(awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' <<< "$old_line" | sed 's/[[:space:]]*$//')
    echo ""
    info "当前备注: ${old_comment:-（无）}"

    read -r -p "  输入新备注: " new_comment
    [ -z "$new_comment" ] && info "已取消" && return

    local new_line="${key_part} ${new_comment}"
    new_line=${new_line//\\/\\\\}
    sed -i "${target_line}c\\${new_line}" "$AUTHORIZED_KEYS"
    success "备注已修改: ${new_comment}"
}

menu() {
    local choice line action
    while true; do
        title "🗝 SSH 公钥管理"
        do_list
        divider
        echo -e "  ${C_BOLD}[编号]${C_RESET} 选择公钥    ${C_BOLD}[A]${C_RESET} 添加公钥"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  选择公钥或操作: " choice
        case "$choice" in
            [Aa]) do_add; echo ""; kairo_pause "按 Enter 返回公钥列表..." ;;
            0) return ;;
            *)
                [[ "$choice" =~ ^[0-9]+$ ]] || { error "无效选择"; sleep 1; continue; }
                line=$(_get_line_num "$choice")
                if [ "$line" -eq 0 ]; then
                    error "无效选择"; sleep 1; continue
                fi
                echo ""
                echo "  [1] 查看完整公钥  [2] 修改备注  [3] 删除公钥  [0] 返回列表"
                read -p "  选择操作: " action
                case "$action" in
                    1) do_view "$choice" ;;
                    2) do_rename "$choice" ;;
                    3) do_remove "$choice" ;;
                    0) continue ;;
                    *) error "无效选项"; sleep 1; continue ;;
                esac
                echo ""; kairo_pause "按 Enter 返回公钥列表..."
                ;;
        esac
    done
}
