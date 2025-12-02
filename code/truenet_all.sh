#!/usr/bin/env bash

# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

# base directory for rf1 project
rf1datadir=/ZPOOL/data/projects/rf1-sra-linux2

# file with full FLAIR paths (n = 236)
paths_file=${scriptdir}/paths_FLAIR_n236.txt

# where all TrUE-Net outputs + summary TSV will live
outroot=${maindir}/derivatives/truenet-evaluate
mkdir -p "$outroot"

tsvfile=${outroot}/truenet-summary.tsv
rm -f "$tsvfile"
touch "$tsvfile"

# header: subject + both models
echo -e "subject\tmwsc_vox\tmwsc_mm3\tukbb_vox\tukbb_mm3" >> "$tsvfile"

# loop over FLAIR paths, derive subject IDs
while read -r FLAIR; do
    # skip empty lines
    [ -z "$FLAIR" ] && continue

    fname=$(basename "$FLAIR")
    sub_with_prefix=$(echo "$fname" | cut -d_ -f1)   # e.g., sub-10317
    sub=${sub_with_prefix#sub-}                      # e.g., 10317
    ses=01

    # T1 path (for existence check)
    T1=${rf1datadir}/bids/sub-${sub}/ses-${ses}/anat/sub-${sub}_ses-${ses}_T1w.nii.gz

    # preprocessed input directory for this subject
    input=${maindir}/derivatives/truenet-preprocess/sub-${sub}

    # subject-specific output dirs for each model
    subjroot=${outroot}/sub-${sub}
    out_mwsc=${subjroot}/mwsc
    out_ukbb=${subjroot}/ukbb
    mkdir -p "$out_mwsc" "$out_ukbb"

    # default NA values; helpful if something goes wrong for one model
    mwsc_vox="NA"
    mwsc_mm3="NA"
    ukbb_vox="NA"
    ukbb_mm3="NA"

    if [ -e "$T1" ] && [ -d "$input" ]; then
        echo "Running TrUE-Net (mwsc + ukbb) for sub-${sub} ..."

        # --- MWSC model ---
        # You can add "-cp_type best" if you want best-checkpoint instead of last
        truenet evaluate -i "$input" -m mwsc -o "$out_mwsc"

        prob_mwsc=${out_mwsc}/Predicted_probmap_truenet_sub-${sub}.nii.gz
        if [ -e "$prob_mwsc" ]; then
            # fslstats -v prints "num_voxels volume_mm3"
            stats=$(fslstats "$prob_mwsc" -l 0.5 -v)
            mwsc_vox=$(echo "$stats" | awk '{print $1}')
            mwsc_mm3=$(echo "$stats" | awk '{print $2}')
        else
            echo "  [WARN] MWSC probmap missing for sub-${sub}"
        fi

        # --- UKBB model ---
        truenet evaluate -i "$input" -m ukbb -o "$out_ukbb"

        prob_ukbb=${out_ukbb}/Predicted_probmap_truenet_sub-${sub}.nii.gz
        if [ -e "$prob_ukbb" ]; then
            stats=$(fslstats "$prob_ukbb" -l 0.5 -v)
            ukbb_vox=$(echo "$stats" | awk '{print $1}')
            ukbb_mm3=$(echo "$stats" | awk '{print $2}')
        else
            echo "  [WARN] UKBB probmap missing for sub-${sub}"
        fi

    else
        echo "Skipping sub-${sub}: missing T1 or preprocessed directory."
    fi

    # append to summary TSV (even if some fields are NA)
    echo -e "${sub}\t${mwsc_vox}\t${mwsc_mm3}\t${ukbb_vox}\t${ukbb_mm3}" >> "$tsvfile"

done < "$paths_file"

