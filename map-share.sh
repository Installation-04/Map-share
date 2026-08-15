#!/usr/bin/env bash
#
# map-share.sh — guided TUI for mounting NFS or SMB/CIFS shares
#
# Uses whiptail for a menu-driven "GUI-ish" console experience:
# dialogs, radio lists, input boxes, and OK/Cancel buttons instead of
# raw read -rp prompts.
#
# Usage:
#   ./map-share.sh
#
# Must be run as root (mounting filesystems, editing /etc/fstab).

set -euo pipefail

LOGFILE="/var/log/map-share.log"
BACKTITLE="Share Mapper — NFS / SMB Mount Helper"

log() {
    echo -e "$1" | tee -a "$LOGFILE" >/dev/null
}

die() {
    whiptail --backtitle "$BACKTITLE" --title "Error" --msgbox "$1" 10 70
    log "ERROR: $1"
    exit 1
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root."
        exit 1
    fi
}

ensure_whiptail() {
    if ! command -v whiptail >/dev/null 2>&1; then
        echo "whiptail not found — installing (needed for the menu UI)..."
        apt update -qq && apt install -y whiptail
    fi
}

ensure_pkg() {
    local pkg="$1"
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        whiptail --backtitle "$BACKTITLE" --title "Installing" --infobox "Installing required package: $pkg ..." 8 60
        apt update -qq && apt install -y "$pkg" >>"$LOGFILE" 2>&1
    fi
}

# ---------------------------------------------------------------------------
# Step 1: choose protocol
# ---------------------------------------------------------------------------

choose_protocol() {
    PROTOCOL=$(whiptail --backtitle "$BACKTITLE" --title "Choose Share Type" \
        --radiolist "Which type of network share do you want to mount?" 12 60 2 \
        "NFS" "Network File System (Linux/Synology/etc.)" ON \
        "SMB" "Windows/Samba/CIFS share" OFF \
        3>&1 1>&2 2>&3) || exit 130
}

# ---------------------------------------------------------------------------
# Step 2: gather connection details
# ---------------------------------------------------------------------------

gather_nfs_details() {
    SERVER_IP=$(whiptail --backtitle "$BACKTITLE" --title "NFS Server" \
        --inputbox "Enter the NFS server IP or hostname:" 10 60 "10.10.200.30" \
        3>&1 1>&2 2>&3) || exit 130
    [[ -n "$SERVER_IP" ]] || die "Server address cannot be empty."

    EXPORT_PATH=$(whiptail --backtitle "$BACKTITLE" --title "NFS Export Path" \
        --inputbox "Enter the exported path on the server (check DSM/NAS NFS permissions for the exact path):" 10 70 "/volume1/video" \
        3>&1 1>&2 2>&3) || exit 130
    [[ -n "$EXPORT_PATH" ]] || die "Export path cannot be empty."
}

gather_smb_details() {
    SERVER_IP=$(whiptail --backtitle "$BACKTITLE" --title "SMB Server" \
        --inputbox "Enter the SMB server IP or hostname:" 10 60 "10.10.200.30" \
        3>&1 1>&2 2>&3) || exit 130
    [[ -n "$SERVER_IP" ]] || die "Server address cannot be empty."

    SMB_SHARE=$(whiptail --backtitle "$BACKTITLE" --title "SMB Share Name" \
        --inputbox "Enter the share name (as it appears in \\\\server\\share):" 10 60 "video" \
        3>&1 1>&2 2>&3) || exit 130
    [[ -n "$SMB_SHARE" ]] || die "Share name cannot be empty."

    SMB_USER=$(whiptail --backtitle "$BACKTITLE" --title "SMB Username" \
        --inputbox "Enter the SMB username:" 10 60 "" \
        3>&1 1>&2 2>&3) || exit 130

    SMB_PASS=$(whiptail --backtitle "$BACKTITLE" --title "SMB Password" \
        --passwordbox "Enter the SMB password (input hidden):" 10 60 \
        3>&1 1>&2 2>&3) || exit 130

    SMB_VERSION=$(whiptail --backtitle "$BACKTITLE" --title "SMB Protocol Version" \
        --radiolist "Choose SMB protocol version (3.0 works for most modern NAS/Windows):" 14 60 4 \
        "3.0" "Recommended default" ON \
        "2.1" "Older NAS/Windows compatibility" OFF \
        "2.0" "Legacy" OFF \
        "1.0" "Very old devices only (insecure)" OFF \
        3>&1 1>&2 2>&3) || exit 130
}

