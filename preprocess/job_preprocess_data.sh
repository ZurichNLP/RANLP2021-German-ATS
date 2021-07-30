#!/bin/bash
#SBATCH --time=00:30:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --partition=generic

# Author: Nicolas Spring


#######################################################################
# HANDLING COMMAND LINE ARGUMENTS
#######################################################################


input_dirs=()
repo_base=''

# arguments that are not supported
print_usage() {
    script=$(basename "$0")
    >&2 echo "Usage: "
    >&2 echo "$script [-i input_dir] [-r repo_base]"
}

# missing arguments that are required
print_missing_arg() {
    missing_arg=$1
    message=$2
    >&2 echo "Missing: $missing_arg"
    >&2 echo "Please provide: $message"
}

# argument parser
while getopts 'i:r:' flag; do
  case "${flag}" in
    i) input_dirs+=("$OPTARG") ;;
    r) repo_base="$OPTARG" ;;
    *) print_usage
       exit 1 ;;
  esac
done

# checking required arguments
if [[ -z $input_dirs ]]; then
    print_missing_arg "[-i input_dir]" "Input directory"
    exit 1
fi

# checking required arguments
if [[ -z $repo_base ]]; then
    print_missing_arg "[-r repo_base]" "Base directory of the repository"
    exit 1
fi


#######################################################################
# HARD CODED VARIABLES
#######################################################################


bpe_tokens=20000

script_path="$repo_base/preprocess/"

moses_scripts="$repo_base/tools/mosesdecoder/scripts"
subword_nmt="$repo_base/tools/subword-nmt/subword_nmt"
fairseq_bt_examples="$repo_base/tools/fairseq/examples/backtranslation"


#######################################################################
# DEFINING PREPROCESSING FUNCTIONS
#######################################################################


get_seeded_random()
{
  seed="$1"
  openssl enc -aes-256-ctr -pass pass:"$seed" -nosalt \
    </dev/zero 2>/dev/null
}


