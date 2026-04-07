#!/bin/bash
# ssh-keys 模块 - SSH 公钥管理

AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"

do_list() {
    echo ""
    if [ ! -f "$AUTHORIZED_KEYS" ]; then
        echo "  未找到 authorized_keys 文件: $AUTHORIZED_KEYS"
        return
    fi

    local count=0
    while IFS= read -r line; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        count=$((count + 1))

        # 提取密钥类型和尾部注释（用户名/主机名）
        local key_type=$(echo "$line" | awk '{print $1}')
        local comment=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//')

        # 截断过长注释
        if [ ${#comment} -gt 50 ]; then
            comment="${comment:0:47}..."
        fi

        printf "  [%d] %-12s %s\n" "$count" "$key_type" "${comment:-（无注释）}"
    done < "$AUTHORIZED_KEYS"

    if [ "$count" -eq 0 ]; then
        echo "  authorized_keys 为空"
    else
        echo ""
        echo "  共 $count 个公钥"
    fi
}

do_add() {
    echo ""
    read -p "  粘贴公钥内容（ssh-rsa / ssh-ed25519 开头）: " key
    key=$(echo "$key" | tr -d '[:space:]')
    [ -z "$key" ] && echo "  已取消" && return

    # 简单校验
    if [[ ! "$key" =~ ^ssh-(rsa|ed25519|ecdsa|dss) ]]; then
        echo "  错误: 公钥格式不正确，应以 ssh-rsa / ssh-ed25519 等开头"
        return
    fi

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    echo "$key" >> "$AUTHORIZED_KEYS"
    chmod 600 "$AUTHORIZED_KEYS"
    echo "  公钥已添加"
}

do_remove() {
    echo ""
    if [ ! -f "$AUTHORIZED_KEYS" ]; then
        echo "  未找到 authorized_keys 文件"
        return
    fi

    do_list
    echo ""
    read -p "  输入要删除的编号: " num
    [ -z "$num" ] && echo "  已取消" && return

    # 校验输入是数字
    [[ ! "$num" =~ ^[0-9]+$ ]] && echo "  错误: 请输入数字" && return

    # 找到对应行号（跳过空行和注释）
    local line_num=0
    local target_line=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line_num=$((line_num + 1))
        if [ "$line_num" -eq "$num" ]; then
            target_line=$((target_line + 1))
            break
        fi
        target_line=$((target_line + 1))
    done < "$AUTHORIZED_KEYS"

    if [ "$target_line" -eq 0 ]; then
        echo "  错误: 编号 $num 不存在"
        return
    fi

    # 显示要删除的内容
    local key_comment=$(sed -n "${target_line}p" "$AUTHORIZED_KEYS" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//')
    echo ""
    echo "  将删除: ${key_comment:-（无注释）}"
    read -p "  确认删除? [y/N]: " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        sed -i "${target_line}d" "$AUTHORIZED_KEYS"
        echo "  已删除编号 $num"
    else
        echo "  已取消"
    fi
}

do_view() {
    echo ""
    if [ ! -f "$AUTHORIZED_KEYS" ]; then
        echo "  未找到 authorized_keys 文件"
        return
    fi

    do_list
    echo ""
    read -p "  输入编号查看完整公钥: " num
    [ -z "$num" ] && echo "  已取消" && return

    [[ ! "$num" =~ ^[0-9]+$ ]] && echo "  错误: 请输入数字" && return

    local line_num=0
    local target_line=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        line_num=$((line_num + 1))
        if [ "$line_num" -eq "$num" ]; then
            target_line=$((target_line + 1))
            break
        fi
        target_line=$((target_line + 1))
    done < "$AUTHORIZED_KEYS"

    if [ "$target_line" -eq 0 ]; then
        echo "  错误: 编号 $num 不存在"
        return
    fi

    echo ""
    sed -n "${target_line}p" "$AUTHORIZED_KEYS"
}

menu() {
    while true; do
        echo ""
        echo "  [1] 查看公钥列表"
        echo "  [2] 添加公钥"
        echo "  [3] 删除公钥"
        echo "  [4] 查看公钥详情"
        echo "  [0] 返回上级"
        echo ""
        read -p "  请输入选项: " choice
        case "$choice" in
            1) do_list; echo ""; read -p "  按回车键继续..." ;;
            2) do_add; echo ""; read -p "  按回车键继续..." ;;
            3) do_remove; echo ""; read -p "  按回车键继续..." ;;
            4) do_view; echo ""; read -p "  按回车键继续..." ;;
            0) return ;;
            *) echo "  无效选项"; sleep 1 ;;
        esac
    done
}
