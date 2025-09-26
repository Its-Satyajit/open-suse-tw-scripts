
### 1. What is Helium?

Helium is a modern, open-source web browser that prioritizes user privacy, speed, and a minimalist interface. Based on Chromium, it aims to provide a "bullshit-free" browsing experience by removing bloat and noise. Key features include built-in ad and tracker blocking (via uBlock Origin), enhanced privacy protections by default, and a lightweight design to ensure fast performance. The project is proudly based on ungoogled-chromium, continuing the goal of providing a web browser that respects user privacy and control.

### 2. Introduction to the Script

The Helium Installer and Launcher script provides a seamless experience for managing the Helium web browser on Linux. It automates the process of downloading, installing, and updating the browser, while also providing desktop integration and intelligent launch parameter handling for Wayland and X11 sessions.

### 3. Disclaimer

This script is an independent, third-party project created to simplify the installation and management of the Helium browser on Linux. The author of this script is not affiliated with, endorsed by, or in any way officially connected with the Helium browser project or its development team.

### 4. Quick Start

For experienced users, here's how to get started in three commands:

```bash
# 1. Download the script
curl -sSL -o helium-launcher.sh https://raw.githubusercontent.com/Its-Satyajit/open-suse-tw-scripts/main/helium-chromium/update-helium-chromium.sh

# 2. Make it executable
chmod +x helium-launcher.sh

# 3. Run it to install and launch Helium
./helium-launcher.sh
```

### 5. Features

*   **Automated Installation and Updates:** The script automatically checks for the latest version of Helium and installs or updates it as needed.
*   **Offline Launch:** If an internet connection is unavailable, the script will launch the existing installation of Helium.
*   **Desktop Integration:** On the first run, the script creates a desktop entry, an application icon, and a command-line shortcut.
*   **Wayland and X11 Detection:** The script auto-detects if a Wayland session is running and applies the necessary flags for optimal performance.
*   **Profile Management:** The script uses an isolated profile directory by default to avoid conflicts with other browser installations.
*   **Checksum Verification:** To ensure the integrity of the downloaded files, the script verifies the SHA256 checksum of the downloaded archive.

### 6. Requirements

*   A modern Linux distribution.
*   The following command-line utilities: `bash`, `curl`, `grep`, `mkdir`, `ln`, `cp`, `chmod`, `tar`, `mktemp`, `readlink`, `rm`, `sha256sum`, `sort`, `tail`.
*   `notify-send` for desktop notifications (optional).

### 7. Installation and Setup

1.  **Download the script:** Obtain the script and save it to a file (e.g., `helium-launcher.sh`).
2.  **Make it executable:** Open a terminal and run the following command:
    ```bash
    chmod +x helium-launcher.sh
    ```
3.  **Place it in your `PATH` (optional but recommended):** For easy access, move the script to a directory in your system's `PATH`, such as `~/.local/bin/`. This step also renames the script for convenience.
    ```bash
    mkdir -p ~/.local/bin
    mv helium-launcher.sh ~/.local/bin/helium-launcher
    ```

### 8. Usage

To run the script, execute it from its current directory before moving it:

```bash
./helium-launcher.sh
```

If you moved the script to your `PATH` as recommended in the setup, you can run it from any directory by its new name:

```bash
helium-launcher
```

**Command-Line Arguments:**

*   `--wayland`: Forces the script to use Wayland-specific flags.
*   `--x11`: Prevents the script from using Wayland-specific flags.

Any other arguments are passed directly to the Helium executable.

### 9. Configuration

#### Environment Variables

You can control the script's behavior by setting environment variables before running it. This is the recommended way to apply custom settings without editing the script itself.

*   `HELIUM_FORCE_WAYLAND=1`: Same as passing the `--wayland` flag.
    ```bash
    HELIUM_FORCE_WAYLAND=1 helium-launcher
    ```
*   `HELIUM_FORCE_X11=1`: Same as passing the `--x11` flag.
    ```bash
    HELIUM_FORCE_X11=1 helium-launcher
    ```