# ---------------------------------------------------------------------------
# Step 3: mount point
# ---------------------------------------------------------------------------

choose_mount_point() {
    local suggested="/mnt/${SERVER_IP//./-}-share"
    MOUNT_POINT=$(whiptail --backtitle "$BACKTITLE" --title "Mount Point" \
        --inputbox "Where should this share be mounted on this machine?" 10 70 "$suggested" \
        3>&1 1>&2 2>&3) || exit 130
    [[ -n "$MOUNT_POINT" ]] || die "Mount point cannot be empty."

    if [[ -d "$MOUNT_POINT" ]] && mountpoint -q "$MOUNT_POINT"; then
        die "Something is already mounted at $MOUNT_POINT. Unmount it first or choose a different path."
    fi
}

# ---------------------------------------------------------------------------
# Step 4: persistence choice
# ---------------------------------------------------------------------------

choose_persistence() {
    if whiptail --backtitle "$BACKTITLE" --title "Persistence" \
        --yesno "Should this mount survive a reboot?\n\n(Adds an entry to /etc/fstab)" 10 60; then
        PERSIST=true
    else
        PERSIST=false
    fi
}

# ---------------------------------------------------------------------------
# Step 5: summary + confirm (the "OK to proceed" screen)
# ---------------------------------------------------------------------------

confirm_summary() {
    local summary=""
    if [[ "$PROTOCOL" == "NFS" ]]; then
        summary="Protocol:     NFS
Server:       ${SERVER_IP}
Export path:  ${EXPORT_PATH}
Mount point:  ${MOUNT_POINT}
Persistent:   ${PERSIST}"
    else
        summary="Protocol:     SMB/CIFS
Server:       ${SERVER_IP}
Share:        ${SMB_SHARE}
Username:     ${SMB_USER}
SMB version:  ${SMB_VERSION}
Mount point:  ${MOUNT_POINT}
Persistent:   ${PERSIST}"
    fi

    whiptail --backtitle "$BACKTITLE" --title "Confirm and Mount" \
        --yesno "The following will be configured:\n\n${summary}\n\nProceed?" 20 70 \
        || { log "Cancelled by user at summary screen."; exit 130; }
}

# ---------------------------------------------------------------------------
# Step 6: perform the mount
# ---------------------------------------------------------------------------

do_nfs_mount() {
    ensure_pkg nfs-common
    mkdir -p "$MOUNT_POINT"

    log "Mounting NFS ${SERVER_IP}:${EXPORT_PATH} -> ${MOUNT_POINT}"
    if ! mount -t nfs "${SERVER_IP}:${EXPORT_PATH}" "$MOUNT_POINT" 2>>"$LOGFILE"; then
        die "Mount failed. Check /var/log/map-share.log for details.\n\nCommon causes: wrong export path, NFS server not allowing this host's IP, or the nfs-common package missing."
    fi

    if $PERSIST; then
        local entry="${SERVER_IP}:${EXPORT_PATH} ${MOUNT_POINT} nfs defaults 0 0"
        if ! grep -qF "$entry" /etc/fstab 2>/dev/null; then
            cp /etc/fstab "/etc/fstab.bak.$(date +%s)"
            echo "$entry" >> /etc/fstab
            log "Added to /etc/fstab: $entry"
        fi
    fi
}

