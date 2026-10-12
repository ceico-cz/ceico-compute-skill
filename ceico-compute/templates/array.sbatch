#!/bin/bash
#SBATCH --job-name=<JOBNAME>
#SBATCH --partition=cpu              # or preempt for restartable tasks
#SBATCH --time=<HH:MM:SS>            # per array task
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=<MEM>
#SBATCH --array=1-<N>%<MAXRUNNING>   # e.g. 1-200%50
#SBATCH --output=logs/%x-%A_%a.out   # create logs/ before sbatch
set -euo pipefail

module purge
module load <MODULES>

# one line of params.txt per task, e.g. "--seed 7 --alpha 0.1"
PARAMS=$(sed -n "${SLURM_ARRAY_TASK_ID}p" params.txt)
echo "task $SLURM_ARRAY_TASK_ID on $(hostname): $PARAMS"
<COMMAND> $PARAMS --out results/task_${SLURM_ARRAY_TASK_ID}   # e.g. python run.py $PARAMS
