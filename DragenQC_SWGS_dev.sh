#!/bin/bash

#Use: bash /staging/scripts/DragenQC.sh /data/archive/novaseq/RUN_ID /staging/samplesheets/SampleSheet.csv

set -euo pipefail

#------------------------#
# Define Input Variables #
#------------------------#

sourceDir=$1
sampleSheet=$2

version="3.0.0"
variables_script="/staging/scripts/dragen_make_variables.py"
pipeline_dir="/home/dragen/"
fastq_dir="/Output/fastq/"

echo "$sourceDir"

# Illumina run directory name
seqId=$(basename "$sourceDir")

echo $seqId


# define base path of local NVMe outputs
fastqDirTemp=/staging/data/fastq
resultsDirTemp=/staging/data/results

fastqDirTempRun="$fastqDirTemp"/"$seqId"/
resultsDirTempRun="$resultsDirTemp"/"$seqId"/

# check fastq run directory does not exist
if [ -d $fastqDirTempRun ]; then
    echo "$fastqDirTempRun already exists"
    exit 1
fi

# check results run directory does not exist
if [ -d $resultsDirTempRun ]; then
    echo "$resultsDirTempRun already exists"
    exit 1
fi

#----------------------#
# Generate FASTQ Files #
#----------------------#

echo "Starting Demultiplex"

# convert BCLs to FASTQ using DRAGEN
/opt/edico/bin/dragen --bcl-conversion-only true --bcl-input-directory "$sourceDir" --output-directory $fastqDirTempRun --sample-sheet $sampleSheet


#---------------------#
# Make Variable Files #
#---------------------#

echo "making variables files"

cd  $fastqDirTempRun

python $variables_script  --samplesheet $sampleSheet --outputdir ./ --seqid $seqId

# move FASTQ & variable files into project folders
for variableFile in $(ls *.variables);do

    # reset variables if defined
    unset sampleId seqId worklistId pipelineVersion pipelineName panel owner workflow

    # load variables into local scope
    . "$variableFile"

    # make sample folder
    mkdir -p ./Data/$panel/"$sampleId"
    mv "$variableFile" ./Data/"$panel"/"$sampleId"
    mv "$sampleId"_S*.fastq.gz ./Data/"$panel"/"$sampleId"

done

# create folder structure and set them up ready for execution
for sampleDir in "$fastqDirTempRun"/Data/*/*;do

    # reset variables if defined
    unset sampleId seqId worklistId pipelineVersion pipelineName panel owner workflow

    cd $sampleDir
    . *.variables

    if [[ $pipelineName =~ "Dragen" ]]; then

        echo "$sampleId --> configuring pipeline: $pipelineName-$pipelineVersion"

        # make results dir
       if [ -d "$resultsDirTempRun"/"$panel"/"$sampleId" ]; then
            echo "$resultsDirTempRun/"$panel"/$sampleId already exists"
            exit
        else
            mkdir -p "$resultsDirTempRun"/"$panel"/"$sampleId"
        fi


       # copy over pipeline files
      cp *.variables "$resultsDirTempRun"/"$panel"/"$sampleId"/

        for i in $(ls "$sampleId"_S*.fastq.gz); do
            ln -s "$PWD"/"$i" "$resultsDirTempRun"/"$panel"/"$sampleId"/
        done

    else

        echo "$sampleId --> DEMULTIPLEX ONLY"

        # move fastq data
        if [ -d "$fastq_dir"/"$seqId"/"$panel"/"$sampleId" ]; then
           echo "$fastq_dir/$seqId/$panel/$sampleId already exists - cannot rsync"
           exit 1
        else

           mkdir -p "$fastq_dir"/"$seqId"/"$panel"/"$sampleId"

           rsync -azP --no-links . "$fastq_dir"/"$seqId"/"$panel"/"$sampleId"
           touch "$fastq_dir"/"$seqId"/"$panel"/"$sampleId"/dragen_demultiplex_only.txt
           cd /staging/
           rm -r $sampleDir

        fi



    fi

done

cd /staging/data/results/"$seqId"/"$panel"
bash /staging/scripts/DragenSWGS.sh

