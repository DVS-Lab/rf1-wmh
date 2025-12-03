#!/usr/bin/env bash

# Run this from the code directory ($scriptdir), just like your other scripts.

set -e

# Figure out scriptdir and maindir just like in truenet_all.sh
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

# Preprocessed data live here:
preprocess_dir="${maindir}/derivatives/truenet-preprocess"

if [ ! -d "$preprocess_dir" ]; then
    echo "[ERROR] Preprocess directory not found: $preprocess_dir"
    exit 1
fi

echo "Using preprocess directory: $preprocess_dir"
echo

# Helper: get dims and pixdims as a single string
get_geom() {
    fslinfo "$1" | awk '
        /^dim1/    {d1=$2}
        /^dim2/    {d2=$2}
        /^dim3/    {d3=$2}
        /^dim4/    {d4=$2}
        /^pixdim1/ {p1=$2}
        /^pixdim2/ {p2=$2}
        /^pixdim3/ {p3=$2}
        /^pixdim4/ {p4=$2}
        END {print d1,d2,d3,d4,p1,p2,p3,p4}
    '
}

# Image types to check/merge
types=("T1" "FLAIR" "WMmask")

# Subject directories under preprocess_dir (sub-XXXXX)
subs=( "${preprocess_dir}"/sub-* )

for t in "${types[@]}"; do
    echo "==============================="
    echo "Checking geometry for type: $t"
    echo "==============================="

    ref_file=""
    ref_geom=""
    mismatch=0
    filelist=()

    # First pass: find a reference file and its geometry
    for subdir in "${subs[@]}"; do
        [ -d "$subdir" ] || continue
        subid=$(basename "$subdir")                      # e.g., sub-11736
        f="${subdir}/${subid}_${t}.nii.gz"               # e.g., .../sub-11736_T1.nii.gz

        if [ -e "$f" ]; then
            ref_file="$f"
            ref_geom=$(get_geom "$f")
            echo "Reference for $t: $ref_file"
            echo "  geom: $ref_geom"
            filelist+=( "$f" )
            break
        fi
    done

    if [ -z "$ref_file" ]; then
        echo "[WARN] No files found for type $t; skipping."
        echo
        continue
    fi

    # Second pass: compare all other subjects to reference
    for subdir in "${subs[@]}"; do
        [ -d "$subdir" ] || continue
        subid=$(basename "$subdir")
        f="${subdir}/${subid}_${t}.nii.gz"

        if [ ! -e "$f" ]; then
            echo "[WARN] Missing $t file for $subid"
            continue
        fi

        # Already used as reference
        if [ "$f" == "$ref_file" ]; then
            continue
        fi

        geom=$(get_geom "$f")

        if [ "$geom" != "$ref_geom" ]; then
            echo "[MISMATCH] $t geometry differs for $f"
            echo "  expected: $ref_geom"
            echo "  got     : $geom"
            mismatch=$((mismatch+1))
        fi

        # In all cases, include the file in the merge list
        filelist+=( "$f" )
    done

    echo
    if [ "$mismatch" -gt 0 ]; then
        echo "[SUMMARY] $mismatch geometry mismatches detected for type $t."
        echo "          Still attempting fslmerge; it may fail if dimensions are incompatible."
    else
        echo "[SUMMARY] All $t images share identical dim/pixdim."
    fi

    # Attempt merge regardless of mismatches
    outname="${preprocess_dir}/merged_${t}.nii.gz"
    echo "Merging ${#filelist[@]} images for $t into:"
    echo "  $outname"

    fslmerge -t "$outname" "${filelist[@]}" || {
        echo "[ERROR] fslmerge failed for type $t. See messages above."
    }

    echo
done
