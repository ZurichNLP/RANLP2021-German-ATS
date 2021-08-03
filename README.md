# RANLP2021-German-ATS

The code for the RANLP 2021 paper "Exploring German Multi-Level Text Simplification" by Nicolas Spring, Annette Rios and Sarah Ebling.

## Purpose

This repository allows you to reproduce the "APA multi" model from the paper.

## Remarks

- Preprocessing makes use of scripts from [mosesdecoder](https://github.com/moses-smt/mosesdecoder), [subword-nmt](https://github.com/rsennrich/subword-nmt) and [fairseq](https://github.com/pytorch/fairseq).
- The ATS model is trained with [sockeye](https://github.com/awslabs/sockeye).
- [Anaconda](https://www.anaconda.com/) was used to create a virtual python environment.
- These scripts are designed to run with the [slurm workload manager](https://slurm.schedmd.com/documentation.html). Adjustments may be needed to make them run on your system.

## Installing

Download and install the code:

```bash
git clone https://github.com/ZurichNLP/RANLP2021-German-ATS.git
cd RANLP2021-German-ATS/

bash install/create_env.sh

# Activate the virtual environment with the "conda activate" command that is prompted
# conda activate /...

bash install/install.sh
```

Download the data:

```bash
mkdir -p data/aligned
cd data
# Download the ZIP file fromhttps://zenodo.org/record/5148163
unzip APA_sentence-aligned_LHA.zip -d aligned/
cd ..
```

## Running the code

Preprocess the data:

```bash
bash preprocess/preprocess.sh
```

Train the ATS model:

```bash
bash train/train.sh
```

