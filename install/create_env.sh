#!/bin/bash

# Author: Nicolas Spring


#######################################################################
# HARD CODED VARIABLES
#######################################################################


script_path="$( cd "$(dirname "$0")" >/dev/null 2>&1 || exit 1; pwd -P )"


#######################################################################
# CREATING A VIRTUAL ENVIRONMENT
#######################################################################

module load generic anaconda3
venv_location="$script_path/venv-sockeye2"

conda create -y --prefix "$venv_location" python=3.9.0 pip
