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
verdict() { echo "VERDICT: $1"; exit "${2:-1}"; }

# Reject anything that could be parsed as an ssh option or isn't a plain name.
if [[ ! "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
    echo "invalid host name: $HOST"; verdict UNKNOWN_ERROR
fi
if [ -n "$USER_ARG" ] && [[ ! "$USER_ARG" =~ ^[A-Za-z_][A-Za-z0-9._-]{0,31}$ ]]; then
    echo "invalid user name: $USER_ARG"; verdict UNKNOWN_ERROR
fi

EXPECTED_FP="${FINGERPRINTS[$HOST]:-}"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"
TARGET="${USER_ARG:+$USER_ARG@}$HOST"

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
scan_line=$(ssh-keyscan -T 10 -t ed25519 "$HOST" 2>/dev/null | grep -v '^#' | head -1)
scanned=$(ssh-keygen -lf - <<<"$scan_line" 2>/dev/null | awk '{print $2}')
if [ -z "$scanned" ]; then
    echo "host key scan: no answer from $HOST:22"
    verdict UNREACHABLE
fi
if [ -z "$EXPECTED_FP" ]; then
    echo "host key: $scanned (unknown host: no expected fingerprint, using known_hosts only)"
else
    echo "host key: $scanned (expected $EXPECTED_FP)"
    [ "$scanned" = "$EXPECTED_FP" ] || verdict HOSTKEY_MISMATCH
    # First contact: record exactly the key that was just verified. Existing entries are
    # never changed; if one is stale, ssh below fails with HOSTKEY_CHANGED.
    if ! ssh-keygen -F "$HOST" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
        mkdir -p "$(dirname "$KNOWN_HOSTS")" && chmod 700 "$(dirname "$KNOWN_HOSTS")"
        echo "$scan_line" >> "$KNOWN_HOSTS"
        echo "known_hosts: added the verified ed25519 key of $HOST to $KNOWN_HOSTS"
    fi
fi

# 3. Real login, non-interactive; the host key must match known_hosts.
err=$(mktemp)
out=$(ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$KNOWN_HOSTS" -- "$TARGET" \
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
