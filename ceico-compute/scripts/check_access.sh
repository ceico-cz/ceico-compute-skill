#!/usr/bin/env bash
# Test non-interactive SSH access to a CEICO login node and print a verdict.
# Usage: check_access.sh <phoebe|koios|HOST> [USERNAME]
#        check_access.sh [USERNAME]            (old form: Phoebe)
# Prints diagnostic lines and finally exactly one line "VERDICT: <CODE>" where CODE is
# OK | NO_KEY | PERMISSION_DENIED | HOSTKEY_MISMATCH | HOSTKEY_CHANGED | UNREACHABLE | UNKNOWN_ERROR
set -u

# ED25519 host keys of the login nodes (published at hpc.ceico.cz/getting-started/ssh/)
declare -A FINGERPRINTS=(
    [phoebe.fzu.cz]="SHA256:xy6+Upes9O4LWWQkME7TjWsmotoTOMlZMSBBWg+j2Zk"
    [koios1.fzu.cz]="SHA256:iIOuILdupxCyIhkFKNjlsRP1hs/cFHvuBKu9XF8HVFQ"
)

case "${1:-}" in
    phoebe|phoebe.fzu.cz) HOST=phoebe.fzu.cz; USER_ARG="${2:-}" ;;
    koios|koios1|koios1.fzu.cz) HOST=koios1.fzu.cz; USER_ARG="${2:-}" ;;
    *.*) HOST="$1"; USER_ARG="${2:-}" ;;
    *) HOST=phoebe.fzu.cz; USER_ARG="${1:-}" ;;
esac
EXPECTED_FP="${FINGERPRINTS[$HOST]:-}"
TARGET="${USER_ARG:+$USER_ARG@}$HOST"

verdict() { echo "VERDICT: $1"; exit "${2:-1}"; }

echo "target: $TARGET"

# 1. Local keys: an agent with identities, or any private key file in ~/.ssh.
keys=()
ssh-add -l >/dev/null 2>&1 && keys+=(agent)
# Default key files plus any IdentityFile configured for this host in ~/.ssh/config.
while read -r f; do
    f="${f/#\~/$HOME}"
    [ -f "$f" ] && keys+=("$f")
done < <(ssh -G "$HOST" 2>/dev/null | awk '$1=="identityfile"{print $2}')
if [ ${#keys[@]} -eq 0 ]; then have_key=no; else have_key="${keys[*]}"; fi
echo "local keys: $have_key"

# 2. Verify the server's host key independently before trusting it on first contact.
scanned=$(ssh-keyscan -T 10 -t ed25519 "$HOST" 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' | head -1)
if [ -z "$scanned" ]; then
    echo "host key scan: no answer from $HOST:22"
    verdict UNREACHABLE
fi
if [ -z "$EXPECTED_FP" ]; then
    echo "host key: $scanned (unknown host: no expected fingerprint, using known_hosts only)"
    hostkey_opt="StrictHostKeyChecking=yes"
else
    echo "host key: $scanned (expected $EXPECTED_FP)"
    [ "$scanned" = "$EXPECTED_FP" ] || verdict HOSTKEY_MISMATCH
    # accept-new is safe here: the fingerprint was just verified
    hostkey_opt="StrictHostKeyChecking=accept-new"
fi

# 3. Real login, non-interactive.
err=$(mktemp)
out=$(ssh -o BatchMode=yes -o ConnectTimeout=15 -o "$hostkey_opt" "$TARGET" \
    'echo CEICO_OK; echo "user: $(id -un)"; echo "host: $(hostname)"; echo "home: $HOME";
     echo "slurm association (account | qos | default qos):";
     sacctmgr -n -P show assoc user="$(id -un)" format=account,qos,defaultqos 2>/dev/null | sed "s/^/  /"' \
    2>"$err")
rc=$?
stderr=$(grep -v -E 'post-quantum|store now, decrypt later|openssh.com/pq.html|server may need to be upgraded' "$err")
rm -f "$err"

if [ $rc -eq 0 ] && grep -q CEICO_OK <<<"$out"; then
    grep -v CEICO_OK <<<"$out"
    if ! grep -q '|' <<<"$out"; then
        echo "warning: no Slurm association found - the user can log in but may not be able to submit jobs."
    fi
    verdict OK 0
fi

[ -n "$stderr" ] && echo "ssh stderr: $stderr"
case "$stderr" in
    *"REMOTE HOST IDENTIFICATION HAS CHANGED"*|*"Host key verification failed"*) verdict HOSTKEY_CHANGED ;;
    *"Permission denied"*)
        if [ "$have_key" = no ]; then verdict NO_KEY; else verdict PERMISSION_DENIED; fi ;;
    *"Could not resolve"*|*"timed out"*|*"No route"*|*"Connection refused"*|*"Network is unreachable"*)
        verdict UNREACHABLE ;;
    *) verdict UNKNOWN_ERROR ;;
esac
