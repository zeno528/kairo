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

@test "远程 SSL 检查复用一次有时限 TLS 握手" {
    run bash -c '
        source "'"$PWD"'/lib/core.sh"
        source "'"$PWD"'/modules/ssl-check.sh"
        calls=$(mktemp)
        timeout() {
            printf "timeout:%s\n" "$1" >> "$calls"
            shift
            "$@"
        }
        openssl() {
            case "$1" in
                s_client)
                    printf "%s\n" "s_client" >> "$calls"
                    printf "%s\n" "-----BEGIN CERTIFICATE-----" "test" "-----END CERTIFICATE-----"
                    ;;
                x509)
                    case " $* " in
                        *" -enddate "*) printf "%s\n" "notAfter=Dec 31 23:59:59 2030 GMT" ;;
                        *) printf "%s\n" "subject=CN = example.com" "issuer=CN = Test" "notAfter=Dec 31 23:59:59 2030 GMT" ;;
                    esac
                    ;;
            esac
        }
        _start_spinner() { :; }
        _stop_spinner() { :; }
        printf "%s\n" example.com 443 | do_remote_check
        [ "$(grep -c "^s_client$" "$calls")" -eq 1 ]
        grep -qx "timeout:15" "$calls"
    '

    [ "$status" -eq 0 ]
    [[ "$output" =~ "剩余" ]]
}
