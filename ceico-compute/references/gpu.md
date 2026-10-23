# GPU jobs: Phoebe `rocky10` (A100) and Koios `gpu` (P100)

| | Phoebe `rocky10` | Koios `gpu` |
|---|---|---|
| Nodes | `gpu1`, `gpu2`: 8× A100 80 GB each | `gpu3`, `gpu4`: 2× P100 16 GB each |
| Compute capability | 8.0 (`sm_80`) | 6.0 (`sm_60`) |
| Request | `--gres=gpu:a100:N` (1–8) | `--gres=gpu:p100:N` (1–2) |
| CUDA | 12.x and 13.x | **12.x only** (CUDA 13 dropped `sm_60`) |
| Software | EESSI (GPU builds), NVHPC, `/usr/local/cuda`, venvs, Apptainer | NVHPC CUDA 12.9 (no cuDNN), PyTorch `cu126`, EESSI CPU builds |

Default to Phoebe. Use Koios only when the user asks, the data is on Koios, or the Phoebe
GPUs are full and the code still supports the P100 — see [Koios P100 nodes](#koios-p100-nodes-gpu).
Moving files between the clusters: [storage.md](storage.md#copying-between-the-clusters).
The rest of this file up to that section is about Phoebe.

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
# once: uv itself, from PyPI with a module Python (on the login node of either cluster)
module load Python/3.12.3-GCCcore-13.3.0 && pip install --user uv && module purge
# uv lands in ~/.local/bin; check with: ~/.local/bin/uv --version
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

## Koios P100 nodes (`gpu`)

- Nodes `gpu3`, `gpu4`: 2× Tesla P100-SXM2 16 GB each (compute capability 6.0), 1× Xeon Gold
  6130 with 32 cores (no SMT), 125 GB RAM, 81 GB `/tmp` **shared by all jobs on the node**
  (use the `mktemp` pattern from [storage.md](storage.md)). Rocky Linux 10.2, driver 580
  (the last driver branch that supports Pascal GPUs).
- Partition `gpu`, max 9-01:03:00, default memory 3 GB/CPU. About 16 CPUs per GPU.
- The Koios `c9` modules are **not** available (`MODULEPATH` still names them, but the
  repository isn't mounted). `/usr/local/cuda` doesn't exist. Python: `/usr/bin/python3` 3.12
  or a uv-managed Python.
- **CUDA 12.x only**: CUDA 13 compilers fail with `Unsupported gpu architecture 'sm_60'`.
  Compile with `-arch=sm_60` (nvcc 12.x warns that pre-`sm_75` targets are deprecated;
  `-Wno-deprecated-gpu-targets` silences it).
- Template: `gpu_koios_p100.sbatch`.

CUDA toolkit, two ways:

1. **NVIDIA HPC SDK 26.5, CUDA 12.9 (default; template `gpu_koios_p100.sbatch`)** — the SDK's
   default `nvcc` (also in the `nvhpc-hpcx-cuda12` module) is CUDA 13.2 and fails for `sm_60`,
   so put the bundled CUDA 12.9 first in `PATH`. The math libraries (cuBLAS, cuFFT, cuSOLVER,
   cuSPARSE, cuRAND) are in a separate directory:
   ```bash
   NVHPC=/opt/nvidia/hpc_sdk/Linux_x86_64/26.5
   export CUDA_HOME=$NVHPC/cuda/12.9 CUDA_MATH=$NVHPC/math_libs/12.9
   export PATH=$CUDA_HOME/bin:$PATH CPATH=$CUDA_MATH/include LIBRARY_PATH=$CUDA_MATH/lib64
   nvcc -arch=sm_60 -Xlinker -rpath=$CUDA_HOME/lib64:$CUDA_MATH/lib64 -o app app.cu -lcublas
   ```
   NCCL is in `$NVHPC/comm_libs/12.9/nccl`; **cuDNN is not included**. With the `nvhpc` module,
   `nvc++ -cuda -gpu=cc60` and OpenACC `-acc -gpu=cc60` also work.
2. **EESSI CUDA toolkit (when cuDNN is needed)** — EESSI has GPU builds only for cc70 and
   newer. On the P100 its detection finds `cc60`, selects no accelerator, and
   `module load CUDA/…` fails with "cannot be loaded as requested". Overriding the target to
   the closest one, `cc70`, makes the toolkit modules loadable:
   ```bash
   export EESSI_ACCELERATOR_TARGET_OVERRIDE=accel/nvidia/cc70
   source /cvmfs/software.eessi.io/versions/2025.06/init/lmod/bash
   module load CUDA/12.8.0 cuDNN/9.10.1.4-CUDA-12.8.0   # load both; cuDNN doesn't pull in CUDA
   nvcc -arch=sm_60 -Xlinker --disable-new-dtags \
        -Xlinker -rpath=$EBROOTCUDNN/lib:$EBROOTCUDA/lib64 -o app app.cu -lcudnn
   ```
   Tested on the P100 (`cudnnCreate` and a ReLU forward pass). `cuDNN/9.15.0.57-CUDA-12.9.1`
   refuses to load ("not supported for … Compute Capabilities: ['7.0']"); `CUDA/12.9.1` alone
   loads fine.
   The override also makes EESSI's GPU *applications* (GROMACS, LAMMPS, …) loadable, but they
   are built for `sm_70`+ and fail on the P100 (`no kernel image is available`). Use the toolkit
   only; for applications use their CPU builds (without the override) or Phoebe. EESSI 2026.06
   has only CUDA 13: use 2025.06.

PyTorch on the P100: only the **CUDA 12.6** builds still contain `sm_60`. The default PyPI
wheel and the `cu128` builds and newer don't (`torch.cuda.is_available()` is `True`, but every
kernel fails with `no kernel image is available`). Tested: `torch 2.14.1+cu126` works.

```bash
uv venv --python 3.12 ~/venvs/torch-p100      # on the Koios login node; own venv, not the Phoebe one
uv pip install --python ~/venvs/torch-p100/bin/python torch --index-url https://download.pytorch.org/whl/cu126
```

Use it with `gpu_pytorch_venv.sbatch`, changing the partition to `gpu` and `--gres` to
`gpu:p100:N`. Check: `python -c "import torch; print(torch.cuda.get_arch_list())"` must list `sm_60`.

## Profiling (Phoebe)

- `nsys profile --trace=cuda,nvtx,osrt -o timeline ./app` — no constraint needed.
- `ncu` and `nsys --gpu-metrics-devices=all` need `#SBATCH --constraint=nsight` (stops DCGM
  monitoring on that node while the job runs — use only for profiling jobs). Limit `ncu` with
  `--kernel-name`, `--launch-skip`, `--launch-count`.
