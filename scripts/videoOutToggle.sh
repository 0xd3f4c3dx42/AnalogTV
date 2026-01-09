#!/usr/bin/env bash
set -euo pipefail

# HDMI <-> Composite toggle for Raspberry Pi 4
#
# File name (assumed):  ~/videoToggle.sh
#
# This version:
#   * Handles BOTH firmware and KMS desktop
#   * Edits config.txt and cmdline.txt
#   * When in composite mode:
#       - Enables composite output
#       - Forces KMS desktop onto Composite-1
#       - Explicitly disables HDMI-A-1 and HDMI-A-2
#   * Automatically reboots after switching (with a 10s countdown)
#
# Usage:
#   sudo ~/videoToggle.sh           # auto-toggle between HDMI/composite
#   sudo ~/videoToggle.sh status    # show current mode (no reboot)
#   sudo ~/videoToggle.sh hdmi      # force HDMI, then auto reboot
#   sudo ~/videoToggle.sh composite # force composite, then auto reboot
#
# NOTE: Reboot is required and will be triggered by this script.

# -----------------------------
# Settings you might want to change
# -----------------------------

# Region: default for US (NTSC). For PAL, use:
#   COMPOSITE_NORM="PAL"
#   COMPOSITE_VIDEO_ARG="video=Composite-1:720x576@50ie"
COMPOSITE_NORM="NTSC"
COMPOSITE_VIDEO_ARG="video=Composite-1:720x480@60ie"

# -----------------------------
# Ensure we are root
# -----------------------------

if [ "$EUID" -ne 0 ]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

# -----------------------------
# Locate config.txt and cmdline.txt
# -----------------------------

CONFIG_FILE=""
for path in /boot/firmware/config.txt /boot/config.txt; do
  if [ -f "$path" ]; then
    CONFIG_FILE="$path"
    break
  fi
done

if [ -z "$CONFIG_FILE" ]; then
  echo "ERROR: Could not find config.txt in /boot/firmware or /boot."
  exit 1
fi

CMDLINE_FILE=""
for path in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
  if [ -f "$path" ]; then
    CMDLINE_FILE="$path"
    break
  fi
done

if [ -z "$CMDLINE_FILE" ]; then
  echo "ERROR: Could not find cmdline.txt in /boot/firmware or /boot."
  exit 1
fi

# -----------------------------
# Helpers
# -----------------------------

backup_config() {
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  local cfg_bak="${CONFIG_FILE}.${stamp}.bak"
  local cmd_bak="${CMDLINE_FILE}.${stamp}.bak"
  cp "$CONFIG_FILE" "$cfg_bak"
  cp "$CMDLINE_FILE" "$cmd_bak"
  echo "Backups created:"
  echo "  $cfg_bak"
  echo "  $cmd_bak"
}

# Rough heuristic: if config/cmdline are set up for Composite-1 and tvout,
# we call that "composite" mode, otherwise "hdmi".
current_mode() {
  if grep -Eq '^[[:space:]]*enable_tvout[[:space:]]*=[[:space:]]*1[[:space:]]*$' "$CONFIG_FILE" \
     || grep -Eq '^[[:space:]]*dtoverlay=.*vc4-kms-v3d.*composite' "$CONFIG_FILE" \
     || grep -Eq 'video=Composite-1:' "$CMDLINE_FILE"; then
    echo "composite"
  else
    echo "hdmi"
  fi
}

# Ensure dtoverlay=vc4-kms-v3d line has ",composite"
ensure_kms_composite() {
  if grep -Eq '^[[:space:]]*dtoverlay=vc4-kms-v3d.*composite' "$CONFIG_FILE"; then
    return 0
  fi

  if grep -Eq '^[[:space:]]*dtoverlay=vc4-kms-v3d' "$CONFIG_FILE"; then
    # Add ",composite" to the existing line
    sed -i -E 's/^([[:space:]]*dtoverlay=vc4-kms-v3d[^#,\r\n]*)(.*)$/\1,composite\2/' "$CONFIG_FILE"
  else
    # No KMS overlay line found; append a basic one
    {
      echo ""
      echo "# KMS graphics driver with composite enabled (managed by videoToggle.sh)"
      echo "dtoverlay=vc4-kms-v3d,composite"
    } >> "$CONFIG_FILE"
  fi
}

# Remove ",composite" from any vc4-kms-v3d overlay lines
remove_kms_composite() {
  sed -i -E 's/^([[:space:]]*dtoverlay=vc4-kms-v3d[^#,\r\n]*),composite(=1)?(.*)$/\1\3/' "$CONFIG_FILE"
}

