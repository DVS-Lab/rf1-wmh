#!/usr/bin/env bash

# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

# updated base directory
rf1datadir=/ZPOOL/data/projects/rf1-sra-linux2

sub=$1
ses=01  # hard-code session for now

# make output directory
mainoutput=${maindir}/derivatives/truenet-preprocess/sub-${sub}
mkdir -p "$mainoutput"

# ready inputs and outputs
FLAIR=${rf1datadir}/bids/sub-${sub}/ses-${ses}/anat/sub-${sub}_ses-${ses}_FLAIR.nii.gz
T1=${rf1datadir}/bids/sub-${sub}/ses-${ses}/anat/sub-${sub}_ses-${ses}_T1w.nii.gz
outbase=${mainoutput}/sub-${sub}

# preprocess data only for existing data
if [ -e "$T1" ] && [ -e "$FLAIR" ]; then
    prepare_truenet_data --FLAIR="$FLAIR" --T1="$T1" --outname="$outbase"
fi
