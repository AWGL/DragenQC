# DragenQC

## Introduction

Script to demultiplex raw sequence data and initiate downstream pipelines on the Dragen server.

The script has the following functions:

1) Demultiplex data on the Dragen.

2) Initiate downstream pipelines on the Dragen.

3) For samples which should not be processed on the Dragen transfer the FASTQ files to another location for processing.


## Requirements

- dragen Version 07.021.408.3.4.12 (Software Release v3.4+)
- slurm workload manager

## Run

```
sbatch --export=sourceDir=/data/archive/novaseq/BCL/200626_A00748_0033_AHL752DRXX DragenQC.sh

```
