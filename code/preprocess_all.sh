#!/usr/bin/env bash



# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"
rf1datadir=/ZPOOL/data/projects/rf1-sra-data

for sub in `cat $scriptdir/sublist_all.txt`; do

	# make output directory
	mainoutput=${maindir}/derivatives/truenet/sub-${sub}
	mkdir -p $mainoutput

	# ready inputs and outputs
	FLAIR=$rf1datadir/bids/sub-${sub}/anat/sub-${sub}_FLAIR.nii.gz
	T1=$rf1datadir/bids/sub-${sub}/anat/sub-${sub}_T1w.nii.gz
	outbase=$mainoutput/sub-${sub}

	# preprocess data only for existing data
	if [ -e $T1 ]; then
		prepare_truenet_data --FLAIR=$FLAIR --T1=$T1 --outname=$outbase
	fi
done
