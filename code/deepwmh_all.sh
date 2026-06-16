#!/usr/bin/env bash

# Run DeepWMH from the Apptainer/Singularity image across a FLAIR path list.
#
# Usage:
#
#   bash code/deepwmh_all.sh 02
#   bash code/deepwmh_all.sh 01
#   bash code/deepwmh_all.sh 01 code/paths_FLAIR_ses-1_n303.txt
#
# Common overrides:
#   DEEPWMH_GPU=0
#   DEEPWMH_SKIP_BFC=1
#   MAX_JOBS=1
#   OVERWRITE=1

set -euo pipefail

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

deepwmh_image="/ZPOOL/data/tools/deepwmh_v1.0.1.sif"

usage() {
    echo "Usage: bash $0 <ses> [paths_file]" >&2
    echo "  ses: 01 or 02" >&2
    echo "  paths_file defaults to the matching code/paths_FLAIR_* file." >&2
}

ses="${1:-}"
if [[ -z "$ses" ]]; then
    usage
    exit 1
fi

case "$ses" in
    1|01)
        ses="01"
        default_paths_file="${scriptdir}/paths_FLAIR_ses-1_n303.txt"
        ;;
    2|02)
        ses="02"
        default_paths_file="${scriptdir}/paths_FLAIR_ses-2_n20.txt"
        ;;
    *)
        echo "[ERROR] Unsupported session: $ses" >&2
        usage
        exit 1
        ;;
esac

paths_file="${2:-$default_paths_file}"
bids_dir="${BIDS_DIR:-/ZPOOL/data/projects/rf1-sra-linux2/bids}"
outroot="${DEEPWMH_OUTROOT:-${maindir}/derivatives/deepwmh}"
gpu="${DEEPWMH_GPU:-0}"
max_jobs="${MAX_JOBS:-1}"
overwrite="${OVERWRITE:-0}"
skip_bfc="${DEEPWMH_SKIP_BFC:-0}"
use_nv="${DEEPWMH_USE_NV:-1}"

if [[ -n "${APPTAINER_CMD:-}" ]]; then
    runtime="$APPTAINER_CMD"
elif command -v apptainer >/dev/null 2>&1; then
    runtime="apptainer"
elif command -v singularity >/dev/null 2>&1; then
    runtime="singularity"
else
    echo "[ERROR] Could not find apptainer or singularity on PATH." >&2
    exit 1
fi

if [[ ! -e "$paths_file" ]]; then
    echo "[ERROR] FLAIR paths file not found: $paths_file" >&2
    exit 1
fi

if [[ ! -e "$deepwmh_image" ]]; then
    echo "[ERROR] DeepWMH image not found: $deepwmh_image" >&2
    exit 1
fi

if ! [[ "$max_jobs" =~ ^[0-9]+$ ]] || [[ "$max_jobs" -lt 1 ]]; then
    echo "[ERROR] MAX_JOBS must be at least 1." >&2
    exit 1
fi

mkdir -p "$outroot" "${outroot}/logs"

summary_tsv="${outroot}/deepwmh-summary_ses-${ses}.tsv"
: > "$summary_tsv"
printf "subject\tsession\tstatus\tflair\toutput_seg\tvox\tmm3\tlog\tnote\n" >> "$summary_tsv"

have_fslstats=0
if command -v fslstats >/dev/null 2>&1; then
    have_fslstats=1
fi

stats_for_seg() {
    local seg="$1"

    if [[ "$have_fslstats" == "1" && -s "$seg" ]]; then
        fslstats "$seg" -V | awk '{print $1 "\t" $2}'
    else
        printf "NA\tNA\n"
    fi
}

extract_session() {
    local fname="$1"
    awk -F'_' '
        {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^ses-/) {
                    sub(/^ses-/, "", $i)
                    print $i
                    exit
                }
            }
        }
    ' <<< "$fname"
}

append_summary() {
    local sub="$1"
    local this_ses="$2"
    local status="$3"
    local flair="$4"
    local seg="$5"
    local vox="$6"
    local mm3="$7"
    local log="$8"
    local note="$9"

    printf "sub-%s\tses-%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$sub" "$this_ses" "$status" "$flair" "$seg" "$vox" "$mm3" "$log" "$note" >> "$summary_tsv"
}

