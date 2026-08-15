# Map-share

A guided, menu-driven TUI (built with `whiptail`) for mounting NFS or SMB/CIFS
network shares on Linux, with optional persistence via `/etc/fstab`.

## Features

- Walks you through mounting an **NFS** or **SMB/CIFS** share step by step.
- Prompts for server address, export path / share name, and (for SMB)
  credentials and protocol version.
- Lets you choose whether the mount should survive a reboot (adds an
  `/etc/fstab` entry, with a timestamped backup of the original file).
- Verifies the mount, and if persistence was requested, tests it by
  unmounting and running `mount -a`.
- Includes a menu to view and unmount currently mounted NFS/SMB shares.
- Logs all actions to `/var/log/map-share.log`.

## Requirements

- Linux with `bash`.
- Root privileges (the script mounts filesystems and can edit `/etc/fstab`).
- `whiptail` (installed automatically if missing).
- `nfs-common` (for NFS mounts) or `cifs-utils` (for SMB mounts) — installed
  automatically as needed.

## Usage

### One-time run (no clone required)

```bash
curl -fsSL https://raw.githubusercontent.com/Installation-04/Map-share/main/map-share.sh | sudo bash
```

### Run from a local clone

```bash
sudo ./map-share.sh
```

Follow the on-screen prompts:

1. Choose **NFS** or **SMB**.
2. Enter the connection details (server, export path / share name, and for
   SMB, username, password, and protocol version).
3. Choose a local mount point.
4. Choose whether the mount should persist across reboots.
5. Confirm the summary screen to perform the mount.

From the main menu you can also view and unmount existing NFS/SMB shares.

## Notes

- SMB credentials are stored in `/etc/samba/creds-<share>-<server>` with
  `600` permissions.
- Every write to `/etc/fstab` is preceded by a timestamped backup
  (`/etc/fstab.bak.<epoch>`).
- Check `/var/log/map-share.log` for details if a mount fails.

## Running inside a Proxmox LXC container or VM

The script works inside both Proxmox **VMs** and **LXC containers**, but
unprivileged LXC containers block the `mount(2)` syscall for `nfs`/`cifs` by
default — even when running as root inside the container. The script
detects when it's running inside an LXC container and will warn you up
front, and adds a troubleshooting hint to the mount-failure screen if this
is likely the cause (typically an "Operation not permitted" error).

To allow NFS/CIFS mounts from inside an unprivileged LXC container, run
this on the **Proxmox host** (not inside the container), then restart the
container:

```bash
pct set <VMID> --features mount=nfs;cifs
```

Alternatively, mark the container **privileged** in its Proxmox options.

VMs are unaffected by this restriction — no extra configuration is needed.
