#!/bin/bash

# FieldStation42 composite screen-toggle setup for Raspberry Pi OS.
#
# This script prepares a fresh Raspberry Pi OS installation for the working
# screenToggle.sh setup:
#   - installs all runtime/diagnostic packages used by screenToggle.sh
#   - enables KMS composite output
#   - forces Composite-1 to a stable NTSC/PAL mode
#   - grants the desktop user passwordless access ONLY to the commands needed
#     by screenToggle.sh's VT recovery path
#   - optionally installs screenToggle.sh when it is beside this installer
#
# Usage:
#   ./install_screenToggle_dependencies.sh
#   ./install_screenToggle_dependencies.sh analog
#   ./install_screenToggle_dependencies.sh analog NTSC
#
# Arguments:
#   $1 = desktop/FieldStation42 user (optional; auto-detected if omitted)
#   $2 = TV standard (optional; default NTSC)
#        Supported: NTSC, NTSC-J, NTSC-443, PAL, PAL-M, PAL-N, PAL60, SECAM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${1:-}"
TV_NORM="${2:-NTSC}"

# -----------------------------------------------------------------------------
# Become root while remembering the original user.
# -----------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: sudo is required to run this installer." >&2
        exit 1
    fi
    exec sudo -E /bin/bash "$0" "$@"
fi

# -----------------------------------------------------------------------------
# Determine the desktop/FieldStation42 user.
# -----------------------------------------------------------------------------
if [ -z "$TARGET_USER" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
fi

if [ -z "$TARGET_USER" ] && command -v loginctl >/dev/null 2>&1; then
    while read -r sid _uid user _rest; do
        [ -n "$sid" ] || continue
        type="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
        active="$(loginctl show-session "$sid" -p Active --value 2>/dev/null || true)"
        if [ "$type" = "wayland" ] && [ "$active" = "yes" ]; then
            TARGET_USER="$user"
            break
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
fi

if [ -z "$TARGET_USER" ]; then
    TARGET_USER="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $6 ~ /^\/home\// {print $1; exit}')"
fi

if [ -z "$TARGET_USER" ] || ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "ERROR: Could not determine the desktop user." >&2
    echo "Run this script with the username explicitly, for example:" >&2
    echo "  sudo $0 analog" >&2
    exit 1
fi

TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    echo "ERROR: Home directory for '$TARGET_USER' was not found." >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Validate TV standard and select the matching forced KMS mode.
# The current working FieldStation42 setup is NTSC: 720x480 at ~59.94 Hz.
# -----------------------------------------------------------------------------
case "$TV_NORM" in
    NTSC|NTSC-J|NTSC-443|PAL-M|PAL60)
        FORCE_MODE="720x480@60ie"
        ;;
    PAL|PAL-N|SECAM)
        FORCE_MODE="720x576@50ie"
        ;;
    *)
        echo "ERROR: Unsupported TV standard: $TV_NORM" >&2
        echo "Use NTSC, NTSC-J, NTSC-443, PAL, PAL-M, PAL-N, PAL60, or SECAM." >&2
        exit 1
        ;;
esac

# -----------------------------------------------------------------------------
# Raspberry Pi boot file locations.
# -----------------------------------------------------------------------------
if [ -f /boot/firmware/config.txt ]; then
    CONFIG=/boot/firmware/config.txt
elif [ -f /boot/config.txt ]; then
    CONFIG=/boot/config.txt
else
    echo "ERROR: Raspberry Pi config.txt was not found." >&2
    exit 1
fi

if [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE=/boot/firmware/cmdline.txt
elif [ -f /boot/cmdline.txt ]; then
    CMDLINE=/boot/cmdline.txt
else
    echo "ERROR: Raspberry Pi cmdline.txt was not found." >&2
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
CONFIG_BACKUP="${CONFIG}.fieldstation42.${STAMP}.bak"
CMDLINE_BACKUP="${CMDLINE}.fieldstation42.${STAMP}.bak"

# -----------------------------------------------------------------------------
# Install packages used by the working script.
# -----------------------------------------------------------------------------
echo ""
echo "=== Installing packages ==="
apt-get update
apt-get install -y \
    alsa-utils \
    kanshi \
    kbd \
    kms++-utils \
    procps \
    socat \
    sudo \
    util-linux \
    wlopm \
    wlr-randr

# -----------------------------------------------------------------------------
# Configure composite output in config.txt.
# Raspberry Pi documentation uses both enable_tvout=1 and the KMS composite
# overlay. This is safe to run repeatedly.
# -----------------------------------------------------------------------------
echo ""
echo "=== Configuring composite output ==="
cp -a "$CONFIG" "$CONFIG_BACKUP"
cp -a "$CMDLINE" "$CMDLINE_BACKUP"

# enable_tvout=1
if grep -Eq '^[[:space:]]*#?[[:space:]]*enable_tvout=' "$CONFIG"; then
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*enable_tvout=.*/enable_tvout=1/' "$CONFIG"
else
    printf '\n# FieldStation42 composite video\nenable_tvout=1\n' >> "$CONFIG"
fi

# Ensure the active vc4-kms-v3d overlay includes the composite parameter.
if grep -Eq '^[[:space:]]*dtoverlay=vc4-kms-v3d([,[:space:]]|$)' "$CONFIG"; then
    if ! grep -Eq '^[[:space:]]*dtoverlay=vc4-kms-v3d([^#\r\n]*,)?composite([,[:space:]#]|$)' "$CONFIG"; then
        sed -i -E '/^[[:space:]]*dtoverlay=vc4-kms-v3d([,[:space:]]|$)/ s/[[:space:]]*(#.*)?$/,composite \1/' "$CONFIG"
    fi
else
    printf 'dtoverlay=vc4-kms-v3d,composite\n' >> "$CONFIG"
fi

# Clean up the common simple case if the edit above introduced a space before
# a comment or an unnecessary trailing space.
sed -i -E 's/^dtoverlay=vc4-kms-v3d,composite[[:space:]]+$/dtoverlay=vc4-kms-v3d,composite/' "$CONFIG"

# -----------------------------------------------------------------------------
# Force Composite-1 present and select the correct TV norm.
# cmdline.txt MUST remain one line.
# -----------------------------------------------------------------------------
TMP_CMDLINE="$(mktemp)"
trap 'rm -f "$TMP_CMDLINE"' EXIT

awk -v norm="$TV_NORM" -v mode="$FORCE_MODE" '
NR == 1 {
    out=""
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^vc4\.tv_norm=/) continue
        if ($i ~ /^video=Composite-1:/) continue
        if (out != "") out = out " "
        out = out $i
    }
    if (out != "") out = out " "
    out = out "vc4.tv_norm=" norm " video=Composite-1:" mode
    print out
    next
}
' "$CMDLINE" > "$TMP_CMDLINE"

