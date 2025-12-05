#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="btrfs-maintenance"
MOUNTPOINT="/"

SCRIPT_PATH="/usr/local/sbin/${SERVICE_NAME}.sh"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_PATH="/etc/systemd/system/${SERVICE_NAME}.timer"

usage() {
  echo "Usage: $0 {install|uninstall|run-once|status}"
  exit 1
}

if [[ "${1:-}" == "" ]]; then
  usage
fi

CMD="$1"

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Use: sudo $0 ${CMD}"
  exit 1
fi

install_all() {
  echo "[*] Installing ${SERVICE_NAME} script to ${SCRIPT_PATH}"

  cat > "${SCRIPT_PATH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MOUNTPOINT="/"
LOGDIR="/var/log/btrfs-maintenance"
LOGFILE="${LOGDIR}/$(date +'%Y-%m-%d').log"

mkdir -p "$LOGDIR"

# Check filesystem type, bail if not btrfs
if ! findmnt -n -o FSTYPE "$MOUNTPOINT" | grep -q btrfs; then
  echo "$(date -Is) - $MOUNTPOINT is not btrfs, exiting." >> "$LOGFILE"
  exit 0
fi

echo "============================" >> "$LOGFILE"
echo "$(date -Is) - Starting Btrfs maintenance on $MOUNTPOINT" >> "$LOGFILE"

# Balance: only chunks <75% used
echo "$(date -Is) - Checking if balance is needed..." >> "$LOGFILE"
USAGE_CHECK=$(btrfs fi usage -T "$MOUNTPOINT" 2>/dev/null || true)

if [[ "$USAGE_CHECK" == *"Data ratio"* ]]; then
  echo "$(date -Is) - Running balance (75% threshold)..." >> "$LOGFILE"
  nice -n 19 ionice -c3 btrfs balance start -dusage=75 -musage=75 "$MOUNTPOINT" >> "$LOGFILE" 2>&1 || \
  echo "$(date -Is) - Balance failed." >> "$LOGFILE"
else
  echo "$(date -Is) - Skipping balance: filesystem reports stable usage." >> "$LOGFILE"
fi

# Scrub (runs monthly, ensures data is healthy)
echo "$(date -Is) - Starting scrub..." >> "$LOGFILE"
if nice -n 19 ionice -c3 btrfs scrub start -d "$MOUNTPOINT" >> "$LOGFILE" 2>&1; then
  echo "$(date -Is) - Scrub started successfully." >> "$LOGFILE"
else
  echo "$(date -Is) - Scrub failed." >> "$LOGFILE"
fi

echo "$(date -Is) - Finished Btrfs maintenance on $MOUNTPOINT" >> "$LOGFILE"
EOF

  chmod 755 "${SCRIPT_PATH}"

  echo "[*] Writing systemd service to ${SERVICE_PATH}"

  cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=Btrfs maintenance (balance + scrub) on root filesystem
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH}
Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF

  echo "[*] Writing systemd timer to ${TIMER_PATH}"

  cat > "${TIMER_PATH}" <<EOF
[Unit]
Description=Monthly Btrfs maintenance timer

[Timer]
OnCalendar=*-*-01 03:30:00
Persistent=true
Unit=${SERVICE_NAME}.service

[Install]
WantedBy=timers.target
EOF

  echo "[*] Reloading systemd and enabling timer..."
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}.timer"

  echo "[+] Install complete. Timer is active."
}

uninstall_all() {
  echo "[*] Disabling timer..."
  systemctl disable --now "${SERVICE_NAME}.timer" 2>/dev/null || true

  echo "[*] Removing service and timer files..."
  rm -f "${SERVICE_PATH}" "${TIMER_PATH}"

  echo "[*] Removing script..."
  rm -f "${SCRIPT_PATH}"

  systemctl daemon-reload
  echo "[+] Uninstall complete."
}

run_once() {
  echo "[*] Running ${SERVICE_NAME}.service once..."
  systemctl start "${SERVICE_NAME}.service"
  systemctl status "${SERVICE_NAME}.service" --no-pager || true
}

status_all() {
  echo "=== Service status ==="
  systemctl status "${SERVICE_NAME}.service" --no-pager || true
  echo
  echo "=== Timer status ==="
  systemctl status "${SERVICE_NAME}.timer" --no-pager || true
}

case "${CMD}" in
  install)
    install_all
    ;;
  uninstall)
    uninstall_all
    ;;
  run-once)
    run_once
    ;;
  status)
    status_all
    ;;
  *)
    usage
    ;;
esac
