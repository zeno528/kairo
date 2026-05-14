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
        local key_type=$(echo "$line" | awk '{print $1}')
        local comment=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//')
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
    read -p "  粘贴公钥内容（ssh-rsa / ssh-ed25519 开头）: " key
    key=$(echo "$key" | tr -d '[:space:]')
    [ -z "$key" ] && info "已取消" && return

    if [[ ! "$key" =~ ^ssh-(rsa|ed25519|ecdsa|dss) ]]; then
        error "公钥格式不正确，应以 ssh-rsa / ssh-ed25519 等开头"
        return
    fi

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    echo "$key" >> "$AUTHORIZED_KEYS"
    chmod 600 "$AUTHORIZED_KEYS"
    success "公钥已添加"
}

do_remove() {
    echo ""
    if [ ! -f "$AUTHORIZED_KEYS" ]; then
        warn "未找到 authorized_keys 文件"
        return
    fi

    do_list
    echo ""
    read -p "  输入要删除的编号（空格分隔多个）: " input
    [ -z "$input" ] && info "已取消" && return

    # 解析编号并验证
    local nums=() invalid=""
    for n in $input; do
        [[ ! "$n" =~ ^[0-9]+$ ]] && invalid="$invalid $n" && continue
        local line=$(_get_line_num "$n")
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
        local tl=$(_get_line_num "$n")
        local kc=$(sed -n "${tl}p" "$AUTHORIZED_KEYS" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//')
        warn "  [$n] ${kc:-（无注释）}"
    done

    read -p "  确认删除 ${#nums[@]} 个公钥? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # 从大到小排序，避免删除后行号偏移
        local sorted=($(printf '%s\n' "${nums[@]}" | sort -rn))
        for n in "${sorted[@]}"; do
            local tl=$(_get_line_num "$n")
            [ "$tl" -gt 0 ] && sed -i "${tl}d" "$AUTHORIZED_KEYS"
        done
        success "已删除 ${#nums[@]} 个公钥"
    else
        info "已取消"
    fi
}

do_view() {
    echo ""
    if [ ! -f "$AUTHORIZED_KEYS" ]; then
        warn "未找到 authorized_keys 文件"
        return
    fi

    do_list
    echo ""
    read -p "  输入编号查看完整公钥: " num
    [ -z "$num" ] && info "已取消" && return
    [[ ! "$num" =~ ^[0-9]+$ ]] && error "请输入数字" && return

    local target_line=$(_get_line_num "$num")
    if [ "$target_line" -eq 0 ]; then
        error "编号 $num 不存在"
        return
    fi

    echo ""
    sed -n "${target_line}p" "$AUTHORIZED_KEYS"
}

do_rename() {
    echo ""
    if [ ! -f "$AUTHORIZED_KEYS" ]; then
        warn "未找到 authorized_keys 文件"
        return
    fi

    do_list
    echo ""
    read -p "  输入编号: " num
    [ -z "$num" ] && info "已取消" && return
    [[ ! "$num" =~ ^[0-9]+$ ]] && error "请输入数字" && return

    local target_line=$(_get_line_num "$num")
    if [ "$target_line" -eq 0 ]; then
        error "编号 $num 不存在"
        return
    fi

    local old_line=$(sed -n "${target_line}p" "$AUTHORIZED_KEYS")
    local key_part=$(echo "$old_line" | awk '{print $1, $2}')
    local old_comment=$(echo "$old_line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//')
    echo ""
    info "当前备注: ${old_comment:-（无）}"

    read -p "  输入新备注: " new_comment
    [ -z "$new_comment" ] && info "已取消" && return

    local new_line="${key_part} ${new_comment}"
    sed -i "${target_line}c\\${new_line}" "$AUTHORIZED_KEYS"
    success "备注已修改: ${new_comment}"
}

menu() {
    while true; do
        title "🗝 SSH 公钥管理"
        do_list
        divider
        echo -e "  ${C_BOLD}[1]${C_RESET} 添加公钥"
        echo -e "  ${C_BOLD}[2]${C_RESET} 删除公钥"
        echo -e "  ${C_BOLD}[3]${C_RESET} 查看公钥详情"
        echo -e "  ${C_BOLD}[4]${C_RESET} 修改公钥备注"
        echo -e "  ${C_BOLD}[0]${C_RESET} 返回上级"
        divider
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_add; echo ""; read -p "  按回车键继续..." ;;
            2) do_remove; echo ""; read -p "  按回车键继续..." ;;
            3) do_view; echo ""; read -p "  按回车键继续..." ;;
            4) do_rename; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}