cat "$TMP_CMDLINE" > "$CMDLINE"

# -----------------------------------------------------------------------------
# Permit only the noninteractive sudo calls the existing working screenToggle
# script makes during VT recovery.
#
# screenToggle.sh currently tests `sudo -n true` before invoking chvt, so both
# /usr/bin/true and /usr/bin/chvt are listed here.
# -----------------------------------------------------------------------------
echo ""
echo "=== Configuring VT recovery permission ==="
SUDOERS_FILE="/etc/sudoers.d/fieldstation42-screen-toggle-${TARGET_USER}"
cat > "$SUDOERS_FILE" <<EOF_SUDOERS
# FieldStation42 screenToggle.sh: allow fast composite KMS recovery.
${TARGET_USER} ALL=(root) NOPASSWD: /usr/bin/true, /usr/bin/chvt *
EOF_SUDOERS
chmod 0440 "$SUDOERS_FILE"

if ! visudo -cf "$SUDOERS_FILE" >/dev/null; then
    echo "ERROR: sudoers validation failed; removing $SUDOERS_FILE" >&2
    rm -f "$SUDOERS_FILE"
    exit 1
fi

# -----------------------------------------------------------------------------
# If screenToggle.sh is beside this installer, put it in the FieldStation42
# scripts directory automatically.
# -----------------------------------------------------------------------------
DEST_DIR="$TARGET_HOME/FieldStation42/scripts"
SOURCE_TOGGLE="$SCRIPT_DIR/screenToggle.sh"
DEST_TOGGLE="$DEST_DIR/screenToggle.sh"

if [ -f "$SOURCE_TOGGLE" ]; then
    echo ""
    echo "=== Installing screenToggle.sh ==="
    mkdir -p "$DEST_DIR"
    cp "$SOURCE_TOGGLE" "$DEST_TOGGLE"
    chown "$TARGET_UID:$TARGET_GID" "$DEST_TOGGLE"
    chmod 0755 "$DEST_TOGGLE"
    echo "Installed: $DEST_TOGGLE"
else
    echo ""
    echo "NOTE: screenToggle.sh was not beside this installer."
    echo "Copy the working screenToggle.sh to:"
    echo "  $DEST_TOGGLE"
fi

# -----------------------------------------------------------------------------
# Check the OSD restart hook expected by screenToggle.sh.
# -----------------------------------------------------------------------------
OSD_SCRIPT="$TARGET_HOME/FieldStation42/scripts/OSD.sh"
if [ -f "$OSD_SCRIPT" ]; then
    echo "OSD restart script found: $OSD_SCRIPT"
else
    echo "WARNING: OSD restart script not found: $OSD_SCRIPT"
    echo "The display toggle will still work, but it cannot restart the OSD until that file exists."
fi

# -----------------------------------------------------------------------------
# Verify commands.
# -----------------------------------------------------------------------------
echo ""
echo "=== Verification ==="
FAILED=0
for cmd in /usr/bin/wlopm /usr/bin/kmsprint /usr/bin/amixer /usr/bin/socat /usr/bin/pgrep /usr/bin/pkill /usr/bin/chvt /usr/sbin/runuser /usr/bin/kanshi; do
    if [ -x "$cmd" ]; then
        printf '  OK      %s\n' "$cmd"
    else
        printf '  MISSING %s\n' "$cmd"
        FAILED=1
    fi
done

printf '\nDesktop user:  %s (UID %s)\n' "$TARGET_USER" "$TARGET_UID"
printf 'Home:          %s\n' "$TARGET_HOME"
printf 'TV standard:   %s\n' "$TV_NORM"
printf 'Forced mode:   Composite-1:%s\n' "$FORCE_MODE"
printf 'config.txt:    %s\n' "$CONFIG"
printf 'cmdline.txt:   %s\n' "$CMDLINE"
printf 'Config backup: %s\n' "$CONFIG_BACKUP"
printf 'Cmdline backup:%s\n' "$CMDLINE_BACKUP"
printf 'sudoers:       %s\n' "$SUDOERS_FILE"

if [ "$FAILED" -ne 0 ]; then
    echo ""
    echo "ERROR: One or more required commands are missing." >&2
    exit 1
fi

echo ""
echo "Setup complete."
echo "REBOOT THE PI before testing screenToggle.sh."
echo ""
echo "After reboot, verify composite with:"
echo "  /usr/bin/kmsprint"
echo ""
echo "Then test the toggle twice:"
echo "  $DEST_TOGGLE"
echo "  $DEST_TOGGLE"
