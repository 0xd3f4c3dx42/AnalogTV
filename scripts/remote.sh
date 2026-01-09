#!/usr/bin/env bash
set -euo pipefail

echo "----------------------------------------"
echo "  AnalogTV – FLIRC Remote Setup"
echo "----------------------------------------"
echo

if ! command -v flirc_util >/dev/null 2>&1; then
  echo "Error: flirc_util not found. Please install the FLIRC tools first."
  exit 1
fi

program_nav_volume_home() {
  echo
  echo "Programming navigation / volume / home buttons."
  echo "Buttons will be recorded in this order:"
  echo "  1) mute"
  echo "  2) vol_down"
  echo "  3) vol_up"
  echo "  4) up"
  echo "  5) down"
  echo "  6) home"
  echo
  echo "Make sure the FLIRC receiver is plugged in and the remote is ready."
  read -rp "Press Enter to begin recording these buttons in order..." _

  flirc_util record mute
  flirc_util record vol_down
  flirc_util record vol_up
  flirc_util record up
  flirc_util record down
  flirc_util record home

  echo
  echo "Navigation / volume / home buttons recorded."
}

program_number_keys() {
  echo
  echo "Programming channel number buttons."
  echo "Buttons will be recorded in this order:"
  echo "  1  2  3  4  5  6  7  8  9  0"
  echo
  echo "Make sure the FLIRC receiver is plugged in and the remote is ready."
  read -rp "Press Enter to begin recording these number buttons in order..." _

  for key in 1 2 3 4 5 6 7 8 9 0; do
    echo
    echo "Recording remote button for key: $key"
    flirc_util record "$key"
  done

  echo
  echo "Number buttons 1–9 and 0 recorded."
}

clear_remote() {
  echo
  echo "WARNING: This will clear ALL FLIRC remote configuration."
  echo "This cannot be undone."
  echo
  read -rp "Are you sure you want to clear all FLIRC settings? [y/N] " ans
  case "${ans:-N}" in
    y|Y|yes|YES)
      echo "Clearing FLIRC configuration..."
      flirc_util format
      echo "FLIRC configuration cleared."
      ;;
    *)
      echo "Canceled. No changes made."
      ;;
  esac
}

while true; do
  echo
  echo "Remote control options:"
  echo "  1) Program navigation / volume / home buttons"
  echo "  2) Program channel number buttons (1–9, 0)"
  echo "  3) Clear all remote settings"
  echo "  0) Exit"
  echo

  read -rp "Enter choice [0-3]: " choice
  case "$choice" in
    1)
      program_nav_volume_home
      ;;
    2)
      program_number_keys
      ;;
    3)
      clear_remote
      ;;
    0|"")
      echo "Exiting remote setup."
      exit 0
      ;;
    *)
      echo "Invalid choice."
      ;;
  esac
done
