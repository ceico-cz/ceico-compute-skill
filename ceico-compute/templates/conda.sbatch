#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=cpu
#SBATCH --time=<HH:MM:SS>
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=<NCPUS>
#SBATCH --mem=<MEM>
#SBATCH --output=%x-%j.out
set -eo pipefail                     # no -u: conda activation scripts use unset variables

module purge
# Phoebe (CPU nodes): Miniforge3 module from the system stack
module load Miniforge3/26.3.2-3
source "${EBROOTMINIFORGE3}/etc/profile.d/conda.sh"
# Koios: no module; use your own install instead of the two lines above:
#   source "$HOME/miniforge3/etc/profile.d/conda.sh"
conda activate <ENV>                 # name in ~/.conda/envs or a --prefix path

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

export TMPDIR=/tmp/$USER/$SLURM_JOB_ID
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

echo "job $SLURM_JOB_ID on $(hostname), python $(command -v python), started $(date -Is)"
<COMMAND>                            # e.g. python my_script.py
echo "finished $(date -Is)"
