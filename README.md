# ceico-compute: a Claude skill for the CEICO clusters

A [Claude skill](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview) that
helps users run their codes on the CEICO HPC clusters at FZU Prague:
**Phoebe** (`phoebe.fzu.cz`, AMD EPYC nodes and A100 GPUs) and **Koios** (`koios1.fzu.cz`,
Xeon CPU nodes). With it, Claude:

- checks that SSH key login works and explains how to fix it when it doesn't;
- picks the cluster, the Slurm partition and the software: Lmod stacks, EESSI, NVHPC,
  conda/uv or Apptainer;
- copies the code there, writes an `sbatch` script from tested templates, shows it to you and
  submits it once you agree;
- follows the job, explains failures and copies the results back.

User documentation: https://hpc.ceico.cz/slurm/claude-skill/

Requirement: a Phoebe/Koios account (your SSH public key added by the cluster administrator,
see https://hpc.ceico.cz/getting-started/account/). Claude needs a shell with `ssh`, e.g.
Claude Code. Without a shell it still writes copy-ready commands and scripts.

## Install

- **CEICO-Cosmo members:** the skill is in the organization's skill library; nothing to install.
  In Claude Code, `/skills` should list `ceico-compute`.
- **Claude Code, manually:** download `ceico-compute.zip` from the
  [latest release](https://github.com/ceico-cz/ceico-compute-skill/releases/latest) and unzip
  it into `~/.claude/skills/` (for you) or `<project>/.claude/skills/` (for one project).
- **claude.ai / Claude desktop:** upload `ceico-compute.zip` as a skill (organization admins:
  to the organization library).

Then ask, for example: *"Run my simulation in ./sim on Phoebe with 32 cores"*,
*"Submit this MPI code on Koios on 2 nodes"* or *"Train train.py on an A100"*.

## Contents

```
ceico-compute/
  SKILL.md                 entry point: access check, cluster choice, workflow, rules
  scripts/check_access.sh  SSH login test: check_access.sh <phoebe|koios> [USER]
                           -> VERDICT: OK | NO_KEY | PERMISSION_DENIED | HOSTKEY_* | UNREACHABLE
  scripts/env_report.sh    live snapshot (partitions, QOS, jobs, software, storage); run on a login node
  references/              access, cluster, software, jobs, gpu, storage, troubleshooting
  templates/               sbatch templates (CPU serial/OpenMP/MPI/array/conda, GPU EESSI/PyTorch, Apptainer)
```

## Releasing

1. Change files under `ceico-compute/`, open a PR, merge.
2. Tag the merge commit and push the tag:
   ```bash
   git tag -a v1.1.0 -m "ceico-compute 1.1.0"
   git push origin v1.1.0
   ```
3. The `release` workflow checks the scripts, builds `ceico-compute.zip` and attaches it to a
   GitHub release.
4. Upload that zip to the CEICO-Cosmo skill library (replace the previous version).

## Maintenance

Cluster facts were last checked against both clusters on 2026-10-12: partitions, QOS, module
trees, EESSI versions, container images and storage. When partitions or software change, update
`references/cluster.md` and `references/software.md` together with the user docs in
[ceico-cz/hpc-docs](https://github.com/ceico-cz/hpc-docs). To compare with a cluster:
`ssh phoebe.fzu.cz 'bash -s' < ceico-compute/scripts/env_report.sh` (or `koios1.fzu.cz`).

Templates were tested with real jobs:
- On Phoebe: serial, OpenMP, 2-node MPI, array, conda and Apptainer (CPU). The GPU templates
  have only been syntax-checked.
- On Koios: serial, OpenMP and Apptainer (CPU, `docker://` image) on `small_int`, and
  2-node MPI (`foss/2024a`, `srun`) on `cpu`.

Known inconsistencies in hpc-docs, which the skill works around:
- `getting-started/ondemand/jupyterlab.md` still offers the dead Phoebe `gpu` / `gpu_int` partitions.
- `slurm/troubleshooting.md` shows an example job pending in partition `gpu`.
- The GPU node NVMe size is given as 3.2, 3.4 and 3.8 TB on different pages.
- Koios has undocumented partitions `rocky10` (n12) and `slurm_test`, and `software/modules.md`
  doesn't say that `SciPy-bundle` and `Mathematica` are missing from the `c9` tree.
