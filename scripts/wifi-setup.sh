#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/wpa_supplicant/wpa_supplicant.conf"
INTERFACE_DEFAULT="wlan0"

echo "----------------------------------------"
echo "  AnalogTV - Wi-Fi Setup"
echo "----------------------------------------"
echo

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (use sudo)."
  exit 1
fi

detect_interface() {
  local iface
  iface="$(iw dev 2>/dev/null | awk '/Interface/ {print $2; exit}')"
  if [ -n "$iface" ]; then
    echo "$iface"
  else
    echo "$INTERFACE_DEFAULT"
  fi
}

IFACE="$(detect_interface)"
echo "Using wireless interface: $IFACE"
echo

# ---------- Path 1: NetworkManager / nmcli ----------
if command -v nmcli >/dev/null 2>&1; then
  echo "NetworkManager (nmcli) detected. Using nmcli for Wi-Fi setup."
  echo

  while true; do
    echo "Scanning for networks..."
    nmcli device wifi rescan ifname "$IFACE" >/dev/null 2>&1 || true
    echo

    # Terse, colon-separated output: SSID:SECURITY:SIGNAL
    mapfile -t LINES < <(
      nmcli -t -f SSID,SECURITY,SIGNAL device wifi list ifname "$IFACE" \
        | awk -F: 'length($1) > 0'
    )

    if [ "${#LINES[@]}" -eq 0 ]; then
      echo "No Wi-Fi networks found."
      echo "  R) Rescan"
      echo "  0) Cancel"
      echo
      read -rp "Choice [R/0]: " choice
      case "$choice" in
        R|r)
          continue
          ;;
        0)
          echo "Canceled."
          exit 0
          ;;
        *)
          echo "Invalid choice."
          exit 1
          ;;
      esac
    fi

    echo "Available networks:"
    i=1
    for line in "${LINES[@]}"; do
      IFS=: read -r ssid sec sig <<< "$line"
      [ -z "$ssid" ] && continue
      [ -z "$sec" ] && sec="open"
      echo "  $i) $ssid  [$sec]  signal ${sig:-?}"
      i=$((i+1))
    done
    echo "  R) Rescan"
    echo "  0) Cancel"
    echo

    read -rp "Choose a network [1-${#LINES[@]}, R, 0]: " choice

    case "$choice" in
      R|r)
        continue
        ;;
      0)
        echo "Canceled."
        exit 0
        ;;
    esac

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
      echo "Invalid choice."
      exit 1
    fi
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#LINES[@]}" ]; then
      echo "Choice out of range."
      exit 1
    fi

    sel="${LINES[$((choice-1))]}"
    IFS=: read -r SSID SEC SIG <<< "$sel"
    [ -z "$SSID" ] && { echo "Empty SSID selected, aborting."; exit 1; }
    break
  done

  PSK=""
  # If SECURITY field indicates encryption, ask for a password
  if [ -n "$SEC" ] && [ "$SEC" != "--" ] && [ "$SEC" != "open" ] && [ "$SEC" != "NONE" ]; then
    read -rsp "Wi-Fi password for '$SSID': " PSK
    echo
  fi

  echo
  echo "About to connect to '$SSID' on $IFACE."
  echo "This will switch Wi-Fi networks."
  echo "If you are connected over SSH, your session may freeze or disconnect."
  echo
  echo "The connection command will run in the background."
  echo "You can reconnect after ~10–20 seconds and check status with:"
  echo "  nmcli device status"
  echo
  read -rp "Proceed with connection? [y/N] " confirm
  case "${confirm:-N}" in
    y|Y|yes|YES) ;;
    *)
      echo "Canceled."
      exit 0
      ;;
  esac

  LOGFILE="/tmp/wifi-setup-nmcli.log"
  echo
  echo "Starting background connection… (log: $LOGFILE)"
  if [ -n "$PSK" ]; then
    nmcli device wifi connect "$SSID" password "$PSK" ifname "$IFACE" \
      >"$LOGFILE" 2>&1 &
  else
    nmcli device wifi connect "$SSID" ifname "$IFACE" \
      >"$LOGFILE" 2>&1 &
  fi

  echo
  echo "Connection attempt launched in background."
  echo "If this SSH session drops, that is expected during the Wi-Fi switch."
  echo "After reconnecting, you can inspect:"
  echo "  nmcli device status"
  echo "  cat $LOGFILE"
  exit 0
fi

# ---------- Path 2: wpa_supplicant + iwlist ----------
echo "NetworkManager not found. Using wpa_supplicant configuration."
echo "Note: switching networks may briefly disrupt SSH."
echo

if [ ! -f "$CONFIG" ]; then
  echo "wpa_supplicant config not found at:"
  echo "  $CONFIG"
  echo "Creating a new one."
  cat > "$CONFIG" <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US
