
#!/bin/bash

# Define the file path to the sublist
#sublist_file="/ZPOOL/data/projects/sharedreward-aging/code/sublist-srndna.txt"

# Define the output directory
output_dir="/ZPOOL/data/projects/rf1-wmh/derivatives/brainageR/"

# Define the final output CSV file
final_output_file="${output_dir}compiled_brainage_output.csv"

# Empty the final output CSV file if it already exists
> "${final_output_file}"

# Read each subject from the sublist file
for sub in `cat /ZPOOL/data/projects/sharedreward-aging/code/sublist-srndna.txt` ; do
#for sub in 107; do
  # Define the input path
  input_path="/ZPOOL/data/projects/rf1-wmh/derivatives/fmriprep/sub-${sub}_desc-preproc_T1w.nii"
  
  # Define the output path
  output_path="${output_dir}sub-${sub}_brainage_output.csv"

  # Run the brainageR command
  /ZPOOL/data/projects/rf1-wmh/brainageR/software/brainageR -f "${input_path}" -o "${output_path}"
  
  # Append the content of the output file to the final output CSV file
  # Assuming the first file has the header, this will skip the header for subsequent files
  if [ ! -s "${final_output_file}" ]; then
    cat "${output_path}" >> "${final_output_file}"
  else
    tail -n +2 "${output_path}" >> "${final_output_file}"
  fi
done
