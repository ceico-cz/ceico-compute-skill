#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=cpu              # same name on Phoebe and Koios
#SBATCH --time=<HH:MM:SS>
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=<NCPUS>      # hardware threads on one node: max 128 on Phoebe, 64 on Koios
#SBATCH --mem=<MEM>                  # per node, e.g. 32G
#SBATCH --output=%x-%j.out
set -euo pipefail

module purge
# Koios (EESSI only): replace the line above with this one; EESSI's init reads unset variables
#   set +u; source /cvmfs/software.eessi.io/versions/2025.06/init/lmod/bash; set -u
module load <MODULES>                # e.g. foss/2024a (Phoebe stack; on Koios from EESSI)

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
