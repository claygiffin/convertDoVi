#!/bin/bash

INPUT="$1"
OUTPUT="$2"

if [[ -z "$INPUT" ]]; then
  echo "Usage: convertDoVi.sh input.mkv [optional_output.mp4]"
  exit 1
fi

# Skip non-.mkv files or macOS metadata files
if [[ "${INPUT##*.}" != "mkv" || "$(basename "$INPUT")" == ._* ]]; then
  echo "Skipping non-MKV or macOS metadata file: $INPUT"
  exit 0
fi

# Check for Dolby Vision
if ! ffmpeg -i "$INPUT" 2>&1 | grep -q "DOVI configuration record"; then
  echo "No Dolby Vision found in $INPUT — skipping"
  exit 0
fi

echo "Dolby Vision detected in $INPUT"

# Prepare paths
TMPDIR="/tmp/convert_dovi"
mkdir -p "$TMPDIR"

BASENAME="$(basename "$INPUT" .mkv)"
DEST_DIR="$(dirname "$INPUT")"
UNIQUE_ID=$(uuidgen | cut -d- -f1)

TMP_HEVC="$TMPDIR/${BASENAME}_${UNIQUE_ID}.hevc"
TMP_MP4="$TMPDIR/${BASENAME}_${UNIQUE_ID}_DoVi.mp4"

# Extract video stream
echo "Extracting video stream..."
ffmpeg -i "$INPUT" -map 0:v -c copy "$TMP_HEVC"

# Extract all audio streams
AUDIO_STREAMS=()
MUXER_INPUTS=()
NUM_AUDIO_STREAMS=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$INPUT" | wc -l)

for i in $(seq 0 $((NUM_AUDIO_STREAMS - 1))); do
  AUDIO_FILE="$TMPDIR/${BASENAME}_${UNIQUE_ID}_audio${i}.ec3"

  # Remember for cleanup
  AUDIO_STREAMS+=("$AUDIO_FILE")
  
  # Extract audio stream
  ffmpeg -i "$INPUT" -map 0:a:$i -c copy "$AUDIO_FILE"

  # Get language code for this stream
  LANG=$(ffprobe -v error -select_streams a:$i -show_entries stream_tags=language -of default=noprint_wrappers=1:nokey=1 "$INPUT")
  LANG=${LANG:-und} # fallback to "und" (undefined) if missing

  # Add to muxer input array
  MUXER_INPUTS+=("-i" "$AUDIO_FILE" "--media-lang" "$LANG")
done


# Mux to MP4
echo "Muxing into DoVi MP4..."
mp4muxer --dv-profile 5 -i "$TMP_HEVC" "${MUXER_INPUTS[@]}" -o "$TMP_MP4"

# Move to final location
if [[ -n "$OUTPUT" ]]; then
  echo "Moving final output to: $OUTPUT"
  mv "$TMP_MP4" "$OUTPUT"
else
  echo "Moving final output to original folder:"
  mv "$TMP_MP4" "$DEST_DIR/${BASENAME}.mp4"
fi

# Clean up
echo "Cleaning up temp files..."
rm -f "$TMP_HEVC"
for AUDIO_FILE in "${AUDIO_STREAMS[@]}"; do
  rm -f "$AUDIO_FILE"
done
