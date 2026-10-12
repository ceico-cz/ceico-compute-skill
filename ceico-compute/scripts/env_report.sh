#!/usr/bin/env bash
# Live snapshot of a CEICO cluster (Phoebe or Koios) for planning a job. Run on the login node:
#   ssh USER@phoebe.fzu.cz 'bash -s' < env_report.sh      (or USER@koios1.fzu.cz)
# Read-only: only queries Slurm, Lmod paths, CVMFS and file systems.

section() { printf '\n=== %s ===\n' "$1"; }

section "identity"
echo "user=$(id -un) host=$(hostname) home=$HOME date=$(date -Is)"
echo "os=$(. /etc/os-release && echo "$PRETTY_NAME")"

section "partitions (state, timelimit, nodes alloc/idle/other/total)"
sinfo -s

section "partition resources (cpus/node, mem MB/node, gres)"
sinfo --noheader -o "%12P %.5a %.12l %.5D %.5c %.8m %G" | sort -u

section "my slurm association"
sacctmgr -n -P show assoc user="$(id -un)" format=account,partition,qos,defaultqos

section "QOS limits"
sacctmgr -n -P show qos format=name,priority,maxwall,maxtrespu,maxtrespj,maxjobspu 2>/dev/null

section "my jobs"
squeue -u "$(id -un)" -o "%.10i %.10P %.25j %.8T %.10M %.12l %.5D %.4C %R"

section "my jobs in last 3 days"
sacct -X -S "$(date -d '3 days ago' +%F)" --format=JobID,JobName%20,Partition,State,Elapsed,ExitCode 2>/dev/null | tail -20

section "module paths"
echo "$MODULEPATH" | tr ':' '\n' | awk '!seen[$0]++'

section "software repositories"
# CVMFS is automounted: test each known path instead of listing /cvmfs
for d in /cvmfs/{2023a,2024a,2025a,2026a,system}.phoebe.lan /cvmfs/c9.phoebe.lan /cvmfs/apptainer.phoebe.lan; do
    [ -d "$d" ] && echo "$d"
done
echo "EESSI versions: $(ls /cvmfs/software.eessi.io/versions 2>/dev/null | tr '\n' ' ')"
echo "apptainer: $(command -v apptainer || echo missing)"

section "storage"
df -h "$HOME" /mnt/proj /mnt/shared-scratch 2>/dev/null
ls -d /mnt/proj/p* 2>/dev/null | while read -r p; do [ -w "$p" ] && echo "writable project dir: $p"; done
