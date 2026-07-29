#!/usr/bin/env bats

setup() {
    export TEST_TMP
    TEST_TMP=$(mktemp -d)
    export LE_LIVE_DIR="${TEST_TMP}/letsencrypt/live"
    # shellcheck disable=SC1091
    source "$PWD/modules/ssl-check.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "SSL 本机证书自动发现 Let's Encrypt fullchain" {
    mkdir -p "${LE_LIVE_DIR}/example.com"
    touch "${LE_LIVE_DIR}/example.com/fullchain.pem"

    run _local_cert_files

    [ "$status" -eq 0 ]
    [ "$output" = "${LE_LIVE_DIR}/example.com/fullchain.pem" ]
}
