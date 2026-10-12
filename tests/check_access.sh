#!/usr/bin/env bash
# Mock SSH so compatibility tests never connect or modify ~/.ssh.
set -eu
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
script_dir=$(cd "$(dirname "$0")/../ceico-compute/scripts" && pwd)
bash_bin=${BASH:-/bin/bash}
cat > "$test_dir/mock" <<'MOCK'
#!/bin/sh
case "${0##*/}" in
    ssh-add) [ "$TEST_KEY" = agent ] ;;
    ssh-keyscan)
        [ "$TEST_MODE" != unreachable ] || exit 1
        echo 'mock-host ssh-ed25519 mock-key' ;;
    ssh-keygen)
        if [ "$1" = -F ]; then
            [ "$TEST_MODE" != unregistered ]
            exit $?
        fi
        IFS= read -r key_line
        [ -n "$key_line" ] || exit 1
        case "$TEST_MODE" in
            mismatch) echo '256 SHA256:wrong mock-host (ED25519)' ;;
            *) echo "256 $TEST_FP mock-host (ED25519)" ;;
        esac ;;
    ssh)
        if [ "$1" = -G ]; then
            [ "$TEST_KEY" != file ] || echo "identityfile $TEST_KEY_FILE"
            exit 0
        fi
        # Fail if the check could update host keys or create/reuse control sockets.
        for required in StrictHostKeyChecking=yes UpdateHostKeys=no ControlMaster=no ControlPath=none PermitLocalCommand=no; do
            found=no
            for arg do [ "$arg" != "$required" ] || found=yes; done
            [ "$found" = yes ] || { echo "missing option: $required" >&2; exit 1; }
        done
        case "$TEST_MODE" in
            denied) echo 'Permission denied (publickey).' >&2; exit 255 ;;
            changed) echo 'Host key verification failed.' >&2; exit 255 ;;
            *) printf 'CEICO_OK\nuser: test\naccount|normal|normal\n' ;;
        esac ;;
esac
MOCK
chmod +x "$test_dir/mock"
for tool in ssh ssh-add ssh-keyscan ssh-keygen; do
    ln -s mock "$test_dir/$tool"
done
export PATH="$test_dir:$PATH"
export TEST_KEY_FILE="$test_dir/test-key"
touch "$TEST_KEY_FILE"
run_case() {
    label=$1 expected=$2
    shift 2
    rc=0
    output=$("$bash_bin" "$script_dir/check_access.sh" "$@") || rc=$?
    printf '%s\n' "$output" | grep -qx "VERDICT: $expected"
    if [ "$expected" = OK ]; then [ "$rc" -eq 0 ]; else [ "$rc" -ne 0 ]; fi
    echo "PASS: $label"
}
export TEST_MODE=ok TEST_KEY=agent
export TEST_FP='SHA256:xy6+Upes9O4LWWQkME7TjWsmotoTOMlZMSBBWg+j2Zk'
run_case phoebe OK phoebe
run_case legacy-username OK testuser
export TEST_FP='SHA256:iIOuILdupxCyIhkFKNjlsRP1hs/cFHvuBKu9XF8HVFQ'
run_case koios OK koios testuser
TEST_KEY=file
run_case identity-file OK koios
TEST_KEY=none TEST_MODE=denied
run_case no-key NO_KEY koios
TEST_KEY=agent
run_case rejected-key PERMISSION_DENIED koios
TEST_MODE=mismatch
run_case fingerprint-mismatch HOSTKEY_MISMATCH koios
TEST_MODE=changed
run_case stale-host-key HOSTKEY_CHANGED koios
TEST_MODE=unregistered
run_case unregistered-host HOSTKEY_NOT_REGISTERED koios
TEST_MODE=unreachable
run_case unreachable UNREACHABLE koios
run_case invalid-username UNKNOWN_ERROR koios '-bad'
run_case invalid-host UNKNOWN_ERROR '-bad.example'