EOF
fi

BACKUP="/etc/wpa_supplicant/wpa_supplicant.conf.bak.$(date +%Y%m%d-%H%M%S)"
echo "Backing up current config to:"
echo "  $BACKUP"
cp "$CONFIG" "$BACKUP"

if ! command -v iwlist >/dev/null 2>&1; then
  echo "Error: iwlist not found. Install wireless-tools or use nmcli-based setup."
  exit 1
fi

SSID=""
while true; do
  echo
  echo "Scanning for networks on $IFACE..."
  mapfile -t ESSIDS < <(
    iwlist "$IFACE" scan 2>/dev/null \
      | awk -F: '/ESSID:/ {
           gsub(/"/, "", $2);
           if (length($2) > 0) print $2;
         }' \
      | sort -u
  )

  if [ "${#ESSIDS[@]}" -eq 0 ]; then
    echo "No Wi-Fi networks found."
    echo "  R) Rescan"
    echo "  0) Cancel"
    echo
    read -rp "Choice [R/0]: " choice
    case "$choice" in
      R|r)
        continue
        ;;
      0)
        echo "Canceled."
        exit 0
        ;;
      *)
        echo "Invalid choice."
        exit 1
        ;;
    esac
  fi

  echo "Available networks:"
  i=1
  for ssid in "${ESSIDS[@]}"; do
    echo "  $i) $ssid"
    i=$((i+1))
  done
  echo "  R) Rescan"
  echo "  0) Cancel"
  echo

  read -rp "Choose a network [1-${#ESSIDS[@]}, R, 0]: " choice

  case "$choice" in
    R|r)
      continue
      ;;
    0)
      echo "Canceled."
      exit 0
      ;;
  esac

  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo "Invalid choice."
    exit 1
  fi
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#ESSIDS[@]}" ]; then
    echo "Choice out of range."
    exit 1
  fi

  SSID="${ESSIDS[$((choice-1))]}"
  break
done

echo
read -rsp "Wi-Fi password (PSK) for '$SSID': " PSK
echo
if [ -z "$PSK" ]; then
  echo "Password cannot be empty."
  exit 1
fi

echo
read -rp "Country code (e.g. US, GB, DE) [US]: " COUNTRY
COUNTRY="${COUNTRY:-US}"

if grep -q "^country=" "$CONFIG"; then
  sed -i "s/^country=.*/country=$COUNTRY/" "$CONFIG"
else
  echo "country=$COUNTRY" >> "$CONFIG"
fi

echo
echo "Adding network '$SSID' as a preferred (high priority) network..."
echo

if ! command -v wpa_passphrase >/dev/null 2>&1; then
  echo "Error: wpa_passphrase not found. Install wpasupplicant tools."
  exit 1
fi

TMP_NET=$(mktemp)
wpa_passphrase "$SSID" "$PSK" > "$TMP_NET"

NETWORK_BLOCK=$(awk '
  /network=/ { innet=1 }
  innet {
    if ($0 ~ /^[[:space:]]*#psk=/) next;
    lines = lines $0 "\n";
    if ($0 ~ /psk=/) {
      lines = lines "    priority=100\n";
    }
    if ($0 ~ /}/) { innet=0 }
  }
  END { printf "%s", lines }
' "$TMP_NET")

rm -f "$TMP_NET"

if [ -z "$NETWORK_BLOCK" ]; then
  echo "Failed to build network block. Rolling back config."
  cp "$BACKUP" "$CONFIG"
  exit 1
fi

awk -v ssid="$SSID" '
  BEGIN { innet=0; keep=1 }
  /network=/ { innet=1; buf=$0 ORS; next }
  innet {
    buf = buf $0 ORS
    if ($0 ~ /}/) {
      innet=0
      if (buf ~ "ssid=\""ssid"\"") {
        buf=""
      } else {
        printf "%s", buf
      }
      buf=""
    }
    next
  }
  { print }
' "$CONFIG" > "${CONFIG}.new"

mv "${CONFIG}.new" "$CONFIG"

printf "\n%s\n" "$NETWORK_BLOCK" >> "$CONFIG"

echo "Updated wpa_supplicant config:"
echo "  $CONFIG"
echo

echo "Reconfiguring Wi-Fi on $IFACE... (SSH may briefly drop)"
if command -v wpa_cli >/dev/null 2>&1; then
  wpa_cli -i "$IFACE" reconfigure || true
fi

echo
echo "Wi-Fi configuration updated."
echo "Network '$SSID' is now configured with high priority (default)."
echo "You may need to disconnect/reconnect or reboot for it to take effect:"
echo "  sudo reboot"
