# Nodes, partitions and policies: Phoebe and Koios

Snapshot from 2026-10 (both clusters: Slurm 25.11). Verify with `sinfo -s`,
`scontrol show partition NAME`, `sacctmgr show qos` on the cluster when it matters.
Each cluster has its own Slurm: a job submitted on Phoebe runs only on Phoebe.

## At a glance

| | Phoebe | Koios |
|---|---|---|
| Login | `phoebe.fzu.cz` | `koios1.fzu.cz` |
| CPU nodes | 20 × 2× AMD EPYC 7543: 64 cores / 128 threads, 512 GB | 27 × 2× Xeon Gold 6130 (Skylake): 32 cores / 64 threads, 384 GB |
| GPU nodes | 2 × 8× A100 80 GB (`rocky10`) | none in Slurm (P100 node dedicated to a project) |
| Interconnect | 100 Gb/s HDR InfiniBand | 100 Gb/s EDR InfiniBand |
| OS | Rocky 8 (CPU), Rocky 10 (GPU) | Rocky 9 |
| Default mem | 2 GB/CPU (GPU nodes 16 GB/CPU) | 3 GB/CPU |
| Max time | `cpu` 18 d, `cpu_int` 20 d, `rocky10` 14 d | 9 d 1 h (`small_int` 7 d) |
| Software | stacks `2023a`–`2026a`, `system`; EESSI | tree `c9`; EESSI |
| `/tmp` in jobs | node-local, shared by jobs on the node | node-local, private per job |
| Shared scratch | none | `/mnt/shared-scratch` |

Both: no default time limit (a job without `--time` gets the partition maximum), memory is a
consumable resource (`CR_Core_Memory`), `MpiDefault=pmix`, priority = QOS + fair share
(reset weekly) + age (up to 7 days), `sprio -j ID` shows the parts. Never pass `--account`.

## Phoebe

### Hardware

| Nodes | CPU / node | RAM / node | GPUs | Local `/tmp` | OS |
|---|---|---|---|---|---|
| `n1`–`n20` | 2× AMD EPYC 7543, 64 cores / 128 threads (SMT on) | 512 GB | – | ~1.7 TB NVMe | Rocky 8 |
| `gpu1`, `gpu2` | 64 cores, SMT off (Slurm: 8 sockets × 8 cores = NUMA domains) | 2 TB | 8× NVIDIA A100 80 GB | ~3 TB NVMe | Rocky 10 |
| `s1`–`s3` | 8 vCPUs of EPYC 73F3 (VMs, no InfiniBand) | 64 GB | – | ~1 TB | Rocky 8 |

### Partitions to use

| Partition | Nodes | Max time | Default mem | Use |
|---|---|---|---|---|
| `cpu` (default) | `n[4-20]` | 18-08:00:00 | 2 GB/CPU | batch CPU work, MPI |
| `cpu_int` | `n[1-20]` | 20-10:12:00 | 2 GB/CPU | interactive and short jobs; higher priority — can **suspend** `cpu` jobs on the same node (GANG,SUSPEND) |
| `preempt` | `n[1-20]` | 5-00:00:00 | 2 GB/CPU | opportunistic; jobs can be **requeued** (`PREEMPTED`) — only for restartable/checkpointing code |
| `small_int` | `s[1-3]` | 7-07:08:00 | ~3.5 GB/CPU | light jobs ≤ 8 CPUs, quick tests, no MPI across nodes |
| `rocky10` | `gpu[1-2]` | 14-04:00:00 | 16 GB/CPU | all GPU work; never suspended. See [gpu.md](gpu.md) |

Do not use: `debug`, `project001` (reserved), `gpu`, `gpu1`, `gpu2`, `gpu_int` (legacy, no
usable nodes or down — jobs there never start).

### QOS

- Default QOS `normal`: max 16 A100 GPUs per user in total, max 3000 jobs.
- Others exist (`manyjobs`, `newbie`, `max64cpu`, `max400cpu`, `gpu_max2`, per-user QOS) and are
  assigned by admins; a user's own may cap CPUs (e.g. `max400cpu` = 3000 CPUs).

### Profiling constraint

GPU hardware counters (Nsight Compute `ncu`, `nsys --gpu-metrics-devices`) need
`--constraint=nsight`. See [gpu.md](gpu.md).

## Koios

The previous-generation cluster; good for CPU work, especially when Phoebe is busy.

### Hardware

| Nodes | CPU / node | RAM / node | Local `/tmp` | OS |
|---|---|---|---|---|
| `n1`–`n27` | 2× Intel Xeon Gold 6130 (Skylake, AVX-512), 32 cores / 64 threads (SMT on) | 384 GB | ~1.7 TB NVMe | Rocky 9 |
| `s1` | 8 vCPUs (VM) | 23 GB | – | Rocky 9 |

The GPU node (`gpu2`, 4× P100 16 GB) is a VM dedicated to a project and is not in Slurm.

### Partitions to use

| Partition | Nodes | Max time | Default mem | Use |
|---|---|---|---|---|
| `cpu` (default) | `n[1-9,11-27]` | 9-01:03:00 | 3 GB/CPU | batch CPU work, MPI |
| `cpu_int` | `n[11-12]` | 9-01:03:00 | 3 GB/CPU | interactive work; only 2 nodes, same priority as `cpu` |
| `preempt` | `n8` | 9-01:03:00 | 3 GB/CPU | one node; jobs can be **requeued** |
| `small_int` | `s1` | 7-07:08:00 | 3.5 GB/CPU | light jobs ≤ 8 CPUs, ≤ 23 GB |

Do not use: `project001` (account `fzu_project001` only), `slurm_test` (account `slurm_test`
only), `rocky10` (a single test node on Koios, not a GPU partition).

### QOS

- Default QOS `normal`: at most 5000 CPUs per user. Some users and projects have their own QOS
  with job-count or CPU caps (e.g. `max10r` = 10 running jobs).
- Check with `sacctmgr -n show assoc user=$USER format=account,qos%40,defaultqos`.

## Allocation rules (both clusters)

- Always give a realistic `--time` (+ ~20–50% margin); backfill can't fit jobs that ask for
  the partition maximum.
- On CPU nodes a Slurm "CPU" is a hardware thread; whole cores are allocated
  (`--cpus-per-task=1` → 2 CPUs). Phoebe GPU nodes have no SMT (1 CPU = 1 core).
  For compute-bound code, `--cpus-per-task=2*threads` with `OMP_NUM_THREADS=threads`
  or `--hint=nomultithread` are both reasonable; keep it simple unless the user cares.
- Exceeding memory kills the job (`OUT_OF_MEMORY`). On Phoebe GPU nodes the 16 GB/CPU default
  adds up fast (8 CPUs = 128 GB) and RAM can run out before GPUs do: set `--mem` explicitly.
- Whole node: `--exclusive --mem=0` (Phoebe: up to 128 tasks per node, Koios: 64).
- `sshare -U` shows the user's fair share.
