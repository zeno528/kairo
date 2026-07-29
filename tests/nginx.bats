#!/usr/bin/env bats
# 测试目标: modules/nginx.sh
# 覆盖: 公共函数 + 配置模板 + 语法

setup() {
    # Bats 子进程 PATH 残缺
    export PATH="/usr/bin:/bin:/usr/local/bin:/usr/libexec:/c/Windows/System32:$PATH"

    # 切到项目根
    cd "$BATS_TEST_DIRNAME/.." || return 1

    # 加载模块需要 kairo.sh 顶层定义的色变量
    export C_RESET="\033[0m"
    export C_BOLD="\033[1m"
    export C_DIM="\033[2m"
    export C_GREEN="\033[1;32m"
    export C_CYAN="\033[1;36m"
    export C_YELLOW="\033[1;33m"
    export C_RED="\033[1;31m"
    export C_GRAY="\033[37m"

    # 临时隔离目录（防止污染真实 /etc/...）
    TEST_TMP="$(mktemp -d)"
    export NGINX_SITES_AVAIL="${TEST_TMP}/sites-available"
    export NGINX_SITES_ENABLED="${TEST_TMP}/sites-enabled"
    export NGINX_CONF_D="${TEST_TMP}/conf.d"
    export LE_LIVE_DIR="${TEST_TMP}/letsencrypt/live"

    # 加载模块（不执行 menu()）
    # shellcheck disable=SC1091
    source "$PWD/modules/nginx.sh"

    # source 之后 nginx.sh 顶层 hardcoded 常量已生效，
    # 必须显式重写指向测试目录（不能 self-assign）
    NGINX_SITES_AVAIL="${TEST_TMP}/sites-available"
    NGINX_SITES_ENABLED="${TEST_TMP}/sites-enabled"
    NGINX_CONF_D="${TEST_TMP}/conf.d"
    LE_LIVE_DIR="${TEST_TMP}/letsencrypt/live"

    # 清理临时目录（每个 test 结束）
    export TEST_TMP
}

teardown() {
    [ -n "$TEST_TMP" ] && rm -rf "$TEST_TMP"
}

# ─── 语法 ──────────────────────────────────────────────────────

@test "nginx.sh bash 语法正确" {
    run /usr/bin/bash -n "$PWD/modules/nginx.sh"
    [ "$status" -eq 0 ]
}

# ─── 纯函数: _nginx_version_is_at_least ──────────────────────

@test "_nginx_version_is_at_least 正确识别相同版本" {
    run _nginx_version_is_at_least "1.30.4-1~jammy" "1.30.4-1~jammy"
    [ "$status" -eq 0 ]
}

@test "_nginx_version_is_at_least 正确识别更高版本" {
    run _nginx_version_is_at_least "1.30.5-1~jammy" "1.30.4-1~jammy"
    [ "$status" -eq 0 ]
}

@test "_nginx_version_is_at_least 正确识别较低版本" {
    run _nginx_version_is_at_least "1.30.3-1~jammy" "1.30.4-1~jammy"
    [ "$status" -ne 0 ]
}

# ─── 纯函数: _has_cert ───────────────────────────────────────

@test "_has_cert 对已存在证书目录返回 0" {
    mkdir -p "${LE_LIVE_DIR}/example.com"
    touch "${LE_LIVE_DIR}/example.com/fullchain.pem"
    run _has_cert "example.com"
    [ "$status" -eq 0 ]
    rm -rf "${LE_LIVE_DIR}/example.com"
}

@test "_has_cert 对不存在证书返回 1" {
    run _has_cert "nonexistent-domain-xyz.com"
    [ "$status" -ne 0 ]
}

@test "_has_cert 对证书目录存在但 fullchain 缺失返回 1" {
    mkdir -p "${LE_LIVE_DIR}/broken.com"
    [ ! -f "${LE_LIVE_DIR}/broken.com/fullchain.pem" ]
    run _has_cert "broken.com"
    [ "$status" -ne 0 ]
    rmdir "${LE_LIVE_DIR}/broken.com"
}

# ─── 纯函数: _make_proxy_conf ─────────────────────────────────

