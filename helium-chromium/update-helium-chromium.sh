#!/bin/bash
#
# TASK: Automate the installation, updating, and launching of Helium on Linux.
# Integrated: Wayland auto-detection + optional forcing + helpful Wayland scaling flags
# Integrated: Internet availability check — if offline, launch existing app directly.
#
# --- VERSIONING ---
# 2025-09-22, Assistant, v1.4 (Helium fork):
#  - Corrected the executable path to 'chrome' inside the installation directory.
#  - This fixes the infinite download loop by correctly detecting the installed version.
#
set -euo pipefail

# --- BASIC CONFIGURATION ---
INSTALL_BASE="$HOME/.local/share"
HELIUM_DIR="$INSTALL_BASE/helium"
HELIUM_PROFILE_DIR="$HOME/.config/helium"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
SCRIPT_ABSOLUTE_PATH=$(readlink -f "${BASH_SOURCE[0]}")

# The executable inside the tar.xz is named 'chrome'
HELIUM_EXECUTABLE_NAME="chrome"

# --- HELPER FUNCTIONS ---
log_notify() {
  local message="$1"
  echo "INFO: ${message}"
  if [[ -n "${DISPLAY-}" ]] && command -v notify-send &>/dev/null; then
    notify-send "Helium Updater" "${message}"
  fi
}

die() {
  local error_message="$1"
  echo "ERROR: ${error_message}" >&2
  if [[ -n "${DISPLAY-}" ]] && command -v notify-send &>/dev/null; then
    notify-send -u critical "Helium Updater FAILED" "${error_message}"
  fi
  exit 1
}

create_desktop_integration() {
  log_notify "Performing first-time desktop integration..."
  mkdir -p "$HELIUM_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"
  # Create a convenient 'helium' command that points to the actual executable
  if ln -sf "$HELIUM_DIR/$HELIUM_EXECUTABLE_NAME" "$BIN_DIR/helium"; then
    log_notify "Created command-line shortcut. You can now type 'helium' in a new terminal."
  else
    log_notify "WARN: Could not create symlink in $BIN_DIR. Is it in your PATH?"
  fi
  cp "$HELIUM_DIR/product_logo_256.png" "$ICON_DIR/helium.png" 2>/dev/null || \
  cp "$HELIUM_DIR/product_logo_48.png" "$ICON_DIR/helium.png" 2>/dev/null || true
  local desktop_file_path="$DESKTOP_DIR/helium.desktop"
  cat >"$desktop_file_path" <<EOF
[Desktop Entry]
Version=1.0
Name=Helium
Comment=Update and Launch the Helium Web Browser
Exec=${SCRIPT_ABSOLUTE_PATH} %U
Icon=helium
Terminal=false
Type=Application
Categories=Network;WebBrowser;
EOF
  chmod +x "$desktop_file_path"
  log_notify "Installation complete. Helium is now available in your application menu."
}

check_internet() {
  if command -v curl &>/dev/null; then
    curl -fsS --head --max-time 5 https://github.com >/dev/null 2>&1 && return 0
  fi
  if command -v ping &>/dev/null; then
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && return 0
  fi
  return 1
}

cleanup() {
  if [[ -n "${TMP_DIR-}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

# --- 1. PREPARE LAUNCH PARAMETERS ---

orig_params=("$@")
filtered_params=()
FORCE_WAYLAND=0
FORCE_X11=0
for p in "${orig_params[@]:-}"; do
  case "$p" in
    --wayland) FORCE_WAYLAND=1 ;;
    --x11) FORCE_X11=1 ;;
    *) filtered_params+=("$p") ;;
  esac
done

if [[ "${HELIUM_FORCE_WAYLAND-}" == "1" ]]; then FORCE_WAYLAND=1; fi
if [[ "${HELIUM_FORCE_X11-}" == "1" ]]; then FORCE_X11=1; fi

helium_params=("${filtered_params[@]:-}")
helium_executable_path="$HELIUM_DIR/$HELIUM_EXECUTABLE_NAME"

if ! grep -q -- '--user-data-dir' <<<"${helium_params[*]}"; then
  log_notify "Using default isolated profile at: ${HELIUM_PROFILE_DIR}"
  helium_params=("--user-data-dir=${HELIUM_PROFILE_DIR}" "${helium_params[@]:-}")
else
  log_notify "User-defined profile directory detected."
fi

add_wayland_flags=0
user_has_ozone_flags=0
for p in "${helium_params[@]:-}"; do
  if [[ "$p" == --ozone-platform=* ]] || [[ "$p" == --enable-features=*UseOzonePlatform* ]]; then
    user_has_ozone_flags=1
    break
  fi
done

