#!/usr/bin/env bash
set -euo pipefail

echo "----------------------------------------"
echo "  AnalogTV / FieldStation42 - Scheduler"
echo "----------------------------------------"

# Fixed locations
PROJECT_DIR="/home/analog/FieldStation42"
REMOTE_SCRIPT="$PROJECT_DIR/scripts/remote.sh"
WIFI_SCRIPT="$PROJECT_DIR/scripts/wifi-setup.sh"
RUNTIME_SCRIPT="$PROJECT_DIR/scripts/runtimeReport.sh"
USB_BASE="/mnt/analogtv"
USB_CONFS="$USB_BASE/confs"
USB_CATALOG="$USB_BASE/catalog"
USB_SCRIPTS="$USB_BASE/scripts"
LOG_DIR="$PROJECT_DIR/logs"
TEMPLATES_DIR="/home/analog/Templates"

if [ ! -f "$PROJECT_DIR/station_42.py" ]; then
  echo "Error: station_42.py not found in:"
  echo "  $PROJECT_DIR"
  exit 1
fi

mkdir -p "$LOG_DIR"

SYMLINK_ISSUE=0

check_usb_mount() {
  if [ ! -d "$USB_BASE" ]; then
    echo "WARNING: AnalogTV drive not detected at:"
    echo "  $USB_BASE"
    exit 1
  fi
}

check_usb_dirs() {
  local missing=()
  local need_confs=0
  local need_catalog=0
  local need_scripts=0

  if [ ! -d "$USB_CONFS" ]; then
    missing+=("confs ($USB_CONFS)")
    need_confs=1
  fi
  if [ ! -d "$USB_CATALOG" ]; then
    missing+=("catalog ($USB_CATALOG)")
    need_catalog=1
  fi
  if [ ! -d "$USB_SCRIPTS" ]; then
    missing+=("scripts ($USB_SCRIPTS)")
    need_scripts=1
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "WARNING: The following expected directories are missing on the AnalogTV drive:"
    for m in "${missing[@]}"; do
      echo "  - $m"
    done
    echo
    echo "These folders can be created from templates in:"
    echo "  $TEMPLATES_DIR"
    echo
    read -rp "Create missing folders from templates now? [y/N] " ans
    case "${ans:-N}" in
      y|Y|yes|YES)
        if [ ! -d "$TEMPLATES_DIR" ]; then
          echo "Error: Templates directory not found at:"
          echo "  $TEMPLATES_DIR"
          echo "Cannot create missing folders automatically."
          exit 1
        fi

        local src dest

        if [ $need_confs -eq 1 ]; then
          src="$TEMPLATES_DIR/confs"
          dest="$USB_CONFS"
          if [ ! -d "$src" ]; then
            echo "Error: Template 'confs' folder not found at:"
            echo "  $src"
          else
            echo "Copying template 'confs' -> $dest"
            sudo cp -r "$src" "$dest"
          fi
        fi

        if [ $need_catalog -eq 1 ]; then
          src="$TEMPLATES_DIR/catalog"
          dest="$USB_CATALOG"
          if [ ! -d "$src" ]; then
            echo "Error: Template 'catalog' folder not found at:"
            echo "  $src"
          else
            echo "Copying template 'catalog' -> $dest"
            sudo cp -r "$src" "$dest"
          fi
        fi

        if [ $need_scripts -eq 1 ]; then
          src="$TEMPLATES_DIR/scripts"
          dest="$USB_SCRIPTS"
          if [ ! -d "$src" ]; then
            echo "Error: Template 'scripts' folder not found at:"
            echo "  $src"
          else
            echo "Copying template 'scripts' -> $dest"
            sudo cp -r "$src" "$dest"
          fi
        fi

        # Re-check after copy
        local still_missing=()
        if [ ! -d "$USB_CONFS" ]; then still_missing+=("$USB_CONFS"); fi
        if [ ! -d "$USB_CATALOG" ]; then still_missing+=("$USB_CATALOG"); fi
        if [ ! -d "$USB_SCRIPTS" ]; then still_missing+=("$USB_SCRIPTS"); fi

        if [ "${#still_missing[@]}" -gt 0 ]; then
          echo
          echo "Error: Some expected directories are still missing after template copy:"
          for d in "${still_missing[@]}"; do
            echo "  - $d"
          done
          echo "Please check the drive and templates, then run AnalogTV again."
          exit 1
        fi

        echo
        echo "Missing AnalogTV directories created from templates."
        ;;

      *)
        echo "Cannot continue without these directories."
        echo "Please prepare the AnalogTV drive and run AnalogTV again."
        exit 1
        ;;
    esac
  fi
}

