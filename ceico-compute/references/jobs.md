# Writing, submitting and monitoring jobs

Docs: https://hpc.ceico.cz/slurm/batch-jobs/, https://hpc.ceico.cz/slurm/interactive/

## Job directory convention

Keep each run in its own directory on the cluster, e.g. `~/jobs/<name>/` (mode `700`: some
home directories are readable by others, and new files on Phoebe are group-writable by default) containing the code (or a
checkout), `job.sbatch`, inputs, and outputs `<jobname>-<jobid>.out`. Submit from there —
Slurm's working directory is the submit directory.

## Templates

Copy from `templates/` and fill every `<PLACEHOLDER>`:

| Template | For |
|---|---|
| `cpu_serial.sbatch` | one process, 1–2 threads |
| `cpu_openmp.sbatch` | one process, many threads (OpenMP, NumPy/BLAS, multiprocessing) |
| `mpi.sbatch` | MPI across tasks/nodes with `foss` + `srun` |
| `array.sbatch` | many independent runs (parameter scans) |
| `conda.sbatch` | conda env on CPU nodes |
| `gpu_eessi.sbatch` | CUDA code/apps from EESSI on `rocky10` |
| `gpu_pytorch_venv.sbatch` | PyTorch (or other pip GPU stack) in a uv venv on `rocky10` |
| `gpu_koios_p100.sbatch` | CUDA 12.x code on the Koios P100 nodes (`gpu`) |
| `apptainer.sbatch` | container image, CPU or GPU |

Common header choices:
- `--time` realistic + margin; formats `MM:SS`, `HH:MM:SS`, `D-HH:MM:SS`.
- `--mem=` per node or `--mem-per-cpu=`; start from the measured peak (`sacct … MaxRSS`,
  `seff`) + 20%.
- `--output=%x-%j.out` (name-jobid); add `--error=%x-%j.err` to split stderr.
- Optional `--mail-type=END,FAIL --mail-user=<email>` only if the user wants e-mail.
- `set -euo pipefail` makes the job fail visibly on the first error. Drop `-u` if sourcing
  scripts that use unset variables (some conda/EESSI init scripts do; the templates handle it).

## Sizing guidance

- Threaded: `--ntasks=1 --cpus-per-task=N`, `export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`
  (for Python/NumPy also `OPENBLAS_NUM_THREADS`, `MKL_NUM_THREADS`). On `n*` nodes, N counts
  hardware threads.
- MPI: `--ntasks=N` (or `--nodes=K --ntasks-per-node=M`), `--cpus-per-task=1` (pure MPI) or >1
  (hybrid). Launch with `srun ./app` — PMIx is the cluster default, so `--mpi` is optional
  (Koios currently uses `pmix_v3`; see the launch notes below). Whole nodes: `--exclusive --mem=0`, up to
  128 tasks/node on Phoebe, 64 on Koios.
  Do not use `mpirun` with a hostfile.
- Python `multiprocessing` / joblib: `--cpus-per-task=N` and use
  `int(os.environ["SLURM_CPUS_PER_TASK"])` workers, never `os.cpu_count()` (that reports the
  whole node).
- Many small independent tasks: job array (`--array=1-100%20` limits to 20 running), not
  thousands of separate `sbatch` calls. Per-task index `$SLURM_ARRAY_TASK_ID`.

## Koios MPI launch and transport

For EESSI OpenMPI CPU applications, use `templates/mpi.sbatch` with the Koios EESSI init
and the same toolchain used for the build. Put the resource layout in `#SBATCH` and launch
with **`srun --unbuffered ./APP ...`**. The step inherits the allocation's task count; no
hostfile, repeated rank count or explicit `--mpi` is needed.

Koios was verified on 2026-11-02 with `MpiDefault=pmix_v3`. Check live settings when diagnosing
launch problems:

```bash
scontrol show config | grep MpiDefault
srun --mpi=list
```

An explicit `--mpi=pmix` overrides the default and need not mean the same plugin: on the
verified Koios installation the unversioned alias selected v6. Prefer omitting `--mpi`;
use `--mpi=pmix_v3` only when deliberately selecting that available plugin. Inherited
`SLURM_MPI_TYPE` can also override the default; inspect it when comparing scripts.

