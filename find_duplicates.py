#!/usr/bin/env python3
"""
General tool to find files in a target directory that already exist in other directories.
Reads from a duplicate file where duplicate groups are separated by empty lines.
Only includes files that actually exist on disk.

Usage:
    python3 find_duplicates.py <duplicate_file> <target_path> [output_file]

Arguments:
    duplicate_file - File containing duplicate groups separated by empty lines
    target_path    - Path prefix to filter (e.g., './primary/', '/home/user/data/')
    output_file    - Optional output file (default: duplicates_<target_basename>.txt)

Examples:
    python3 find_duplicates.py dup.out ./primary/
    python3 find_duplicates.py dup.out /home/user/backup/ my_duplicates.txt
"""

import os
import sys

def parse_duplicates(filepath, target_path):
    """Parse the duplicate file and extract target files that have duplicates in other directories."""
    target_duplicates = []
    skipped_count = 0
    other_dirs = set()

    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # Normalize target path
    target_path = target_path.rstrip('/')
    if not target_path.endswith('/'):
        target_path += '/'

    # Group lines by duplicate sets (separated by empty lines)
    current_group = []

    for line in lines:
        path = line.strip()

        if path:  # Non-empty line
            current_group.append(path)
        else:  # Empty line - end of group
            if current_group:
                # Process the current group
                target_files = [p for p in current_group if p.startswith(target_path)]
                other_files = [p for p in current_group if not p.startswith(target_path)]

                # Track which directories are being compared
                for of in other_files:
                    if of.startswith('/') or of.startswith('./'):
                        # Extract the base directory
                        parts = of.split('/')
                        if len(parts) >= 3:
                            if of.startswith('./'):
                                base_dir = '/'.join(parts[:3])
                            else:
                                base_dir = '/'.join(parts[:4]) if len(parts) >= 4 else '/'.join(parts[:3])
                            other_dirs.add(base_dir)

                if other_files and target_files:
                    # Check if at least one other file exists
                    other_exists = any(os.path.exists(p) for p in other_files)

                    if other_exists:
                        # Only include target files that actually exist
                        for tf in target_files:
                            if os.path.exists(tf):
                                target_duplicates.append(tf)
                            else:
                                skipped_count += 1

                # Reset for next group
                current_group = []

    # Process last group if exists
    if current_group:
        target_files = [p for p in current_group if p.startswith(target_path)]
        other_files = [p for p in current_group if not p.startswith(target_path)]

        for of in other_files:
            if of.startswith('/') or of.startswith('./'):
                parts = of.split('/')
                if len(parts) >= 3:
                    if of.startswith('./'):
                        base_dir = '/'.join(parts[:3])
                    else:
                        base_dir = '/'.join(parts[:4]) if len(parts) >= 4 else '/'.join(parts[:3])
                    other_dirs.add(base_dir)

        if other_files and target_files:
            other_exists = any(os.path.exists(p) for p in other_files)

            if other_exists:
                for tf in target_files:
                    if os.path.exists(tf):
                        target_duplicates.append(tf)
                    else:
                        skipped_count += 1

    return target_duplicates, skipped_count, sorted(other_dirs)


def main():
    # Check arguments
    if len(sys.argv) < 3:
        print(__doc__)
        print("\nError: Missing required arguments")
        print("Usage: python3 find_duplicates.py <duplicate_file> <target_path> [output_file]")
        sys.exit(1)

    input_file = sys.argv[1]
    target_path = sys.argv[2]

    # Generate output filename
    if len(sys.argv) > 3:
        output_file = sys.argv[3]
    else:
        # Extract basename from target path for output filename
        target_basename = os.path.basename(target_path.rstrip('/'))
        if not target_basename:
            target_basename = 'target'
        output_file = f'duplicates_{target_basename}.txt'

    try:
        duplicates, skipped, other_dirs = parse_duplicates(input_file, target_path)

        # Write results to file
        with open(output_file, 'w', encoding='utf-8') as f:
            for path in duplicates:
                f.write(path + '\n')

        print(f"Target path: {target_path}")
        print(f"Found {len(duplicates)} files in '{target_path}' that have duplicates")
        print(f"Skipped {skipped} files that don't exist on disk")
        print(f"\nDetected comparison with these directories:")
        for d in other_dirs:
            print(f"  - {d}")
        print(f"\nResults written to: {output_file}")

        # Also print first 20 and last 20 to console
        if duplicates:
            print(f"\nFirst 20 files from '{target_path}' that have duplicates:")
            print("=" * 80)
            for path in duplicates[:20]:
                print(path)

            if len(duplicates) > 40:
                print("\n... ({} more files) ...\n".format(len(duplicates) - 40))
                print("Last 20 files:")
                print("=" * 80)
                for path in duplicates[-20:]:
                    print(path)

    except FileNotFoundError:
        print(f"Error: {input_file} not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