@test "_make_proxy_conf 生成 80 → 443 重定向块" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "return 301 https://\$host\$request_uri" ]]
}

@test "_make_proxy_conf 含 ssl_protocols TLSv1.2 TLSv1.3" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "ssl_protocols TLSv1.2 TLSv1.3" ]]
}

@test "_make_proxy_conf 含 Mozilla Intermediate ssl_ciphers（ECDHE 套件）" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "ECDHE-ECDSA-AES128-GCM-SHA256" ]]
    [[ "$output" =~ "ECDHE-RSA-CHACHA20-POLY1305" ]]
}

@test "_make_proxy_conf 含 client_max_body_size 20m" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "client_max_body_size 20m" ]]
}

@test "_make_proxy_conf 含所有标准 proxy_set_header" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "proxy_set_header Host" ]]
    [[ "$output" =~ "proxy_set_header X-Real-IP" ]]
    [[ "$output" =~ "proxy_set_header X-Forwarded-For" ]]
    [[ "$output" =~ "proxy_set_header X-Forwarded-Proto" ]]
}

@test "_make_proxy_conf 含 WebSocket Upgrade / Connection 头" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "proxy_set_header Upgrade" ]]
    [[ "$output" =~ "proxy_set_header Connection" ]]
    [[ "$output" =~ 'Connection        $connection_upgrade' ]]
}

@test "_make_proxy_conf 含 WebSocket proxy_http_version 1.1" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "proxy_http_version 1.1" ]]
}

@test "_make_proxy_conf 含 WebSocket 长连接超时 proxy_read_timeout" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "proxy_read_timeout 86400s" ]]
}

@test "_make_proxy_conf 含 HSTS 头 max-age=63072000" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "Strict-Transport-Security" ]]
    [[ "$output" =~ "max-age=63072000" ]]
}

@test "_make_proxy_conf 含 SSL 会话复用 ssl_session_cache" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "ssl_session_cache shared:SSL:10m" ]]
    [[ "$output" =~ "ssl_session_timeout 1d" ]]
}

@test "_make_proxy_conf 反代正确的上游 host:port" {
    run _make_proxy_conf "test.com" "192.168.1.100" "9999" "n"
    [[ "$output" =~ "proxy_pass http://192.168.1.100:9999" ]]
}

@test "_make_proxy_conf with_www=y 时 server_name 含 www" {
    run _make_proxy_conf "example.com" "127.0.0.1" "8080" "y"
    [[ "$output" =~ "server_name example.com www.example.com" ]]
}

@test "_make_proxy_conf with_www=n 时 server_name 不含 www" {
    run _make_proxy_conf "example.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "server_name example.com;" ]]
    [[ ! "$output" =~ "server_name example.com www" ]]
}

@test "_make_proxy_conf 注释里含 Kairo 生成标记" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [[ "$output" =~ "由 Kairo 生成于" ]]
}

# ─── 纯函数: 域名校验 (do_add_proxy 内联) ──────────────────

@test "合法域名通过校验正则" {
    local domain="example.com"
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

@test "带子域名合法" {
    local domain="sub.example.com"
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

@test "空字符串拒绝" {
    local domain=""
    ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

@test "无 TLD 拒绝" {
    local domain="example"
    ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

@test "含特殊字符拒绝" {
    local domain="exa_mple.com"
    ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

# ─── 公共暴露 ────────────────────────────────────────────────

@test "nginx.sh 暴露 menu 函数" {
    type menu
}

@test "nginx.sh 暴露 do_install 函数" {
    type do_install
}

@test "nginx.sh 暴露 do_add_proxy 函数" {
    type do_add_proxy
}

@test "nginx.sh 暴露 do_del_proxy 函数" {
    type do_del_proxy
}

@test "nginx.sh 暴露 do_cert 函数" {
    type do_cert
}

@test "nginx.sh 暴露 do_test_conf 函数" {
    type do_test_conf
}

@test "nginx.sh 暴露 do_view_conf 函数" {
    type do_view_conf
}

@test "nginx.sh 暴露 do_cert_list 函数" {
    type do_cert_list
}

@test "nginx.sh 暴露 _ensure_ws_map 函数" {
    type _ensure_ws_map
}
