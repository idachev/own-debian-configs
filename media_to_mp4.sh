#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT_ARG="${1%/}"
VID_EXT=${2}

if [ -z "${INPUT_ARG}" ]; then
  echo "Usage: $0 <file|directory> [video ext]"
  echo ""
  echo "Converts video files to MP4 (H.265 video + AAC audio)"
  echo ""
  echo "Supported formats: mp4, avi, mov, mkv, wmv, flv, m4v, webm, 3gp, mts (case insensitive)"
  echo "By default processes all supported formats. Specify ext to limit to one."
  echo ""
  echo "Environment variables:"
  echo "  VIDEO_CRF     - Video quality 0-51, lower=better (default: 28)"
  echo "  AUDIO_BITRATE - Audio bitrate in kbps (default: 128)"
  echo "  MAX_RES       - Max resolution height in pixels (default: no resize)"
  echo "                  e.g., MAX_RES=1080 limits to 1080p, MAX_RES=720 limits to 720p"
  echo "  STORE_HASH    - Store SHA512 of original in XMP metadata (default: 1)"
  echo "                  Set to 0 to disable. Useful for sync to detect already-converted files"
  echo "  TWO_PASS      - Set to 1 for two-pass encoding (better quality, slower)"
  echo ""
  echo "Required dependencies: ffmpeg, ffprobe, exiftool"
  echo ""
  echo "To check if a mp4 was converted from a specific file:"
  echo "  exiftool -XMP:OriginalDocumentID file.mp4"
  exit 1
fi

if [ ! -e "${INPUT_ARG}" ]; then
  echo "Error: '${INPUT_ARG}' does not exist"
  exit 1
fi

INPUT=$(realpath "${INPUT_ARG}")

# Defaults
if [ -z "${VIDEO_CRF}" ]; then
  VIDEO_CRF=28
fi

if [ -z "${AUDIO_BITRATE}" ]; then
  AUDIO_BITRATE=128
fi

if [ -z "${TWO_PASS}" ]; then
  TWO_PASS=0
fi

if [ -z "${STORE_HASH}" ]; then
  STORE_HASH=1
fi

# Check required dependencies
command -v ffmpeg >/dev/null 2>&1 || \
  { echo -e "ffmpeg is missing, please install it using:\nsudo apt-get install ffmpeg" && exit 1; }

command -v ffprobe >/dev/null 2>&1 || \
  { echo -e "ffprobe is missing, please install it using:\nsudo apt-get install ffmpeg" && exit 1; }

command -v exiftool >/dev/null 2>&1 || \
  { echo -e "exiftool is missing, please install it using:\nsudo apt-get install libimage-exiftool-perl" && exit 1; }

# Function to convert a single file
convert_file() {
  local file="$1"
  local dir=$(dirname "${file}")
  local ext="${file##*.}"
  local base_name=$(basename "${file}" ."${ext}")
  local output_file="${dir}/${base_name}.h265.mp4"
  local temp_file="${dir}/.tmp_convert_${base_name}.mp4"
  local passlog_file="${dir}/.tmp_passlog_${base_name}"

  # Skip if output already exists
  if [ -f "${output_file}" ]; then
    echo "Skipping ${file}: Output already exists"
    return 0
  fi

  echo "Processing ${file}"

  # Calculate SHA512 of original file before any processing (if requested)
  local original_hash=""
  if [ "${STORE_HASH}" = "1" ]; then
    original_hash=$(sha512sum "${file}" | cut -d' ' -f1)
  fi

  # Build ffmpeg filter for resize
  local vf_filter=""
  if [ -n "${MAX_RES}" ]; then
    # Scale to max height, maintain aspect ratio, ensure even dimensions
    vf_filter="-vf scale=-2:'min(${MAX_RES},ih)':flags=lanczos"
  fi

  # Build ffmpeg command
  # -movflags +faststart: optimize for web streaming
  # -map_metadata 0: copy metadata from input
  # -tag:v hvc1: compatibility tag for Apple devices
  local ffmpeg_common="-i \"${file}\" ${vf_filter} -c:v libx265 -crf ${VIDEO_CRF} -preset medium -c:a aac -b:a ${AUDIO_BITRATE}k -map_metadata 0 -movflags +faststart -tag:v hvc1"

  if [ "${TWO_PASS}" = "1" ]; then
    echo "  Pass 1/2..."
    eval ffmpeg -y -hide_banner -loglevel warning ${ffmpeg_common} -pass 1 -passlogfile "${passlog_file}" -f null /dev/null
    if [ $? -ne 0 ]; then
      echo "Error: Failed to encode ${file} (pass 1)"
      rm -f "${passlog_file}"* "${passlog_file}"-*.log "${passlog_file}"-*.log.mbtree 2>/dev/null
      return 1
    fi

    echo "  Pass 2/2..."
    eval ffmpeg -y -hide_banner -loglevel warning ${ffmpeg_common} -pass 2 -passlogfile "${passlog_file}" "${temp_file}"
    local result=$?
    rm -f "${passlog_file}"* "${passlog_file}"-*.log "${passlog_file}"-*.log.mbtree 2>/dev/null

    if [ ${result} -ne 0 ]; then
      echo "Error: Failed to encode ${file} (pass 2)"
      rm -f "${temp_file}"
      return 1
    fi
  else
    eval ffmpeg -y -hide_banner -loglevel warning ${ffmpeg_common} "${temp_file}"
    if [ $? -ne 0 ]; then
      echo "Error: Failed to encode ${file}"
      rm -f "${temp_file}"
      return 1
    fi
  fi

  # Copy all EXIF/metadata from original file to ensure nothing is lost
  exiftool -quiet -overwrite_original -TagsFromFile "${file}" -all:all "${temp_file}" 2>/dev/null

  # Store SHA512 hash in XMP metadata
  if [ -n "${original_hash}" ]; then
    exiftool -quiet -overwrite_original -XMP:OriginalDocumentID="sha512:${original_hash}" "${temp_file}"
  fi

  # Preserve original file modification timestamp
  touch -r "${file}" "${temp_file}"

  # Move temp to final destination
  mv "${temp_file}" "${output_file}"

  # Show size comparison
  local orig_size=$(stat -c%s "${file}")
  local new_size=$(stat -c%s "${output_file}")
  local ratio=$((new_size * 100 / orig_size))
  echo "  Done: ${ratio}% of original size ($(numfmt --to=iec ${orig_size}) -> $(numfmt --to=iec ${new_size}))"
}

if [ -f "${INPUT}" ]; then
  # Single file mode
  convert_file "${INPUT}"
else
  # Directory mode
  if [ -z "${VID_EXT}" ]; then
    VID_EXTENSIONS="mp4 avi mov mkv wmv flv m4v webm 3gp mts"
  else
    VID_EXTENSIONS="${VID_EXT}"
  fi

  found=false
  for ext in ${VID_EXTENSIONS}; do
    # Check both lowercase and uppercase extensions
    for file in "${INPUT}"/*."${ext}" "${INPUT}"/*."${ext^^}"; do
      [ -e "${file}" ] || continue
      found=true
      convert_file "${file}"
    done
  done

  if [ "${found}" = false ]; then
    echo "No video files found in ${INPUT}"
    echo "Supported formats: ${VID_EXTENSIONS}"
    exit 1
  fi
fi
