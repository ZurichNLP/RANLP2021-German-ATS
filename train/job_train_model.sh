#!/bin/bash
#SBATCH --time=72:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --gres=gpu:1
#SBATCH --qos=vesta
#SBATCH --partition=volta

# Author: Nicolas Spring


#######################################################################
# HANDLING COMMAND LINE ARGUMENTS
#######################################################################


repo_base=''

# arguments that are not supported
print_usage() {
    script=$(basename "$0")
    >&2 echo "Usage: "
    >&2 echo "$script [-r repo_base]"
}

# missing arguments that are required
print_missing_arg() {
    missing_arg=$1
    message=$2
    >&2 echo "Missing: $missing_arg"
    >&2 echo "Please provide: $message"
}

# argument parser
while getopts 'r:' flag; do
  case "${flag}" in
    r) repo_base="$OPTARG" ;;
    *) print_usage
       exit 1 ;;
  esac
done

# checking required arguments
if [[ -z $repo_base ]]; then
    print_missing_arg "[-r repo_base]" "Base directory of the repository"
    exit 1
fi


#######################################################################
# HARD CODED VARIABLES
#######################################################################


script_path="$repo_base/train/"


#######################################################################
# TRAINING THE MODEL
#######################################################################

combined_dir="$script_path/../data/combined"
model_dir="$script_path/../model"
lock_dir="$script_path/../lock_dir"

mkdir -p "$model_dir" "$lock_dir"

python -m sockeye.train \
    --source "$combined_dir/train.de-simpde.combined.de" \
    --target "$combined_dir/train.de-simpde.combined.simpde" \
    --validation-source "$combined_dir/dev.de-simpde.combined.de" \
    --validation-target "$combined_dir/dev.de-simpde.combined.simpde" \
    --output "$model_dir" \
    --lock-dir "$lock_dir" \
    --weight-tying-type src_trg_softmax \
    --transformer-feed-forward-num-hidden 2048 \
    --transformer-attention-heads 4 \
    --embed-dropout 0.3 \
    --num-layers 5 \
    --label-smoothing 0.3 \
    --transformer-dropout-act 0 \
    --update-interval 2 \
    --batch-size 2048 \
    --shared-vocab \
    --optimized-metric bleu \
    --keep-last-params 10 \
    --learning-rate-reduce-num-not-improved 4 \
    --max-num-checkpoint-not-improved 10
