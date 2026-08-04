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

    # shellcheck disable=SC1091
    source "$PWD/lib/core.sh"
    # 临时隔离目录（防止污染真实 /etc/...）
    TEST_TMP="$(mktemp -d)"
    export NGINX_SITES_AVAIL="${TEST_TMP}/sites-available"
    export NGINX_SITES_ENABLED="${TEST_TMP}/sites-enabled"
    export NGINX_CONF_D="${TEST_TMP}/conf.d"
    export LE_LIVE_DIR="${TEST_TMP}/letsencrypt/live"
    # 新增常量用 ${VAR:-default}，source 前导出即可生效
    export NGINX_CONF_FILE="${TEST_TMP}/nginx.conf"
    export NGINX_LOG_DIR="${TEST_TMP}/log"
    export NGINX_SNAPSHOT_DIR="${TEST_TMP}/snapshots"
    export NGINX_ETC_DIR="${TEST_TMP}/nginx-etc"
    export NGINX_SNAPSHOT_KEEP=5

    # 加载模块（不执行 menu()）
    # shellcheck disable=SC1091
    source "$PWD/modules/nginx.sh"

    # source 之后 nginx.sh 顶层 hardcoded 常量已生效，
    # 必须显式重写指向测试目录（不能 self-assign）
    NGINX_SITES_AVAIL="${TEST_TMP}/sites-available"
    NGINX_SITES_ENABLED="${TEST_TMP}/sites-enabled"
    NGINX_CONF_D="${TEST_TMP}/conf.d"
    LE_LIVE_DIR="${TEST_TMP}/letsencrypt/live"
    NGINX_RELEASE_CACHE="${TEST_TMP}/nginx-release.info"

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

@test "_get_nginx_release_date 解析 nginx.org 源码包日期" {
    curl() { printf 'Last-Modified: Wed, 15 Jul 2026 17:24:14 GMT\r\n'; }

    run _get_nginx_release_date "1.30.4"

    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-15" ]
}

# ─── 纯函数: 发布日期本地缓存 ───────────────────────────────

@test "_nginx_cached_release_date 读取本地缓存的发布日期" {
    printf '1.30.4 2026-07-15\n1.29.5 2026-05-01\n' > "$NGINX_RELEASE_CACHE"
    run _nginx_cached_release_date "1.30.4"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-15" ]
}

@test "_nginx_cached_release_date 无匹配版本返回空" {
    printf '1.30.4 2026-07-15\n' > "$NGINX_RELEASE_CACHE"
    run _nginx_cached_release_date "9.9.9"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "_nginx_store_release_date 写入并覆盖同版本记录" {
    sudo() { "$@"; }
    _nginx_store_release_date "1.30.4" "2026-07-15"
    _nginx_store_release_date "1.30.4" "2026-07-16"
    _nginx_store_release_date "1.29.5" "2026-05-01"
    run cat "$NGINX_RELEASE_CACHE"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "1.30.4 2026-07-16" ]]
    [[ "$output" =~ "1.29.5 2026-05-01" ]]
    [ "$(grep -c '^1\.30\.4 ' "$NGINX_RELEASE_CACHE")" -eq 1 ]
}

@test "do_status 显示缓存发布日期且不联网拉取" {
    printf '1.30.4 2026-07-15\n' > "$NGINX_RELEASE_CACHE"
    nginx() { echo 'nginx version: nginx/1.30.4' >&2; }
    systemctl() { echo active; }
    ss() { :; }
    curl() { echo "SHOULD_NOT_CALL_CURL"; return 1; }
    run do_status
    [ "$status" -eq 0 ]
    [[ "$output" =~ "v1.30.4" ]]
    [[ "$output" =~ "2026-07-15 发布" ]]
    [[ ! "$output" =~ "SHOULD_NOT_CALL_CURL" ]]
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

@test "do_view_conf 仅列出已启用站点且空输入返回" {
    mkdir -p "$NGINX_SITES_AVAIL" "$NGINX_SITES_ENABLED"
    touch "${NGINX_SITES_AVAIL}/example.com" "${NGINX_SITES_AVAIL}/example.com.bak"
    ln -s "${NGINX_SITES_AVAIL}/example.com" "${NGINX_SITES_ENABLED}/example.com"
    nginx() { :; }
    info() { printf '%s\n' "$1"; }

    run do_view_conf <<< ""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "example.com" ]]
    [[ ! "$output" =~ "example.com.bak" ]]
    [[ "$output" =~ "已返回" ]]
}

