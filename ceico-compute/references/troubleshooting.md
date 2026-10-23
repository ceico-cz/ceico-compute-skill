# Troubleshooting jobs on Phoebe and Koios

Run all commands on the cluster where the job was submitted.

Docs: https://hpc.ceico.cz/slurm/troubleshooting/

Start every diagnosis with:

```bash
sacct -j ID --format=JobID,JobName%20,Partition,State,ExitCode,DerivedExitCode,Elapsed,Timelimit,AllocCPUS,ReqMem,MaxRSS,NodeList
tail -n 100 <jobname>-ID.out
seff ID
```

## Job finished in a bad state

| State / symptom | Meaning | Fix |
|---|---|---|
| `OUT_OF_MEMORY`, `oom-kill` in output | exceeded `--mem` | raise `--mem` to MaxRSS + 20–30%; reduce problem size / threads |
| `TIMEOUT` | hit `--time` | longer `--time` (partition max: Phoebe cpu 18 d, rocky10 14 d, preempt 5 d; Koios 9 d) or add checkpoints |
| `FAILED`, ExitCode `N:0` | program exited with N | read the output; often missing module, file not found, wrong path |
| ExitCode `0:9` / `0:15` | killed by signal | OOM, time limit, or `scancel` |
| `PREEMPTED` / requeued | `preempt` partition gave way | expected there; use `cpu` or make code restartable (`--requeue`, checkpoint/resume) |
| `NODE_FAIL` | node problem | resubmit; if repeated on one node, report it to the admin with the job ID |
| `CANCELLED by <uid>` | the user or admin cancelled | ask the user / admin |
| job runs but `SUSPENDED` for a while | Phoebe: `cpu` job paused by a `cpu_int` job (GANG) | normal; the clock pauses too. Use `cpu_int` for latency-sensitive short jobs |

## Common errors inside the job

| Error | Cause | Fix |
|---|---|---|
| `module: command not found` | non-login shell without Lmod | first line `#!/bin/bash` (sbatch uses a login-like env); or `source /etc/profile.d/lmod.sh` |
| `Lmod has detected the following error: … unknown module` on a GPU node | Phoebe stacks aren't available on `rocky10` | use EESSI / NVHPC / venv (see [gpu.md](gpu.md)) |
| `These module(s) or extension(s) exist but cannot be loaded as requested` | dependency from a different stack / toolchain needed first | `module spider NAME/VERSION` and load what it lists; don't mix stacks |
| `GLIBC_2.xx not found`, `libfoo.so: cannot open shared object` | binary or venv built on another cluster / node type (Phoebe Rocky 8 vs Koios Rocky 9 vs the Rocky 10 GPU nodes of both) | rebuild where it runs; use uv-managed Python for venvs |
| `module: Miniforge3` / `CUDA` / `Mathematica` unknown on Koios | Koios has no `system` stack | own Miniforge in `~/miniforge3`; GPU and Mathematica work on Phoebe |
| file not found that exists "on the cluster" | it is in the other cluster's home | copy it ([storage.md](storage.md#copying-between-the-clusters)) |
| `libcudnn…` / `libcublas…` not found with EESSI | EESSI doesn't set `LD_LIBRARY_PATH` | link with RPATH (`-Xlinker --disable-new-dtags -Xlinker -rpath=…`), see [software.md](software.md#eessi-cvmfssoftwareeessiio) |
| `torch.cuda.is_available() == False` | no `--gres`, CPU-only wheel, or job on a CPU partition | `--partition=rocky10 --gres=gpu:a100:1` (Koios: `--partition=gpu --gres=gpu:p100:1`); reinstall the CUDA wheel |
| `CUDA error: no kernel image is available` | built without the GPU's architecture (A100 `sm_80`, P100 `sm_60`), or an EESSI GPU app / PyTorch build without `sm_60` on Koios | compile with `-arch=sm_80` / `-arch=sm_60`; on the P100 see [gpu.md](gpu.md#koios-p100-nodes-gpu) |
| `nvcc fatal: Unsupported gpu architecture 'sm_60'` | CUDA 13 compiler (NVHPC default, EESSI 2026.06) on Koios P100 | use CUDA 12.x: NVHPC `…/26.5/cuda/12.9/bin` (template `gpu_koios_p100`) or EESSI 2025.06 `CUDA/12.9.1` |
| `CUDA/… cannot be loaded as requested` on Koios `gpu` | EESSI has no cc60 (P100) builds | use NVHPC CUDA 12.9; only if cuDNN is needed: `export EESSI_ACCELERATOR_TARGET_OVERRIDE=accel/nvidia/cc70` before the EESSI init (toolkit only) |
| `module: … unknown` on Koios `gpu` nodes | `c9` tree isn't available on the Rocky 10 GPU nodes | EESSI or own envs, see [gpu.md](gpu.md#koios-p100-nodes-gpu) |
| `CUDA out of memory` | 80 GB per GPU exceeded | smaller batch, mixed precision, more GPUs |
| MPI hangs / `PMIx` errors | `mpirun` with wrong launcher, or mixed MPI | launch with `srun`, single toolchain, `module purge` first |
| Very slow, `seff` CPU efficiency ≪ 100% | threads not matching allocation, or I/O bound | set `OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`; stage data to `/tmp` |
| CPU efficiency > 100% / node overloaded | code uses all cores of the node (`os.cpu_count()`) | limit threads to `$SLURM_CPUS_PER_TASK` |
| `Permission denied` writing output | output dir doesn't exist / not yours | `mkdir -p` it before `sbatch`; `--output` dir must exist |

## Job stays PENDING

`squeue -j ID -o "%.10i %.9P %.8T %.20R"` shows the reason; `squeue -j ID --start` the estimate.

| Reason | Meaning | Action |
|---|---|---|
| `Priority`, `Resources` | waiting its turn / for free nodes | normal; smaller `--time`/resources start earlier through backfill |
| `QOSMaxGRESPerUser` | user already uses 16 GPUs (Phoebe) | wait or cancel some |
| `QOSMaxJobsPerUserLimit` | per-user QOS job cap (e.g. Koios `max10r`) | wait; use a job array with `%N` throttling |
| `QOSMaxCpuPerUserLimit`, `AssocGrp*` | user's / group's CPU or GPU cap reached | wait; ask the admin if a higher limit is justified |
| `ReqNodeNotAvail`, `PartitionDown`, `PartitionNodeLimit` | wrong partition (Phoebe `gpu`, `gpu_int`, `project001`) or nodes down / in maintenance | use `rocky10` / `cpu`; check `sinfo -R` |
| `AccountNotAllowed`, `InvalidAccount` (submit error) | reserved partition (`project001`, `slurm_test`) | use `cpu` / `cpu_int` |
| `BadConstraints` / GPU request on Koios | GPUs requested on a CPU partition, or `a100` on Koios | Koios: `--partition=gpu --gres=gpu:p100:N` (N ≤ 2); A100s are on Phoebe `rocky10` |
| `PartitionTimeLimit` | `--time` > partition max | lower `--time` |
| `BadConstraints`, `InvalidQOS` | unsatisfiable request (e.g. GPUs on a CPU partition, > 8 GPUs per node) | fix the request |
| `MaxMemPerLimit` / never starts on GPU node | `--mem` too large (> ~2 TB) or memory already allocated by others | lower `--mem` |

## Escalating

If it looks like a cluster problem (node failures, CVMFS errors, file system hangs), give the
user the cluster, job ID, node, time and error lines to send to the cluster administrator; don't retry in a loop.
