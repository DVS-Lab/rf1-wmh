# rf1-wmh

White matter hyperintensity analyses for the RF1 grant.

## DeepWMH workflow

The DeepWMH scripts live beside the existing TrUE-Net scripts and do not change
the TrUE-Net workflow.

Run DeepWMH from the Apptainer/Singularity image:

```bash
cd /path/to/rf1-wmh

bash code/deepwmh_all.sh 02
```

The script uses `/ZPOOL/data/tools/deepwmh_v1.0.1.sif` and automatically picks
the matching FLAIR path list for sessions 01 and 02. You can also pass a custom
path list as the second argument.

Useful overrides:

```bash
DEEPWMH_GPU=1 bash code/deepwmh_all.sh 02
DEEPWMH_SKIP_BFC=1 bash code/deepwmh_all.sh 02
OVERWRITE=1 bash code/deepwmh_all.sh 02
STOP_ON_FAILURE=0 bash code/deepwmh_all.sh 02
APPTAINER_CLEANENV=0 bash code/deepwmh_all.sh 02
bash code/deepwmh_all.sh 01 code/paths_FLAIR_ses-1_n303.txt
```

By default the script uses `apptainer --cleanenv`, runs container dependency
checks before the subject loop, stops after the first failed subject, and prints
the last 80 lines of the relevant log. Per-subject and preflight logs live in:

```text
derivatives/deepwmh/logs/
```

The script runs the SIF through `apptainer run` so it uses the image entrypoint.
If needed, the older explicit-command behavior is available with:

```bash
DEEPWMH_APPTAINER_MODE=exec bash code/deepwmh_all.sh 02
```

DeepWMH outputs are written to:

```text
derivatives/deepwmh/sub-<ID>/ses-<SES>/
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
cd /path/to/rf1-wmh

SES=01 bash code/standardize_deepwmh_wmh_to_mni.sh code/h1_doors.tsv
```

The merged 4-D standard-space file and manifest are written under:

```text
derivatives/deepwmh/merged/
```
