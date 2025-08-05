#!/bin/sh
set -euo pipefail

# Description: shell script to launch dragen analysis 

version="0.1.0"

raw="/Data-MSA/raw"

dragen_markers="/Data-MSA/raw/dragen_markers"

function processJobs {
	echo "checking for jobs in $1 ..."

	#Find runs that have finished sequencing
	for path in $(find "$1" -maxdepth 2 -mindepth 2 -type f -name "RTAComplete.txt" -exec dirname '{}' \;); do

		instrumentType=$(basename $(dirname "$path"))
		run=$(basename "$path")

		echo "Processing $run on $instrumentType"

		#Skip any that don't need to be processed
		if [ -f "$path"/do_not_process ]; then
			
			echo "Not processing run $run"
		else
			
			#For novaseq, need CopyComplete.txt
			if [[ -f $raw/$instrumentType/$run/CopyComplete.txt && "$instrumentType" = "novaseq" ]] || [[ "$instrumentType" != "novaseq"  ]]; then

				#Only run if we have a SampleSheet
				if [ -f $raw/$instrumentType/$run/SampleSheet.csv ]; then

					#remove spaces from sample sheet - Is this still a thing?
					sed -i 's/ //g' $raw/$instrumentType/$run/SampleSheet.csv

					#Modify RTA complete so it's not kicked off again
					mv $raw/$instrumentType/$run/RTAComplete.txt $raw/$instrumentType/$run/_RTAComplete.txt 

					#Work out if it needs a dragen?
					set +e 
					is_swgs=$(cat "$path"/SampleSheet.csv | grep "SWGS" | wc -l)
					is_dragen=$(cat "$path"/SampleSheet.csv | grep "Dragen" | wc -l)
					is_ctdna=$(cat "$path"/SampleSheet.csv | grep "tso500_ctdna" | wc -l)
					set -e

					#If dragen or swgs, send to dragen1, dragen2 or dragen4 (do we need to do WGS on dragen2/4 and WES on dragen1 - need to test more)
					if [ $is_dragen -gt 0 ]; then

						#Check if the dragen is currently locked by another run, if none free, re-queue for the cron to pick up again
						if [ ! -f "${dragen_markers}/*_dragen1_locked" ]; then

							echo "Running $run on dragen1"
							ssh -i ~/.ssh/id_rsa_dragen dragen@192.168.1.19 "nohup bash /mnt/Data-MSA/diagnostics/pipelines/DragenQC/DragenQC.sh ${path} > /mnt/Data-MSA/raw/logs/${run}.log 2>&1 &"
							touch $dragen_markers/${run}_dragen1_locked

						elif [ ! -f "${dragen_markers}/*_dragen2_locked" ]; then

							echo "Running $run on dragen2"
							# UPDATE WHEN DRAGEN2 IS ONLINE
#							ssh -i ~/.ssh/id_rsa_dragen dragen@192.168.1.19 "nohup bash /mnt/Data-MSA/diagnostics/pipelines/DragenQC/DragenQC.sh ${path} > /mnt/Data-MSA/raw/logs/${run}.log 2>&1 &"
							touch $dragen_markers/${run}_dragen2_locked

						elif [ ! -f "${dragen_markers}/*_dragen4_locked" ]; then

 							 echo "Running $run on dragen4"
                                                        # UPDATE WHEN DRAGEN4 IS ONLINE
#                                                       ssh -i ~/.ssh/id_rsa_dragen dragen@192.168.1.19 "nohup bash /mnt/Data-MSA/diagnostics/pipelines/DragenQC/DragenQC.sh ${path} > /mnt/Data-MSA/raw/logs/${run}.log 2>&1 &"
                                                        touch $dragen_markers/${run}_dragen4_locked


						else
							echo "All suitable dragens are currently unavailable. Try again later."
							mv $raw/$instrumentType/$run/_RTAComplete.txt $raw/$instrumentType/$run/RTAComplete.txt

						fi

					
					#If ctDNA, send to dragen3
					elif [ $is_ctdna -gt 0 ]; then

						#Need to work out what to do for ctDNA
						echo "ctDNA"
					
					#If swgs, send to dragen4
					elif [ $is_swgs -gt 0 ]; then

						#Check if the dragen is currently locked by another run, if none free, re-queue for the cron to pick up again
                                                if [ ! -f "${dragen_markers}/*_dragen1_locked" ]; then

                                                        echo "Running $run on dragen1"
							#STILL NEED TO COPY AND TEST SWGS SCRIPT
#                                                        ssh -i ~/.ssh/id_rsa_dragen dragen@192.168.1.19 "nohup bash /mnt/Data-MSA/diagnostics/pipelines/DragenQC/DragenQC.sh ${path} > /mnt/Data-MSA/raw/logs/${run}.log 2>&1 &"
                                                        touch $dragen_markers/${run}_dragen1_locked

                                                elif [ ! -f "${dragen_markers}/*_dragen2_locked" ]; then

                                                        echo "Running $run on dragen2"
                                                        # UPDATE WHEN DRAGEN2 IS ONLINE
#                                                       ssh -i ~/.ssh/id_rsa_dragen dragen@192.168.1.19 "nohup bash /mnt/Data-MSA/diagnostics/pipelines/DragenQC/DragenQC.sh ${path} > /mnt/Data-MSA/raw/logs/${run}.log 2>&1 &"
                                                        touch $dragen_markers/${run}_dragen2_locked

                                                elif [ ! -f "${dragen_markers}/*_dragen4_locked" ]; then

                                                         echo "Running $run on dragen4"
                                                        # UPDATE WHEN DRAGEN4 IS ONLINE
#                                                       ssh -i ~/.ssh/id_rsa_dragen dragen@192.168.1.19 "nohup bash /mnt/Data-MSA/diagnostics/pipelines/DragenQC/DragenQC.sh ${path} > /mnt/Data-MSA/raw/logs/${run}.log 2>&1 &"
                                                        touch $dragen_markers/${run}_dragen4_locked


                                                else
                                                        echo "All suitable dragens are currently unavailable. Try again later."
                                                        mv $raw/$instrumentType/$run/_RTAComplete.txt $raw/$instrumentType/$run/RTAComplete.txt

                                                fi
					
					#All the other non-dragen pipelines - do the cloud
					else

						echo "Do the cloud"

					fi

				else
					echo "No SampleSheet.csv"
				fi

			else
				echo "Not running until CopyComplete.txt is there"

			fi

		fi

	done

}

processJobs "$raw/nextseq"
processJobs "$raw/novaseq"
