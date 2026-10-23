#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=gpu              # Koios only: 2 nodes with 2x Tesla P100 16 GB each
#SBATCH --time=<HH:MM:SS>
#SBATCH --gres=gpu:p100:<NGPUS>      # 1-2 per node
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=<NCPUS>      # node has 32 cores (no SMT), ~16 per GPU
#SBATCH --mem=<MEM>                  # node has 125 GB; default is 3 GB per CPU
#SBATCH --output=%x-%j.out
set -euo pipefail

# P100 = compute capability 6.0 (sm_60): needs a CUDA 12.x toolkit, CUDA 13 can't target it.
# Rocky 10 node without the Koios c9 modules. CUDA 12.9 from the NVIDIA HPC SDK; not its
# default nvcc (CUDA 13.2), which fails for sm_60. Build with:
#   nvcc -arch=sm_60 -Xlinker -rpath=$CUDA_HOME/lib64:$CUDA_MATH/lib64 ... [-lcublas -lcufft ...]
module purge
NVHPC=/opt/nvidia/hpc_sdk/Linux_x86_64/26.5
export CUDA_HOME=$NVHPC/cuda/12.9
export CUDA_MATH=$NVHPC/math_libs/12.9     # cuBLAS, cuFFT, cuSOLVER, cuSPARSE, cuRAND
export PATH=$CUDA_HOME/bin:$PATH
export CPATH=$CUDA_MATH/include${CPATH:+:$CPATH}
export LIBRARY_PATH=$CUDA_MATH/lib64${LIBRARY_PATH:+:$LIBRARY_PATH}
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$CUDA_MATH/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
# NCCL: $NVHPC/comm_libs/12.9/nccl. No cuDNN here: for cuDNN use the EESSI 2025.06 CUDA
# toolkit instead (needs an accelerator override, see references/gpu.md)

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
# private scratch: /tmp on the Koios GPU nodes is shared by all jobs on the node
TMPDIR=$(mktemp -d "/tmp/${USER}.${SLURM_JOB_ID:?submit with sbatch}.XXXXXX")
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

echo "job $SLURM_JOB_ID on $(hostname), CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES, started $(date -Is)"
nvidia-smi --query-gpu=index,name,memory.total --format=csv
<COMMAND>                            # e.g. ./my_cuda_app
echo "finished $(date -Is)"
