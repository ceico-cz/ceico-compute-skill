#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=rocky10          # Phoebe only: the only GPU partition
#SBATCH --time=<HH:MM:SS>
#SBATCH --gres=gpu:a100:<NGPUS>      # 1-8 per node
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=<NCPUS>      # ~8 per GPU
#SBATCH --mem=<MEM>                  # set explicitly; default is 16 GB per CPU
#SBATCH --output=%x-%j.out
set -eo pipefail                     # no -u: EESSI init uses unset variables

# EESSI replaces the module system on the Rocky 10 GPU nodes (Phoebe stacks are not available)
source /cvmfs/software.eessi.io/versions/2025.06/init/lmod/bash
module load <MODULES>                # e.g. CUDA/12.9.1 (check: module avail CUDA GROMACS)

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export TMPDIR=/tmp/$USER/$SLURM_JOB_ID
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

echo "job $SLURM_JOB_ID on $(hostname), CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES, started $(date -Is)"
nvidia-smi --query-gpu=index,name,memory.total --format=csv
<COMMAND>                            # e.g. ./my_cuda_app, or deviceQuery (module CUDA-Samples)
echo "finished $(date -Is)"
