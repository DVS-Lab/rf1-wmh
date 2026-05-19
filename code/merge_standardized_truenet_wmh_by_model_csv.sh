#!/usr/bin/env bash

# Merge already-normalized TrUE-Net WMH maps into model-specific 4-D files.
#
# This script does NOT run flirt, bet, or any registration. It assumes that the
# subject-level standard-space files were already created by:
#   standardize_truenet_wmh_to_mni.sh
#
# Default behavior:
#   - Read df_model1.csv and df_model5.csv from this code directory.
#   - Use the sub_id column to define the subject/volume order.
#   - Merge the p > 0.5 binary standard-space WMH maps.
#   - For each merged 4-D file, create a 3-D mask of voxels with a nonzero
#     value in any volume.
#
# Typical usage from /ZPOOL/data/projects/rf1-wmh/code:
#   bash merge_standardized_truenet_wmh_by_model_csv.sh
#
# Or pass explicit CSVs:
#   bash merge_standardized_truenet_wmh_by_model_csv.sh df_model1.csv df_model5.csv
#
# Common overrides:
#   MAP_KIND=probseg bash merge_standardized_truenet_wmh_by_model_csv.sh
#   MAP_KIND=both bash merge_standardized_truenet_wmh_by_model_csv.sh
#   MODEL=mwsc bash merge_standardized_truenet_wmh_by_model_csv.sh
#   OVERWRITE=1 bash merge_standardized_truenet_wmh_by_model_csv.sh
#   FAIL_ON_MISSING=0 bash merge_standardized_truenet_wmh_by_model_csv.sh

set -euo pipefail

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

# Defaults inherited from the standardization script.
ses="${SES:-01}"
model="${MODEL:-ukbb}"                  # ukbb or mwsc
prob_kind="${PROB_KIND:-WMmasked}"      # WMmasked or unmasked
map_kind="${MAP_KIND:-dseg}"            # dseg, probseg, or both
overwrite="${OVERWRITE:-0}"
fail_on_missing="${FAIL_ON_MISSING:-1}"

project_dir="${WMH_PROJECT_DIR:-$maindir}"
evaluate_dir="${TRUENET_EVALUATE_DIR:-${project_dir}/derivatives/truenet-evaluate}"

space_tag="${SPACE_TAG:-MNI152NLin6Asym}"
resolution_tag="${RESOLUTION_TAG:-1}"

model_upper="$(echo "$model" | tr '[:lower:]' '[:upper:]')"
case "$prob_kind" in
    WMmasked|wmmasked|wm|WM)
        prob_desc="WMmasked"
        ;;
    unmasked|raw|prob|none)
        prob_desc="unmasked"
        ;;
    *)
        echo "[ERROR] PROB_KIND must be WMmasked or unmasked. Got: $prob_kind" >&2
        exit 1
        ;;
esac

deriv_desc="truenet${model_upper}${prob_desc}"
merge_root="${evaluate_dir}/merged/space-${space_tag}_res-${resolution_tag}/model-${model}"

required_cmds=(fslmerge fslmaths fslinfo awk sed head basename)
for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Required command not found on PATH: $cmd" >&2
        exit 1
    fi
done

if [[ ! -d "$evaluate_dir" ]]; then
    echo "[ERROR] TrUE-Net evaluate directory not found: $evaluate_dir" >&2
    echo "        Set TRUENET_EVALUATE_DIR=/path/to/derivatives/truenet-evaluate if needed." >&2
    exit 1
fi

# If no CSVs are supplied, use the two expected model CSVs in the code directory.
if [[ "$#" -eq 0 ]]; then
    csvs=("${scriptdir}/df_model1.csv" "${scriptdir}/df_model5.csv")
else
    csvs=("$@")
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

choose_delim() {
    local table="$1"
    local header
    header="$(head -n 1 "$table")"
    if [[ "$header" == *$'\t'* && "$header" != *","* ]]; then
        printf '\t'
    else
        printf ','
    fi
}

read_subjects_from_table() {
    local table="$1"
    local delim
    delim="$(choose_delim "$table")"

    awk -v FS="$delim" '
        function clean(x) {
            gsub(/\r/, "", x)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", x)
            gsub(/^"|"$/, "", x)
            return x
        }
        NR == 1 {
            sub_col = 0
            for (i = 1; i <= NF; i++) {
                col = clean($i)
                if (col == "sub_id" || col == "sub" || col == "subject" || col == "participant_id") {
                    sub_col = i
                }
            }
            if (sub_col == 0) {
                print "[ERROR] Could not find a sub_id, sub, subject, or participant_id column in " FILENAME > "/dev/stderr"
                exit 2
            }
            next
        }
        NF > 0 {
            s = clean($sub_col)
            gsub(/^sub-/, "", s)
            if (s != "") print s
        }
    ' "$table"
}

group_label_from_csv() {
    local csv="$1"
    local stem
    stem="$(basename "$csv")"
    stem="${stem%.*}"
    stem="${stem#df_}"
    # BIDS-ish entity values should avoid underscores and punctuation.
    echo "$stem" | sed 's/[^A-Za-z0-9]/-/g'
}

source_file_for_subject() {
    local sub="$1"
    local kind="$2"
    local model_dir="${evaluate_dir}/sub-${sub}/${model}"

    case "$kind" in
        dseg)
            printf "%s/sub-%s_ses-%s_space-%s_res-%s_label-WMH_desc-%sPgt05_dseg.nii.gz" \
                "$model_dir" "$sub" "$ses" "$space_tag" "$resolution_tag" "$deriv_desc"
            ;;
        probseg)
            printf "%s/sub-%s_ses-%s_space-%s_res-%s_label-WMH_desc-%s_probseg.nii.gz" \
                "$model_dir" "$sub" "$ses" "$space_tag" "$resolution_tag" "$deriv_desc"
            ;;
        *)
            echo "[ERROR] Unknown map kind: $kind" >&2
            exit 1
            ;;
    esac
}

