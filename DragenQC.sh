#!/bin/bash
set -eo pipefail

#Usage: bash /data/pipelines/DragenQC/DragenQC-0.0.1/DragenQC.sh /mnt/novaseq/191010_D00501_0366_BH5JWHBCX3/

#------------------------#
# Define Input Variables # 
#------------------------#

version="1.0.0"

# run directory location
sourceDir=$1

echo "$sourceDir"

# Illumina run directory name 
seqId=$(basename "$sourceDir")

# instrument name
instrument=$(echo $sourceDir | cut -d"/" -f2) 

# define base path of local NVMe outputs
fastqDirTemp=/staging/data/fastq
resultsDirTemp=/staging/data/results

# create temp directories in staging
mkdir -p $fastqDirTemp
mkdir -p $resultsDirTemp

#-----------------#
# Extract Quality #
#-----------------#

# collect interop data
summary=$(/data/apps/interop-distros/InterOp-1.0.25-Linux-GNU-4.8.2/bin/summary --level=3 --csv=1 "$sourceDir")

# extract fields
yieldGb=$(echo "$summary" | grep ^Total | cut -d, -f2)
q30Pct=$(echo "$summary" | grep ^Total | cut -d, -f7)
avgDensity=$(echo "$summary" | grep -A999 "^Level" | grep ^[[:space:]]*[0-9] | awk -F',| ' '{print $1"\t"$4}' | sort | uniq | awk -F'\t' '{total += $2; count++} END {print total/count}')
avgPf=$(echo "$summary" | grep -A999 "^Level" |grep ^[[:space:]]*[0-9] | awk -F',| ' '{print $1"\t"$7}' | sort | uniq | awk -F'\t' '{total += $2; count++} END {print total/count}')
totalReads=$(echo "$summary" | grep -A999 "^Level" | grep ^[[:space:]]*[0-9] | awk -F',| ' '{print $1"\t"$19}' | sort | uniq | awk -F'\t' '{total += $2} END {print total}')

#----------------------#
# Generate FASTQ Files #
#----------------------#

echo "Staring Demultiplex"

# convert BCLs to FASTQ using DRAGEN
dragen \
    --bcl-conversion-only true \
    --bcl-input-directory "$sourceDir" \
    --output-directory $fastqDirTemp/$seqId 

# copy files to keep to long-term storage
fastqDirTempRun="$fastqDirTemp"/"$seqId"/
resultsDirTempRun="$resultsDirTemp"/"$seqId"/


cd $fastqDirTempRun
cp "$sourceDir"/SampleSheet.csv .
cp "$sourceDir"/?unParameters.xml RunParameters.xml
cp "$sourceDir"/RunInfo.xml .
cp -R "$sourceDir"/InterOp .

# print metrics headers to file
if [ -e "$seqId"_metrics.txt ]; then
    rm "$seqId"_metrics.txt
fi

# print metrics to file
echo -e "Run\tTotalGb\tQ30\tAvgDensity\tAvgPF\tTotalMReads" > "$seqId"_metrics.txt
echo -e "$(basename $sourceDir)\t$yieldGb\t$q30Pct\t$avgDensity\t$avgPf\t$totalReads" >> "$seqId"_metrics.txt


#---------------------#
# Make Variable Files #
#---------------------#

echo "making variables files"

java -jar /data/apps/MakeVariableFiles/MakeVariableFiles-2.1.0.jar \
    SampleSheet.csv \
    RunParameters.xml

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

has_pipeline=false

# trigger pipeline if defined in variables file
for sampleDir in ./Data/*/*;do

    # reset variables if defined
    unset sampleId seqId worklistId pipelineVersion pipelineName panel owner workflow

    cd $sampleDir
    . *.variables

    if [[ $pipelineName =~ "Dragen" ]]; then

        echo "$sampleId --> running pipeline: $pipelineName-$pipelineVersion"
        # run pipeline save data to /staging/data/results/
        bash /data/pipelines/$pipelineName/"$pipelineName"-"$pipelineVersion"/"$pipelineName".sh "$sampleDir"
        
        has_pipeline=true

 
    else
        echo "$sampleId --> DEMULTIPLEX ONLY"
        touch "$sampleDir"/no_dragen_pipeline_initiated.txt
        



    fi

    cd $fastqDirTempRun

done


# all DRAGEN analyses finished

# move FASTQ and delete from staging
rsync -azP /staging/data/fastq/"$seqId" /mnt/novaseq-archive-fastq/"$seqid"
rm -r /staging/data/fastq/"$seqId"



# move results and delete from staging - only execute if we have a pipeline so results folder has been created
if [ "$has_pipeline" = true ] ; then

    rsync -azP /staging/data/results/"$seqId" /mnt/novaseq-results/"$seqid"
    rm -r /staging/data/results/"$seqId"

fi


# mark as complete
for i in /mnt/novaseq-results/"$seqId"/*; do

touch "$i"/dragen_complete.txt 

done

# write dragen-complete file to raw (flag for moving by host cron)
touch $sourceDir/dragen-complete
