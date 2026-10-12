# Software on Phoebe and Koios

Where software comes from depends on the cluster and node type:

| Node type | Module stacks available |
|---|---|
| Phoebe: login node, `cpu`, `cpu_int`, `preempt`, `small_int` (Rocky 8) | Phoebe stacks `2023a`–`2026a` + `system` (default `MODULEPATH`), legacy `/sw/phoebe/*` |
| Phoebe `rocky10` GPU nodes (Rocky 10) | **none by default** → EESSI, NVIDIA HPC SDK, `/usr/local/cuda`, own Python envs, Apptainer |
| Koios: login and all nodes (Rocky 9) | Koios tree `c9` (default `MODULEPATH`); EESSI; own installs — see [Koios](#koios) |

Docs: https://hpc.ceico.cz/software/modules/, https://hpc.ceico.cz/software/eessi/

## Phoebe Lmod stacks (EasyBuild, on CVMFS)

| Stack | Path | Toolchain |
|---|---|---|
| `2026a` | `/cvmfs/2026a.phoebe.lan` | `foss/2026.1` (GCC 15.2), `lfoss/2026.1` (LLVM) |
| `2025a` | `/cvmfs/2025a.phoebe.lan` | `foss/2025a` (GCC 14.2) |
| `2024a` | `/cvmfs/2024a.phoebe.lan` | `foss/2024a` (GCC 13.3, OpenMPI 5.0.3, FlexiBLAS/OpenBLAS, FFTW, ScaLAPACK) |
| `2023a` | `/cvmfs/2023a.phoebe.lan` | `foss/2023a` (GCC 12.3) |
| `system` | `/cvmfs/system.phoebe.lan` | toolchain-free: `CUDA` (Rocky 8 nodes only), `Miniforge3`, `Mathematica`, `MATLAB`, `Julia`, `VTune`, … |
| legacy | `/sw/phoebe/2022a`, `2022b`, `standalone` | old `foss/2022a` etc. — only for existing workflows |

Rules:
- Use the newest stack that has everything needed; never mix stacks (e.g. `GCCcore-13.3.0`
  modules belong to 2024a, `GCCcore-14.2.0` to 2025a, `GCCcore-15.2.0` to 2026a).
- **Dependencies are hidden modules** (`OpenMPI`, `GCC`, `OpenBLAS`, `FFTW`… show as
  `.name` and `module spider OpenMPI` finds nothing). Load the toolchain instead:
  `module load foss/2024a` gives GCC + OpenMPI + FlexiBLAS + FFTW + ScaLAPACK.
- Find things: `module spider NAME` (all versions), `module spider NAME/VERSION` (how to load),
  `module -t avail 2>&1 | grep -i NAME`. Module names are case-sensitive (`Python`, `SciPy-bundle`).
- Notable modules (check live): `Python` 3.11–3.14, `SciPy-bundle`, `matplotlib`, `mpi4py`,
  `IPython`, `JupyterLab`, `HDF5`, `PETSc`, `GSL`, `CFITSIO`, `HEALPix`, `Julia`, `Rust`, `Go`,
  `CMake`, `LLVM`/`Clang`, `NVHPC`, `Valgrind`, `Miniforge3`, `Mathematica`, `MATLAB`.
- Collections: `module save NAME` / `module restore NAME` (stored in `~/.config/lmod`).
- Always `module purge` at the start of job scripts, then load explicit versions.

Missing software: first `module spider`, then EESSI (works on CPU nodes too), then a user
install (pip/uv/conda/Spack/own build in `~` or `/mnt/proj`). Users can also ask the admin
to add an EasyBuild module.

## EESSI (`/cvmfs/software.eessi.io`)

The module stack for the Phoebe GPU nodes; also usable on the Phoebe CPU nodes and on Koios
(there it selects `x86_64/intel/skylake_avx512`).

```bash
# replaces Lmod setup, purges loaded modules (simplest; use in GPU jobs)
source /cvmfs/software.eessi.io/versions/2025.06/init/lmod/bash
# or: keep already loaded modules (e.g. NVHPC) and add EESSI
module use /cvmfs/software.eessi.io/init/modules
module load EESSI/2025.06
```

| Version | Toolchains | GPU modules |
|---|---|---|
| `2026.06` | `foss/2026.1` (GCC 15.2) | `CUDA/13.3.0`, `cuDNN/9.23.0.39-CUDA-13.3.0` |
| `2025.06` | `foss/2024a`–`foss/2025b` | `CUDA/12.6.0`, `12.8.0`, `12.9.1`; cuDNN 9.x; GPU builds of GROMACS, ESPResSo, Siesta, NCCL, ollama, … |
| `2023.06` | `foss/2022b`–`foss/2023b` | `CUDA/12.1.1`, `12.4.0`; cuDNN 8.9; GPU builds of GROMACS, LAMMPS, LightGBM, … |

- Autodetects `x86_64/amd/zen3` and `accel/nvidia/cc80` (A100).
- EESSI `CUDA`/`cuDNN` modules work only on the GPU nodes.
- EESSI modules **don't set `LD_LIBRARY_PATH`**: link own code with an RPATH, e.g.
  `nvcc … -lcudnn -Xlinker --disable-new-dtags -Xlinker -rpath=$EBROOTCUDNN/lib:$EBROOTCUDA/lib64`.
- Saved Lmod collections from Phoebe stacks don't work under EESSI (harmless warning).
- Catalogue: https://www.eessi.io/docs/available_software/overview/

## GPU-node native tools

- CUDA 13.4 toolkit in `/usr/local/cuda` (`export PATH=/usr/local/cuda/bin:$PATH`).
- NVIDIA HPC SDK (nvc/nvc++/nvfortran, HPC-X MPI):
  `module use /opt/nvidia/hpc_sdk/modulefiles; module load nvhpc-hpcx-cuda13`.
- `nsys` on PATH; `ncu`, `compute-sanitizer`, `cuda-gdb` in `/usr/local/cuda/bin`.

## Python

Pick one approach and stick to it per project.

1. **Module Python + venv** (CPU nodes; simplest for pure pip packages):
   ```bash
   module purge; module load Python/3.12.3-GCCcore-13.3.0 SciPy-bundle/2024.05-gfbf-2024a
   python -m venv --system-site-packages ~/venvs/<name>
   source ~/venvs/<name>/bin/activate; pip install -r requirements.txt
   ```
   A venv built with module Python only works with that same module loaded, and only on
   Rocky 8 nodes.
2. **uv** (fast, any Python version, works on GPU nodes too): install once with
   `pip install --user uv` (or the standalone installer), then
   `uv venv --python 3.12 ~/venvs/<name>; uv pip install --python ~/venvs/<name> torch …`.
   uv-managed Pythons are self-contained, so one venv can serve both Rocky 8 and 10 for
   pure-Python + wheels. Docs: https://hpc.ceico.cz/software/python-uv/
3. **conda / mamba** (non-Python deps, R, bioinformatics, specific CUDA libs):
   ```bash
   module load Miniforge3          # 24.7.1-2, 25.3.1-0, 26.3.2-3; system stack, Rocky 8 nodes
   source "${EBROOTMINIFORGE3}/etc/profile.d/conda.sh"
   conda create -n <name> -c conda-forge python=3.12 numpy …
   conda activate <name>
   ```
   Envs go to `~/.conda/envs` (shared project envs: `--prefix /mnt/proj/pNNN_x/envs/<name>`).
   On GPU nodes `Miniforge3` module is not available — call the env's binaries directly
   (`~/.conda/envs/<name>/bin/python`) or `source <miniforge-install>/etc/profile.d/conda.sh`
   from a user-installed Miniforge in `~`. Docs: https://hpc.ceico.cz/software/conda/
4. PyTorch, TensorFlow, JAX, CuPy are **not** modules: pip/uv wheels (bundle CUDA) — see
   [gpu.md](gpu.md); or the Apptainer images below.

Create environments on the login node (I/O-bound, fine) or in a `cpu_int` job if the build is heavy.

## Containers: Apptainer

- `apptainer` (and `singularity`) in `/usr/bin` on the login and compute nodes. No Docker.
- Ready images on CVMFS `/cvmfs/apptainer.phoebe.lan/`:
  - `nvcr.io/nvidia/pytorch/26.05-py3/pytorch_26.05-py3.sif` — NGC PyTorch (`latest` symlink dir too)
  - `nvcr.io/nvidia/cuda-dl-base/25.02-cuda12.8-devel-ubuntu24.04/…sif`
  - `tensorflow_apptainer/tensorflow_2.18.0-gpu-jupyter.sif`
  - `colab/colab-cpu.sif`, `colab/colab-gpu.sif`
  - `wolfram_engine_apptainer/wolfram14-2-0_rocky8.sif`
  List with `find /cvmfs/apptainer.phoebe.lan -name '*.sif'`.
- Own images: `apptainer pull docker://image:tag` (into `~/containers` or `/mnt/proj`; set
  `APPTAINER_CACHEDIR` to avoid filling `~/.apptainer`).
- GPU: `apptainer exec --nv image.sif python train.py`. Bind extra paths with `-B /mnt/proj`.
  `$HOME` and the current directory are bound by default.

## Koios

Koios (Rocky 9) has its own, smaller tree `/cvmfs/c9.phoebe.lan` and none of the Phoebe stacks.

| Kind | Modules (check with `module -t avail`) |
|---|---|
| Toolchains | `foss/2022a`, `foss/2023a`, `foss/2024a`, `foss/2025a` (OpenMPI etc. hidden, as on Phoebe) |
| Python | `Python/3.10.4-GCCcore-11.3.0-bare`, `3.11.3-GCCcore-12.3.0`, `3.12.3-GCCcore-13.3.0`, `3.13.1-GCCcore-14.2.0` — no `SciPy-bundle` module: pip-install NumPy/SciPy into a venv |
| Libraries | `HDF5` (`gompi-2022a`, `2023a`, `2025a`), `GSL`, `CFITSIO`, `HEALPix`, `PFFT`, `Szip` |
| Tools | `Clang`, `Rust`, `VTune` |

- No `system` stack: **no Miniforge3, CUDA, Mathematica or MATLAB modules**, and no
  `/cvmfs/apptainer.phoebe.lan` images.
- conda: install Miniforge into the home directory once, then source it in every job
  (https://hpc.ceico.cz/software/conda/#on-koios):
  ```bash
  wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
  bash Miniforge3-Linux-x86_64.sh -b -p $HOME/miniforge3
  source $HOME/miniforge3/etc/profile.d/conda.sh     # instead of the Phoebe module lines
  ```
- uv works the same as on Phoebe (install into `~/.local/bin`).
- EESSI: `source /cvmfs/software.eessi.io/versions/2025.06/init/lmod/bash` gives far more
  software (e.g. `SciPy-bundle`, `GROMACS`, `LAMMPS`) built for Skylake.
- Apptainer is installed; pull images yourself (`apptainer pull docker://…`).
- `/usr/bin/python3` is 3.9; don't build environments on it.
- Anything compiled or any venv made with Phoebe modules won't work on Koios and vice versa
  (different OS and module trees); rebuild on the cluster where it runs.

## Licensed applications (Phoebe `system` stack)

- Mathematica: `module load Mathematica/14.1.0`; batch: `math -run < script.m` or
  `wolframscript -file script.wls`; licence server `license.ceico.cz` (limited seats; check
  with the admin before running many parallel kernels). https://hpc.ceico.cz/software/mathematica/
- MATLAB: `module spider MATLAB`; batch: `matlab -batch "myscript"`.

## Other CVMFS repositories

HEP software is mounted on both clusters: `/cvmfs/sft.cern.ch` (LCG views), `atlas.cern.ch`, `alice.cern.ch`,
`dune.opensciencegrid.org`, `oasis.opensciencegrid.org`, `farm.particle.cz`, … e.g.
`source /cvmfs/sft.cern.ch/lcg/views/LCG_<ver>/x86_64-el8-gcc13-opt/setup.sh` on Rocky 8 nodes
(`el9`/compatible builds may be needed on Rocky 10 — test first).
