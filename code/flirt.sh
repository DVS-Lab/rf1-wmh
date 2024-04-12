#!/usr/bin/env bash


# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

sub=$1

# make output directory
mainoutput=${maindir}/derivatives/deepbrain/data
mkdir -p $mainoutput

# ready inputs and outputs
outbase=$mainoutput/Subject${sub}_T1_BrainAligned
inputdatadir=/ZPOOL/data/projects/rf1-sra-data/derivatives/fmriprep

# skull strip T1w
fslmaths $inputdatadir/sub-${sub}/anat/sub-${sub}_desc-preproc_T1w.nii.gz \
-mas $inputdatadir/sub-${sub}/anat/sub-${sub}_desc-brain_mask.nii.gz \
$mainoutput/sub-${sub}_masked

# affine registration of skull stripped T1w
flirt -in $mainoutput/sub-${sub}_masked \
-ref ${maindir}/masks/MNI152_T1_1mm_brain_LPS_filled.nii.gz \
-out $outbase \
-omat ${outbase}.mat \
-bins 256 -cost corratio -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 12  -interp trilinear

# clean up tmp files
rm -rf ${outbase}.mat