do_smb_mount() {
    ensure_pkg cifs-utils
    mkdir -p "$MOUNT_POINT"

    local credfile="/etc/samba/creds-${SMB_SHARE}-$(echo "$SERVER_IP" | tr '.' '-')"
    mkdir -p /etc/samba
    cat > "$credfile" << EOF
username=${SMB_USER}
password=${SMB_PASS}
EOF
    chmod 600 "$credfile"
    log "Wrote credentials file: $credfile (permissions 600)"

    log "Mounting SMB //${SERVER_IP}/${SMB_SHARE} -> ${MOUNT_POINT}"
    if ! mount -t cifs "//${SERVER_IP}/${SMB_SHARE}" "$MOUNT_POINT" \
        -o "credentials=${credfile},vers=${SMB_VERSION},uid=0,gid=0,iocharset=utf8" 2>>"$LOGFILE"; then
        die "Mount failed. Check /var/log/map-share.log for details.\n\nCommon causes: wrong username/password, wrong share name, or SMB version mismatch with the server."
    fi

    if $PERSIST; then
        local entry="//${SERVER_IP}/${SMB_SHARE} ${MOUNT_POINT} cifs credentials=${credfile},vers=${SMB_VERSION},uid=0,gid=0,iocharset=utf8 0 0"
        if ! grep -qF "$entry" /etc/fstab 2>/dev/null; then
            cp /etc/fstab "/etc/fstab.bak.$(date +%s)"
            echo "$entry" >> /etc/fstab
            log "Added to /etc/fstab: $entry"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Step 7: verify + result screen
# ---------------------------------------------------------------------------

verify_and_report() {
    local listing
    listing=$(ls -la "$MOUNT_POINT" 2>&1 | head -n 20)

    if $PERSIST; then
        whiptail --backtitle "$BACKTITLE" --title "Testing Persistence" \
            --infobox "Testing that the mount survives a remount cycle (umount + mount -a)..." 8 70
        umount "$MOUNT_POINT" 2>>"$LOGFILE" || true
        if mount -a 2>>"$LOGFILE" && mountpoint -q "$MOUNT_POINT"; then
            log "Persistence test passed."
        else
            whiptail --backtitle "$BACKTITLE" --title "Warning" \
                --msgbox "The share mounted initially, but the persistence test (umount + mount -a) failed.\n\nCheck /etc/fstab and /var/log/map-share.log manually." 12 70
        fi
    fi

    whiptail --backtitle "$BACKTITLE" --title "Success" \
        --msgbox "Share mounted at: ${MOUNT_POINT}\n\nContents:\n${listing}\n\nLog file: ${LOGFILE}" 20 78
}

# ---------------------------------------------------------------------------
# Extra: manage / unmount existing shares
# ---------------------------------------------------------------------------

manage_existing() {
    local mounts
    mounts=$(mount | grep -E "type (nfs|cifs)" | awk '{print $3}')

    if [[ -z "$mounts" ]]; then
        whiptail --backtitle "$BACKTITLE" --title "No Shares Found" \
            --msgbox "No currently mounted NFS or SMB shares were found." 8 60
        return
    fi

    local menu_items=()
    local i=1
    while read -r m; do
        menu_items+=("$i" "$m")
        i=$((i+1))
    done <<< "$mounts"

    local choice
    choice=$(whiptail --backtitle "$BACKTITLE" --title "Unmount a Share" \
        --menu "Select a mounted share to unmount:" 18 70 8 \
        "${menu_items[@]}" \
        3>&1 1>&2 2>&3) || return

    local selected_path
    selected_path=$(echo "$mounts" | sed -n "${choice}p")

    if whiptail --backtitle "$BACKTITLE" --title "Confirm Unmount" \
        --yesno "Unmount ${selected_path}?\n\n(Any /etc/fstab entry will remain — remove it manually if you want this permanent.)" 12 70; then
        if umount "$selected_path" 2>>"$LOGFILE"; then
            whiptail --backtitle "$BACKTITLE" --title "Done" --msgbox "Unmounted ${selected_path}" 8 60
        else
            whiptail --backtitle "$BACKTITLE" --title "Error" --msgbox "Failed to unmount. It may be busy (files in use). Check /var/log/map-share.log." 10 70
        fi
    fi
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------

main_menu() {
    local choice
    choice=$(whiptail --backtitle "$BACKTITLE" --title "Main Menu" \
        --menu "What would you like to do?" 15 60 3 \
        "1" "Mount a new NFS or SMB share" \
        "2" "View / unmount an existing share" \
        "3" "Exit" \
        3>&1 1>&2 2>&3) || exit 0

    case "$choice" in
        1) run_mount_wizard ;;
        2) manage_existing; main_menu ;;
        3) exit 0 ;;
    esac
}

run_mount_wizard() {
    choose_protocol
    choose_mount_point

    if [[ "$PROTOCOL" == "NFS" ]]; then
        gather_nfs_details
    else
        gather_smb_details
    fi

    choose_persistence
    confirm_summary

    if [[ "$PROTOCOL" == "NFS" ]]; then
        do_nfs_mount
    else
        do_smb_mount
    fi

    verify_and_report
    main_menu
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

require_root
ensure_whiptail
touch "$LOGFILE"
main_menu