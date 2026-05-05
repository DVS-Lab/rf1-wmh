#!/usr/bin/env bash

# Normalize TrUE-Net WMH probability maps to FSL 1-mm MNI standard space.
#
# Assumptions:
#   1. This script lives in your project code/ directory, so that
#      maindir=$(dirname "$scriptdir") points to the project root.
#   2. TrUE-Net was run from derivatives/truenet-preprocess and wrote outputs to
#      derivatives/truenet-evaluate/sub-*/{ukbb,mwsc}, as in your existing scripts.
#   3. The TrUE-Net probability map is in the same space/grid as the preprocessed
#      FLAIR image for that subject/session.
#
# Usage:
#   bash standardize_truenet_wmh_to_mni.sh /path/to/h1_doors.tsv
#
# Useful overrides:
#   SES=01 MODEL=ukbb PROB_KIND=WMmasked bash standardize_truenet_wmh_to_mni.sh h1_doors.tsv
#   OVERWRITE=1 bash standardize_truenet_wmh_to_mni.sh h1_doors.tsv
#   FAIL_ON_MISSING=0 bash standardize_truenet_wmh_to_mni.sh h1_doors.tsv

set -euo pipefail

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

subject_tsv="${1:-${scriptdir}/h1_doors.tsv}"
ses=01
model="${MODEL:-ukbb}"                  # example: ukbb or mwsc
prob_kind="${PROB_KIND:-WMmasked}"      # WMmasked or unmasked
overwrite="${OVERWRITE:-0}"
fail_on_missing="${FAIL_ON_MISSING:-1}"

preprocess_dir="${TRUENET_PREPROCESS_DIR:-${maindir}/derivatives/truenet-preprocess}"
evaluate_dir="${TRUENET_EVALUATE_DIR:-${maindir}/derivatives/truenet-evaluate}"
standard="${STANDARD:-${FSLDIR:-}/data/standard/MNI152_T1_1mm_brain.nii.gz}"
space_tag="${SPACE_TAG:-MNI152NLin6Asym}"
resolution_tag="${RESOLUTION_TAG:-1}"

model_upper="$(echo "$model" | tr '[:lower:]' '[:upper:]')"
case "$prob_kind" in
    WMmasked|wmmasked|wm|WM)
        prob_suffix="_WMmasked"
        prob_desc="WMmasked"
        ;;
    unmasked|raw|prob|none)
        prob_suffix=""
        prob_desc="unmasked"
        ;;
    *)
        echo "[ERROR] PROB_KIND must be WMmasked or unmasked. Got: $prob_kind" >&2
        exit 1
        ;;
esac

deriv_desc="truenet${model_upper}${prob_desc}"
merge_dir="${evaluate_dir}/merged/space-${space_tag}_res-${resolution_tag}/model-${model}"
mkdir -p "$merge_dir"

manifest="${merge_dir}/group-h1doors_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}_manifest.tsv"
prob_list="${merge_dir}/group-h1doors_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}_probseg_files.txt"
bin_list="${merge_dir}/group-h1doors_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}Pgt05_dseg_files.txt"
merged_prob="${merge_dir}/group-h1doors_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}_probseg.nii.gz"
merged_bin="${merge_dir}/group-h1doors_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}Pgt05_dseg.nii.gz"

required_cmds=(flirt convert_xfm fslmaths fslmerge fslinfo)
for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Required FSL command not found on PATH: $cmd" >&2
        exit 1
    fi
done

if [[ ! -e "$subject_tsv" ]]; then
    echo "[ERROR] Subject TSV not found: $subject_tsv" >&2
    exit 1
fi

if [[ ! -e "$standard" ]]; then
    echo "[ERROR] Standard-space reference not found: $standard" >&2
    echo "        Set STANDARD=/path/to/MNI152_T1_1mm_brain.nii.gz and rerun." >&2
    exit 1
fi

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

read_subjects_from_tsv() {
    local tsv="$1"
    awk -F'\t' '
        NR == 1 {
            sub_col = 0
            for (i = 1; i <= NF; i++) {
                gsub(/\r/, "", $i)
                if ($i == "sub" || $i == "subject" || $i == "participant_id") {
                    sub_col = i
                }
            }
            if (sub_col == 0) {
                print "[ERROR] Could not find a sub, subject, or participant_id column in TSV." > "/dev/stderr"
                exit 2
            }
            next
        }
        NF > 0 {
            s = $sub_col
            gsub(/\r/, "", s)
            gsub(/^sub-/, "", s)
            if (s != "") print s
        }
    ' "$tsv"
}

needs_run() {
    local outfile="$1"
    [[ "$overwrite" == "1" || ! -s "$outfile" ]]
}

