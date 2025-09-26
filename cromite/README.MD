
# update-cromite.sh

## Description

A Bash script that automates the installation, management, and execution of the Cromite web browser on Linux systems.

This script functions as a comprehensive wrapper, providing automatic updates, Wayland integration, offline launch support, and proper desktop environment integration. It is designed to be a seamless and reliable launcher for Cromite.

The full script source is available at:
[Its‑Satyajit/open‑suse‑tw‑scripts/blob/main/cromite/update‑cromite.sh](https://github.com/Its-Satyajit/open-suse-tw-scripts/blob/main/cromite/update-cromite.sh)

---

## Features

*   **Automated Installation and Updates**: Fetches and installs the latest Cromite version directly from the official GitHub repository.
*   **Accurate Version Tracking**: Maintains a local version file to ensure reliable update comparisons against full release tags.
*   **Display Server Support**:
    *   Automatically detects Wayland sessions and applies the necessary Ozone flags for native rendering.
    *   Provides command-line flags (`--wayland`, `--x11`) to override backend detection.
    *   Supports HiDPI scaling on Wayland via the `CROMITE_DEVICE_SCALE` environment variable.
*   **Offline Launch Capability**: Checks for an active internet connection before attempting an update. If the system is offline, it launches the existing Cromite installation.
*   **Download Integrity Verification**: Scrapes the SHA-256 checksum from the GitHub release assets page to verify the integrity of the downloaded archive.
*   **Isolated User Profile**: Utilizes a dedicated profile directory (`~/.config/cromite`) by default to prevent conflicts with other browser installations.
*   **Desktop Environment Integration**: Creates a `.desktop` file for application menus, a symbolic link for command-line execution (`cromite`), and installs the application icon.
*   **System Notifications**: Leverages `notify-send` (if available) to provide status updates for updates, launches, and errors.

---

## Installation

**1. Prerequisites**

Ensure the following utilities are available on your system. For openSUSE, they can be installed with:
```bash
sudo zypper install curl tar sha256sum libnotify-tools
```
*(Note: `libnotify-tools` provides the `notify-send` command).*

**2. Download and Execute**

Download the script and set its permissions to be executable:
```bash
curl -Lo update-cromite.sh \
  https://raw.githubusercontent.com/Its-Satyajit/open-suse-tw-scripts/main/cromite/update-cromite.sh
chmod +x update-cromite.sh
```

**3. Initial Run**

Execute the script to install Cromite:
```bash
./update-cromite.sh
```
On its first run, the script will:
1.  Fetch the latest Cromite release from GitHub.
2.  Download the `chrome-lin64.tar.gz` archive.
3.  Verify the SHA-256 checksum against the official value.
4.  Install the browser to `~/.local/share/cromite/`.
5.  Perform the necessary desktop integration steps.

---

## Usage

After installation, Cromite can be launched from your application menu or directly from the terminal. The script will automatically check for updates on each run.

*   **Standard Launch**:
    ```bash
    # This command is available in new terminal sessions after installation
    cromite
    ```

*   **Passing Command-Line Arguments**: Additional arguments are passed directly to the Cromite binary.
    ```bash
    cromite --incognito
    cromite --password-store=gnome
    ```

*   **Override User Profile Directory**:
    ```bash
    cromite --user-data-dir=/path/to/custom/profile
    ```

*   **Force Display Backend**:
    ```bash
    # Force the use of Wayland flags
    cromite --wayland

    # Force the use of X11 (disables Wayland auto-detection)
    cromite --x11
    ```

*   **Configure HiDPI Scaling (Wayland)**: Use the `CROMITE_DEVICE_SCALE` environment variable to set a custom scale factor.
    ```bash
    CROMITE_DEVICE_SCALE=1.5 cromite
    ```

---

## Installed File Paths

| Component         | Location                                                |
| ----------------- | ------------------------------------------------------- |
| Application Files | `~/.local/share/cromite/`                               |
| Version File      | `~/.local/share/cromite/.version`                       |
| Command-Line Link | `~/.local/bin/cromite`                                  |
| Desktop Entry     | `~/.local/share/applications/cromite.desktop`           |
| Icon File         | `~/.local/share/icons/hicolor/256x256/apps/cromite.png` |
| Default Profile   | `~/.config/cromite/`                                    |

---

## Security and Reliability

*   **Update Logic**: Compares full version tags (e.g., `125.0.6422.165-2`) to ensure update accuracy and prevent version parsing errors.
*   **Integrity Verification**: Ensures downloads are authentic by comparing the SHA-256 checksum with the value published on the official GitHub release page.
*   **Error Handling**: The script is designed to abort safely on failed downloads, checksum mismatches, or invalid release tags. The internet check prevents update attempts when offline.
*   **Scripting Practices**: Uses `set -euo pipefail` and a cleanup trap to ensure predictable behavior and prevent partial state changes on error.

---

## Troubleshooting

*   **`cromite: command not found`**: This error indicates that `~/.local/bin` is not in your shell's `PATH`. To fix this, add `export PATH="$HOME/.local/bin:$PATH"` to your `~/.bashrc` or `~/.zshrc` file and restart your terminal session.
*   **Checksum Mismatch Error**: A network issue may have resulted in a corrupted download. The script removes temporary files automatically. Re-running the script will attempt the download again.
*   **Display or Scaling Issues**: If the browser appears incorrectly scaled on a Wayland session, try setting a manual scale factor (e.g., `CROMITE_DEVICE_SCALE=1.25 cromite`). If the display backend is not detected correctly, use the `--wayland` or `--x11` flags to enforce the proper mode.

---

## Uninstallation

To completely remove the Cromite browser and all associated configuration files created by this script, execute the following command:
```bash
rm -rf ~/.local/share/cromite \
       ~/.config/cromite \
       ~/.local/bin/cromite \
       ~/.local/share/applications/cromite.desktop \
       ~/.local/share/icons/hicolor/256x256/apps/cromite.png
```

---

## License

This script is distributed under the MIT License. See the [LICENSE](https://github.com/Its-Satyajit/open-suse-tw-scripts/blob/main/LICENSE) file for more details.

---

## Credits

*   **Author**: [Its-Satyajit](https://github.com/Its-Satyajit)
*   **Inspiration**: [ghnbr's issue comment](https://github.com/uazo/cromite/issues/771#issuecomment-2050103749)
*   **Project**: Based on the [uazo/cromite](https://github.com/uazo/cromite) browser.