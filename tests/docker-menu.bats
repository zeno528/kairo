#!/usr/bin/env bats

@test "Docker 容器菜单按运行状态显示停止和实际镜像版本" {
    run bash -c '
        source "'$PWD'/lib/core.sh"
        source "'$PWD'/modules/docker.sh"
        docker() {
            case "$1 $2" in
                "inspect --format") printf "true\n" ;;
                "image inspect") printf "v2.2.5\n" ;;
            esac
        }
        _menu_actions() { printf "%s\n" "$2"; }
        printf "0\n" | _container_ops_menu nezha-dashboard
        _docker_image_display ghcr.io/nezhahq/nezha:latest
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[1;31m[1] 停止'* ]]
    [[ "$output" != *"[1] 启动"* ]]
    [[ "$output" == *"ghcr.io/nezhahq/nezha:v2.2.5"* ]]
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