normalize_path() {
  local p="$1"
  while [[ "$p" != "/" && "$p" == */ ]]; do
    p="${p%/}"
  done
  echo "$p"
}

# Detection-only: mark issues, do not exit
ensure_symlink() {
  local link_path="$1"
  local target="$2"
  local name="$3"

  if [ -L "$link_path" ]; then
    local current_target
    current_target="$(readlink "$link_path")"

    local current_norm
    local target_norm
    current_norm="$(normalize_path "$current_target")"
    target_norm="$(normalize_path "$target")"

    if [ "$current_norm" = "$target_norm" ]; then
      echo "$name symlink OK: $link_path -> $current_target"
    else
      echo "WARNING: $name symlink points to:"
      echo "  $current_target"
      echo "but expected:"
      echo "  $target"
      echo "This will be fixed if you choose the symlink repair option."
      SYMLINK_ISSUE=1
    fi
  elif [ -e "$link_path" ]; then
    echo "WARNING: '$link_path' exists but is not a symlink."
    echo "This will be replaced by the symlink repair option."
    SYMLINK_ISSUE=1
  else
    echo "WARNING: $name symlink not found at $link_path."
    echo "It will be created by the symlink repair option."
    SYMLINK_ISSUE=1
  fi
}

fix_symlinks() {
  echo
  echo "Fixing confs, catalog, and scripts symlinks in $PROJECT_DIR"
  for spec in \
    "confs:$USB_CONFS" \
    "catalog:$USB_CATALOG" \
    "scripts:$USB_SCRIPTS"
  do
    local name="${spec%%:*}"
    local target="${spec#*:}"
    local link_path="$PROJECT_DIR/$name"

    if [ -L "$link_path" ]; then
      local current_target
      current_target="$(readlink "$link_path")"
      if [ "$(normalize_path "$current_target")" != "$(normalize_path "$target")" ]; then
        echo "Updating $name symlink: $link_path -> $target"
        rm "$link_path"
        ln -s "$target" "$link_path"
      else
        echo "$name symlink already correct: $link_path -> $current_target"
      fi
    elif [ -e "$link_path" ]; then
      echo "Removing non-symlink $link_path and recreating as symlink -> $target"
      rm -rf "$link_path"
      ln -s "$target" "$link_path"
    else
      echo "Creating missing $name symlink: $link_path -> $target"
      ln -s "$target" "$link_path"
    fi
  done
  echo "Symlink repair complete."
}

program_remote() {
  echo
  echo "Launching remote control options (FLIRC)..."
  echo "Note: this is interactive. Do not close the terminal until it finishes."
  echo

  if [ ! -f "$REMOTE_SCRIPT" ]; then
    echo "remote.sh not found at:"
    echo "  $REMOTE_SCRIPT"
    echo "Expected path: /home/analog/FieldStation42/scripts/remote.sh"
    return 1
  fi

  if [ ! -x "$REMOTE_SCRIPT" ]; then
    echo "remote.sh is not executable. Making it executable."
    chmod +x "$REMOTE_SCRIPT" || {
      echo "Failed to chmod +x remote.sh"
      return 1
    }
  fi

  "$REMOTE_SCRIPT"
}

wifi_setup() {
  echo
  echo "Launching Wi-Fi setup..."
  echo

  if [ ! -f "$WIFI_SCRIPT" ]; then
    echo "wifi-setup.sh not found at:"
    echo "  $WIFI_SCRIPT"
    echo "Expected path: /home/analog/FieldStation42/scripts/wifi-setup.sh"
    return 1
  fi

  if [ "$(id -u)" -ne 0 ]; then
    echo "Running wifi-setup with sudo (root required for Wi-Fi configuration)..."
    sudo "$WIFI_SCRIPT"
  else
    "$WIFI_SCRIPT"
  fi
}

