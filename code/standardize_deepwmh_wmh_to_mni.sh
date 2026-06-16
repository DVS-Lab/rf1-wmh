#!/usr/bin/env bash

# Normalize DeepWMH binary WMH segmentations to FSL 1-mm MNI standard space.
#
# This mirrors the TrUE-Net standardization workflow but reads DeepWMH's final
# native-space segmentation:
#
#   derivatives/deepwmh/sub-${sub}/ses-${SES}/002_Segmentations/003_postproc_fov/sub-${sub}_ses-${SES}.nii.gz
#
# Typical usage:
#   bash code/standardize_deepwmh_wmh_to_mni.sh code/h1_doors.tsv
#
# Common overrides:
#   SES=02 bash code/standardize_deepwmh_wmh_to_mni.sh code/h1_doors.tsv
#   FAIL_ON_MISSING=0 bash code/standardize_deepwmh_wmh_to_mni.sh code/h1_doors.tsv
#   OVERWRITE=1 bash code/standardize_deepwmh_wmh_to_mni.sh code/h1_doors.tsv

set -euo pipefail

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

subject_tsv="${1:-${scriptdir}/h1_doors.tsv}"

ses="${SES:-01}"
overwrite="${OVERWRITE:-0}"
fail_on_missing="${FAIL_ON_MISSING:-1}"

bids_dir="${BIDS_DIR:-/ZPOOL/data/projects/rf1-sra-linux2/bids}"
project_dir="${WMH_PROJECT_DIR:-$maindir}"
deepwmh_dir="${DEEPWMH_DIR:-${project_dir}/derivatives/deepwmh}"
t1_fallback_ses="${T1_FALLBACK_SES:-01}"

standard="${STANDARD:-${FSLDIR:-}/data/standard/MNI152_T1_1mm_brain.nii.gz}"
space_tag="${SPACE_TAG:-MNI152NLin6Asym}"
resolution_tag="${RESOLUTION_TAG:-1}"

bet_t1_opts="${BET_T1_OPTS:--R -f 0.30 -g 0}"
bet_flair_opts="${BET_FLAIR_OPTS:--R -f 0.30 -g 0}"

seg_desc="${SEG_DESC:-deepwmhPostprocFov}"
merge_dir="${deepwmh_dir}/merged/space-${space_tag}_res-${resolution_tag}"
mkdir -p "$merge_dir"

manifest="${merge_dir}/group-h1doors_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${seg_desc}_manifest.tsv"
bin_list="${merge_dir}/group-h1doors_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${seg_desc}_dseg_files.txt"
merged_bin="${merge_dir}/group-h1doors_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${seg_desc}_dseg.nii.gz"

required_cmds=(flirt convert_xfm fslmaths fslmerge fslinfo bet awk)
for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Required command not found on PATH: $cmd" >&2
        exit 1
    fi
done

if [[ ! -e "$subject_tsv" ]]; then
    echo "[ERROR] Subject TSV not found: $subject_tsv" >&2
    exit 1
fi

if [[ ! -d "$bids_dir" ]]; then
    echo "[ERROR] BIDS directory not found: $bids_dir" >&2
    echo "        Set BIDS_DIR=/path/to/bids if needed." >&2
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

find_t1w() {
    local sub="$1"
    local raw_t1="${bids_dir}/sub-${sub}/ses-${ses}/anat/sub-${sub}_ses-${ses}_T1w.nii.gz"
    local fallback_t1="${bids_dir}/sub-${sub}/ses-${t1_fallback_ses}/anat/sub-${sub}_ses-${t1_fallback_ses}_T1w.nii.gz"

    if [[ -e "$raw_t1" ]]; then
        printf "%s\t\n" "$raw_t1"
    elif [[ "$t1_fallback_ses" != "$ses" && -e "$fallback_t1" ]]; then
        printf "%s\tusing ses-%s T1w fallback\n" "$fallback_t1" "$t1_fallback_ses"
    else
        printf "%s\tmissing T1w\n" "$raw_t1"
    fi
}

