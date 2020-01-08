# DragenQC

## Introduction

Script to demultiplex raw sequence data and initiate downstream pipelines on the Dragen server.

Demultiplexes data to:

/staging/data/fastq/$seqid/Data/$panel/$sample

Inititates pipeline if specified in SampleSheet. Checks whether the $pipelineName has 'Dragen' within it. If so we try and initiate a Dragen pipeline. Otherwise we just demultiplex.

## Requirements

dragen Version 07.021.408.3.4.12 (Software Release v3.4)

## Run

```
bash /data/pipelines/DragenQC/DragenQC-0.0.1/DragenQC.sh /mnt/novaseq/191010_D00501_0366_BH5JWHBCX3/

```