# Clean any composite-related bits from cmdline
cleanup_cmdline_composite_tokens() {
  sed -i -E \
    -e 's/ ?video=Composite-1:[^ ]*//g' \
    -e 's/ ?vc4\.tv_norm=[^ ]*//g' \
    -e 's/ ?video=HDMI-A-1:[^ ]*//g' \
    -e 's/ ?video=HDMI-A-2:[^ ]*//g' \
    -e 's/[[:space:]]+$//' \
    "$CMDLINE_FILE"
}

# Safely rewrite cmdline.txt as a single line with extra args appended
append_to_cmdline_single_line() {
  local extra_args="$1"

  # Read entire file into one line (remove newlines)
  local line
  line="$(tr -d '\n' < "$CMDLINE_FILE")"

  # Ensure there is exactly one space before extra args
  line="${line} ${extra_args}"

  # Trim trailing spaces and write back as a single line
  echo "$line" | sed -E 's/[[:space:]]+$//' > "$CMDLINE_FILE"
}

set_composite() {
  echo "Switching to COMPOSITE output (Pi 4)..."
  backup_config

  # 1) Firmware side: enable tvout + sdtv_* for early boot
  # Remove old lines first
  sed -i -E '/^[[:space:]]*#?[[:space:]]*enable_tvout[[:space:]]*=/d' "$CONFIG_FILE"
  sed -i -E '/^[[:space:]]*#?[[:space:]]*sdtv_mode[[:space:]]*=/d' "$CONFIG_FILE"
  sed -i -E '/^[[:space:]]*#?[[:space:]]*sdtv_aspect[[:space:]]*=/d' "$CONFIG_FILE"

  {
    echo ""
    echo "# --- Composite video settings (managed by videoToggle.sh) ---"
    echo "enable_tvout=1          # Enable composite (also slows clocks a tiny bit on Pi 4)"
    echo "sdtv_mode=0             # 0=NTSC, 2=PAL (change if needed)"
    echo "sdtv_aspect=1           # 1=4:3, 3=16:9"
  } >> "$CONFIG_FILE"

  # 2) KMS driver: make sure vc4-kms-v3d is in composite mode
  ensure_kms_composite

  # 3) cmdline: force desktop onto Composite-1 and disable HDMI connectors
  cleanup_cmdline_composite_tokens

  local extra="${COMPOSITE_VIDEO_ARG} vc4.tv_norm=${COMPOSITE_NORM} video=HDMI-A-1:d video=HDMI-A-2:d"
  append_to_cmdline_single_line "$extra"

  echo
  echo "Composite mode configured:"
  echo "  config:   $CONFIG_FILE"
  echo "  cmdline:  $CMDLINE_FILE"
  echo
  echo "After reboot, both boot and desktop should come out of COMPOSITE only."
}

set_hdmi() {
  echo "Switching to HDMI output..."
  backup_config

  # 1) Firmware: disable tvout / remove sdtv_* so HDMI behaves normally
  sed -i -E '/^[[:space:]]*#?[[:space:]]*enable_tvout[[:space:]]*=/d' "$CONFIG_FILE"
  sed -i -E '/^[[:space:]]*#?[[:space:]]*sdtv_mode[[:space:]]*=/d' "$CONFIG_FILE"
  sed -i -E '/^[[:space:]]*#?[[:space:]]*sdtv_aspect[[:space:]]*=/d' "$CONFIG_FILE"

  # 2) KMS overlay: remove ",composite" if present
  remove_kms_composite

  # 3) cmdline: drop composite & HDMI-disable tokens
  cleanup_cmdline_composite_tokens

  echo
  echo "HDMI mode configured:"
  echo "  config:   $CONFIG_FILE"
  echo "  cmdline:  $CMDLINE_FILE"
  echo
  echo "After reboot, boot + desktop will go back to HDMI."
}

# -----------------------------
# Argument parsing
# -----------------------------

ACTION="${1:-toggle}"

case "$ACTION" in
  status)
    echo "Using config:  $CONFIG_FILE"
    echo "Using cmdline: $CMDLINE_FILE"
    echo "Current mode:  $(current_mode)"
    exit 0
    ;;
  hdmi)
    TARGET="hdmi"
    ;;
  composite)
    TARGET="composite"
    ;;
  toggle)
    CURR="$(current_mode)"
    if [ "$CURR" = "composite" ]; then
      TARGET="hdmi"
    else
      TARGET="composite"
    fi
    ;;
  *)
    echo "Usage: $0 [hdmi|composite|toggle|status]"
    exit 1
    ;;
esac

echo "Using config:  $CONFIG_FILE"
echo "Using cmdline: $CMDLINE_FILE"
echo "Target mode:   $TARGET"
echo

if [ "$TARGET" = "composite" ]; then
  set_composite
else
  set_hdmi
fi

echo
echo "System will reboot in 10 seconds to apply the video mode change."
echo "Press Ctrl+C now to cancel the reboot."

sleep 10
reboot