output_paths_for_group() {
    local group="$1"
    local kind="$2"
    local outdir="${merge_root}/group-${group}"
    mkdir -p "$outdir"

    case "$kind" in
        dseg)
            out_base="${outdir}/group-${group}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}Pgt05_dseg"
            ;;
        probseg)
            out_base="${outdir}/group-${group}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}_probseg"
            ;;
        *)
            echo "[ERROR] Unknown map kind: $kind" >&2
            exit 1
            ;;
    esac
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

process_one_csv_one_kind() {
    local csv="$1"
    local kind="$2"
    local group
    group="$(group_label_from_csv "$csv")"

    if [[ ! -e "$csv" ]]; then
        echo "[ERROR] CSV not found: $csv" >&2
        exit 1
    fi

    mapfile -t subjects < <(read_subjects_from_table "$csv")
    if [[ "${#subjects[@]}" -eq 0 ]]; then
        echo "[ERROR] No subjects found in $csv" >&2
        exit 1
    fi

    output_paths_for_group "$group" "$kind"

    local merged="${out_base}.nii.gz"
    local mask="${out_base%_*}_desc-nonzeroAny_mask.nii.gz"
    # For names ending in _probseg or _dseg, the line above removes the suffix before adding mask.
    # If that ever produces a confusing name, this explicit fallback remains readable.
    if [[ "$kind" == "dseg" ]]; then
        mask="${merge_root}/group-${group}/group-${group}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}Pgt05NonzeroAny_mask.nii.gz"
    else
        mask="${merge_root}/group-${group}/group-${group}_ses-${ses}_space-${space_tag}_res-${resolution_tag}_label-WMH_desc-${deriv_desc}ProbNonzeroAny_mask.nii.gz"
    fi

    local file_list="${out_base}_files.txt"
    local manifest="${out_base}_manifest.tsv"

    echo "========================================"
    echo "CSV        : $csv"
    echo "Group      : $group"
    echo "Map kind   : $kind"
    echo "Rows       : ${#subjects[@]}"
    echo "Output 4-D : $merged"
    echo "Output mask: $mask"

    : > "$manifest"
    printf "row\tsubject\tstatus\tstandardized_input\tmerged_4d\tany_nonzero_mask\tnote\n" >> "$manifest"

    local files=()
    local missing_count=0
    local row=0

    for sub in "${subjects[@]}"; do
        row=$((row + 1))
        src="$(source_file_for_subject "$sub" "$kind")"

        if [[ ! -s "$src" ]]; then
            echo "[MISSING] Row ${row}, sub-${sub}: missing $src"
            printf "%s\tsub-%s\tmissing\t%s\t%s\t%s\tmissing standardized input\n" \
                "$row" "$sub" "$src" "$merged" "$mask" >> "$manifest"
            missing_count=$((missing_count + 1))
            continue
        fi

        files+=("$src")
        printf "%s\tsub-%s\tok\t%s\t%s\t%s\t\n" \
            "$row" "$sub" "$src" "$merged" "$mask" >> "$manifest"
    done

    echo "Missing rows: $missing_count"
    echo "Manifest    : $manifest"

    if [[ "$missing_count" -gt 0 && "$fail_on_missing" == "1" ]]; then
        echo "[ERROR] Missing subject-level inputs for $csv."
        echo "        Refusing to merge because the 4-D volume order would no longer match the full CSV row order."
        echo "        Rerun the standardization script for missing subjects, or set FAIL_ON_MISSING=0 to merge available rows only."
        exit 1
    fi

    if [[ "${#files[@]}" -eq 0 ]]; then
        echo "[ERROR] No files available to merge for $csv / $kind." >&2
        exit 1
    fi

    printf "%s\n" "${files[@]}" > "$file_list"
    echo "File list   : $file_list"

    check_merge_geometry "group-${group} ${kind}" "${files[@]}"

    if [[ "$overwrite" == "1" || ! -s "$merged" ]]; then
        echo "Merging ${#files[@]} files..."
        fslmerge -t "$merged" "${files[@]}"
    else
        echo "Reusing existing merged file. Set OVERWRITE=1 to recreate it."
    fi

    if [[ "$overwrite" == "1" || ! -s "$mask" ]]; then
        echo "Creating nonzero-any-volume mask..."
        fslmaths "$merged" -Tmax -thr 0 -bin "$mask"
    else
        echo "Reusing existing nonzero-any-volume mask. Set OVERWRITE=1 to recreate it."
    fi

    echo "Done:"
    echo "  4-D file : $merged"
    echo "  mask     : $mask"
    echo "  manifest : $manifest"
    echo
}

case "$map_kind" in
    dseg|binary|bin)
        kinds=(dseg)
        ;;
    probseg|prob|probability)
        kinds=(probseg)
        ;;
    both)
        kinds=(dseg probseg)
        ;;
    *)
        echo "[ERROR] MAP_KIND must be dseg, probseg, or both. Got: $map_kind" >&2
        exit 1
        ;;
esac

echo "Using TrUE-Net evaluate directory: $evaluate_dir"
echo "Using model                    : $model"
echo "Using probability kind         : $prob_kind"
echo "Using map kind(s)              : ${kinds[*]}"
echo "Using session                  : $ses"
echo

for csv in "${csvs[@]}"; do
    for kind in "${kinds[@]}"; do
        process_one_csv_one_kind "$csv" "$kind"
    done
done

echo "All requested model-specific 4-D merges and masks are complete."
