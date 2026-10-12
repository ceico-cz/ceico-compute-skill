#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=cpu
#SBATCH --time=<HH:MM:SS>
#SBATCH --nodes=<NNODES>             # e.g. 2
#SBATCH --ntasks-per-node=<NTASKS>   # MPI ranks per node: Phoebe up to 128 (64 = 1 per core), Koios up to 64 (32)
#SBATCH --cpus-per-task=1            # >1 for hybrid MPI+OpenMP
#SBATCH --mem-per-cpu=<MEM>          # e.g. 2G; or --exclusive + --mem=0 for whole nodes
#SBATCH --output=%x-%j.out
set -euo pipefail

module purge
module load foss/2024a <MODULES>     # same toolchain the program was built with

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export SLURM_UNBUFFEREDIO=1

echo "job $SLURM_JOB_ID: $SLURM_NTASKS ranks on $SLURM_JOB_NODELIST, started $(date -Is)"
# srun starts the ranks via PMIx (cluster default); do not use mpirun with a hostfile
srun <COMMAND>                       # e.g. ./my_mpi_app input.dat
echo "finished $(date -Is)"
