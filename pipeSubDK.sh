#!/bin/bash
# =============================================================================
# Authors: Michael Schirner, Simon Rothmeier, Petra Ritter
# BrainModes Research Group (head: P. Ritter)
# Charité University Medicine Berlin & Max Planck Institute Leipzig, Germany
# Correspondence: petra.ritter@charite.de
#
# When using this code please cite as follows:
# Schirner M, Rothmeier S, Jirsa V, McIntosh AR, Ritter P (in prep)
# Constructing subject-specific Virtual Brains from multimodal neuroimaging
#
# This software is distributed under the terms of the GNU General Public License
# as published by the Free Software Foundation. Further details on the GPL
# license can be found at http://www.gnu.org/copyleft/gpl.html.
# =============================================================================

#Report PID
echo "The PID: $$"

subID=$1
split=$2
setupPath=$3

#Init all Toolboxes
source ${setupPath}/pipeSetup.sh

#Define the jobFile
jobFile=${rootPath}/logfiles/jobFile${subID}.txt

### 1.) The Preprocessinge-Job ####################################
#oarsub -n pipe_${subID} -l walltime=16:00:00 -p "host > 'n01'" "${rootPath}/preprocDK.sh ${rootPath}/ ${subID} ${split}"
sbatch -J pipe_${subID} -t 12:00:00 -n 16 -p normal -o logfiles/pipe_${subID}.o%j ${rootPath}/preprocDK.sh ${subFolder}/ ${subID} ${split} > $jobFile
echo "Wait for the Preprocessing-Job to finish"
#Extract the Job ID from the previously submitted job
jobID=$(tail -n 1 $jobFile | cut -f 4 -d " ")

### 2.1) RUN functional Processing ##########################
#oarsub -n fc_${subID} -l walltime=02:00:00 -p "host > 'n01'" "${rootPath}/fmriFC.sh ${rootPath}/ ${subID}"
sbatch -J fc_${subID} --dependency=afterok:${jobID} -o logfiles/fc_${subID}.o%j -N 1 -n 1 -p normal -t 10:00:00 ${rootPath}/fmriFC.sh ${subFolder}/ ${subID}

### 2.2) RUN generateMask.m ##################################
#oarsub -n Mask_${subID} -l walltime=01:00:00 -p "host > 'n01'" "${rootPath}/genMaskDK.sh ${rootPath} ${subID}"
sbatch -J Mask_${subID} --dependency=afterok:${jobID} -o logfiles/Mask_${subID}.o%j -N 1 -n 1 -p normal -t 01:00:00 ${rootPath}/genMaskDK.sh ${subFolder} ${subID} ${rootPath} > $jobFile
echo "Wait fo the Mask-Job to finish"
#Extract the Job ID from the previously submitted job
jobID=$(tail -n 1 $jobFile | cut -f 4 -d " ")

### 3.) RUN the Tracking ####################################
cp ${rootPath}/trackingClusterDK.sh ${subFolder}/${subID}/mrtrix_68/masks_68
cp ${rootPath}/pipeSetup.sh ${subFolder}/${subID}/mrtrix_68/masks_68
cp  ${rootPath}/runTracking.sh ${subFolder}/${subID}/mrtrix_68/masks_68
cd ${subFolder}/${subID}/mrtrix_68/masks_68
mkdir counter
sbatch -J trk_${subID} --dependency=afterok:${jobID} -n 192 -p normal -o trk_${subID}.o%%j -t 03:30:00 ./runTracking.sh > $jobFile
echo "Tracking jobs submitted"
#Extract the Job ID from the previously submitted job
jobID=$(tail -n 1 $jobFile | cut -f 4 -d " ")

### 4.) RUN computeSC_cluster_new.m #########################
cp ${rootPath}/matlab_scripts/*.m ${subFolder}/${subID}/mrtrix_68/tracks_68
cp ${rootPath}/runOctave.sh ${subFolder}/${subID}/mrtrix_68/tracks_68
cd ${subFolder}/${subID}/mrtrix_68/tracks_68

#Generate a set of commands for the SC-jobs...
if [ ! -f "compSCcommand.txt" ]; then
	for i in {1..68}
	do
	 echo "\"computeSC_clusterDK('./','_tracks${subID}.tck','../masks_68/wmborder.mat',${i},'SC_row_${i}${subID}.mat')\"" >> compSCcommand.txt
	done
fi

#Now submit the job....
sbatch -J cSC_${subID} --dependency=afterok:${jobID} -o cSC_${subID}.o%j -n 68 -p normal -t 05:00:00 ./runCompSC.sh > $jobFile
echo "computeSC jobs submitted"
#Extract the Job ID from the previously submitted job
jobID=$(tail -n 1 $jobFile | cut -f 4 -d " ")

### 5). RUN aggregateSC_new.m ################################
cd ${subFolder}/${subID}/mrtrix_68/masks_68
touch ${subFolder}/${subID}/doneCompSC.txt
cd ${subFolder}/${subID}/mrtrix_68/tracks_68

sbatch -J aggreg_${subID} --dependency=afterok:${jobID} -o aggreg_${subID}.o%j -t 01:50:00 -N 1 -n 1 -p normal ./runOctave.sh "aggregateSC_clusterDK('${subID}_SC.mat','${subFolder}/${subID}/mrtrix_68/masks_68/wmborder.mat','${subID}')" > $jobFile
echo "aggregateSC job submitted"
#Extract the Job ID from the previously submitted job
jobID=$(tail -n 1 $jobFile | cut -f 4 -d " ")

### 6). Convert the Files into a single (TVB compatible) ZIP File ##############
sbatch -J conn2TVB_${subID} --dependency=afterok:${jobID} -o conn2TVB_${subID}.o%j -t 00:10:00 -N 1 -n 1 -p normal ./runOctave.sh "connectivity2TVBFS('${subID}','${subFolder}/${subID}','${subID}_SC.mat','recon_all')"
echo "connectivity2TVB job submitted"
