#!/usr/bin/env python3
import os
import shutil
import re

# Get all files in the current directory
files = os.listdir()

# Define the pattern
pattern = re.compile(r'.*_(\d{4})(\d{2})\d{2}.*\.\w+(\.\w+)?')

# Loop through all files
for file in files:
    # Check if file matches the format name_name_YYYYMMDD.ext
    match = pattern.match(file)
    if match:
        # Extract year and month
        year, month, ext = match.groups()

        # Create new directory path
        new_dir = os.path.join(year, year+month)

        # Create new directory if it doesn't exist
        if not os.path.exists(new_dir):
           os.makedirs(new_dir)

        # Move file to new directory
        shutil.move(file, new_dir)
        print('Move %s to %s' % (file, new_dir))