runtime_report() {
  echo
  echo "Running total playtime scan for all channels..."
  echo

  if [ ! -f "$RUNTIME_SCRIPT" ]; then
    echo "runtimeReport.sh not found at:"
    echo "  $RUNTIME_SCRIPT"
    echo "Expected path: /home/analog/FieldStation42/scripts/runtimeReport.sh"
    return 1
  fi

  if [ ! -x "$RUNTIME_SCRIPT" ]; then
    echo "runtimeReport.sh is not executable. Making it executable."
    chmod +x "$RUNTIME_SCRIPT" || {
      echo "Failed to chmod +x runtimeReport.sh"
      return 1
    }
  fi

  "$RUNTIME_SCRIPT"
}

run_in_background() {
  local desc="$1"
  shift
  local cmds=("$@")

  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local logfile="$LOG_DIR/AnalogTV_${ts}.log"

  echo
  echo "Starting job:"
  echo "  $desc"
  echo "Log file:"
  echo "  $logfile"
  echo
  echo "Live log output (you can close this window; the job will continue):"
  echo "------------------------------------------------------------------"

  (
    trap '' HUP INT
    cd "$PROJECT_DIR" || exit 1
    {
      echo "[$(date)] AnalogTV job started: $desc"
      for cmd in "${cmds[@]}"; do
        echo "[$(date)] Running: $cmd"
        eval "$cmd"
        status=$?
        echo "[$(date)] Finished: $cmd (exit=$status)"
        if [ $status -ne 0 ]; then
          echo "[$(date)] Command failed, stopping job."
          exit $status
        fi
      done
      echo "[$(date)] AnalogTV job completed: $desc"
    } >>"$logfile" 2>&1
  ) &
  local worker_pid=$!

  tail -f "$logfile" &
  local tail_pid=$!

  wait "$worker_pid" 2>/dev/null || true
  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true

  echo "------------------------------------------------------------------"
  echo "Job finished: $desc"
  echo "Full log stored at: $logfile"
}

schedule_options_menu() {
  echo
  echo "Schedule options:"
  echo "  1) Add a day to the schedule"
  echo "  2) Add a week to the schedule"
  echo "  3) Add a month to the schedule"
  echo "  0) Back / cancel"
  echo

  read -rp "Enter choice [0-3]: " schoice
  local desc=""
  local cmds=()

  case "$schoice" in
    1)
      desc="Add a day to the schedule"
      cmds=("python3 station_42.py -d")
      ;;
    2)
      desc="Add a week to the schedule"
      cmds=("python3 station_42.py -w")
      ;;
    3)
      desc="Add a month to the schedule"
      cmds=("python3 station_42.py -m")
      ;;
    0|"")
      echo "Canceled. No changes made."
      return 0
      ;;
    *)
      echo "Invalid choice. No changes made."
      return 1
      ;;
  esac

  echo
  echo "You chose: $desc"
  read -rp "Proceed? [y/N] " confirm
  case "${confirm:-N}" in
    y|Y|yes|YES)
      run_in_background "$desc" "${cmds[@]}"
      ;;
    *)
      echo "Canceled. No changes made."
      ;;
  esac
}

# ---- startup checks ----

check_usb_mount
check_usb_dirs
ensure_symlink "$PROJECT_DIR/confs"   "$USB_CONFS"   "Config (confs)"
ensure_symlink "$PROJECT_DIR/catalog" "$USB_CATALOG" "Catalog"
ensure_symlink "$PROJECT_DIR/scripts" "$USB_SCRIPTS" "Scripts"

echo
echo "Using project directory:"
echo "  $PROJECT_DIR"
echo

cd "$PROJECT_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 not found in PATH."
  exit 1
fi

if [ "$SYMLINK_ISSUE" -eq 1 ]; then
  echo "NOTE: Symlink issues were detected. It is recommended to use option 6 to repair them."
  echo
fi

echo "What would you like to do?"
echo "  1) Scan new files and rebuild catalog"
echo "  2) Schedule options (add day / week / month)"
echo "  3) Show schedule for all channels"
echo "  4) Scan total playtime for all channels"
echo "  5) Delete all schedules (advanced / destructive)"
echo "  6) Fix confs/catalog/scripts symlinks"
echo "  7) Remote control options"
echo "  8) Join new Wi-Fi network"
echo "  9) Reboot AnalogTV"
echo "  0) Cancel / exit"
echo

