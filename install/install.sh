#!/bin/bash

# Author: Nicolas Spring


#######################################################################
# HARD CODED VARIABLES
#######################################################################


script_path="$( cd "$(dirname "$0")" >/dev/null 2>&1 || exit 1; pwd -P )"
repo_base="$script_path/.."

CUDA_VERSION=100


#######################################################################
# INSTALLING PACKAGES
#######################################################################

tools="$repo_base/tools"
mkdir -p "$tools"

sockeye="$tools/sockeye"
fairseq="$tools/fairseq"
mosesdecoder="$tools/mosesdecoder"
subword_nmt="$tools/subword-nmt"

if [[ ! -d "$sockeye" ]]; then
    git clone git@github.com:awslabs/sockeye.git "$sockeye"
fi
if [[ ! -d "$fairseq" ]]; then
    git clone git@github.com:pytorch/fairseq.git "$fairseq"
fi
if [[ ! -d "$mosesdecoder" ]]; then
    git clone git@github.com:moses-smt/mosesdecoder.git "$mosesdecoder"
fi
if [[ ! -d "$subword_nmt" ]]; then
    git clone git@github.com:rsennrich/subword-nmt.git "$subword_nmt"
fi

pip install matplotlib mxboard seaborn nltk scipy methodtools requests sacremoses

# switching to sockeye 2.3.8
git -C "$sockeye" checkout b6d8d356b3d2b626a12cde767b2d995fadbb9751

pip install \
    --no-deps \
    -r "$sockeye/requirements/requirements.gpu-cu${CUDA_VERSION}.txt" \
    "$sockeye"
