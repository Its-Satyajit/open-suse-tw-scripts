#!/bin/bash
#
# TASK: Automate the installation, updating, and launching of Cromite on Linux.
#
# --- VERSIONING ---
# 2025-07-04, Gemini, v7.0 (Production):
#   - FINAL, CRITICAL FIX: Implemented "smart profile" isolation.
#   - The script now automatically uses an isolated profile directory at
#     ~/.config/cromite to prevent conflicts with other Chromium-based browsers.
#   - It will still respect a user-provided --user-data-dir for advanced use.
#   - This resolves the clashing issue and creates a truly independent browser.
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

  cp "$CROMITE_DIR/product_logo_256.png" "$ICON_DIR/cromite.png"

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

cromite_params=("$@")

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

cromite_executable_path="$CROMITE_DIR/chrome"
is_installed=false
if [[ -f "$cromite_executable_path" ]]; then
  is_installed=true
  installed_version=$("$cromite_executable_path" --version | sed -E 's/Cromite ([0-9.]+).*/\1/')
else
  log_notify "Cromite not found in ${CROMITE_DIR}. Preparing for first-time installation."
  mkdir -p "$CROMITE_DIR"
  installed_version="0.0.0.0"
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

# --- Smart Profile Handling ---
# Check if the user has already specified a user-data-dir.
# The `<<<` is a "here string", a clean way to pipe a variable to grep.
if ! grep -q -- '--user-data-dir' <<<"${cromite_params[*]}"; then
  # If not, add our default, isolated profile directory to the parameters.
  log_notify "Using default isolated profile at: ${CROMITE_PROFILE_DIR}"
  cromite_params=("--user-data-dir=${CROMITE_PROFILE_DIR}" "${cromite_params[@]}")
else
  log_notify "User-defined profile directory detected. Respecting user choice."
fi

log_notify "Starting Cromite..."
(nohup "$cromite_executable_path" "${cromite_params[@]}" &) >/dev/null 2>&1

exit 0
