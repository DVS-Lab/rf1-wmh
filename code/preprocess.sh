#!/usr/bin/env bash

# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

# updated base directory
rf1datadir=/ZPOOL/data/projects/rf1-sra-linux2

sub=$1
ses=02  # hard-code session for now

# make output directory
mainoutput=${maindir}/derivatives/truenet-preprocess/sub-${sub}/ses-${ses}
mkdir -p "$mainoutput"

# ready inputs and outputs
FLAIR=${rf1datadir}/bids/sub-${sub}/ses-${ses}/anat/sub-${sub}_ses-${ses}_FLAIR.nii.gz
if [[] $sub -eq 10590 || $sub -eq 10617 ]]; then # missing ses-2 T1w scans for these two for some reason
    T1=${rf1datadir}/bids/sub-${sub}/ses-1/anat/sub-${sub}_ses-1_T1w.nii.gz
else
    T1=${rf1datadir}/bids/sub-${sub}/ses-${ses}/anat/sub-${sub}_ses-${ses}_T1w.nii.gz
fi
outbase=${mainoutput}/sub-${sub}

# preprocess data only for existing data
if [ -e "$T1" ] && [ -e "$FLAIR" ]; then
    prepare_truenet_data --FLAIR="$FLAIR" --T1="$T1" --outname="$outbase"
fi


ERROR: Could not find image /ZPOOL/data/projects/rf1-sra-linux2/bids/sub-10590/ses-02/anat/sub-10590_ses-02_T1w.nii.gz.nii.gz
ERROR: Could not find image /ZPOOL/data/projects/rf1-sra-linux2/bids/sub-10617/ses-02/anat/sub-10617_ses-02_T1w.nii.gz.nii.gz