read -rp "Enter choice [0-9]: " choice

ACTION_DESC=""
COMMANDS=()
RUN_IN_BACKGROUND=1   # default: use run_in_background, except where overridden

case "$choice" in
  1)
    ACTION_DESC="Scan new files and rebuild catalog"
    COMMANDS=(
      "python3 station_42.py --rebuild_catalog"
      "python3 station_42.py -m"
    )
    ;;
  2)
    schedule_options_menu
    exit 0
    ;;
  3)
    ACTION_DESC="Show schedule for all channels"
    COMMANDS=("python3 station_42.py --schedule")
    RUN_IN_BACKGROUND=0
    ;;
  4)
    ACTION_DESC="Scan total playtime for all channels"
    COMMANDS=("runtime_report")
    RUN_IN_BACKGROUND=0
    ;;
  5)
    echo
    echo "WARNING: This will DELETE ALL SCHEDULES."
    echo "  - This cannot be undone."
    echo "  - With no prebuilt schedules, channel changes may take longer."
    echo
    read -rp "Are you sure you want to delete ALL schedules? [y/N] " really
    case "${really:-N}" in
      y|Y|yes|YES)
        read -rp "After deleting, automatically add a month to all schedules? [y/N] " addmonth
        case "${addmonth:-N}" in
          y|Y|yes|YES)
            ACTION_DESC="Delete all schedules, then add a month"
            COMMANDS=(
              "python3 station_42.py --delete_schedules"
              "python3 station_42.py -m"
            )
            ;;
          *)
            ACTION_DESC="Delete all schedules (no automatic month added)"
            COMMANDS=("python3 station_42.py --delete_schedules")
            ;;
        esac
        ;;
      *)
        echo "Canceled. No changes made."
        exit 0
        ;;
    esac
    ;;
  6)
    ACTION_DESC="Fix confs/catalog/scripts symlinks"
    COMMANDS=("fix_symlinks")
    RUN_IN_BACKGROUND=0
    ;;
  7)
    ACTION_DESC="Remote control options"
    COMMANDS=("program_remote")
    RUN_IN_BACKGROUND=0
    ;;
  8)
    ACTION_DESC="Join new Wi-Fi network"
    COMMANDS=("wifi_setup")
    RUN_IN_BACKGROUND=0
    ;;
  9)
    echo
    echo "Rebooting will stop playback and restart the system."
    read -rp "Reboot AnalogTV now? [y/N] " rb
    case "${rb:-N}" in
      y|Y|yes|YES)
        echo "Rebooting AnalogTV..."
        sudo reboot
        exit 0
        ;;
      *)
        echo "Canceled. No changes made."
        exit 0
        ;;
    esac
    ;;
  0|"")
    echo "Canceled. No changes made."
    exit 0
    ;;
  *)
    echo "Invalid choice. Exiting without doing anything."
    exit 1
    ;;
esac

if [ "${#COMMANDS[@]}" -eq 0 ]; then
  echo "No commands to run. Exiting."
  exit 0
fi

echo
echo "You chose: $ACTION_DESC"

if [ "$ACTION_DESC" = "Scan total playtime for all channels" ]; then
  echo "Note: This scan can take several minutes, especially if you have a lot of content."
fi

read -rp "Proceed? [y/N] " confirm
case "${confirm:-N}" in
  y|Y|yes|YES)
    if [ "$RUN_IN_BACKGROUND" -eq 0 ]; then
      echo
      for cmd in "${COMMANDS[@]}"; do
        echo "Running: $cmd"
        eval "$cmd"
        echo
      done
      echo "Done."
    else
      run_in_background "$ACTION_DESC" "${COMMANDS[@]}"
    fi

    # After option 1 finishes, offer a reboot
    if [ "$ACTION_DESC" = "Scan new files and rebuild catalog" ]; then
      echo
      read -rp "Reboot AnalogTV now? [y/N] " rb_after
      case "${rb_after:-N}" in
        y|Y|yes|YES)
          echo "Rebooting AnalogTV..."
          sudo reboot
          ;;
        *)
          echo "No reboot selected."
          ;;
      esac
    fi
    ;;
  *)
    echo "Canceled. No changes made."
    exit 0
    ;;
esac
