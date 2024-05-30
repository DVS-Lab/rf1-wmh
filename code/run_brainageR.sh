#!/bin/bash

# Define the file path to the sublist
#sublist_file="/ZPOOL/data/projects/sharedreward-aging/code/sublist-srndna.txt"

# Define the output directory
output_dir="/ZPOOL/data/projects/rf1-wmh/derivatives/brainageR/"

# Read each subject from the sublist file
#for sub in `cat /ZPOOL/data/projects/sharedreward-aging/code/sublist-srndna.txt` ; do
for sub in 107; do
  # Define the input path
  input_path="/ZPOOL/data/projects/rf1-wmh/derivatives/fmriprep/sub-${sub}_desc-preproc_T1w.nii"
  
  # Define the output path
  output_path="${output_dir}sub-${sub}_brainage_output.csv"

  # Run the brainageR command
  /ZPOOL/data/projects/rf1-wmh/brainageR/software/brainageR -f "${input_path}" -o "${output_path}"
done
