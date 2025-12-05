
# Btrfs Maintenance Automation

This project provides automated periodic maintenance for systems using a Btrfs root filesystem.  
A systemd service and timer are used to schedule and execute the following operations:

- `btrfs scrub` to validate and repair silent corruption  
- `btrfs balance` to relocate fragmented chunks when beneficial

The logic is managed by a single installer script that handles deployment, updates, removal, and manual execution.

---

## Features

- Monthly maintenance schedule
- Balance operation triggered only when usage thresholds indicate it is useful
- Recorded logs stored per-run under:

```

/var/log/btrfs-maintenance/YYYY-MM-DD.log

````

- Missed schedules executed on next boot due to `Persistent=true`
- One installer script manages installation and configuration

---

## Installation

The script may be installed either by cloning the repository or fetching it directly.

### Method 1: Clone the repository

```sh
cd ~
git clone https://github.com/Its-Satyajit/open-suse-tw-scripts.git
cd open-suse-tw-scripts/btrfs-maintenance
chmod +x btrfs-maintenance-installer.sh
sudo ./btrfs-maintenance-installer.sh install
````

### Method 2: Install using curl

```sh
sudo curl -o /usr/local/bin/btrfs-maintenance-installer.sh \
https://raw.githubusercontent.com/Its-Satyajit/open-suse-tw-scripts/main/btrfs-maintenance/btrfs-maintenance-installer.sh

sudo chmod +x /usr/local/bin/btrfs-maintenance-installer.sh
sudo btrfs-maintenance-installer.sh install
```

---

## Verification

The systemd timer may be checked with:

```sh
systemctl list-timers | grep btrfs
```

A result similar to the following indicates the timer is scheduled:

```
btrfs-maintenance.timer   Thu 2026-01-01 03:30:00
```

---

## Usage

The installer script provides multiple actions.

| Command                                           | Description                               |
| ------------------------------------------------- | ----------------------------------------- |
| `sudo ./btrfs-maintenance-installer.sh install`   | Installs or updates the service and timer |
| `sudo ./btrfs-maintenance-installer.sh uninstall` | Removes all installed components          |
| `sudo ./btrfs-maintenance-installer.sh run-once`  | Executes maintenance immediately          |
| `sudo ./btrfs-maintenance-installer.sh status`    | Displays service and timer status         |

---

## Installed Files

| File                                            | Location            | Purpose                    |
| ----------------------------------------------- | ------------------- | -------------------------- |
| `/usr/local/sbin/btrfs-maintenance.sh`          | Executed by systemd | Maintenance script         |
| `/etc/systemd/system/btrfs-maintenance.service` | Service unit        | Runs the script            |
| `/etc/systemd/system/btrfs-maintenance.timer`   | Timer unit          | Schedules execution        |
| `/var/log/btrfs-maintenance/`                   | Directory           | Stores generated log files |

---

## Manual Checks

Scrub status may be reviewed using:

```sh
sudo btrfs scrub status /
```

Recent output logs may be viewed with:

```sh
sudo tail -n 50 /var/log/btrfs-maintenance/$(date +'%Y-%m-%d').log
```

---

## Requirements

* Systemd-based Linux system
* Btrfs filesystem mounted at `/`
* Root access for installation and management

---

## Notes

If the system is not using Btrfs, the script exits and logs that no action was performed.
The design attempts to minimize unnecessary SSD wear by avoiding unnecessary balancing.

---

## License

MIT License

```