check_seg_matches_raw_flair() {
    local seg="$1"
    local raw_flair="$2"
    local seg_geom raw_geom

    seg_geom="$(get_geom "$seg")"
    raw_geom="$(get_geom "$raw_flair")"

    if [[ "$seg_geom" != "$raw_geom" ]]; then
        echo "  [WARN] DeepWMH segmentation dim/pixdim differs from raw/native BIDS FLAIR."
        echo "         seg       : $seg_geom"
        echo "         raw FLAIR : $raw_geom"
        echo "         Continuing, but inspect this subject before trusting group maps."
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
printf "row\tsubject\tstatus\tinput_seg\traw_flair\traw_t1w\tflair2t1_mat\tt12std_mat\tflair2std_mat\toutput_dseg\tnote\n" >> "$manifest"

bin_files=()
missing_count=0
row=0

printf "Using subject TSV: %s\n" "$subject_tsv"
printf "Subjects/rows found: %s\n" "${#subjects[@]}"
printf "Session: %s\n" "$ses"
printf "BIDS directory: %s\n" "$bids_dir"
printf "DeepWMH directory: %s\n" "$deepwmh_dir"
printf "Standard-space reference: %s\n" "$standard"
printf "Merge directory: %s\n\n" "$merge_dir"

for sub in "${subjects[@]}"; do
    row=$((row + 1))

    raw_anat_dir="${bids_dir}/sub-${sub}/ses-${ses}/anat"
    raw_flair="${raw_anat_dir}/sub-${sub}_ses-${ses}_FLAIR.nii.gz"
    case_name="sub-${sub}_ses-${ses}"
    seg_in="${deepwmh_dir}/sub-${sub}/ses-${ses}/002_Segmentations/003_postproc_fov/${case_name}.nii.gz"

    read -r raw_t1 t1_note <<< "$(find_t1w "$sub")"

    xfm_dir="${deepwmh_dir}/xfm/sub-${sub}/ses-${ses}"
    mkdir -p "$xfm_dir"

    flair2t1="${xfm_dir}/sub-${sub}_ses-${ses}_from-FLAIR_to-T1w_mode-image_xfm.mat"
    t12std="${xfm_dir}/sub-${sub}_ses-${ses}_from-T1w_to-${space_tag}_mode-image_xfm.mat"
    flair2std="${xfm_dir}/sub-${sub}_ses-${ses}_from-FLAIR_to-${space_tag}_mode-image_xfm.mat"

    flair_copy="${xfm_dir}/sub-${sub}_ses-${ses}_desc-rawcopy_FLAIR.nii.gz"
    t1_copy="${xfm_dir}/sub-${sub}_ses-${ses}_desc-rawcopy_T1w.nii.gz"
    flair_brain="${xfm_dir}/sub-${sub}_ses-${ses}_desc-brain_FLAIR.nii.gz"
    t1_brain="${xfm_dir}/sub-${sub}_ses-${ses}_desc-brain_T1w.nii.gz"

    flair_in_t1="${xfm_dir}/sub-${sub}_ses-${ses}_from-FLAIR_to-T1w_desc-brain.nii.gz"
    t1_in_std="${xfm_dir}/sub-${sub}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_desc-brain_T1w.nii.gz"
    flair_in_std="${xfm_dir}/sub-${sub}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_desc-FLAIR.nii.gz"

    out_dir="${deepwmh_dir}/sub-${sub}/ses-${ses}"
    out_bin="${out_dir}/sub-${sub}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${seg_desc}_dseg.nii.gz"

    missing_note=""
    for f in "$raw_flair" "$raw_t1" "$seg_in"; do
        if [[ ! -e "$f" ]]; then
            missing_note+="missing ${f}; "
        fi
    done
    if [[ -n "$t1_note" && "$t1_note" != "missing T1w" ]]; then
        missing_note+="${t1_note}; "
    fi

    if [[ -n "$missing_note" && "$missing_note" == *"missing"* ]]; then
        echo "[MISSING] Row ${row}, sub-${sub}: ${missing_note}"
        printf "%s\tsub-%s\tmissing\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$row" "$sub" "$seg_in" "$raw_flair" "$raw_t1" "$flair2t1" "$t12std" "$flair2std" "$out_bin" "$missing_note" >> "$manifest"
        missing_count=$((missing_count + 1))
        continue
    fi

    echo "========================================"
    echo "Row ${row}: sub-${sub}"
    echo "  input seg        : $seg_in"
    echo "  raw/native FLAIR : $raw_flair"
    echo "  raw/native T1w   : $raw_t1"
    echo "  output bin       : $out_bin"

    check_seg_matches_raw_flair "$seg_in" "$raw_flair"

    if needs_run "$flair_copy"; then
        fslmaths "$raw_flair" "$flair_copy"
    fi
    if needs_run "$t1_copy"; then
        fslmaths "$raw_t1" "$t1_copy"
    fi

    if needs_run "$t1_brain"; then
        echo "  Skull-stripping raw/native T1w copy..."
        # shellcheck disable=SC2086
        bet "$t1_copy" "${t1_brain%.nii.gz}" $bet_t1_opts
    else
        echo "  Reusing skull-stripped T1w: $t1_brain"
    fi

    if needs_run "$flair_brain"; then
        echo "  Skull-stripping raw/native FLAIR copy..."
        # shellcheck disable=SC2086
        bet "$flair_copy" "${flair_brain%.nii.gz}" $bet_flair_opts
    else
        echo "  Reusing skull-stripped FLAIR: $flair_brain"
    fi

    if needs_run "$flair2std" || [[ ! -s "$flair2t1" || ! -s "$t12std" ]]; then
        echo "  Estimating raw/native FLAIR -> raw/native T1w transform, 6 DOF..."
        flirt \
            -in "$flair_brain" \
            -ref "$t1_brain" \
            -out "$flair_in_t1" \
            -omat "$flair2t1" \
            -bins 256 \
            -cost normmi \
            -searchrx -90 90 \
            -searchry -90 90 \
            -searchrz -90 90 \
            -dof 6 \
            -interp trilinear

        echo "  Estimating raw/native T1w -> ${space_tag}, 12 DOF..."
        flirt \
            -in "$t1_brain" \
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

        echo "  Concatenating raw/native FLAIR -> ${space_tag} transform..."
        convert_xfm -omat "$flair2std" -concat "$t12std" "$flair2t1"

        echo "  Writing raw/native FLAIR-in-standard QC image..."
        flirt \
            -in "$flair_copy" \
            -ref "$standard" \
            -applyxfm \
            -init "$flair2std" \
            -out "$flair_in_std" \
            -interp trilinear
    else
        echo "  Reusing existing transform: $flair2std"
    fi

    if needs_run "$out_bin"; then
        echo "  Applying FLAIR -> MNI transform to DeepWMH binary segmentation..."
        flirt \
            -in "$seg_in" \
            -ref "$standard" \
            -applyxfm \
            -init "$flair2std" \
            -out "$out_bin" \
            -interp nearestneighbour
        fslmaths "$out_bin" -bin "$out_bin"
    else
        echo "  Reusing existing binary output."
    fi

    bin_files+=("$out_bin")

    printf "%s\tsub-%s\tok\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$row" "$sub" "$seg_in" "$raw_flair" "$raw_t1" "$flair2t1" "$t12std" "$flair2std" "$out_bin" "$t1_note" >> "$manifest"
done

printf "\nFinished subject-level normalization.\n"
printf "Manifest: %s\n" "$manifest"
printf "Missing rows: %s\n" "$missing_count"

if [[ "$missing_count" -gt 0 && "$fail_on_missing" == "1" ]]; then
    echo "[ERROR] At least one subject/row was missing required inputs."
    echo "        Refusing to create group 4-D files because the merged volumes would no longer match the full TSV row order."
    echo "        Review the manifest, fix missing files, or rerun with FAIL_ON_MISSING=0 to merge available outputs only."
    exit 1
fi

if [[ "${#bin_files[@]}" -eq 0 ]]; then
    echo "[ERROR] No normalized outputs were available for merging." >&2
    exit 1
fi

printf "%s\n" "${bin_files[@]}" > "$bin_list"

check_merge_geometry "binary outputs" "${bin_files[@]}"

printf "\nMerging binary outputs in TSV order...\n"
printf "  list: %s\n" "$bin_list"
printf "  out : %s\n" "$merged_bin"
fslmerge -t "$merged_bin" "${bin_files[@]}"

printf "\nDone.\n"
printf "4-D binary file    : %s\n" "$merged_bin"
printf "Subject/order file : %s\n" "$manifest"
