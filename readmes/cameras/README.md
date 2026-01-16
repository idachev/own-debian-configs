# Build Files DB

First we build the Files DB from a directory where we have 
all desired and structured sub dirs and file names.

The command is:
```bash
files_db.py -t 4 -db ./source
```

It makes the DB files and cache files in a subdirectory by default `./source/.working`

After we have the DB build we can reorganize any directory to match 
the saved file structure. This will move and rename files. 

All files for which we do not have info in the DB will be moved in a subdirectory: `.working/.check`

All duplicate files will be moved to: `.working/.recycle`

The command is:
```bash
files_db.py -t 4 -root ./source ./target
```

The `./source` is the directory where we have a DB info in `./source/.working/...`

The `./target` is the directory which will be modified to match the structure.

# Media Info 

To check which camera was used we can execute this command on an image or video file:
```bash
exiftool -a -u -g1 source.jpg
```

Or from `~/bin/` scripts:
```bash
media_info.sh source.jpg
```

> Know that not all video formats are keeping a meta info for the camera that was used. 

These are some cameras been used in my collection:
* CannonI750 - This should be from Alex
* CannonA540 - This should be from Kneja
* CannonSD780 - This is the small one in Sofia 
* SamsungSL30 - This is the other one in Sofia
* PentaxK100DS - This is the big one in Sofia Pentax K100D Super

# Rename Media

When we rename the images we use this:
```bash
media_rename.sh jpg
```

For `*.mov` files:
```bash
media_rename.sh mov
```

For `*.mov` files from CannonSD780 I put a time offset fix +3.
This could be checked from the `*.thm` files timestamps.

For `*.jpg` we do not need to fix the offset.

For rename photos from Nexus only this, as the file name already contains timestamp:
```bash
rename -n -vf 'y/A-Z/a-z/' *
```

# Directory Naming

For naming convention of the directory and easy sorting we do this:

`YYYY-MM-Location-Tag-Tag-...-CameraModel`

Examples:
* 2011-01-Sofia-Lego-Pentax
* 2010-09-Sofia-Sevdalina-CannonI750
* 2010-09-Kneja-Naves-CannonA540
* 2010-09-Sofia-Sevdalina-Produced-Flip

Each year has its own separate folder.

# Deleted Media Files

To keep info about deleted media files we move them to `Trash`.

After that all files from `Trash` are moved to normal directory, 
and we use other script to index them and store their hashes.

After we index them we can safely delete the files.

To add to deleted files DB use this:
```bash
deleted_files_db.py -db --deleted-files-db=./cameras/.working/deleted_files.db ./files_for_delete_dir
```

To mark for actual delete from another folder:
```bash
deleted_files_db.py -del --deleted-files-db=./cameras/.working/deleted_files.db ./files_in_folder
```

It will move all files for delete in a folder: `.to-delete`

The actual delete should be executed by you after double-check.

# Duplicate Images

For finding duplicate images by content similarity we use this:
```bash
czkawka_cli image -d ./dir1 ./dir2
```

# Copy Media File Metadata

Use this to copy media file metadata:
```bash
media_copy_info.sh ./source.jpg ./target.jpg
```

# Convert to WebP

Convert images to WebP format with optional resize and metadata preservation.

**Dependencies:** `cwebp`, `convert` (ImageMagick), `exiftool`

```bash
# Install dependencies
sudo apt-get install webp imagemagick libimage-exiftool-perl
```

## Basic Conversion

```bash
# Convert single file
media_to_webp.sh image.jpg

# Convert all images in directory
media_to_webp.sh ./photos
```

## With Resize (for document photos)

```bash
# Resize longest side to 2048px and convert
MAX_SIZE=2048 media_to_webp.sh ./photos

# Custom quality (0-100, default: 75)
MAX_SIZE=2048 WEBP_QUALITY=85 media_to_webp.sh ./photos

# Parallel processing (8 concurrent conversions)
PARALLEL=8 MAX_SIZE=2048 media_to_webp.sh ./photos
```

## With Hash Storage (for sync detection)

```bash
# Store SHA512 of original in webp metadata
STORE_HASH=1 MAX_SIZE=2048 media_to_webp.sh ./photos

# Check stored hash
exiftool -XMP:OriginalDocumentID image.webp
```

## Rotate WebP

Rotate webp images while preserving EXIF metadata and timestamp.

```bash
# Rotate 90, 180, or 270 degrees clockwise
media_rotate_webp.sh image.webp 90
media_rotate_webp.sh image.webp 180
media_rotate_webp.sh image.webp 270

# Custom quality
WEBP_QUALITY=85 media_rotate_webp.sh image.webp 90
```

## Cleanup Converted Originals

Safely move original files to `./for-cleanup` after verifying they were converted.

Only moves files where:
1. Matching `.webp` file exists
2. SHA512 hash matches the hash stored in webp metadata

```bash
# Dry run first (recommended)
DRY_RUN=1 media_cleanup_converted.sh ./photos

# Actually move verified originals
media_cleanup_converted.sh ./photos
```

Files are moved to `./photos/for-cleanup/` - review before deleting.

# Video Tips

To convert `*.mov` from Cannon we use these settings for Any Video Converter.

Video:
* xvid
* 640x480
* 1024 bitrate
* 25 frames

Audio:
* mp3
* 128 bitrate
* 44100
* 1 audio channel

For WM9:
* 640x480 -> 320x240 WM9 1024bprs
* 1280x720 -> 480x272 WM9 1024bps