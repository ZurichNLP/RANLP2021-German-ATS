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

module load generic
sbatch -D "$repo_base" \
    -o "$script_path/../logs/%j-preprocessing.out" \
    "$script_path/job_preprocess_data.sh" \
        -i "$repo_base/data/aligned/" \
        -r "$repo_base"
