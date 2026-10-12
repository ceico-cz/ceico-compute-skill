#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=cpu
#SBATCH --time=<HH:MM:SS>
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=<NCPUS>      # hardware threads on one node: max 128 on Phoebe, 64 on Koios
#SBATCH --mem=<MEM>                  # per node, e.g. 32G
#SBATCH --output=%x-%j.out
set -euo pipefail

module purge
module load <MODULES>                # e.g. foss/2024a (exists on both clusters)

# use exactly the allocated CPUs (BLAS libraries and Python pools included)
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OPENBLAS_NUM_THREADS=$SLURM_CPUS_PER_TASK MKL_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PLACES=cores OMP_PROC_BIND=close

# private node-local scratch (mode 700, unpredictable name); stops outside a Slurm job
TMPDIR=$(mktemp -d "/tmp/${USER}.${SLURM_JOB_ID:?submit with sbatch}.XXXXXX")
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

echo "job $SLURM_JOB_ID on $(hostname), $OMP_NUM_THREADS threads, started $(date -Is)"
<COMMAND>                            # e.g. ./my_openmp_app input.dat
echo "finished $(date -Is)"
