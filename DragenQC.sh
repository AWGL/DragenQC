#!/bin/bash
set -eo pipefail

# Description:
# Author: Joseph Halstead / Chris Medway
# Usage: bash DragenQc.sh /raw/seqid/

#------------------------#
# Define Input Variables # 
#------------------------#

version="2.0.1"

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

# copy files to keep to long-term storage
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

echo "Starting Demultiplex"

# convert BCLs to FASTQ using DRAGEN
/opt/edico/bin/dragen --bcl-conversion-only true --bcl-input-directory "$sourceDir" --output-directory $fastqDirTemp/$seqId

# copy files to keep to long-term storage
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

python /data/apps/dragen_make_variables/dragen_make_variables.py  --samplesheet SampleSheet.csv --outputdir ./ --seqid $seqId

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
        if [ -d "$resultsDirTempRun"/$panel/$sampleId ]; then
            echo "$resultsDirTempRun/$panel/$sampleId already exists"
            exit
        else
            mkdir -p "$resultsDirTempRun"/$panel/$sampleId
        fi

        # copy over pipeline files
        cp /data/pipelines/$pipelineName/"$pipelineName"-"$pipelineVersion"/"$pipelineName".sh /staging/data/results/$seqId/$panel/$sampleId/
        cp *.variables "$resultsDirTempRun"/"$panel"/"$sampleId"/

        for i in $(ls "$sampleId"_S*.fastq.gz); do
            ln -s "$PWD"/"$i" "$resultsDirTempRun"/"$panel"/"$sampleId"/ 
        done 
 
    else
        echo "$sampleId --> DEMULTIPLEX ONLY"
        mkdir -p "$resultsDirTempRun"/"$panel"/"$sampleId"/
        touch "$resultsDirTempRun"/"$panel"/"$sampleId"/demultiplex_only
    
    fi

done


# do separate loop for bashing pipelines as the scripts need to count number of directories correctly
for sampleDir in "$fastqDirTempRun"/Data/*/*;do

    echo $sampleDir - executing code
    # reset variables if defined
    unset sampleId seqId worklistId pipelineVersion pipelineName panel owner workflow
   
    cd $sampleDir
    . *.variables

    cd  /staging/data/results/$seqId/$panel/$sampleId/

    if [[ $pipelineName =~ "Dragen" ]]; then
          echo bashing the script /staging/data/results/$seqId/$panel/$sampleId/"$pipelineName".sh
          bash "$pipelineName".sh "$sampleDir" > "$seqId"-"$sampleId".log 2>&1

    else
	   touch "$fastqDirTempRun"/Data/"$panel"/demultiplex_only
           echo "$sampleId --> DEMULTIPLEX ONLY"

    fi



done


# data permissions - need to be 775 so transfer which is in same group as dragen can write
chmod -R 775 $fastqDirTempRun
chmod -R 775 $resultsDirTempRun


# move results data - don't move symlinks fastqs
if [ -d /mnt/novaseq-results/"$seqId" ]; then
    echo "/mnt/novaseq-results/$seqId already exists - cannot rsync"
    exit 1
else

    rsync -azP --no-links /staging/data/results/"$seqId" /mnt/novaseq-results/ > /staging/data/tmp/rsync-"$seqId"-results.log 2>&1
 
    # get md5 sums for source
    find /staging/data/results/"$seqId" -type f | egrep -v "*md5" | xargs md5sum | cut -d" " -f 1 | sort > source.md5

    # get md5 sums for destination

    find /mnt/novaseq-results/"$seqId" -type f | egrep -v "*md5*" | xargs md5sum | cut -d" " -f 1 | sort > destination.md5

    sourcemd5file=$(md5sum source.md5 | cut -d" " -f 1)
    destinationmd5file=$(md5sum destination.md5 | cut -d" " -f 1)

    if [ "$sourcemd5file" = "$destinationmd5file" ]; then
        echo "MD5 sum of source destination matches that of destination"
    else
        echo "MD5 sum of source destination matches does not match that of destination - exiting program "
        exit 1
    fi


fi

# mark results as complete - do this first so post processing can start asap
for i in /mnt/novaseq-results/"$seqId"/*; do
    cp /staging/data/tmp/rsync-"$seqId"-results.log  "$i"/dragen_complete.txt
done

# move fastq data
if [ -d /mnt/novaseq-archive-fastq/"$seqId" ]; then
    echo "/mnt/novaseq-archive-fastq/$seqId already exists - cannot rsync"
    exit 1
else 

    mkdir -p /mnt/novaseq-archive-fastq/"$seqId"

    # only do for demultiplex only data
    for path in $(find "$fastqDirTempRun"/Data/  -maxdepth 2 -mindepth 2 -type f -name "demultiplex_only" -exec dirname '{}' \;); do
	
	echo $path

        panel=$(basename $path)
                 
        rsync -azP $path /mnt/novaseq-archive-fastq/"$seqId"/ > /staging/data/tmp/rsync-"$seqId"-"$panel"-fastq.log 2>&1
        
        cp /staging/data/tmp/rsync-"$seqId"-"$panel"-fastq.log "$path"/dragen_complete.txt
        
        rm  /staging/data/tmp/rsync-"$seqId"-"$panel"-fastq.log

    done

fi

# sometimes being in the directory you delete messes things up so move to home and then delete
cd ~
rm -r /staging/data/fastq/"$seqId"
rm -r /staging/data/results/"$seqId"

# write dragen-complete file to raw (flag for moving by host cron)
touch $sourceDir/dragen-complete
