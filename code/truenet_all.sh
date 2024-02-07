#!/usr/bin/env bash



# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"
rf1datadir=/ZPOOL/data/projects/rf1-sra-data

# load pre-trained model
export TRUENET_PRETRAINED_MODEL_PATH="/ZPOOL/data/tools/truenet_models/Pretrained_models_for_testing/MWSC_FLAIR_T1"

tsvfile=${maindir}/derivatives/truenet-evaluate-mwsc/truenet-summary.tsv
rm -rf $tsvfile
touch $tsvfile
echo -e "subject\twmh" >> $tsvfile
for sub in `cat $scriptdir/sublist_all.txt`; do

	# not needed, but just a reference
	T1=$rf1datadir/bids/sub-${sub}/anat/sub-${sub}_T1w.nii.gz

	# set directories
	input=${maindir}/derivatives/truenet-preprocess/sub-${sub}
	output=${maindir}/derivatives/truenet-evaluate-mwsc/sub-${sub}
	mkdir -p $output

	# evaluate model and print results to file, only for existing data
	if [ -e $T1 ]; then
		truenet evaluate -i $input -m mwsc -o $output
		wmh=`fslstats $output/Predicted_probmap_truenet_sub-${sub}.nii.gz -l 0.5 -v | awk '{print $2}'`
		echo -e "$sub\t$wmh" >> $tsvfile
	fi

done
