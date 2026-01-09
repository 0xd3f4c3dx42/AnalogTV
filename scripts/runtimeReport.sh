#!/usr/bin/env bash
set -euo pipefail

# runtimeReport.sh
# Summarize runtime of all video files per channel and overall
# under /mnt/analogtv/catalog/.

CATALOG_ROOT="/mnt/analogtv/catalog"

VIDEO_EXTENSIONS=("mkv" "mp4" "mov" "avi" "mpeg" "mpg")

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: ffprobe not found. Please install ffmpeg (e.g. 'sudo apt install ffmpeg')."
  exit 1
fi

if [ ! -d "$CATALOG_ROOT" ]; then
  echo "Error: Catalog root not found:"
  echo "  $CATALOG_ROOT"
  exit 1
fi

# Build the 'find' expression for the video extensions
build_find_expr() {
  local -n _out=$1
  _out=()
  for ext in "${VIDEO_EXTENSIONS[@]}"; do
    if [ "${#_out[@]}" -gt 0 ]; then
      _out+=("-o")
    fi
    _out+=("-iname" "*.${ext}")
  done
}

# Format seconds into human-readable like "12 days, 3 hours and 5 mins"
format_duration() {
  local total="$1"
  local days=$(( total / 86400 ))
  local hours=$(( (total % 86400) / 3600 ))
  local minutes=$(( (total % 3600) / 60 ))
  local seconds=$(( total % 60 ))

  local parts=()

  if (( days > 0 )); then
    if (( days == 1 )); then
      parts+=("1 day")
    else
      parts+=("$days days")
    fi
  fi

  if (( hours > 0 )); then
    if (( hours == 1 )); then
      parts+=("1 hour")
    else
      parts+=("$hours hours")
    fi
  fi

  if (( minutes > 0 )); then
    if (( minutes == 1 )); then
      parts+=("1 min")
    else
      parts+=("$minutes mins")
    fi
  fi

  if (( seconds > 0 )); then
    if (( seconds == 1 )); then
      parts+=("1 sec")
    else
      parts+=("$seconds secs")
    fi
  fi

  if ((${#parts[@]} == 0)); then
    echo "0 seconds"
    return
  fi

  if ((${#parts[@]} == 1)); then
    echo "${parts[0]}"
    return
  fi

  local last_index=$(( ${#parts[@]} - 1 ))
  local last="${parts[$last_index]}"
  unset 'parts[$last_index]'

  local joined=""
  if ((${#parts[@]} > 0)); then
    joined=$(IFS=", "; echo "${parts[*]}")
    echo "$joined and $last"
  else
    echo "$last"
  fi
}

shopt -s nullglob

echo "Scanning channels under:"
echo "  $CATALOG_ROOT"
echo

total_seconds_all=0
any_channel_found=0

build_find_expr find_expr

spinner_chars='-\|/'

for channel_dir in "$CATALOG_ROOT"/*/; do
  [ -d "$channel_dir" ] || continue

  any_channel_found=1
  channel_name=$(basename "$channel_dir")
  channel_seconds=0
  file_count=0

  echo "Scanning channel: $channel_name"

  while IFS= read -r -d '' file; do
    duration_raw=$(ffprobe -v error -show_entries format=duration \
                           -of default=noprint_wrappers=1:nokey=1 \
                           "$file" 2>/dev/null || echo "")

    if [ -z "$duration_raw" ]; then
      continue
    fi

    duration_sec=$(awk -v d="$duration_raw" 'BEGIN { printf "%.0f\n", d }')
    if (( duration_sec <= 0 )); then
      continue
    fi

    file_count=$((file_count + 1))
    channel_seconds=$((channel_seconds + duration_sec))

    # Simple spinner to indicate progress
    spinner_index=$(( file_count % 4 ))
    spinner_char=${spinner_chars:$spinner_index:1}
    printf "\r  Scanning files... %s" "$spinner_char"
  done < <(find "$channel_dir" -type f \( "${find_expr[@]}" \) -print0)

  # Finish spinner line cleanly
  if (( file_count > 0 )); then
    printf "\r  Scanning files... done\n"
  else
    # No files; ensure we don't leave a half-line
    echo "  No matching video files found for this channel."
    echo
    continue
  fi

  total_seconds_all=$((total_seconds_all + channel_seconds))
  human_channel=$(format_duration "$channel_seconds")
  echo "  Files counted: $file_count"
  echo "  Runtime for this channel: $human_channel"
  echo
done

if (( any_channel_found == 0 )); then
  echo "No channel folders found under:"
  echo "  $CATALOG_ROOT"
  exit 0
fi

if (( total_seconds_all == 0 )); then
  echo "No video files with extensions: ${VIDEO_EXTENSIONS[*]}"
  echo "found under:"
  echo "  $CATALOG_ROOT"
  exit 0
fi

echo "========================================"
echo " Overall total runtime for all channels"
echo "========================================"
human_total=$(format_duration "$total_seconds_all")
echo "$human_total of total content"
