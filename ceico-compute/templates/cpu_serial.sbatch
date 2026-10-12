#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=cpu              # cpu | cpu_int | small_int | preempt: same names on Phoebe and Koios
#SBATCH --time=<HH:MM:SS>            # always set; no default limit
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2            # = 1 core (2 hardware threads)
#SBATCH --mem=<MEM>                  # e.g. 4G
#SBATCH --output=%x-%j.out
set -euo pipefail

module purge
module load <MODULES>                # e.g. Python/3.12.3-GCCcore-13.3.0 (one stack only)

# private node-local scratch (mode 700, unpredictable name); stops outside a Slurm job
TMPDIR=$(mktemp -d "/tmp/${USER}.${SLURM_JOB_ID:?submit with sbatch}.XXXXXX")
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

echo "job $SLURM_JOB_ID on $(hostname) started $(date -Is)"
<COMMAND>                            # e.g. python my_script.py input.dat
echo "finished $(date -Is)"
