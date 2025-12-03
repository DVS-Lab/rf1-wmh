#!/usr/bin/env bash

# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

# need to ensure it can find these since my install was bad
export TRUENET_PRETRAINED_MODEL_PATH=$CONDA_PREFIX/data/truenet/models/

# white-matter mask in MNI space (already binarized at your chosen threshold)
WMmask=${scriptdir}/masks/avg152T1_white_bin.nii.gz
if [ ! -e "$WMmask" ]; then
    echo "[WARN] WM mask not found at $WMmask; WM-masked volumes will be NA."
fi

# base directory for rf1 project
rf1datadir=/ZPOOL/data/projects/rf1-sra-linux2

# file with full FLAIR paths (n = 236)
paths_file=${maindir}/paths_FLAIR_n236.txt

# where all TrUE-Net outputs + summary TSV will live
outroot=${maindir}/derivatives/truenet-evaluate
mkdir -p "$outroot"

tsvfile=${outroot}/truenet-summary.tsv
rm -f "$tsvfile"
touch "$tsvfile"

# header: subject + both models (unmasked + WM-masked)
echo -e "subject\tmwsc_vox\tmwsc_mm3\tmwsc_wm_vox\tmwsc_wm_mm3\tukbb_vox\tukbb_mm3\tukbb_wm_vox\tukbb_wm_mm3" >> "$tsvfile"

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
    mwsc_wm_vox="NA"
    mwsc_wm_mm3="NA"

    ukbb_vox="NA"
    ukbb_mm3="NA"
    ukbb_wm_vox="NA"
    ukbb_wm_mm3="NA"

    if [ -e "$T1" ] && [ -d "$input" ]; then
        echo "Running TrUE-Net (mwsc + ukbb) for sub-${sub} ..."

        # --- MWSC model ---
        truenet evaluate -i "$input" -m mwsc -o "$out_mwsc"

        prob_mwsc=${out_mwsc}/Predicted_probmap_truenet_sub-${sub}.nii.gz
        if [ -e "$prob_mwsc" ]; then
            # Unmasked stats: voxels with prob > 0.5
            stats=$(fslstats "$prob_mwsc" -l 0.5 -v)
            mwsc_vox=$(echo "$stats" | awk '{print $1}')
            mwsc_mm3=$(echo "$stats" | awk '{print $2}')

            # Reslice WM mask to probmap grid (once per subject) and get WM-masked stats
            if [ -e "$WMmask" ]; then
                subj_WMmask=${subjroot}/WMmask_likeTruenet_sub-${sub}.nii.gz
                if [ ! -e "$subj_WMmask" ]; then
                    # Use world-space alignment (MNI→MNI), nearest-neighbour to keep it binary
                    flirt -in "$WMmask" \
                          -ref "$prob_mwsc" \
                          -applyxfm -usesqform \
                          -interp nearestneighbour \
                          -out "$subj_WMmask"
                fi

                masked_mwsc=${out_mwsc}/Predicted_probmap_truenet_sub-${sub}_WMmasked.nii.gz
                fslmaths "$prob_mwsc" -mas "$subj_WMmask" "$masked_mwsc"
                stats_wm=$(fslstats "$masked_mwsc" -l 0.5 -v)
                mwsc_wm_vox=$(echo "$stats_wm" | awk '{print $1}')
                mwsc_wm_mm3=$(echo "$stats_wm" | awk '{print $2}')
            else
                echo "  [WARN] WMmask not found; skipping WM-masked MWSC stats for sub-${sub}"
            fi
        else
            echo "  [WARN] MWSC probmap missing for sub-${sub}"
        fi

        # --- UKBB model ---
        truenet evaluate -i "$input" -m ukbb -o "$out_ukbb"

        prob_ukbb=${out_ukbb}/Predicted_probmap_truenet_sub-${sub}.nii.gz
        if [ -e "$prob_ukbb" ]; then
            # Unmasked stats
            stats=$(fslstats "$prob_ukbb" -l 0.5 -v)
            ukbb_vox=$(echo "$stats" | awk '{print $1}')
            ukbb_mm3=$(echo "$stats" | awk '{print $2}')

            # WM-masked stats using same resliced WM mask
            if [ -e "$subj_WMmask" ]; then
                masked_ukbb=${out_ukbb}/Predicted_probmap_truenet_sub-${sub}_WMmasked.nii.gz
                fslmaths "$prob_ukbb" -mas "$subj_WMmask" "$masked_ukbb"
                stats_wm=$(fslstats "$masked_ukbb" -l 0.5 -v)
                ukbb_wm_vox=$(echo "$stats_wm" | awk '{print $1}')
                ukbb_wm_mm3=$(echo "$stats_wm" | awk '{print $2}')
            elif [ -e "$WMmask" ]; then
                echo "  [WARN] subj_WMmask missing for sub-${sub} (MWSC must have failed earlier); skipping WM-masked UKBB stats."
            fi
        else
            echo "  [WARN] UKBB probmap missing for sub-${sub}"
        fi

    else
        echo "Skipping sub-${sub}: missing T1 or preprocessed directory."
    fi

    # append to summary TSV (even if some fields are NA)
    echo -e "${sub}\t${mwsc_vox}\t${mwsc_mm3}\t${mwsc_wm_vox}\t${mwsc_wm_mm3}\t${ukbb_vox}\t${ukbb_mm3}\t${ukbb_wm_vox}\t${ukbb_wm_mm3}" >> "$tsvfile"

done < "$paths_file"
