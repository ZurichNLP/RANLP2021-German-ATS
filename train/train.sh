#!/bin/bash

# Author: Nicolas Spring


#######################################################################
# HARD CODED VARIABLES
#######################################################################


script_path="$( cd "$(dirname "$0")" >/dev/null 2>&1 || exit 1; pwd -P )"
repo_base="$script_path/.."


#######################################################################
# QUEUEING JOBS
#######################################################################

mkdir -p "$script_path/../logs"

module load volta cuda/10.0
sbatch -D "$repo_base" \
    -o "$script_path/../logs/%j-training.out" \
    "$script_path/job_train_model.sh" \
        -r "$repo_base"