run_one() {
    local flair="$1"
    local fname sub_with_prefix sub this_ses case_name subjroot log seg vox mm3 status note
    local bind_path
    local -a runtime_args deepwmh_args
    local -a extra_binds

    [[ -z "$flair" ]] && return 0

    fname="$(basename "$flair")"
    sub_with_prefix="$(cut -d_ -f1 <<< "$fname")"
    sub="${sub_with_prefix#sub-}"
    this_ses="$(extract_session "$fname")"
    this_ses="${this_ses:-$ses}"
    case_name="sub-${sub}_ses-${this_ses}"

    subjroot="${outroot}/sub-${sub}/ses-${this_ses}"
    log="${outroot}/logs/${case_name}.log"
    seg="${subjroot}/002_Segmentations/003_postproc_fov/${case_name}.nii.gz"
    mkdir -p "$subjroot"

    if [[ ! -e "$flair" ]]; then
        append_summary "$sub" "$this_ses" "missing" "$flair" "$seg" "NA" "NA" "$log" "missing FLAIR"
        echo "[MISSING] ${case_name}: $flair"
        return 0
    fi

    if [[ "$overwrite" != "1" && -s "$seg" ]]; then
        read -r vox mm3 <<< "$(stats_for_seg "$seg")"
        append_summary "$sub" "$this_ses" "exists" "$flair" "$seg" "$vox" "$mm3" "$log" "set OVERWRITE=1 to rerun"
        echo "[EXISTS] ${case_name}: $seg"
        return 0
    fi

    runtime_args=()
    if [[ "$use_nv" == "1" ]]; then
        runtime_args+=(--nv)
    fi
    runtime_args+=(--bind "${bids_dir}:${bids_dir}")
    runtime_args+=(--bind "${maindir}:${maindir}")

    if [[ -n "${DEEPWMH_EXTRA_BINDS:-}" ]]; then
        IFS=',' read -r -a extra_binds <<< "$DEEPWMH_EXTRA_BINDS"
        for bind_path in "${extra_binds[@]}"; do
            [[ -n "$bind_path" ]] && runtime_args+=(--bind "$bind_path")
        done
    fi

    deepwmh_args=(
        DeepWMH_predict
        -i "$flair"
        -n "$case_name"
        -m /model
        -o "$subjroot"
        -g "$gpu"
    )
    if [[ "$skip_bfc" == "1" ]]; then
        deepwmh_args+=(--skip-bfc)
    fi

    echo "[RUN] ${case_name}"
    if "$runtime" exec "${runtime_args[@]}" "$deepwmh_image" "${deepwmh_args[@]}" > "$log" 2>&1; then
        if [[ -s "$seg" ]]; then
            read -r vox mm3 <<< "$(stats_for_seg "$seg")"
            status="ok"
            note=""
        else
            vox="NA"
            mm3="NA"
            status="failed"
            note="DeepWMH completed but final segmentation was not found"
        fi
    else
        vox="NA"
        mm3="NA"
        status="failed"
        note="DeepWMH command failed; inspect log"
    fi

    append_summary "$sub" "$this_ses" "$status" "$flair" "$seg" "$vox" "$mm3" "$log" "$note"
    echo "[${status^^}] ${case_name}"
}

wait_for_slot() {
    while [[ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$max_jobs" ]]; do
        sleep 5
    done
}

echo "DeepWMH image : $deepwmh_image"
echo "Runtime       : $runtime"
echo "Paths file    : $paths_file"
echo "Output root   : $outroot"
echo "Summary TSV   : $summary_tsv"
echo "GPU           : $gpu"
echo "MAX_JOBS      : $max_jobs"
echo

while IFS= read -r flair; do
    [[ -z "$flair" ]] && continue

    if [[ "$max_jobs" -gt 1 ]]; then
        wait_for_slot
        run_one "$flair" &
        sleep 1
    else
        run_one "$flair"
    fi
done < "$paths_file"

wait

echo
echo "Done."
echo "Summary TSV: $summary_tsv"
