#!/usr/bin/env bash



# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"
rf1datadir=/ZPOOL/data/projects/rf1-sra-data

export TRUENET_PRETRAINED_MODEL_PATH="/ZPOOL/data/tools/truenet_models/Pretrained_models_for_testing/MWSC_FLAIR_T1"

for sub in 10317 10369; do

	input=${maindir}/derivatives/truenet/sub-${sub}
	output=${maindir}/derivatives/truenet-evaluate-mwsc/sub-${sub}
	mkdir -p $output

	truenet evaluate -i $input -m mwsc -o $output

done
