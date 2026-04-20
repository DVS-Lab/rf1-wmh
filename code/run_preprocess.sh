#!/usr/bin/env bash

# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"


# Notes from 2026-04-20 update
# (base) tug87422@CLA19787:/ZPOOL/data/projects/rf1-sra-linux2$ ls -1 bids/sub-*/ses-01/anat/sub-*_ses-01_FLAIR.nii.gz | wc -l
# 303
# (base) tug87422@CLA19787:/ZPOOL/data/projects/rf1-sra-linux2$ ls -1 bids/sub-*/ses-02/anat/sub-*_ses-02_FLAIR.nii.gz | wc -l
# 20


# file with full FLAIR paths (n = 236)
paths_file=${scriptdir}/paths_FLAIR_ses-1_n303.txt

SCRIPTNAME=${scriptdir}/preprocess.sh
NCORES=50

# loop over each FLAIR path and extract the subject ID (e.g., 10317 from sub-10317_ses-01_FLAIR.nii.gz)
while read -r FLAIR; do
    # skip empty lines
    [ -z "$FLAIR" ] && continue

    fname=$(basename "$FLAIR")
    sub_with_prefix=$(echo "$fname" | cut -d_ -f1)   # e.g., sub-10317
    sub=${sub_with_prefix#sub-}                      # e.g., 10317

    # simple concurrency control
    while [ "$(ps -ef | grep -v grep | grep "$SCRIPTNAME" | wc -l)" -ge "$NCORES" ]; do
        sleep 5s
    done

    bash "$SCRIPTNAME" "$sub" &
    sleep 1s

done < "$paths_file"
