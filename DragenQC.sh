#!/bin/bash

#SBATCH --time=72:00:00
#SBATCH --output=DragenQC-%N-%j.output
#SBATCH --error=DragenQC-%N-%j.error
#SBATCH --partition=dragen2
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --threads-per-core=2
#SBATCH --nodes=1

set -euo pipefail

# set max processes and open files as these differ between wren and head node
ulimit -S -u 16384
ulimit -S -n 65535

# Description:
# Author: Joseph Halstead / Chris Medway
# Usage: bash DragenQc.sh /raw/seqid/

#------------------------#
# Define Input Variables # 
#------------------------#


version="3.0.0"
variables_script="/data/diagnostics/scripts/dragen_make_variables.py"
pipeline_dir="/data/diagnostics/pipelines/"
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
/opt/edico/bin/dragen --bcl-conversion-only true --bcl-input-directory "$sourceDir" --output-directory $fastqDirTempRun # --first-tile-only true


#---------------------#
# Make Variable Files #
#---------------------#

echo "making variables files"

cd  $fastqDirTempRun

python $variables_script  --samplesheet "$sourceDir"/SampleSheet.csv --outputdir ./ --seqid $seqId

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
	cp "$pipeline_dir"/$pipelineName/"$pipelineName"-"$pipelineVersion"/"$pipelineName".sh  "$resultsDirTempRun"/"$panel"/"$sampleId"
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

# do separate loop for bashing pipelines as the scripts need to count number of directories correctly
for sampleDir in "$fastqDirTempRun"/Data/*/*;do

    echo $sampleDir - executing code
    # reset variables if defined
    unset sampleId seqId worklistId pipelineVersion pipelineName panel owner workflow
   
    cd $sampleDir
    . *.variables

    cd  "$resultsDirTempRun"/"$panel"/"$sampleId"

    if [[ $pipelineName =~ "Dragen" ]]; then
          echo "Running job $pipelineName for $sampleId"
          bash  "$pipelineName".sh  > "$seqId"-"$sampleId".log 2>&1  

    else
          echo "$sampleId --> DEMULTIPLEX ONLY"
                                    
    fi

done