check_probmap_matches_flair() {
    local prob="$1"
    local flair="$2"
    local prob_geom flair_geom
    prob_geom="$(get_geom "$prob")"
    flair_geom="$(get_geom "$flair")"
    if [[ "$prob_geom" != "$flair_geom" ]]; then
        echo "  [WARN] Probmap geometry differs from preprocessed FLAIR."
        echo "         prob : $prob_geom"
        echo "         FLAIR: $flair_geom"
        echo "         Continuing because the affine header may still encode the correct relationship."
    fi
}

check_merge_geometry() {
    local label="$1"
    shift
    local files=("$@")
    local ref="${files[0]}"
    local ref_geom geom mismatch=0
    ref_geom="$(get_geom "$ref")"

    for f in "${files[@]}"; do
        geom="$(get_geom "$f")"
        if [[ "$geom" != "$ref_geom" ]]; then
            echo "[MISMATCH] ${label} geometry differs: $f" >&2
            echo "           expected: $ref_geom" >&2
            echo "           got     : $geom" >&2
            mismatch=$((mismatch + 1))
        fi
    done

    if [[ "$mismatch" -gt 0 ]]; then
        echo "[ERROR] ${label}: $mismatch geometry mismatches detected; refusing to merge." >&2
        exit 1
    fi
}

mapfile -t subjects < <(read_subjects_from_tsv "$subject_tsv")
if [[ "${#subjects[@]}" -eq 0 ]]; then
    echo "[ERROR] No subjects found in $subject_tsv" >&2
    exit 1
fi

: > "$manifest"
printf "row\tsubject\tstatus\tinput_probmap\tinput_flair\tinput_t1\tflair2std_mat\toutput_probseg\toutput_pgt05_dseg\tnote\n" >> "$manifest"

prob_files=()
bin_files=()
missing_count=0
row=0

printf "Using subject TSV: %s\n" "$subject_tsv"
printf "Subjects/rows found: %s\n" "${#subjects[@]}"
printf "Model: %s\n" "$model"
printf "Input probability kind: %s\n" "$prob_kind"
printf "Standard-space reference: %s\n" "$standard"
printf "Merge directory: %s\n\n" "$merge_dir"

