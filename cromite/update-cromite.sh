#!/bin/bash
#
# TASK: Automate the installation, updating, and launching of Cromite on Linux.
# Integrated: Wayland auto-detection + optional forcing + helpful Wayland scaling flags
# Integrated: Internet availability check — if offline, launch existing app directly.
#
# --- VERSIONING ---
# 2025-09-09, Assistant, v7.2 (Wayland + offline start):
#  - Auto-detects Wayland (checks `XDG_SESSION_TYPE` and `WAYLAND_DISPLAY`) and adds Ozone/Wayland flags.
#  - Supports explicit flags `--wayland` and `--x11` (also env vars `CROMITE_FORCE_WAYLAND=1` and `CROMITE_FORCE_X11=1`) to force backend.
#  - Adds Wayland-specific flags: `--enable-features=UseOzonePlatform,WaylandPerSurfaceScale,WaylandUiScale`, `--ozone-platform=wayland`, and `--gtk-version=4` — but **only** if the user hasn't already provided ozone/enable-features flags.
#  - Optional device scale: set `CROMITE_DEVICE_SCALE=1.25` (or pass via env) to add `--force-device-scale-factor=...`.
#  - If no Internet is available at start, the script will skip update/download and immediately attempt to launch the installed Cromite (if present). If Cromite is not installed, it will exit with a clear error.
#  - Keeps your smart-profile logic, checksum checks, desktop integration and original behaviour unchanged.
#
set -euo pipefail

INSTALL_BASE="$HOME/.local/share"
CROMITE_DIR="$INSTALL_BASE/cromite"
CROMITE_PROFILE_DIR="$HOME/.config/cromite"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
SCRIPT_ABSOLUTE_PATH=$(readlink -f "${BASH_SOURCE[0]}")

log_notify() {
  local message="$1"
  echo "INFO: ${message}"
  if [[ -n "${DISPLAY-}" ]] && command -v notify-send &>/dev/null; then
    notify-send "Cromite Updater" "${message}"
  fi
}

die() {
  local error_message="$1"
  echo "ERROR: ${error_message}" >&2
  if [[ -n "${DISPLAY-}" ]] && command -v notify-send &>/dev/null; then
    notify-send -u critical "Cromite Updater FAILED" "${error_message}"
  fi
  exit 1
}

create_desktop_integration() {
  log_notify "Performing first-time desktop integration..."

  mkdir -p "$CROMITE_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

  if ln -sf "$CROMITE_DIR/chrome" "$BIN_DIR/cromite"; then
    log_notify "Created command-line shortcut. You can now type 'cromite' in a new terminal."
  else
    log_notify "WARN: Could not create symlink in $BIN_DIR. Is it in your PATH?"
  fi

  cp "$CROMITE_DIR/product_logo_48.png" "$ICON_DIR/cromite.png" || true

  local desktop_file_path="$DESKTOP_DIR/cromite.desktop"
  cat >"$desktop_file_path" <<EOF
[Desktop Entry]
Version=1.0
Name=Cromite
Comment=Update and Launch the Cromite Web Browser
Exec=${SCRIPT_ABSOLUTE_PATH} %U
Icon=cromite
Terminal=false
Type=Application
Categories=Network;WebBrowser;
EOF

  chmod +x "$desktop_file_path"

  log_notify "Installation complete. Cromite is now available in your application menu."
}

cleanup() {
  if [[ -n "${TMP_DIR-}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

orig_params=("$@")
filtered_params=()
FORCE_WAYLAND=0
FORCE_X11=0

for p in "${orig_params[@]:-}"; do
  case "$p" in
    --wayland)
      FORCE_WAYLAND=1
      ;;
    --x11)
      FORCE_X11=1
      ;;
    *)
      filtered_params+=("$p")
      ;;
  esac
done


if [[ "${CROMITE_FORCE_WAYLAND-}" == "1" ]]; then
  FORCE_WAYLAND=1
fi
if [[ "${CROMITE_FORCE_X11-}" == "1" ]]; then
  FORCE_X11=1
fi

cromite_params=("${filtered_params[@]:-}")

# --- Internet check ---
check_internet() {
 
  if command -v curl &>/dev/null; then
    if curl -fsS --head --max-time 5 https://github.com >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v ping &>/dev/null; then
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}


cromite_executable_path="$CROMITE_DIR/chrome"
is_installed=false
if [[ -f "$cromite_executable_path" ]]; then
  is_installed=true
  installed_version=$("$cromite_executable_path" --version 2>/dev/null | sed -E 's/[^0-9]*([0-9.]+).*/\1/' || true)
else
  installed_version="0.0.0.0"
fi

if ! check_internet; then
  log_notify "No Internet connection detected."
  if [[ "$is_installed" == true ]]; then
    log_notify "Launching installed Cromite without checking for updates."

    SKIP_UPDATES=1
  else
    die "No Internet and Cromite is not installed. Connect to the Internet to perform the initial installation."
  fi
else
  SKIP_UPDATES=0
fi