@test "do_cert 支持域名站点并允许空输入返回" {
    mkdir -p "$NGINX_SITES_AVAIL" "$NGINX_SITES_ENABLED"
    touch "${NGINX_SITES_AVAIL}/example.com"
    ln -s "${NGINX_SITES_AVAIL}/example.com" "${NGINX_SITES_ENABLED}/example.com"
    nginx() { :; }
    info() { printf '%s\n' "$1"; }
    sudo() { [ "$1" = "-n" ] && return 0; command sudo "$@"; }

    run do_cert <<< ""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "example.com" ]]
    [[ "$output" =~ "已返回" ]]
}

@test "Nginx 启动失败返回非零" {
    nginx() { :; }
    systemctl() { return 42; }
    sudo() { "$@"; }

    run do_start

    [ "$status" -ne 0 ]
    [[ "$output" =~ "启动失败" ]]
}

@test "Nginx 配置语法检查失败返回非零" {
    nginx() {
        [ "$1" = "-t" ] && return 42
        return 0
    }
    sudo() { "$@"; }

    run do_test_conf

    [ "$status" -ne 0 ]
    [[ "$output" =~ "配置语法检查失败" ]]
}

# ─── 纯函数: _make_proxy_conf ─────────────────────────────────

@test "_make_proxy_conf 生成 80 → 443 重定向块" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "return 301 https://\$host\$request_uri" ]]
}

@test "_make_proxy_conf 无证书模式先生成可用 HTTP 反代" {
    run _make_proxy_conf "test.com" "127.0.0.1" "8080" "n" "n"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "listen 80" ]]
    [[ "$output" =~ "proxy_pass http://127.0.0.1:8080" ]]
    [[ ! "$output" =~ "ssl_certificate" ]]
    [[ ! "$output" =~ "return 301 https" ]]
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

@test "menu 将 Nginx 操作归类为服务和站点管理" {
    title() { :; }
    do_status() { :; }
    divider() { :; }

    run menu <<< "0"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "服务管理" ]]
    [[ "$output" =~ "反代站点管理" ]]
    [[ "$output" =~ "反代站点管理" ]]
    [[ ! "$output" =~ "[12]" ]]
}

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

# ─── 新增功能: 日志分析 / 安全扫描 / 启用禁用 / 快照 ─────────

@test "do_log_top 聚合今天的 Top IP / URL / 状态码" {
    mkdir -p "$NGINX_LOG_DIR"
    local d; d=$(date '+%d/%b/%Y')
    printf '%s - - [%s +0800] "GET /a HTTP/1.1" 200 100 "-" "ua"\n' "1.1.1.1" "$d" > "$NGINX_LOG_DIR/access.log"
    printf '%s - - [%s +0800] "POST /b HTTP/1.1" 404 50 "-" "ua"\n' "2.2.2.2" "$d" >> "$NGINX_LOG_DIR/access.log"
    sudo() { [ "$1" = "-n" ] && return 0; "$@"; }
    nginx() { :; }
    run do_log_top
    [ "$status" -eq 0 ]
    [[ "$output" =~ "1.1.1.1" ]]
    [[ "$output" =~ "/a" ]]
    [[ "$output" =~ "404" ]]
}