**PMIx handles process startup/coordination; it does not select InfiniBand.** OpenMPI
selects its communication transport separately. With EESSI 2025.06 `foss/2024a`
(OpenMPI 5.0.3) on Koios CPU nodes with active IB, UCX was selected automatically, and
cross-node MPI communication used IB without setting `OMPI_MCA_pml`, `OMPI_MCA_osc`,
`OMPI_MCA_coll`, `UCX_TLS` or `UCX_NET_DEVICES`. Start without these overrides; inspect
inherited settings if old scripts behave differently. Do not force TCP or disable
collective components as routine setup. OpenMPI 5 uses UCX for IB; old `openib` BTL
recipes do not apply. See [OpenMPI's IB/UCX documentation](https://docs.open-mpi.org/en/v5.0.3/tuning-apps/networking/ib-and-roce.html).

Keep resource and binding choices proportional to the application:

- Pure MPI: `--cpus-per-task=1`, `OMP_NUM_THREADS=1`; limit incidental BLAS threads
  (e.g. `OPENBLAS_NUM_THREADS=1`) to avoid nested threading.
- Koios has 32 physical cores / 64 hardware threads per CPU node. For one rank per
  physical core, request up to 32 ranks/node with `--threads-per-core=1`; 64 ranks/node
  uses SMT. Hybrid MPI/OpenMP needs fewer ranks and more CPUs per rank.
- Start with Slurm's default CPU binding. `--cpu-bind=none` is a diagnostic option for
  a demonstrated affinity problem, not a general requirement. Benchmark placement and
  threading at the production layout before assuming that a small smoke test scales.

Validate a small input across **two CPU nodes**, check rank placement and an MPI data
exchange as well as application output and `sacct` exit codes. A PMIx launch or successful
single-node run alone does not establish IB use. If transport verification is needed,
inspect OpenMPI/UCX diagnostic logs and active IB port counters before/after an actual
cross-node payload; counters on shared nodes can include other traffic.

`mpirun ./APP` inside a Slurm allocation is also supported and discovers the allocation
without a hostfile; plain `srun` is the tested local template convention, not an upstream
OpenMPI requirement. See [OpenMPI's Slurm launch documentation](https://docs.open-mpi.org/en/v5.0.x/launching-apps/slurm.html).

## Interactive work

```bash
srun --partition=cpu_int --cpus-per-task=4 --mem=8G --time=02:00:00 --pty bash       # Phoebe; Koios: cpu
srun --partition=rocky10 --gres=gpu:a100:1 --cpus-per-task=8 --mem=64G --time=02:00:00 --pty bash   # Phoebe
srun --partition=gpu --gres=gpu:p100:1 --cpus-per-task=8 --mem=32G --time=02:00:00 --pty bash       # Koios
```

Koios has no `cpu_int`: use `cpu` for interactive `srun` there.
Run inside `screen`/`tmux` on the login node so a dropped SSH does not kill it. From an
agent shell (no TTY), prefer a short batch job, or `srun … bash -c '<commands>'` without
`--pty` for a quick one-off test (e.g. building on a GPU node):

```bash
ssh phoebe 'cd ~/jobs/x && srun -p rocky10 --gres=gpu:a100:1 -c 8 --mem=32G -t 00:20:00 bash -c "nvidia-smi && make"'
# longer command sequences: pipe a script to the job's shell (srun forwards stdin)
ssh phoebe 'cd ~/jobs/x && srun -p cpu_int -c 4 --mem=8G -t 00:20:00 bash -s' < probe.sh
```

Several steps in one allocation (user's terminal): `salloc` reserves resources and opens a
shell on the login node; each `srun` inside then runs on the allocated node, and `exit`
releases it.

```bash
salloc --partition=cpu_int --cpus-per-task=4 --mem=8G --time=02:00:00
srun hostname          # runs on the compute node
srun --pty bash        # or open a shell there
exit                   # end the allocation
```

Notes:
- The interactive job's working directory is the directory where `srun` was started;
  modules loaded on the login node are inherited, so `module purge` first on the GPU nodes
  (Rocky 10, no Phoebe stacks).
- Inside, `$SLURM_JOB_ID`, `$SLURM_CPUS_PER_TASK` and `CUDA_VISIBLE_DEVICES` are set as in
  batch jobs. `squeue --me` shows the session as a running job; it counts against limits
  until `exit`, so don't leave idle sessions open for days.

## Submitting

```bash
ssh phoebe 'cd ~/jobs/<name> && sbatch job.sbatch'
# -> Submitted batch job 123456
sbatch --test-only job.sbatch     # validate + estimated start, submits nothing
sbatch --dependency=afterok:123456 post.sbatch
```

Options given on the `sbatch` command line override `#SBATCH` lines.

## Monitoring

```bash
squeue --me                                   # pending/running, with reason
squeue -j ID -o "%.10i %.9P %.20j %.8T %.10M %.10l %R"
squeue -j ID --start                          # scheduler's start estimate
scontrol show job ID                          # full allocation details
sacct -j ID --format=JobID,JobName%20,Partition,State,Elapsed,Timelimit,AllocCPUS,ReqMem,MaxRSS,ExitCode
seff ID                                       # CPU and memory efficiency after the end
tail -n 50 ~/jobs/<name>/<jobname>-ID.out
sstat -j ID --format=JobID,AveCPU,MaxRSS     # live stats of a running step
```

Web (Phoebe): https://jobs.phoebe.fzu.cz shows each job's CPU/GPU usage.

When polling from an agent, wait sensibly (e.g. check every few minutes for short jobs; for
long jobs give the user the commands and stop), and don't busy-loop `squeue`.

## After the job

1. `sacct` state `COMPLETED` and `ExitCode 0:0`.
2. Read the output file; verify the expected results files exist.
3. `seff ID`: if memory or CPU efficiency is low, suggest smaller requests next time.
4. Copy results back (`rsync`) if wanted; big outputs stay on the cluster.

## Cancelling / changing (on the user's request)

```bash
scancel ID; scancel -u $USER --state=PENDING
scontrol update JobId=ID TimeLimit=2-00:00:00   # can only be lowered by users
scontrol hold ID; scontrol release ID
```
