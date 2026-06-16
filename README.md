# rf1-wmh

White matter hyperintensity analysis code for the RF1 project.

This repository currently supports two WMH segmentation workflows:

- `DeepWMH`, run from the project Apptainer/Singularity image.
- `TrUE-Net`, retained as the existing comparison workflow.

The older brain-age/BAG workflow has been removed. That included the vendored
`brainageR` software, DeepBrainNet wrapper scripts, generated brain-age outputs,
and exploratory BAG analysis code. Those outputs were not trusted enough to keep
as an active project path.

## Repository Layout

```text
code/          Shell, R, and MATLAB scripts plus path/model subject lists.
derivatives/   Small tracked tabular summaries used by the scripts.
LICENSE        Repository license.
```

Generated NIfTI outputs are ignored by Git. The expected working location on the
Linux analysis host is:

```text
/ZPOOL/data/projects/rf1-wmh
```

Most scripts assume the source BIDS data live at:

```text
/ZPOOL/data/projects/rf1-sra-linux2/bids
```

See `code/README.md` for a file-by-file description of the scripts and tables.

## Requirements

The shell scripts assume a Linux environment with the relevant neuroimaging
tools available on `PATH`.

DeepWMH requires:

- Apptainer or Singularity.
- The DeepWMH SIF image at `/ZPOOL/data/tools/deepwmh_v1.0.1.sif`.
- GPU support if running with the default `DEEPWMH_GPU=0` setting.

TrUE-Net and standardization scripts require:

- FSL commands such as `fslmaths`, `fslstats`, `fslmerge`, `fslinfo`, `flirt`,
  `convert_xfm`, and `bet`.
- TrUE-Net commands such as `prepare_truenet_data` and `truenet`.
- A TrUE-Net environment where `TRUENET_PRETRAINED_MODEL_PATH` resolves to the
  pretrained models.

## DeepWMH

Run DeepWMH from the Apptainer/Singularity image:

```bash
cd /ZPOOL/data/projects/rf1-wmh
bash code/deepwmh_all.sh 02
```

The first argument is the session, currently `01` or `02`. The script
automatically chooses the matching FLAIR path list:

- Session `01`: `code/paths_FLAIR_ses-1_n303.txt`
- Session `02`: `code/paths_FLAIR_ses-2_n20.txt`

You can pass a custom path list as the second argument:

```bash
bash code/deepwmh_all.sh 01 code/paths_FLAIR_ses-1_n303.txt
```

Useful overrides:

```bash
DEEPWMH_GPU=1 bash code/deepwmh_all.sh 02
DEEPWMH_SKIP_BFC=1 bash code/deepwmh_all.sh 02
MAX_JOBS=2 bash code/deepwmh_all.sh 02
OVERWRITE=1 bash code/deepwmh_all.sh 02
STOP_ON_FAILURE=0 bash code/deepwmh_all.sh 02
APPTAINER_CLEANENV=0 bash code/deepwmh_all.sh 02
DEEPWMH_WRITABLE_TMPFS=0 bash code/deepwmh_all.sh 02
```

By default the script uses `apptainer exec --cleanenv --nv --writable-tmpfs`,
runs container dependency checks before the subject loop, stops after the first
failed subject, and prints the last 80 lines of the relevant log. Writable tmpfs
is enabled because nnU-Net writes runtime logs beneath `/model`, which is
otherwise read-only in a SIF image.

Logs live in:

```text
derivatives/deepwmh/logs/
```

The final native-space binary WMH segmentation for each subject is:

```text
derivatives/deepwmh/sub-<ID>/ses-<SES>/002_Segmentations/003_postproc_fov/sub-<ID>_ses-<SES>.nii.gz
```

A batch summary with native-space WMH volume is written to:

```text
derivatives/deepwmh/deepwmh-summary_ses-<SES>.tsv
```

Normalize DeepWMH segmentations to 1 mm MNI space and merge them in TSV row
order:

```bash
cd /ZPOOL/data/projects/rf1-wmh
SES=01 bash code/standardize_deepwmh_wmh_to_mni.sh code/h1_doors.tsv
```

The merged 4-D standard-space file and manifest are written under:

```text
derivatives/deepwmh/merged/
```

## TrUE-Net

The TrUE-Net workflow is still present and unchanged in spirit. It has three
main phases:

1. Preprocess T1w and FLAIR images for TrUE-Net:

```bash
cd /ZPOOL/data/projects/rf1-wmh
bash code/run_preprocess.sh
```

2. Run both TrUE-Net pretrained models and summarize native-space WMH volume:

```bash
bash code/truenet_all.sh
```

3. Normalize TrUE-Net WMH probability maps to 1 mm MNI space:

```bash
SES=01 MODEL=ukbb PROB_KIND=WMmasked \
  bash code/standardize_truenet_wmh_to_mni.sh code/h1_doors.tsv
```

The TrUE-Net evaluation summaries tracked in this repo are under:

```text
derivatives/truenet-evaluate*/
```

## Group Merges

The standardization scripts create 4-D files in the row order of the input
subject table. This is important for downstream model fitting.

For TrUE-Net maps that have already been standardized, use:

```bash
bash code/merge_standardized_truenet_wmh_by_model_csv.sh
```

By default that script reads:

- `code/df_model1.csv`
- `code/df_model5.csv`

## Summary Correlations

After DeepWMH and TrUE-Net have both been run for a session, compare the
native-space WMH summary volumes:

```bash
python3 code/correlate_wmh_summaries.py --ses 02
```

By default this correlates `derivatives/deepwmh/deepwmh-summary_ses-02.tsv`
against `derivatives/truenet-evaluate/truenet-summary_ses-02.tsv`, using the
DeepWMH `mm3` column and all TrUE-Net `*_mm3` columns. Outputs are written to:

```text
derivatives/wmh-correlations/
```

## Notes

- `code/h1_doors.tsv`, `code/df_model1.csv`, and `code/df_model5.csv` are
  subject/order tables for downstream group analyses.
- `code/wmh_age_qc.m` is retained because it evaluates chronological age
  relationships with WMH summaries, not brain-age/BAG estimates.
- Brain-age/BAG outputs should not be regenerated into this repository unless
  that workflow is rebuilt and validated separately.
