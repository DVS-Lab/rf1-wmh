#!/usr/bin/env bash

# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

# updated base directory
rf1datadir=/ZPOOL/data/projects/rf1-sra-linux2

# load pre-trained model (unchanged)
export TRUENET_PRETRAINED_MODEL_PATH="/ZPOOL/data/tools/truenet_models/Pretrained_models_for_testing/MWSC_FLAIR_T1"

# summary TSV
tsvdir=${maindir}/derivatives/truenet-evaluate-mwsc
mkdir -p "$tsvdir"
tsvfile=${tsvdir}/truenet-summary.tsv

rm -f "$tsvfile"
touch "$tsvfile"
echo -e "subject\twmh" >> "$tsvfile"

paths_file=${scriptdir}/paths_FLAIR_n236.txt

# loop over FLAIR paths, derive subject IDs
while read -r FLAIR; do
    [ -z "$FLAIR" ] && continue

    fname=$(basename "$FLAIR")
    sub_with_prefix=$(echo "$fname" | cut -d_ -f1)   # sub-10317
    sub=${sub_with_prefix#sub-}                      # 10317
    ses=01

    # T1 path (for existence check)
    T1=${rf1datadir}/bids/sub-${sub}/ses-${ses}/anat/sub-${sub}_ses-${ses}_T1w.nii.gz

    # set directories
    input=${maindir}/derivatives/truenet-preprocess/sub-${sub}
    output=${maindir}/derivatives/truenet-evaluate-mwsc/sub-${sub}
    mkdir -p "$output"

    # evaluate model and print results to file, only for existing data
    if [ -e "$T1" ] && [ -d "$input" ]; then
        truenet evaluate -i "$input" -m mwsc -o "$output"

        # get total WMH volume in voxels above 0.5 probability
        probmap=${output}/Predicted_probmap_truenet_sub-${sub}.nii.gz
        if [ -e "$probmap" ]; then
            wmh=$(fslstats "$probmap" -l 0.5 -v | awk '{print $2}')
            echo -e "${sub}\t${wmh}" >> "$tsvfile"
        fi
    fi

done < "$paths_file"
