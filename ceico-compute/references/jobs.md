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
  (hybrid). Launch with `srun ./app` — `MpiDefault=pmix` so `--mpi` is optional
  (`--mpi=pmix_v3` and `pmix_v6` exist on Phoebe). Whole nodes: `--exclusive --mem=0`, up to
  128 tasks/node on Phoebe, 64 on Koios.
  Do not use `mpirun` with a hostfile.
- Python `multiprocessing` / joblib: `--cpus-per-task=N` and use
  `int(os.environ["SLURM_CPUS_PER_TASK"])` workers, never `os.cpu_count()` (that reports the
  whole node).
- Many small independent tasks: job array (`--array=1-100%20` limits to 20 running), not
  thousands of separate `sbatch` calls. Per-task index `$SLURM_ARRAY_TASK_ID`.

## Interactive work

```bash
srun --partition=cpu_int --cpus-per-task=4 --mem=8G --time=02:00:00 --pty bash
srun --partition=rocky10 --gres=gpu:a100:1 --cpus-per-task=8 --mem=64G --time=02:00:00 --pty bash   # Phoebe
srun --partition=gpu --gres=gpu:p100:1 --cpus-per-task=8 --mem=32G --time=02:00:00 --pty bash       # Koios
```

Koios `cpu_int` has only 2 nodes; there `cpu` works for interactive `srun` too.
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
  (Rocky 10, no Phoebe stacks or Koios `c9`).
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
