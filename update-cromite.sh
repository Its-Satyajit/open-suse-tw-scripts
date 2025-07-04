#!/bin/bash

# --- Strict Mode & Error Handling ---
# -e: exit immediately if a command exits with a non-zero status.
# -u: treat unset variables as an error when substituting.
# -o pipefail: the return value of a pipeline is the status of the last command
#              to exit with a non-zero status, or zero if no command exited
#              with a non-zero status.
set -euo pipefail

#######################################
# Sends a notification to the desktop user or prints to the console.
# Globals:
#   DISPLAY
# Arguments:
#   A message string.
# Outputs:
#   Writes the message to stdout and sends a desktop notification if possible.
#######################################
log_notify() {
    local message="$1"
    echo "INFO: ${message}"
    # Only attempt to send a notification if a display server is running
    # and the `notify-send` command is available.
    if [[ -n "${DISPLAY-}" ]] && command -v notify-send &>/dev/null; then
        notify-send "Cromite Updater" "${message}"
    fi
}

#######################################
# Logs a critical error message and exits the script.
# Arguments:
#   An error message string.
# Outputs:
#   Writes the error message to stderr and exits with status 1.
#######################################
die() {
    local error_message="$1"
    echo "ERROR: ${error_message}" >&2
    if [[ -n "${DISPLAY-}" ]] && command -v notify-send &>/dev/null; then
        notify-send -u critical "Cromite Updater FAILED" "${error_message}"
    fi
    exit 1
}

# --- Cleanup ---
# A trap to ensure the temporary directory is removed on script exit,
# error, or interrupt.
# shellcheck disable=SC2154 # TMP_DIR is defined and checked before use.
cleanup() {
    if [[ -n "${TMP_DIR-}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
        log_notify "Temporary files cleaned up."
    fi
}
trap cleanup EXIT

# --- Main Script ---

# 1. ✅ Correctness: Handle script arguments.
if [[ $# -lt 1 ]]; then
    # Default to a 'chrome-lin' subdirectory in the script's own directory
    # if no folder is provided. This matches the original script's intent.
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
    cromite_install_dir="${script_dir}/chrome-lin"
    log_notify "No destination folder provided. Defaulting to ${cromite_install_dir}"
else
    cromite_install_dir="${1%/}" # Remove trailing slash if present
    shift # Removes the first argument, leaving the rest for Cromite
fi

# All remaining arguments will be passed to the cromite executable.
cromite_params=("$@")

# 2. ✅ Correctness: Fetch release information.
# The 'latest' URL redirects to the canonical, versioned release page.
# Using `curl -Ls -w %{url_effective}` is a robust way to get the final URL.
log_notify "Locating the latest Cromite release..."
latest_release_url=$(curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/uazo/cromite/releases/latest") ||
    die "Could not resolve the latest release URL. Check network or GitHub status."

# Construct the full URLs for the metadata and checksum files.
metadata_url="${latest_release_url}/download/updateurl.txt"
checksum_url="${latest_release_url}/download/sha256sum.txt"
archive_name="chrome-lin64.tar.gz"
download_url="${latest_release_url}/download/${archive_name}"

metadata=$(curl -fsSL "${metadata_url}") || die "Failed to download update metadata from ${metadata_url}."

# 🧼 Quality: Use awk for reliable key-value parsing. More robust than grep.
available_version=$(echo "${metadata}" | awk -F'[=;]' '{for(i=1;i<=NF;i+=2) if($i=="version") print $(i+1)}')

if [[ -z "$available_version" ]]; then
    die "Could not parse the available version from metadata. The format may have changed."
fi

# 3. ✅ Correctness: Check the currently installed version.
if [[ -f "${cromite_install_dir}/chrome" ]]; then
    # Use sed to reliably extract just the version number string.
    installed_version=$("${cromite_install_dir}/chrome" --version | sed -E 's/Cromite ([0-9.]+).*/\1/')
else
    log_notify "Cromite not found in ${cromite_install_dir}. Will perform a fresh installation."
    mkdir -p "${cromite_install_dir}"
    installed_version="0.0.0.0" # Set to a base version for comparison.
fi

# 4. ✅ Correctness: Compare versions using `sort -V` (version sort).
# This correctly handles version strings like '125.0.6422.14' vs '124.0.6367.85'.
if [[ "$(printf '%s\n' "$available_version" "$installed_version" | sort -V | head -n1)" == "$available_version" ]] && \
   [[ "$available_version" != "$installed_version" ]]; then
    log_notify "Cromite is up to date. Version: ${installed_version}."
else
    # 5. 🔐 Security & 🧼 Quality: Begin update process.
    log_notify "New version ${available_version} available. (Installed: ${installed_version})"
    
    # Use mktemp to create a secure temporary directory.
    TMP_DIR=$(mktemp -d)
    archive_path="${TMP_DIR}/${archive_name}"

    log_notify "Downloading from ${download_url}"
    curl --progress-bar -L "${download_url}" -o "${archive_path}"

    # 6. 🔐 SECURITY: CRITICAL STEP - Verify the download's integrity.
    log_notify "Verifying download integrity with SHA256 checksum..."
    checksum_data=$(curl -fsSL "${checksum_url}") || die "Could not download checksum file."

    # Find the specific checksum for our archive.
    expected_checksum=$(echo "${checksum_data}" | grep "${archive_name}" | awk '{print $1}')

    if [[ -z "$expected_checksum" ]]; then
        die "Could not find a checksum for ${archive_name} in the release assets."
    fi

    # 👩‍💻 Explanation: Use `sha256sum --check` for a robust and simple verification.
    # The status flag makes it silent on success, perfect for scripting.
    echo "${expected_checksum}  ${archive_path}" | sha256sum --check --status
    if [[ $? -ne 0 ]]; then
        die "CHECKSUM MISMATCH! The downloaded file may be corrupt or tampered with. Deleting."
    fi
    log_notify "Checksum valid. Proceeding with installation."

    # 7. ✅ Correctness: Extract and install the update.
    log_notify "Extracting archive to ${cromite_install_dir}/"
    # --strip-components=1 removes the top-level 'chrome-lin/' directory from the
    # archive, placing its contents directly into our target directory.
    tar -xf "${archive_path}" --strip-components=1 -C "${cromite_install_dir}"
    log_notify "Update complete. Cromite is now at version ${available_version}."
fi

# 8. 🚀 Run Cromite.
# 👩‍💻 Explanation: Launch Cromite as a background process (`&`) and detach it from the
# terminal (`nohup`), ensuring it keeps running even if the terminal is closed.
# Pass any extra arguments from the original script call (`"${cromite_params[@]}"`).
log_notify "Starting Cromite..."
(nohup "${cromite_install_dir}/chrome" "${cromite_params[@]}" &) > /dev/null 2>&1



exit 0