for sub in "${subjects[@]}"; do
    row=$((row + 1))

    if [[ ! "$sub" =~ ^[0-9A-Za-z]+$ ]]; then
        echo "[WARN] Row ${row}: subject value looks unusual: ${sub}"
    fi

    input_dir="${preprocess_dir}/sub-${sub}/ses-${ses}"
    flair="${input_dir}/sub-${sub}_FLAIR.nii.gz"
    t1="${input_dir}/sub-${sub}_T1.nii.gz"

    model_dir="${evaluate_dir}/sub-${sub}/${model}"
    prob_in="${model_dir}/Predicted_probmap_truenet_sub-${sub}${prob_suffix}.nii.gz"

    xfm_dir="${evaluate_dir}/xfm/sub-${sub}/ses-${ses}"
    mkdir -p "$xfm_dir"

    flair2t1="${xfm_dir}/sub-${sub}_ses-${ses}_from-FLAIR_to-T1w_mode-image_xfm.mat"
    t12std="${xfm_dir}/sub-${sub}_ses-${ses}_from-T1w_to-${space_tag}_mode-image_xfm.mat"
    flair2std="${xfm_dir}/sub-${sub}_ses-${ses}_from-FLAIR_to-${space_tag}_mode-image_xfm.mat"

    # QC images for checking registration. These are intentionally separate from the final WMH outputs.
    flair_in_t1="${xfm_dir}/sub-${sub}_ses-${ses}_from-FLAIR_to-T1w_mode-image.nii.gz"
    t1_in_std="${xfm_dir}/sub-${sub}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_desc-T1w.nii.gz"
    flair_in_std="${xfm_dir}/sub-${sub}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_desc-FLAIR.nii.gz"

    out_prob="${model_dir}/sub-${sub}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}_probseg.nii.gz"
    out_bin="${model_dir}/sub-${sub}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}Pgt05_dseg.nii.gz"

    missing_note=""
    for f in "$flair" "$t1" "$prob_in"; do
        if [[ ! -e "$f" ]]; then
            missing_note+="missing ${f}; "
        fi
    done

    if [[ -n "$missing_note" ]]; then
        echo "[MISSING] Row ${row}, sub-${sub}: ${missing_note}"
        printf "%s\tsub-%s\tmissing\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$row" "$sub" "$prob_in" "$flair" "$t1" "$flair2std" "$out_prob" "$out_bin" "$missing_note" >> "$manifest"
        missing_count=$((missing_count + 1))
        continue
    fi

    echo "========================================"
    echo "Row ${row}: sub-${sub}"
    echo "  input prob : $prob_in"
    echo "  input FLAIR: $flair"
    echo "  input T1   : $t1"
    echo "  output prob: $out_prob"
    echo "  output bin : $out_bin"

    check_probmap_matches_flair "$prob_in" "$flair"

    if needs_run "$flair2std" || [[ ! -s "$flair2t1" || ! -s "$t12std" ]]; then
        echo "  Estimating FLAIR -> T1 transform..."
        flirt \
            -in "$flair" \
            -ref "$t1" \
            -out "$flair_in_t1" \
            -omat "$flair2t1" \
            -bins 256 \
            -cost normmi \
            -searchrx -90 90 \
            -searchry -90 90 \
            -searchrz -90 90 \
            -dof 6 \
            -interp trilinear

        echo "  Estimating T1 -> ${space_tag} transform..."
        flirt \
            -in "$t1" \
            -ref "$standard" \
            -out "$t1_in_std" \
            -omat "$t12std" \
            -bins 256 \
            -cost corratio \
            -searchrx -90 90 \
            -searchry -90 90 \
            -searchrz -90 90 \
            -dof 12 \
            -interp trilinear

        echo "  Concatenating FLAIR -> ${space_tag} transform..."
        convert_xfm -omat "$flair2std" -concat "$t12std" "$flair2t1"

        echo "  Writing FLAIR-in-standard QC image..."
        flirt \
            -in "$flair" \
            -ref "$standard" \
            -applyxfm \
            -init "$flair2std" \
            -out "$flair_in_std" \
            -interp trilinear
    else
        echo "  Reusing existing transform: $flair2std"
    fi

    if needs_run "$out_prob"; then
        echo "  Applying transform to probability map with trilinear interpolation..."
        flirt \
            -in "$prob_in" \
            -ref "$standard" \
            -applyxfm \
            -init "$flair2std" \
            -out "$out_prob" \
            -interp trilinear
    else
        echo "  Reusing existing probability output."
    fi

    if needs_run "$out_bin"; then
        echo "  Thresholding native probability map at p > 0.5, binarizing, then applying transform with nearest-neighbor interpolation..."
        tmpdir="$(mktemp -d)"
        native_bin="${tmpdir}/sub-${sub}_native_pgt05_bin.nii.gz"
        fslmaths "$prob_in" -thr 0.5000001 -bin "$native_bin"
        flirt \
            -in "$native_bin" \
            -ref "$standard" \
            -applyxfm \
            -init "$flair2std" \
            -out "$out_bin" \
            -interp nearestneighbour
        fslmaths "$out_bin" -bin "$out_bin"
        rm -rf "$tmpdir"
    else
        echo "  Reusing existing binary output."
    fi

    prob_files+=("$out_prob")
    bin_files+=("$out_bin")

    printf "%s\tsub-%s\tok\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$row" "$sub" "$prob_in" "$flair" "$t1" "$flair2std" "$out_prob" "$out_bin" "" >> "$manifest"
done

printf "\nFinished subject-level normalization.\n"
printf "Manifest: %s\n" "$manifest"
printf "Missing rows: %s\n" "$missing_count"

if [[ "$missing_count" -gt 0 && "$fail_on_missing" == "1" ]]; then
    echo "[ERROR] At least one subject/row was missing required inputs."
    echo "        Refusing to create group 4-D files because the merged volumes would no longer match the full TSV row order."
    echo "        Review the manifest above, fix missing files, or rerun with FAIL_ON_MISSING=0 to merge available outputs only."
    exit 1
fi

if [[ "${#prob_files[@]}" -eq 0 || "${#bin_files[@]}" -eq 0 ]]; then
    echo "[ERROR] No normalized outputs were available for merging." >&2
    exit 1
fi

printf "%s\n" "${prob_files[@]}" > "$prob_list"
printf "%s\n" "${bin_files[@]}" > "$bin_list"

check_merge_geometry "probability outputs" "${prob_files[@]}"
check_merge_geometry "binary outputs" "${bin_files[@]}"

printf "\nMerging probability outputs in TSV order...\n"
printf "  list: %s\n" "$prob_list"
printf "  out : %s\n" "$merged_prob"
fslmerge -t "$merged_prob" "${prob_files[@]}"

printf "\nMerging binary p > 0.5 outputs in TSV order...\n"
printf "  list: %s\n" "$bin_list"
printf "  out : %s\n" "$merged_bin"
fslmerge -t "$merged_bin" "${bin_files[@]}"

printf "\nDone.\n"
printf "4-D probability file: %s\n" "$merged_prob"
printf "4-D binary file     : %s\n" "$merged_bin"
printf "Subject/order file  : %s\n" "$manifest"