@test "do_security_scan 报告 server_tokens 与站点安全项" {
    printf 'server_tokens off;\n' > "$NGINX_CONF_FILE"
    mkdir -p "$NGINX_SITES_AVAIL" "$NGINX_SITES_ENABLED"
    printf 'server {\n listen 443 ssl http2;\n ssl_protocols TLSv1.2 TLSv1.3;\n add_header Strict-Transport-Security "x";\n add_header X-Content-Type-Options nosniff;\n add_header X-Frame-Options SAMEORIGIN;\n client_max_body_size 20m;\n}\n' > "$NGINX_SITES_AVAIL/example.com"
    ln -s "$NGINX_SITES_AVAIL/example.com" "$NGINX_SITES_ENABLED/example.com"
    sudo() { [ "$1" = "-n" ] && return 0; "$@"; }
    nginx() { :; }
    title() { :; }
    C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""
    run do_security_scan
    [ "$status" -eq 0 ]
    [[ "$output" =~ "server_tokens off" ]]
    [[ "$output" =~ "example.com" ]]
    [[ "$output" =~ "NoSniff" ]]
    [[ "$output" =~ "Frame" ]]
    local expected_header
    expected_header=$(printf '  %-28s %-4s %-5s %-8s %-7s %-6s %s' \
        "站点" "TLS" "HSTS" "NoSniff" "Frame" "Body" "证书")
    [[ "$output" == *"$expected_header"* ]]
}

@test "do_disable_site 移除软链但保留配置" {
    mkdir -p "$NGINX_SITES_AVAIL" "$NGINX_SITES_ENABLED"
    echo "server { }" > "$NGINX_SITES_AVAIL/example.com"
    ln -s "$NGINX_SITES_AVAIL/example.com" "$NGINX_SITES_ENABLED/example.com"
    sudo() { [ "$1" = "-n" ] && return 0; "$@"; }
    nginx() { return 0; }
    systemctl() { return 0; }
    run do_disable_site "example.com" <<< $'y\n'
    [ "$status" -eq 0 ]
    [ ! -e "$NGINX_SITES_ENABLED/example.com" ]
    [ -f "$NGINX_SITES_AVAIL/example.com" ]
}

@test "do_enable_site 为未启用站点建立软链" {
    mkdir -p "$NGINX_SITES_AVAIL" "$NGINX_SITES_ENABLED"
    echo "server { }" > "$NGINX_SITES_AVAIL/example.com"
    sudo() { [ "$1" = "-n" ] && return 0; "$@"; }
    nginx() { return 0; }
    systemctl() { return 0; }
    run do_enable_site "example.com"
    [ "$status" -eq 0 ]
    [ -L "$NGINX_SITES_ENABLED/example.com" ]
}

@test "do_snapshot 创建快照并保留最近 N 个" {
    mkdir -p "$NGINX_ETC_DIR" "$NGINX_SNAPSHOT_DIR/nginx-old1" "$NGINX_SNAPSHOT_DIR/nginx-old2"
    touch -d '2020-01-01' "$NGINX_SNAPSHOT_DIR/nginx-old1" "$NGINX_SNAPSHOT_DIR/nginx-old2"
    sudo() { [ "$1" = "-n" ] && return 0; "$@"; }
    nginx() { :; }
    NGINX_SNAPSHOT_KEEP=1
    run do_snapshot
    [ "$status" -eq 0 ]
    [ "$(find "$NGINX_SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
}

@test "nginx.sh 暴露 do_log_top 函数" {
    type do_log_top
}

@test "nginx.sh 暴露 do_security_scan 函数" {
    type do_security_scan
}

@test "nginx.sh 暴露 do_enable_site 函数" {
    type do_enable_site
}

@test "nginx.sh 暴露 do_disable_site 函数" {
    type do_disable_site
}

@test "nginx.sh 暴露 do_snapshot 函数" {
    type do_snapshot
}

@test "nginx.sh 暴露 do_restore 函数" {
    type do_restore
}
