#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=cpu              # same name on Phoebe and Koios
#SBATCH --time=<HH:MM:SS>
#SBATCH --nodes=<NNODES>             # e.g. 2
#SBATCH --ntasks-per-node=<NTASKS>   # MPI ranks per node: Phoebe up to 128 (64 = 1 per core), Koios up to 64 (32)
#SBATCH --cpus-per-task=1            # >1 for hybrid MPI+OpenMP
#SBATCH --mem-per-cpu=<MEM>          # e.g. 2G; or --exclusive + --mem=0 for whole nodes
#SBATCH --output=%x-%j.out
set -euo pipefail

module purge
# Koios (EESSI only): replace the line above with this one; EESSI's init reads unset variables
#   set +u; source /cvmfs/software.eessi.io/versions/2025.06/init/lmod/bash; set -u
module load foss/2024a <MODULES>     # same toolchain the program was built with

# Pure MPI: one thread per rank. For hybrid code, match the allocated CPUs.
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OPENBLAS_NUM_THREADS=1        # avoid incidental BLAS threads; tune if the app needs them
# Koios: for one rank per physical core, use <=32 ranks/node and add
#   #SBATCH --threads-per-core=1
# to the header. Start with default CPU binding; tune only after measuring.
export SLURM_UNBUFFEREDIO=1

echo "job $SLURM_JOB_ID: $SLURM_NTASKS ranks on $SLURM_JOB_NODELIST, started $(date -Is)"
# Plain srun uses the PMIx default (Koios: pmix_v3); --mpi=pmix can select a different alias.
# EESSI OpenMPI selects UCX/IB automatically on Koios CPU nodes: no transport overrides needed.
# See references/jobs.md for transport checks. No hostfile is needed.
srun <COMMAND>                       # e.g. ./my_mpi_app input.dat
echo "finished $(date -Is)"
