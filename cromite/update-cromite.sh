#!/bin/bash
#
# TASK: Automate the installation, updating, and launching of Cromite on Linux.
# Integrated: Wayland auto-detection + optional forcing + helpful Wayland scaling flags
# Integrated: Internet availability check — if offline, launch existing app directly.
#
# --- VERSIONING ---
# 2025-09-22, v7.3:
#  - Corrected the version detection logic. The script now stores the installed package
#    version in a `.version` file instead of incorrectly parsing the Chromium engine
#    version from the executable. This fixes incorrect update behavior.
#  - Now compares the full Cromite release tag (e.g., 125.0.6422.165-2) for more
#    accurate update detection.
#
# 2025-09-09, v7.2 (Wayland + offline start):
#  - Auto-detects Wayland and adds appropriate Ozone/Wayland flags.
#  - Supports forcing backends with --wayland and --x11 flags.
#  - Skips update checks if no internet is available and launches the existing app.
#
set -euo pipefail

# --- BASIC CONFIGURATION ---
INSTALL_BASE="$HOME/.local/share"
CROMITE_DIR="$INSTALL_BASE/cromite"
CROMITE_PROFILE_DIR="$HOME/.config/cromite"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
SCRIPT_ABSOLUTE_PATH=$(readlink -f "${BASH_SOURCE[0]}")

# --- HELPER FUNCTIONS ---
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

	cp "$CROMITE_DIR/product_logo_256.png" "$ICON_DIR/cromite.png" 2>/dev/null || \
	cp "$CROMITE_DIR/product_logo_48.png" "$ICON_DIR/cromite.png" 2>/dev/null || true

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

if [[ "${CROMITE_FORCE_WAYLAND-}" == "1" ]]; then FORCE_WAYLAND=1; fi
if [[ "${CROMITE_FORCE_X11-}" == "1" ]]; then FORCE_X11=1; fi

cromite_params=("${filtered_params[@]:-}")
cromite_executable_path="$CROMITE_DIR/chrome"

# --- 2. CHECK INSTALLATION STATUS ---

is_installed=false
installed_version="0.0.0.0" 
version_file="$CROMITE_DIR/.version"


if [[ -f "$cromite_executable_path" && -f "$version_file" ]]; then
  is_installed=true
  installed_version=$(cat "$version_file")
fi


# --- 3. DECIDE WHETHER TO UPDATE OR LAUNCH DIRECTLY ---

if ! check_internet; then
	log_notify "No Internet connection detected."
	if [[ "$is_installed" == true ]]; then
		log_notify "Launching installed Cromite directly..."
		SKIP_UPDATES=1
	else
		die "No Internet and Cromite is not installed. Connect to the Internet for the first run."
	fi
else
	SKIP_UPDATES=0
fi

if [[ "$SKIP_UPDATES" -eq 0 ]]; then
	log_notify "Checking for Cromite updates..."
	latest_release_url=$(curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/uazo/cromite/releases/latest") ||
		die "Could not resolve the latest release URL. Check network or GitHub status."

	if ! [[ "${latest_release_url}" == *"github.com/uazo/cromite/releases/tag/"* ]]; then
		die "Failed to get a valid release tag URL. Received: ${latest_release_url}"
	fi

	release_tag="${latest_release_url##*/}"
	available_version="${release_tag#v}"
	if [[ -z "$available_version" ]]; then
		die "Could not parse version number from release tag: ${release_tag}"
	fi

	if [[ "$is_installed" == true && "$(printf '%s\n' "$available_version" "$installed_version" | sort -V | tail -n1)" == "$installed_version" ]]; then
		log_notify "Cromite is up to date (Version: ${installed_version}). Launching directly."
	else
		log_notify "New version ${available_version} available. (Installed: ${installed_version})"
		
		TMP_DIR=$(mktemp -d)
		archive_name="chrome-lin64.tar.gz"
		download_url="https://github.com/uazo/cromite/releases/download/${release_tag}/${archive_name}"
		assets_url="https://github.com/uazo/cromite/releases/expanded_assets/${release_tag}"
		archive_path="${TMP_DIR}/${archive_name}"

		log_notify "Downloading Cromite..."
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

		log_notify "Installing to ${CROMITE_DIR}..."
		mkdir -p "$CROMITE_DIR"
		tar -xf "${archive_path}" --strip-components=1 -C "$CROMITE_DIR"

		echo "${available_version}" > "${version_file}"
		
		log_notify "Update complete. Cromite is now at version ${available_version}."

		if [[ "$is_installed" == false ]]; then
			create_desktop_integration
		fi
	fi
fi


# --- 4. LAUNCH CROMITE ---

if ! grep -q -- '--user-data-dir' <<<"${cromite_params[*]}"; then
	log_notify "Using default isolated profile at: ${CROMITE_PROFILE_DIR}"
	cromite_params=("--user-data-dir=${CROMITE_PROFILE_DIR}" "${cromite_params[@]:-}")
else
	log_notify "User-defined profile directory detected."
fi

# --- Wayland Flag Handling ---
add_wayland_flags=0
user_has_ozone_flags=0
for p in "${cromite_params[@]:-}"; do
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
		log_notify "Cromite: user forced X11. Skipping Wayland flags."
	elif [[ "$FORCE_WAYLAND" -eq 1 || "$WAYLAND_PRESENT" -eq 1 ]]; then
		log_notify "Wayland session detected or forced. Enabling Wayland/Ozone flags."
		add_wayland_flags=1
	else
		log_notify "No Wayland session detected. Starting with defaults (X11 / XWayland)."
	fi
fi

if [[ "$add_wayland_flags" -eq 1 ]]; then
	wayland_flags=("--enable-features=UseOzonePlatform,WaylandPerSurfaceScale,WaylandUiScale" "--ozone-platform=wayland" "--gtk-version=4")
	if [[ -n "${CROMITE_DEVICE_SCALE-}" ]]; then
		wayland_flags+=("--force-device-scale-factor=${CROMITE_DEVICE_SCALE}")
		log_notify "Applying device scale factor from CROMITE_DEVICE_SCALE=${CROMITE_DEVICE_SCALE}"
	fi
	cromite_params=("${wayland_flags[@]}" "${cromite_params[@]:-}")
fi

log_notify "Starting Cromite..."
(nohup "$cromite_executable_path" "${cromite_params[@]:-}" &) >/dev/null 2>&1

exit 0