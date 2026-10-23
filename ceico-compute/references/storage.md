# Storage on Phoebe and Koios

Docs: https://hpc.ceico.cz/systems/storage/

| What | Path | Size / limits | Notes |
|---|---|---|---|
| Home | `/home/<user>` | BeeGFS, ~218 TB shared by all | No quota, but **ask the admin before storing large data** (≳ 1 TB). **Each cluster has its own home**: files on Phoebe don't appear on Koios. Visible on all nodes of the cluster. |
| Project space | `/mnt/proj/pNNN_<name>` | NFS, 1 TB total for all projects | Group-shared (setgid), **the same directories on Phoebe and Koios**. Request a directory from the admin. Good for shared envs and small shared data. |
| Node-local scratch, Phoebe | `/tmp` on each node | ~1.7 TB (CPU), ~3 TB (GPU), ~1 TB (small) NVMe | Shared by all jobs on the node, **not** cleaned at job end; files unused for 10 days are deleted. `$TMPDIR` is not set. |
| Node-local scratch, Koios | `/tmp` on each node | ~1.7 TB NVMe | **Private to each job** and deleted when the job ends. |
| Shared scratch, Koios only | `/mnt/shared-scratch` | BeeGFS | Visible on all Koios nodes (multi-node jobs, passing data between jobs). Not cleaned automatically, no backup — delete your files when done. |
| Software | `/cvmfs/*` | read-only | see [software.md](software.md) |

- Phoebe has no shared scratch file system; Koios has `/mnt/shared-scratch`.
- **Nothing is backed up.** Remind users to keep important code in git and copies of
  important results elsewhere.
- Check usage: `du -sh ~/jobs/*` (BeeGFS `du` on huge trees is slow — run it sparingly);
  `df -h /home /mnt/proj`.

## Node-local `/tmp` pattern

Use for I/O-heavy work (many small files, temporary files, databases). The single-process
templates (`cpu_serial`, `cpu_openmp`, `conda`, `gpu_eessi`, `gpu_pytorch_venv`, `apptainer`)
set this up; `array` and `mpi` don't (for `mpi` see multi-node below). On Koios `/tmp` is
already private per job, and the same lines work there unchanged:

```bash
# private (mode 700), unpredictable name; ${SLURM_JOB_ID:?} stops the script outside a job
TMPDIR=$(mktemp -d "/tmp/${USER}.${SLURM_JOB_ID:?submit with sbatch}.XXXXXX")
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT
cp -r "$SLURM_SUBMIT_DIR/input" "$TMPDIR/"     # stage in
cd "$TMPDIR" && <run>                          # work locally
cp -r results "$SLURM_SUBMIT_DIR/"             # stage out before the trap cleans up
```

Don't use a fixed path like `/tmp/$USER/...`: on Phoebe `/tmp` is shared by all jobs on a node,
so another user could create that directory first and read or replace the files. And without
the `:?` guard, running the script outside Slurm would make the trap delete all of `/tmp/$USER`.

Multi-node jobs: each node has its own `/tmp`; let every task create its own directory with
`mktemp -d` inside the program or a wrapper script started by `srun`.

## Copying between the clusters

The homes are separate and the login nodes don't SSH to each other (no host keys, no agent
forwarding). Options:

- Through the user's machine, without a local copy: `scp -3 -r phoebe:jobs/x koios:jobs/`
  (`-3` routes the data through the local machine; uses the aliases from [access.md](access.md)).
- Via the shared project space `/mnt/proj/pNNN_*` (small data; 1 TB in total).
- Or `rsync` down and up again.

## Guidance

- Write job outputs into the job directory under `/home`; avoid thousands of tiny files per
  job (pack with `tar`, use HDF5/NetCDF/Parquet).
- Don't run many jobs that all read/write the same single file.
- Conda/uv/pip caches can grow large: `conda clean -a`, `uv cache clean`, `pip cache purge`.
