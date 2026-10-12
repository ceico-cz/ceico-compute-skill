# GPU jobs on Phoebe (`rocky10`)

GPU work runs only on Phoebe: Koios has no GPUs in Slurm (its P100 node is dedicated to a
project). If the user's files are on Koios, copy them to Phoebe first
([storage.md](storage.md#copying-between-the-clusters)).

Docs: https://hpc.ceico.cz/slurm/gpu-jobs/, https://hpc.ceico.cz/slurm/gpu-profiling/

## Facts

- Nodes `gpu1`, `gpu2`: 8× NVIDIA A100 80 GB (compute capability 8.0) each, 64 cores (no SMT),
  2 TB RAM, ~3 TB NVMe `/tmp`. Rocky Linux 10, driver supports CUDA ≤ 13.4.
- Partition `rocky10` (14-04:00:00 max), jobs never suspended. Old partitions `gpu`, `gpu1`,
  `gpu2`, `gpu_int` don't work.
- Max 16 GPUs per user across all jobs (QOS `normal`).
- Usage per job (SM activity, memory BW, power) at https://jobs.phoebe.fzu.cz — check it after
  a first run; near-zero SM activity means the code isn't using the GPU (or is starved by I/O / too few CPUs).

## Requesting

```bash
#SBATCH --partition=rocky10
#SBATCH --gres=gpu:a100:1        # 1–8 per node (or --gpus=N)
#SBATCH --cpus-per-task=8        # ~8 per GPU
#SBATCH --mem=64G                # explicit! default is 16 GB per CPU
#SBATCH --time=04:00:00
```

- Multi-GPU on one node: `--gres=gpu:a100:4 --cpus-per-task=32`. Multi-node GPU: `--nodes=2
  --ntasks-per-node=8 --gres=gpu:a100:8` — only for codes that really scale; nodes are often busy.
- Specific node: `--nodelist=gpu1` (only if needed).
- Slurm sets `CUDA_VISIBLE_DEVICES`; the job sees only its GPUs, numbered from 0. Never
  hard-code physical indices.
- Check queue first: `squeue -p rocky10`, `sinfo -p rocky10 -O NodeList,GresUsed:40,CPUsState,AllocMem,Memory`.
  If both nodes are full, tell the user the expected wait (`squeue -j ID --start`).

## Software on GPU nodes

The Phoebe CVMFS stacks and their `CUDA` modules are **not** available. Options:

1. **EESSI** — CUDA, cuDNN, NCCL, GPU builds of GROMACS/LAMMPS/… (template `gpu_eessi.sbatch`):
   `source /cvmfs/software.eessi.io/versions/2025.06/init/lmod/bash; module load CUDA/12.9.1`
2. **System CUDA 13.4** — `export PATH=/usr/local/cuda/bin:$PATH` (nvcc, ncu, compute-sanitizer).
3. **NVIDIA HPC SDK** — `module use /opt/nvidia/hpc_sdk/modulefiles; module load nvhpc-hpcx-cuda13`
   (nvc/nvc++/nvfortran with OpenACC/CUDA Fortran, HPC-X MPI).
4. **pip / uv venv** — PyTorch, JAX, CuPy, TensorFlow wheels bundle their CUDA libs
   (template `gpu_pytorch_venv.sbatch`).
5. **Apptainer** — NGC PyTorch image on CVMFS
   (`/cvmfs/apptainer.phoebe.lan/nvcr.io/nvidia/pytorch/26.05-py3/pytorch_26.05-py3.sif`), run
   with `--nv` (template `apptainer.sbatch`).

Code compiled on the Rocky 8 login/CPU nodes may fail on Rocky 10 (glibc / library
differences, missing module libraries). **Build GPU code on a GPU node**, e.g.
`srun -p rocky10 --gres=gpu:a100:1 -c 8 --mem=32G -t 00:30:00 bash -c "…; make"`.
Use `-arch=sm_80` (A100) for nvcc.

## PyTorch with uv (recommended for Python ML)

Set up once (download-bound; fine on the login node). The venv must be created with a
uv-managed Python (not module Python, which is missing on Rocky 10, nor `/usr/bin/python3`
3.6 on the login node):

```bash
# once: uv itself
curl -LsSf https://astral.sh/uv/install.sh | sh        # or: pip install --user uv
# venv with a self-contained Python, usable on Rocky 8 and 10
uv venv --python 3.12 ~/venvs/torch
uv pip install --python ~/venvs/torch/bin/python torch torchvision   # CUDA 12.x wheels
```

Check in a job: `python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"`.

Keep the cache out of small home areas if needed: `export UV_CACHE_DIR=/mnt/proj/<p>/uv-cache`.

Multi-GPU (single node), DDP:

```bash
#SBATCH --gres=gpu:a100:4 --cpus-per-task=32 --ntasks=1
torchrun --standalone --nproc_per_node=$SLURM_GPUS_ON_NODE train.py
```

Data loading: `num_workers` ≈ CPUs per GPU − 1; stage many-small-file datasets into
`/tmp/$USER/$SLURM_JOB_ID` first (see [storage.md](storage.md)).

## Profiling

- `nsys profile --trace=cuda,nvtx,osrt -o timeline ./app` — no constraint needed.
- `ncu` and `nsys --gpu-metrics-devices=all` need `#SBATCH --constraint=nsight` (stops DCGM
  monitoring on that node while the job runs — use only for profiling jobs). Limit `ncu` with
  `--kernel-name`, `--launch-skip`, `--launch-count`.
