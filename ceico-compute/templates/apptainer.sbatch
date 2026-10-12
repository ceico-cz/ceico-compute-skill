#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=rocky10          # Phoebe GPU; for CPU-only images (Phoebe or Koios) use cpu and drop --gres and --nv
#SBATCH --time=<HH:MM:SS>
#SBATCH --gres=gpu:a100:<NGPUS>
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=<NCPUS>
#SBATCH --mem=<MEM>
#SBATCH --output=%x-%j.out
set -euo pipefail

# images on CVMFS (Phoebe only): find /cvmfs/apptainer.phoebe.lan -name '*.sif', or your own from
#   apptainer pull docker://<image>:<tag>
IMAGE=<IMAGE>   # e.g. /cvmfs/apptainer.phoebe.lan/nvcr.io/nvidia/pytorch/26.05-py3/pytorch_26.05-py3.sif

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
# private node-local scratch (mode 700, unpredictable name); stops outside a Slurm job
TMPDIR=$(mktemp -d "/tmp/${USER}.${SLURM_JOB_ID:?submit with sbatch}.XXXXXX")
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

echo "job $SLURM_JOB_ID on $(hostname), image $IMAGE, started $(date -Is)"
# --nv exposes the job's GPUs; $HOME and the current directory are bound automatically
apptainer exec --nv -B "$TMPDIR" "$IMAGE" <COMMAND>   # e.g. python train.py
echo "finished $(date -Is)"