if [[ "$SKIP_UPDATES" == "0" ]]; then
  log_notify "Checking for Cromite updates..."
  latest_release_url=$(curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/uazo/cromite/releases/latest") ||
    die "Could not resolve the latest release URL. Check network or GitHub status."

  if ! [[ "${latest_release_url}" == *"github.com/uazo/cromite/releases/tag/"* ]]; then
    die "Failed to get a valid release tag URL. Received: ${latest_release_url}"
  fi

  release_tag="${latest_release_url##*/}"
  archive_name="chrome-lin64.tar.gz"
  download_url="https://github.com/uazo/cromite/releases/download/${release_tag}/${archive_name}"
  assets_url="https://github.com/uazo/cromite/releases/expanded_assets/${release_tag}"

  available_version=$(echo "${release_tag}" | sed -E 's/^v?([0-9.]+).*/\1/')
  if [[ -z "$available_version" ]]; then
    die "Could not parse version number from release tag: ${release_tag}"
  fi

  if [[ "$is_installed" == false ]]; then
    log_notify "Cromite not found in ${CROMITE_DIR}. Preparing for first-time installation."
    mkdir -p "$CROMITE_DIR"
  fi

  if [[ "$(printf '%s\n' "$available_version" "$installed_version" | sort -V | tail -n1)" == "$installed_version" ]]; then
    log_notify "Cromite is up to date. Version: ${installed_version}."
  else
    log_notify "New version ${available_version} available. (Installed: ${installed_version})"

    TMP_DIR=$(mktemp -d)
    archive_path="${TMP_DIR}/${archive_name}"

    log_notify "Downloading Cromite..."
    curl -sS -L "${download_url}" -o "${archive_path}" || die "Download failed from ${download_url}"

    log_notify "Verifying download integrity..."
    assets_html=$(curl -fsSL "${assets_url}") || die "Could not download release assets HTML to verify checksum."
    expected_checksum=$(echo "${assets_html}" | grep "${archive_name}" | grep -o 'sha256:[0-9a-f]\{64\}' | cut -d ':' -f 2 || true)
    if [[ -z "$expected_checksum" ]]; then
      die "Could not parse checksum from the release assets page. The page layout may have changed."
    fi

    if ! echo "${expected_checksum}  ${archive_path}" | sha256sum --check --status; then
      die "CHECKSUM MISMATCH! The downloaded file may be corrupt or tampered with. Deleting."
    fi

    log_notify "Checksum valid. Installing to ${CROMITE_DIR}..."
    tar -xf "${archive_path}" --strip-components=1 -C "$CROMITE_DIR"
    log_notify "Update complete. Cromite is now at version ${available_version}."

    if [[ "$is_installed" == false ]]; then
      create_desktop_integration
    fi
  fi
else
  log_notify "Skipped update checks because Internet is not available."
fi

# --- Smart Profile Handling ---
if ! grep -q -- '--user-data-dir' <<<"${cromite_params[*]}"; then
  log_notify "Using default isolated profile at: ${CROMITE_PROFILE_DIR}"
  cromite_params=("--user-data-dir=${CROMITE_PROFILE_DIR}" "${cromite_params[@]:-}")
else
  log_notify "User-defined profile directory detected. Respecting user choice."
fi


add_wayland_flags=0

for p in "${cromite_params[@]:-}"; do
  if [[ "$p" == --ozone-platform=* ]] || [[ "$p" == --enable-features=*UseOzonePlatform* ]]; then
    add_wayland_flags=0
    break
  fi
done


XDG_TYPE="${XDG_SESSION_TYPE-}"
WAYLAND_PRESENT=0
if [[ -n "${WAYLAND_DISPLAY-}" || "${XDG_TYPE}" == "wayland" ]]; then
  WAYLAND_PRESENT=1
fi

if [[ "$FORCE_X11" == "1" ]]; then
  log_notify "Cromite: user forced X11. Skipping Wayland flags."
else
  if [[ "$FORCE_WAYLAND" == "1" ]]; then
    log_notify "Cromite: user forced Wayland via --wayland or CROMITE_FORCE_WAYLAND=1"
    add_wayland_flags=1
  elif [[ "$WAYLAND_PRESENT" == "1" ]]; then
    log_notify "Wayland session detected (XDG_SESSION_TYPE=${XDG_TYPE}). Enabling Wayland/Ozone flags."
    add_wayland_flags=1
  else
    log_notify "No Wayland session detected. Starting with defaults (X11 / XWayland)."
    add_wayland_flags=0
  fi
fi

if [[ "$add_wayland_flags" == "1" ]]; then

  need_ozone=1
  for p in "${cromite_params[@]:-}"; do
    if [[ "$p" == --ozone-platform=* ]] || [[ "$p" == --enable-features=*UseOzonePlatform* ]]; then
      need_ozone=0
      break
    fi
  done

  if [[ "$need_ozone" == "1" ]]; then
    wayland_flags=("--enable-features=UseOzonePlatform,WaylandPerSurfaceScale,WaylandUiScale" "--ozone-platform=wayland" "--gtk-version=4")
    if [[ -n "${CROMITE_DEVICE_SCALE-}" ]]; then
      wayland_flags+=("--force-device-scale-factor=${CROMITE_DEVICE_SCALE}")
      log_notify "Applying device scale factor from CROMITE_DEVICE_SCALE=${CROMITE_DEVICE_SCALE}"
    fi
    cromite_params=("${wayland_flags[@]}" "${cromite_params[@]:-}")
    log_notify "Added Wayland/Ozone flags to Cromite launch parameters."
  else
    log_notify "Ozone/Wayland flags already provided by user; not adding additional Wayland flags."
  fi
fi

log_notify "Starting Cromite..."
(nohup "$cromite_executable_path" "${cromite_params[@]:-}" &) >/dev/null 2>&1 || log_notify "Failed to launch Cromite (exit code failure)."

exit 0