*   `HELIUM_DEVICE_SCALE=<factor>`: Forces a specific UI scale factor, which is useful on HiDPI displays under Wayland.
    ```bash
    HELIUM_DEVICE_SCALE=1.5 helium-launcher
    ```

#### Internal Script Configuration

The script includes a "BASIC CONFIGURATION" section where you can permanently change the default installation and profile directories.

*   `INSTALL_BASE`: The base directory for the installation. Defaults to `$HOME/.local/share`.
*   `HELIUM_DIR`: The directory where Helium will be installed. Defaults to `$INSTALL_BASE/helium`.
*   `HELIUM_PROFILE_DIR`: The directory for the Helium user profile. Defaults to `$HOME/.config/helium`.

### 10. Security Considerations

*   **Code Execution:** This script downloads an executable binary from the internet (from the official Helium GitHub releases) and runs it on your system. You should only run scripts from sources you trust.
*   **Checksum Verification:** To ensure the downloaded file is authentic and not corrupted, the script fetches the official SHA256 checksum from the release page and verifies the archive against it. If the checksums do not match, the script will exit with an error, preventing a corrupted or malicious file from being installed.
*   **Warning:** In the event that an official checksum cannot be found on the release page, the script will print a warning and proceed without verification. This is a fallback measure and should be noted by the user.
*   **HTTPS:** All downloads are performed over HTTPS, ensuring a secure connection to GitHub.

### 11. Troubleshooting

*   **Problem: Script fails with "Permission denied."**
    *   **Solution:** The script file is not executable. Run `chmod +x /path/to/helium-launcher.sh`.

*   **Problem: Download fails or checksum mismatch.**
    *   **Solution:** This usually indicates a network problem. Check your internet connection. A checksum mismatch means the downloaded file is incomplete or corrupt; the script will automatically delete it.

*   **Problem: Helium does not launch after the script runs.**
    *   **Solution:** Run the script from a terminal to see errors. Try forcing a display server mode with `--wayland` or `--x11`. If issues persist, you can reset your profile by running: `mv ~/.config/helium ~/.config/helium.bak`.

*   **Problem: The application icon or `helium-launcher` command does not work.**
    *   **Solution:** Your desktop environment may need to refresh its application cache. Try logging out and back in. For the command-line shortcut, ensure that `$HOME/.local/bin` is in your shell's `PATH`.

### 12. Uninstalling Helium

To completely remove Helium and all associated files created by the script, follow these steps. Open a terminal and run the following commands:

1.  **Remove the main application files:**
    ```bash
    rm -rf ~/.local/share/helium
    ```

2.  **Remove the user profile and data:**
    **Warning:** This step will permanently delete all your bookmarks, history, and settings.
    ```bash
    rm -rf ~/.config/helium
    ```

3.  **Remove the desktop integration files:**
    ```bash
    rm -f ~/.local/bin/helium
    rm -f ~/.local/share/applications/helium.desktop
    rm -f ~/.local/share/icons/hicolor/256x256/apps/helium.png
    ```

4.  **Remove the launcher script itself:**
    If you placed the script in `~/.local/bin`, remove it with:
    ```bash
    rm -f ~/.local/bin/helium-launcher
    ```

### 13. License

This script is released under the **MIT License**. You are free to use, modify, and distribute it as you see fit, provided you include the original copyright and license notice in any substantial portions of the software.

### 14. Reporting Bugs

If you find a bug in the script or have a suggestion for improvement, please open an issue on the project's official GitHub page:
[https://github.com/Its-Satyajit/open-suse-tw-scripts/tree/main/helium-chromium](https://github.com/Its-Satyajit/open-suse-tw-scripts/tree/main/helium-chromium)

### 15. Version History

*   **v1.5 (2025-09-22):** Corrected version detection logic by storing the installed package version in a `.version` file, fixing an infinite download loop.
*   **v1.4 (2025-09-22):** Corrected the executable path to 'chrome' inside the installation directory.