if [[ "$user_has_ozone_flags" -eq 0 ]]; then
  XDG_TYPE="${XDG_SESSION_TYPE-}"
  WAYLAND_PRESENT=0
  if [[ -n "${WAYLAND_DISPLAY-}" || "${XDG_TYPE}" == "wayland" ]]; then WAYLAND_PRESENT=1; fi

  if [[ "$FORCE_X11" -eq 1 ]]; then
    log_notify "Helium: user forced X11. Skipping Wayland flags."
  elif [[ "$FORCE_WAYLAND" -eq 1 || "$WAYLAND_PRESENT" -eq 1 ]]; then
    log_notify "Wayland session detected or forced. Enabling Wayland/Ozone flags."
    add_wayland_flags=1
  else
    log_notify "No Wayland session detected. Starting with defaults (X11 / XWayland)."
  fi
fi

if [[ "$add_wayland_flags" -eq 1 ]]; then
  wayland_flags=("--enable-features=UseOzonePlatform,WaylandPerSurfaceScale,WaylandUiScale" "--ozone-platform=wayland" "--gtk-version=4")
  if [[ -n "${HELIUM_DEVICE_SCALE-}" ]]; then
    wayland_flags+=("--force-device-scale-factor=${HELIUM_DEVICE_SCALE}")
    log_notify "Applying device scale factor from HELIUM_DEVICE_SCALE=${HELIUM_DEVICE_SCALE}"
  fi
  helium_params=("${wayland_flags[@]}" "${helium_params[@]:-}")
fi

# --- 2. CHECK INSTALLATION STATUS ---
is_installed=false
if [[ -f "$helium_executable_path" ]]; then
  is_installed=true
  installed_version=$("$helium_executable_path" --version 2>/dev/null | sed -E 's/[^0-9]*([0-9.]+).*/\1/' || echo "unknown")
else
  installed_version="0.0.0.0"
fi

# --- 3. DECIDE WHETHER TO UPDATE OR LAUNCH DIRECTLY ---

if ! check_internet; then
  log_notify "No Internet connection detected."
  if [[ "$is_installed" == true ]]; then
    log_notify "Launching installed Helium directly..."
    exec "$helium_executable_path" "${helium_params[@]:-}"
  else
    die "No Internet and Helium is not installed. Connect to the Internet for the first run."
  fi
fi

log_notify "Checking for Helium updates..."
latest_release_url=$(curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/imputnet/helium-linux/releases/latest") ||
  die "Could not resolve the latest release URL. Check network or GitHub status."

if ! [[ "${latest_release_url}" == *"github.com/imputnet/helium-linux/releases/tag/"* ]]; then
  die "Failed to get a valid release tag URL. Received: ${latest_release_url}"
fi
release_tag="${latest_release_url##*/}"
available_version=$(echo "${release_tag}" | sed -E 's/^v?([0-9.]+).*/\1/')
if [[ -z "$available_version" ]]; then
  die "Could not parse version number from release tag: ${release_tag}"
fi

if [[ "$is_installed" == true && "$(printf '%s\n' "$available_version" "$installed_version" | sort -V | tail -n1)" == "$installed_version" ]]; then
  log_notify "Helium is up to date (Version: ${installed_version}). Launching directly."
  exec "$helium_executable_path" "${helium_params[@]:-}"
fi

# --- 4. PERFORM UPDATE/INSTALLATION ---

log_notify "New version ${available_version} available. (Installed: ${installed_version})"
TMP_DIR=$(mktemp -d)
archive_name="helium-${available_version}-x86_64_linux.tar.xz"
download_url="https://github.com/imputnet/helium-linux/releases/download/${release_tag}/${archive_name}"
assets_url="https://github.com/imputnet/helium-linux/releases/expanded_assets/${release_tag}"
archive_path="${TMP_DIR}/${archive_name}"

log_notify "Downloading Helium..."
curl -sS -L "${download_url}" -o "${archive_path}" || die "Download failed from ${download_url}"

log_notify "Verifying download integrity..."
assets_html=$(curl -fsSL "${assets_url}") || die "Could not download release assets HTML."
expected_checksum=$(echo "${assets_html}" | grep -A 8 "${archive_name}" | grep -o 'sha256:[0-9a-f]\{64\}' | cut -d ':' -f 2 | head -n 1 || true)

if [[ -z "$expected_checksum" ]]; then
  log_notify "WARN: Could not parse checksum. Proceeding without verification."
else
  log_notify "Found expected checksum: ${expected_checksum}"
  echo "${expected_checksum}  ${archive_path}" | sha256sum --check --status || die "CHECKSUM MISMATCH!"
  log_notify "Checksum valid."
fi

log_notify "Installing to ${HELIUM_DIR}..."
mkdir -p "$HELIUM_DIR"
tar -xf "${archive_path}" --strip-components=1 -C "$HELIUM_DIR"
log_notify "Update complete. Helium is now at version ${available_version}."

if [[ "$is_installed" == false ]]; then
  create_desktop_integration
fi

# --- 5. LAUNCH AFTER SUCCESSFUL UPDATE ---
log_notify "Starting updated Helium..."
(nohup "$helium_executable_path" "${helium_params[@]:-}" &) >/dev/null 2>&1

exit 0