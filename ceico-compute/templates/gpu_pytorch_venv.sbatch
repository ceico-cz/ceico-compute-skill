#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=rocky10          # Phoebe only
#SBATCH --time=<HH:MM:SS>
#SBATCH --gres=gpu:a100:<NGPUS>      # 1-8 per node
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=<NCPUS>      # ~8 per GPU
#SBATCH --mem=<MEM>                  # e.g. 64G per GPU
#SBATCH --output=%x-%j.out
set -euo pipefail

# venv created once with a uv-managed Python (see references/gpu.md):
#   uv venv --python 3.12 ~/venvs/torch && uv pip install --python ~/venvs/torch/bin/python torch
source <VENV>/bin/activate           # e.g. ~/venvs/torch

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export TMPDIR=/tmp/$USER/$SLURM_JOB_ID
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

echo "job $SLURM_JOB_ID on $(hostname), CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES, started $(date -Is)"
python -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available(), torch.cuda.device_count(), 'GPU(s)')"

# one GPU:     python train.py ...
# several GPUs on the node (DDP):
#              torchrun --standalone --nproc_per_node=$SLURM_GPUS_ON_NODE train.py ...
<COMMAND>
echo "finished $(date -Is)"
