#!/usr/bin/env bats

@test "Docker 容器菜单按运行状态显示停止和实际镜像版本" {
    run bash -c '
        source "'$PWD'/lib/core.sh"
        source "'$PWD'/modules/docker.sh"
        docker() {
            case "$1 $2" in
                "inspect --format") printf "true\n" ;;
                "image inspect") printf "<no value>\n" ;;
                "exec nezha-dashboard") printf "v2.2.5\n" ;;
            esac
        }
        _menu_actions() { printf "%s\n" "$2"; }
        printf "00\n" | _container_ops_menu nezha-dashboard
        _docker_image_display ghcr.io/nezhahq/nezha:latest nezha-dashboard
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[1;31m[1] 停止'* ]]
    [[ "$output" != *"[1] 启动"* ]]
    [[ "$output" == *"[00] 返回主菜单"* ]]
    [[ "$output" == *"ghcr.io/nezhahq/nezha:v2.2.5"* ]]
}

@test "Docker 总览保留状态时长与完整端口，并在窄终端分行" {
    run bash -c '
        source "'$PWD'/lib/core.sh"
        source "'$PWD'/modules/docker.sh"
        tput() { printf "200\\n"; }
        [ "$(_docker_status_display "Up About an hour")" = "运行中 · 已运行 约 1 小时" ]
        [ "$(_docker_status_display "Exited (0) 1 minute ago")" = "已退出 · 1 分钟前" ]
        _docker_print_ports "0.0.0.0:8008->8008/tcp, [::]:8008->8008/tcp"
        tput() { printf "60\\n"; }
        _docker_print_ports "0.0.0.0:8008->8008/tcp, [::]:8008->8008/tcp"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"端口     0.0.0.0:8008->8008/tcp, [::]:8008->8008/tcp"* ]]
    [[ "$output" == *$'端口     0.0.0.0:8008->8008/tcp\n              [::]:8008->8008/tcp'* ]]
}

@test "Docker 官方 apt 源按 Debian 和 Ubuntu 选择" {
    run bash -c '
        source "'$PWD'/lib/core.sh"
        source "'$PWD'/modules/docker.sh"
        os_release=$(mktemp)
        printf "ID=debian\\nVERSION_CODENAME=bookworm\\n" > "$os_release"
        DOCKER_OS_RELEASE="$os_release" _docker_apt_source
        printf "ID=ubuntu\\nVERSION_CODENAME=noble\\nUBUNTU_CODENAME=noble\\n" > "$os_release"
        DOCKER_OS_RELEASE="$os_release" _docker_apt_source
        rm -f "$os_release"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *$'debian\tbookworm'* ]]
    [[ "$output" == *$'ubuntu\tnoble'* ]]
}

@test "Docker 总览按镜像归属显示容器详情" {
    run bash -c '
        source "'$PWD'/lib/core.sh"
        source "'$PWD'/modules/docker.sh"
        clear() { :; }
        tput() { printf "200\\n"; }
        _menu_actions() { :; }
        C_BOLD="" C_RESET="" C_DIM="" C_GREEN="" C_GRAY=""
        docker() {
            case "$1" in
                info) return 0 ;;
                ps) printf "nezha-dashboard\\tUp About an hour\\t0.0.0.0:8008->8008/tcp, [::]:8008->8008/tcp\\n" ;;
                inspect) printf "sha256:nezha\\n" ;;
                images) printf "ghcr.io/nezhahq/nezha:latest\\tsha256:nezha\\t122MB\\n" ;;
                image) printf "<no value>\\n" ;;
                exec) printf "2.3.2\\n" ;;
            esac
        }
        printf "0\\n" | do_overview
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"    📦 镜像    ● ghcr.io/nezhahq/nezha:2.3.2 (122MB)"* ]]
    [[ "$output" == *"         容器1"*"● nezha-dashboard"* ]]
    [[ "$output" == *"         状态     运行中 · 已运行 约 1 小时"* ]]
    [[ "$output" == *"         端口     0.0.0.0:8008->8008/tcp, [::]:8008->8008/tcp"* ]]
}

@test "Docker 总览以完整 Image ID 关联运行、停止和无容器镜像" {
    run bash -c '
        source "'$PWD'/lib/core.sh"
        source "'$PWD'/modules/docker.sh"
        clear() { :; }
        tput() { printf "200\\n"; }
        _menu_actions() { :; }
        C_BOLD="" C_RESET="" C_DIM="" C_GREEN="" C_GRAY="" C_YELLOW=""
        docker() {
            case "$1" in
                info) return 0 ;;
                ps) printf "compose-running\\tUp 34 minutes (healthy)\\t8080/tcp\\nstopped-app\\tExited (0) 2 minutes ago\\t\\norphan-app\\tUp 1 minute\\t9000/tcp\\n" ;;
                inspect)
                    case "$4" in
                        compose-running) printf "sha256:compose\\n" ;;
                        stopped-app) printf "sha256:stopped\\n" ;;
                        orphan-app) printf "sha256:deleted\\n" ;;
                    esac
                    ;;
                images) printf "compose-build:latest\\tsha256:compose\\t120MB\\nstopped-build:latest\\tsha256:stopped\\t110MB\\nempty-build:latest\\tsha256:empty\\t100MB\\n" ;;
                image) printf "<no value>\\n" ;;
            esac
        }
        printf "0\\n" | do_overview
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"容器1"*"● compose-running"* ]]
    [[ "$output" == *"容器2"*"○ stopped-app"* ]]
    [[ "$output" == *"empty-build:latest (100MB)"* ]]
    [[ "$output" != *"容器  无"* ]]
    [[ "$output" == *"未关联镜像（原镜像标签已删除或已更新）"*"容器3"*"● orphan-app"* ]]
}

@test "Docker 镜像列表按最长名称对齐列" {
    run bash -c '
        source "'$PWD'/lib/core.sh"
        source "'$PWD'/modules/docker.sh"
        clear() { :; }
        _menu_actions() { :; }
        C_BOLD="" C_RESET="" C_DIM="" C_GREEN="" C_GRAY=""
        docker() {
            case "$1" in
                info) return 0 ;;
                images) printf "example/image:very-long-tag\\tsha256:one\\t122MB\\t22 hours ago\\nexample/image:short\\tsha256:two\\t127MB\\t6 weeks ago\\n" ;;
            esac
        }
        printf "0\\n" | do_images
    '

    [ "$status" -eq 0 ]
    long_line=$(printf '%s\n' "$output" | grep 'example/image:very-long-tag')
    short_line=$(printf '%s\n' "$output" | grep 'example/image:short')
    long_prefix=${long_line%%122MB*}
    short_prefix=${short_line%%127MB*}
    [ "${#long_prefix}" -eq "${#short_prefix}" ]
}

@test "已停止的哪吒 Agent 菜单只显示启动" {
    run bash -c '
        source "'$PWD'/lib/core.sh"
        source "'$PWD'/modules/nezha-agent.sh"
        clear() { :; }
        _menu_actions() { printf "%s\n" "$2"; }
        systemctl() {
            case "$1" in
                list-unit-files) printf "nezha-agent.service enabled\n" ;;
                is-active) return 1 ;;
            esac
        }
        printf "1\n0\n0\n" | menu
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[1;32m\033[1m[1]'* ]]
    [[ "$output" == *"启动"* ]]
    [[ "$output" != *"[1] 停止"* ]]
}