extract_raw_text() {
    params=("$@")
    input_dirs="${params[@]::${#params[@]}-1}"
    raw_dir="${params[-1]}"

    for input_dir in $input_dirs; do
        for direction in "a2-or" "b1-or"; do
            src=${direction##*-}
            trg=${direction%%-*}
            out_direction="$src-$trg"
            mkdir -p "$raw_dir/$out_direction"
            src_out="$raw_dir/$out_direction/$out_direction.$src"
            trg_out="$raw_dir/$out_direction/$out_direction.$trg"
            while IFS= read -r -d '' directory; do
                while IFS= read -r -d '' file; do
                    document=${file%_??.simpde}
                    cat "$document.de" >> "$src_out"
                    cat "$file" >> "$trg_out"
                done < <(find "$directory" -type f -iname "*.simpde" -print0)
            done < <(find "$input_dir" -type d -iname "$direction" -print0)
        done
    done
}


deduplicate_text() {
    raw_dir=$1
    dedup_dir=$2
    fairseq_bt_examples=$3
    moses_scripts=$4

    cleaning_script="$moses_scripts/training/clean-corpus-n.perl"

    for direction in "or-a2" "or-b1"; do
        mkdir -p "$dedup_dir/$direction" "/var/tmp/$direction"
        src=${direction%%-*}
        trg=${direction##*-}
        # ratio of 10 is basically there to remove empty segments
        perl "$cleaning_script" -ratio 10 "$raw_dir/$direction/$direction" "$src" "$trg" "/var/tmp/$direction/$direction" 1 250
        paste -d $'\001' "/var/tmp/$direction/$direction.$src" "/var/tmp/$direction/$direction.$trg" \
        > "/var/tmp/dedup.raw.pasted"

        dedup_prefix="$dedup_dir/$direction/$direction"
        python "$fairseq_bt_examples/deduplicate_lines.py" "/var/tmp/dedup.raw.pasted" \
        | awk -v dedup="$dedup_prefix" -v src="$src" -v trg="$trg" \
            -F $'\001' \
            '{print $1 > dedup"."src; print $2 > dedup"."trg}'
    done
}


split_train_dev_test() {
    dedup_dir=$1
    split_dir=$2

    for direction in "or-a2" "or-b1"; do
        mkdir -p "$split_dir/$direction"
        src=${direction%%-*}
        trg=${direction##*-}
        split_prefix="$split_dir/$direction/shuf.$direction"
        paste -d $'\001' "$dedup_dir/$direction/$direction.$src" "$dedup_dir/$direction/$direction.$trg" \
        | shuf --random-source=<(get_seeded_random 42) \
        | awk -v splitp="$split_prefix" -v src="$src" -v trg="$trg" \
            -F $'\001' \
            '{print $1 > splitp"."src; print $2 > splitp"."trg}'
        for lang in "$src" "$trg"; do
            cat "$split_dir/$direction/shuf.$direction.$lang" \
            | head -n 1000 \
            > "/var/tmp/devtest.$direction.txt"

            cat "$split_dir/$direction/shuf.$direction.$lang" \
            | tail -n +1001 \
            > "$split_dir/$direction/train.$direction.$lang"

            cat "/var/tmp/devtest.$direction.txt" \
            | head -n 500 \
            > "$split_dir/$direction/dev.$direction.$lang"

            cat "/var/tmp/devtest.$direction.txt" \
            | tail -n +501 \
            > "$split_dir/$direction/test.$direction.$lang"
        done
    done
}


tokenize() {
    split_dir=$1
    tok_dir=$2
    moses_scripts=$3

    for direction in "or-a2" "or-b1"; do
        mkdir -p "$tok_dir/$direction"
        src=${direction%%-*}
        trg=${direction##*-}
        for lang in "$src" "$trg"; do
            for set in "train" "dev" "test"; do
                cat "$split_dir/$direction/$set.$direction.$lang" \
                | perl "$moses_scripts/tokenizer/normalize-punctuation.perl" "de" \
                | perl "$moses_scripts/tokenizer/remove-non-printing-char.perl" \
                | perl "$moses_scripts/tokenizer/tokenizer.perl" -threads 1 -a -l "de" \
                > "$tok_dir/$direction/$set.$direction.tok.$lang"
            done
        done
    done
}


learn_bpe() {
    tok_dir=$1
    bpe_dir=$2
    subword_nmt=$3

    bpe_train="/var/tmp/bpe_train.all"
    cat "$tok_dir"/*/train.* > "$bpe_train"
    python "$subword_nmt/learn_bpe.py" -s "$bpe_tokens" < "$bpe_train" > "$bpe_dir/bpe_code"
}


apply_bpe() {
    tok_dir=$1
    bpe_dir=$2
    subword_nmt=$3

    for direction in "or-a2" "or-b1"; do
        mkdir -p "$bpe_dir/$direction"
        src=${direction%%-*}
        trg=${direction##*-}
        for lang in "$src" "$trg"; do
            for set in "train" "dev" "test"; do
                cat "$tok_dir/$direction/$set.$direction.tok.$lang" \
                | python "$subword_nmt/apply_bpe.py" -c "$bpe_dir/bpe_code" \
                > "$bpe_dir/$direction/$set.$direction.bpe.$lang"
            done
        done
    done
}


combine_and_shuffle() {
    input_dir=$1
    prev_step_description=$2
    combined_dir=$3

    mkdir -p "$combined_dir/tmp"
    true > "$combined_dir/tmp/train.de-simpde.combined.de"
    true > "$combined_dir/tmp/train.de-simpde.combined.simpde"
    true > "$combined_dir/tmp/dev.de-simpde.combined.de"
    true > "$combined_dir/tmp/dev.de-simpde.combined.simpde"
    true > "$combined_dir/tmp/test.de-simpde.combined.de"
    true > "$combined_dir/tmp/test.de-simpde.combined.simpde"
    for direction in "or-a2" "or-b1"; do
        mkdir -p "$combined_dir/$direction"
        src=${direction%%-*}
        trg=${direction##*-}
        for lang in "$src" "$trg"; do
            for set in "dev" "test"; do
                cp "$input_dir/$direction/$set.$direction.$prev_step_description.$lang" \
                    "$combined_dir/$direction/$set.$direction.$lang"
                if [[ "$lang" == "$trg" ]]; then
                    out_tag="simpde"
                else
                    out_tag="de"
                fi
                cat "$input_dir/$direction/$set.$direction.$prev_step_description.$lang" \
                >> "$combined_dir/tmp/$set.de-simpde.combined.$out_tag"
            done
        done
        cat "$input_dir/$direction/train.$direction.$prev_step_description.$src" \
        >> "$combined_dir/tmp/train.de-simpde.combined.de"
        cat "$input_dir/$direction/train.$direction.$prev_step_description.$trg" \
        >> "$combined_dir/tmp/train.de-simpde.combined.simpde"
    done
    for set in "train" "dev" "test"; do
        paste -d $'\001' "$combined_dir/tmp/$set.de-simpde.combined.de" "$combined_dir/tmp/$set.de-simpde.combined.simpde" \
        | shuf --random-source=<(get_seeded_random 42) \
        | awk -v comb="$combined_dir/" -v src="de" -v trg="simpde" -v set="$set" \
            -F $'\001' \
            '{print $1 > comb""set".de-simpde.combined."src; print $2 > comb""set".de-simpde.combined."trg}'
    done
}


#######################################################################
# CREATING OUTPUT DIRECTORIES
#######################################################################


raw_dir="$script_path/../data/raw"
dedup_dir="$script_path/../data/deduplicated"
split_dir="$script_path/../data/splits"
tok_dir="$script_path/../data/tokenized"
bpe_dir="$script_path/../data/bpe"
labeled_dir="$script_path/../data/labeled"
combined_dir="$script_path/../data/combined"
rm -rf "$raw_dir"
mkdir -p "$raw_dir" "$dedup_dir" "$split_dir" "$tok_dir" "$bpe_dir" "$labeled_dir" "$combined_dir"


#######################################################################
# EXTRACTING RAW TEXT
#######################################################################


>&2 echo "extracting raw text..."
extract_raw_text "${input_dirs[@]}" "$raw_dir"


#######################################################################
# DEDUPLICATING TEXT
#######################################################################

>&2 echo "deduplicating..."
deduplicate_text "$raw_dir" "$dedup_dir" "$fairseq_bt_examples" "$moses_scripts"


#######################################################################
# SPLITTING INTO TRAIN, DEV AND TEST
#######################################################################


>&2 echo "creating train, dev and test..."
split_train_dev_test "$dedup_dir" "$split_dir"


#######################################################################
# PREPROCESSING TEXT
#######################################################################

>&2 echo "tokenizing..."
tokenize "$split_dir" "$tok_dir" "$moses_scripts"

>&2 echo "learning BPE..."
learn_bpe "$tok_dir" "$bpe_dir" "$subword_nmt"

>&2 echo "applying BPE..."
apply_bpe "$tok_dir" "$bpe_dir" "$subword_nmt"


#######################################################################
# LABELING SOURCE SEGMENTS WITH TARGET LEVEL
#######################################################################


>&2 echo "labeling segments..."
for direction in "or-a2" "or-b1"; do
    mkdir -p "$labeled_dir/$direction"
    src=${direction%%-*}
    trg=${direction##*-}
    for set in "train" "dev" "test"; do
        cat "$bpe_dir/$direction/$set.$direction.bpe.$src" \
        | sed -e "s/^/<$trg> /" \
        > "$labeled_dir/$direction/$set.$direction.labeled.$src"
        cp "$bpe_dir/$direction/$set.$direction.bpe.$trg" "$labeled_dir/$direction/$set.$direction.labeled.$trg"
    done
done


#######################################################################
# COMBINING AND SHUFFLING THE TRAINING DATA
#######################################################################


>&2 echo "combining training data..."
combine_and_shuffle "$labeled_dir" "labeled" "$combined_dir"
