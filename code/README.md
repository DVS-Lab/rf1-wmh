# Code Directory

This directory contains the active WMH processing scripts and the small subject
lists/tables they use. The current active segmentation workflows are DeepWMH and
TrUE-Net. Brain-age/BAG scripts have been removed from the repository.

## DeepWMH Scripts

| File | Purpose |
| --- | --- |
| `deepwmh_all.sh` | Runs DeepWMH across a FLAIR path list using `/ZPOOL/data/tools/deepwmh_v1.0.1.sif`. It performs container preflight checks, runs one subject per path-list row, records per-subject logs, and writes a native-space WMH summary TSV. |
| `standardize_deepwmh_wmh_to_mni.sh` | Registers DeepWMH native-space binary segmentations to FSL 1 mm MNI space, writes subject-level standard-space segmentations, and merges them into a 4-D file in TSV row order. |

Typical DeepWMH usage:

```bash
cd /ZPOOL/data/projects/rf1-wmh
bash code/deepwmh_all.sh 02
SES=02 bash code/standardize_deepwmh_wmh_to_mni.sh code/h1_doors.tsv
```

## TrUE-Net Scripts

| File | Purpose |
| --- | --- |
| `preprocess.sh` | Prepares one subject/session for TrUE-Net using `prepare_truenet_data`. The script currently targets session `02` and falls back to session `01` T1w images for subjects `10590` and `10617`. |
| `run_preprocess.sh` | Batch wrapper around `preprocess.sh`. It reads `paths_FLAIR_ses-2_n20.txt`, extracts subject IDs, and runs preprocessing jobs with simple concurrency control. |
| `qc_and_merge_truenet_preprocess.sh` | Checks geometry of TrUE-Net preprocessed `T1`, `FLAIR`, and `WMmask` files, then attempts to merge each image type with `fslmerge`. |
| `truenet_all.sh` | Runs TrUE-Net evaluation for both `mwsc` and `ukbb` models, creates WM-masked probability maps when a subject WM mask is available, and writes a session `02` summary TSV. |
| `standardize_truenet_wmh_to_mni.sh` | Registers TrUE-Net probability maps to FSL 1 mm MNI space and writes both continuous probability maps and p > 0.5 binary maps. It can use either `ukbb` or `mwsc`, and either WM-masked or unmasked maps. |
| `merge_standardized_truenet_wmh_by_model_csv.sh` | Merges already-standardized TrUE-Net maps into model-specific 4-D files using subject order from CSV/TSV inputs. Defaults to `df_model1.csv` and `df_model5.csv`. |

Typical TrUE-Net usage:

```bash
cd /ZPOOL/data/projects/rf1-wmh
bash code/run_preprocess.sh
bash code/truenet_all.sh
SES=01 MODEL=ukbb PROB_KIND=WMmasked \
  bash code/standardize_truenet_wmh_to_mni.sh code/h1_doors.tsv
bash code/merge_standardized_truenet_wmh_by_model_csv.sh
```

## Analysis And QC Scripts

| File | Purpose |
| --- | --- |
| `correlate_wmh_summaries.py` | Compares DeepWMH native-space WMH volume against TrUE-Net summary volume columns, writing a matched-subject TSV and raw/log10 correlation table. |
| `wmh_age_qc.m` | MATLAB QC script for chronological-age relationships with TrUE-Net WMH summary volumes. This is not a brain-age/BAG script. |
| `Correlation_matrix.R` | Exploratory R script that reads `noddi-summary.csv`, selects numeric columns, computes a correlation matrix, and plots it with `corrplot`. |

## Subject Lists And Model Tables

| File | Purpose |
| --- | --- |
| `paths_FLAIR_ses-1_n303.txt` | Full paths to 303 session `01` FLAIR images. Used by DeepWMH and can be used by other session `01` workflows. |
| `paths_FLAIR_ses-2_n20.txt` | Full paths to 20 session `02` FLAIR images. Used by current TrUE-Net batch scripts and DeepWMH session `02`. |
| `paths_FLAIR_n236.txt` | Older FLAIR path list with 236 rows. Kept for provenance and possible comparison work. |
| `sublist_all.txt` | Subject list with 110 rows. Older helper list retained for provenance. |
| `sublist-new.txt` | Subject list with 28 rows. Older helper list retained for provenance. |
| `h1_doors.tsv` | TSV subject/order table for h1 doors analyses and standard-space 4-D merge order. |
| `df_model1.csv` | Model-specific subject/order CSV with behavioral/environmental columns and image paths for model 1 analyses. |
| `df_model5.csv` | Model-specific subject/order CSV with behavioral/environmental columns and image paths for model 5 analyses. |

## Common Environment Overrides

| Variable | Used by | Meaning |
| --- | --- | --- |
| `BIDS_DIR` | DeepWMH and standardization scripts | Source BIDS directory. Defaults to `/ZPOOL/data/projects/rf1-sra-linux2/bids`. |
| `SES` | Standardization scripts | Session to normalize or merge, usually `01` or `02`. |
| `OVERWRITE` | DeepWMH and standardization scripts | Set to `1` to recreate existing outputs. |
| `FAIL_ON_MISSING` | Standardization and merge scripts | Set to `0` to merge available outputs even when some rows are missing. |
| `MODEL` | TrUE-Net standardization/merge | TrUE-Net model, usually `ukbb` or `mwsc`. |
| `PROB_KIND` | TrUE-Net standardization/merge | Use `WMmasked` or `unmasked` TrUE-Net probability maps. |
| `DEEPWMH_GPU` | `deepwmh_all.sh` | GPU index passed to DeepWMH. |
| `STOP_ON_FAILURE` | `deepwmh_all.sh` | Set to `0` to continue after failed DeepWMH subjects. |
