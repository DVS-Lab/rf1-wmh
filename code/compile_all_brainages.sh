#!/bin/bash

# Define the directory containing the derived BrainAges
input_dir="/ZPOOL/data/projects/rf1-wmh/derivatives/brainageR"

# Define the output .csv
output_file="${input_dir}/compiled_brainage_output_test.csv"

# Check if the output file already exists; if so, delete it to start fresh
if [ -f "$output_file" ]; then
    rm "$output_file"
fi

# Initialize a variable to track whether the header has been written
header_written=false

# Loop through each CSV file that begins with "sub" in the specified directory
for csv_file in "${input_dir}/sub"*.csv; do
    # Check if the file is not the output file
    if [[ "$csv_file" != "$output_file" ]]; then
        # Read each CSV file
        while IFS= read -r line; do
            # If header has not been written, write it and set the flag
            if ! $header_written; then
                echo "$line" >> "$output_file"
                header_written=true
            else
                # Skip the header line of each CSV file
                if [[ "$line" != "File,brain.predicted_age,lower.CI,upper.CI" ]]; then
                    echo "$line" >> "$output_file"
                fi
            fi
        done < "$csv_file"
    fi
done

echo "Compilation of CSV files is complete. Output saved to $output_file."
