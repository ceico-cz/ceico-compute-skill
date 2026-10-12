# Access to Phoebe and Koios

## Facts

| Cluster | Login node | OS | ED25519 host key |
|---|---|---|---|
| Phoebe | `phoebe.fzu.cz` (VM `login1.phoebe.lan`) | Rocky 8 | `SHA256:xy6+Upes9O4LWWQkME7TjWsmotoTOMlZMSBBWg+j2Zk` |
| Koios | `koios1.fzu.cz` (`koios1.koios.lan`) | Rocky 9 | `SHA256:iIOuILdupxCyIhkFKNjlsRP1hs/cFHvuBKu9XF8HVFQ` |

- SSH works from anywhere.
- Authentication: **SSH keys only** (no passwords). Accounts are managed in Phoebe's FreeIPA
  by the CEICO admins; an account exists only after the admin has added the user and their
  public key.
- Username: the FZU username, usually the part of the FZU e-mail before `@`.
- Phoebe and Koios share accounts and keys but have **separate home directories**; the
  login nodes cannot SSH to each other by default (see [storage.md](storage.md#copying-between-the-clusters)).
- Docs: https://hpc.ceico.cz/getting-started/ssh/ and https://hpc.ceico.cz/getting-started/ssh-key/

## Fixing `check_access.sh` verdicts

### NO_KEY
No SSH key found locally (no agent identity, no `~/.ssh/id_*`). Have the user create one:

```bash
ssh-keygen -t ed25519 -C "<FZU-email>"
```

(Windows: OpenSSH in PowerShell works the same; MobaXterm also works.) Then the user sends
**only the public key** (`~/.ssh/id_ed25519.pub`) to the cluster administrator (one account covers Phoebe and Koios) as described at
https://hpc.ceico.cz/getting-started/account/. Access works once the admin confirms.
Never ask the user to paste the private key.

### PERMISSION_DENIED
The server rejected all offered keys. Check, in this order:
1. Wrong username — retry `check_access.sh <fzu-username>`; the local login name often differs.
2. Key not loaded — key has a passphrase and no agent: `ssh-add ~/.ssh/id_ed25519`
   (the user types the passphrase themselves; non-interactive SSH can't prompt).
3. Key in a non-default file — add `IdentityFile` to the alias below.
4. Account not created yet or a different public key registered — the user must contact the
   admin with their public key. Compare: `ssh-keygen -lf ~/.ssh/id_ed25519.pub`.

### HOSTKEY_MISMATCH
`ssh-keyscan` returned a different fingerprint than expected. **Stop**: do not connect.
Could be a DNS/network interception or a changed server (compare with the table above). Tell the user to check with the admin.

### HOSTKEY_CHANGED
Local `known_hosts` has an old/different key for the host, but the live key matched the
expected fingerprint (the scan step passed). After the user agrees, remove the stale entry:
`ssh-keygen -R phoebe.fzu.cz` (or `koios1.fzu.cz`) and re-run the check.

### UNREACHABLE
DNS failure or no TCP/22. Check the user's internet connection, `nc -vz phoebe.fzu.cz 22` (or `koios1.fzu.cz`).
Some networks block outgoing SSH; try another network or the FZU VPN.

## SSH config aliases

Suggest (only add with the user's consent) in `~/.ssh/config`:

```
Host phoebe koios
    User <fzu-username>
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
Host phoebe
    HostName phoebe.fzu.cz
Host koios
    HostName koios1.fzu.cz
```

`ControlMaster` makes the many short `ssh phoebe '…'` / `ssh koios '…'` calls of this workflow fast.

## File transfer

```bash
rsync -av --exclude .git --exclude __pycache__ ./ phoebe:jobs/<name>/   # upload (or koios:)
rsync -av phoebe:jobs/<name>/results/ ./results/                       # download
scp file phoebe:jobs/<name>/
```

sshfs mount: https://hpc.ceico.cz/getting-started/sshfs/. Large data (>100 GB): ask the admin
first (see [storage.md](storage.md)).

## Other ways in

- Phoebe only — Open OnDemand (browser: JupyterLab, desktop): `https://ood.phoebe.ceico.cz` from the FZU
  network/VPN (Kerberos password), or `https://ext.phoebe.fzu.cz` from anywhere with a passkey
  after an e-mailed invite.
- Job / GPU usage portal: `https://jobs.phoebe.fzu.cz`.
- VS Code: remote tunnel running inside a Slurm job — https://hpc.ceico.cz/getting-started/vscode-tunnel/.
  Do not run VS Code Remote-SSH servers with heavy extensions on the login node.
