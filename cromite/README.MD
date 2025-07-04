# 🛠️ update‑cromite.sh

**A Bash script that automates installation, updates, and launching of Cromite on Linux (supports openSUSE Tumbleweed and others).**

You can find the full script source here:
[Its‑Satyajit/open‑suse‑tw‑scripts/blob/main/cromite/update‑cromite.sh](https://github.com/Its-Satyajit/open-suse-tw-scripts/blob/main/cromite/update-cromite.sh)

---

## ⚙️ Features

* **Auto-install & auto-update** Cromite from the latest GitHub release
* **Smart profile isolation** using `~/.config/cromite` by default
* **Checksum verification** via SHA‑256 from GitHub assets
* **Desktop integration** (symlink, icon, `.desktop` file)
* **Desktop notifications** via `notify-send` (if available)

---

## 🚀 Installation

Ensure these tools are installed:

```bash
sudo zypper install curl tar sha256sum notify-send
```

Then download and make the script executable:

```bash
curl -Lo update-cromite.sh \
  https://raw.githubusercontent.com/Its-Satyajit/open-suse-tw-scripts/main/cromite/update-cromite.sh
chmod +x update-cromite.sh
```

Run:

```bash
./update-cromite.sh
```

The script will:

1. Fetch the latest Cromite release from GitHub
2. Compare versions and download if newer
3. Verify SHA‑256 checksum
4. Install under `~/.local/share/cromite/`
5. Set up desktop integration if first run

---

## ▶️ Usage

* **Launch Cromite**:

  ```bash
  ./update-cromite.sh
  # or
  cromite
  ```

* **Pass additional Chromium flags**, e.g.:

  ```bash
  ./update-cromite.sh --incognito
  ```

* **Override profile directory**:

  ```bash
  ./update-cromite.sh --user-data-dir=/path/to/my/profile
  ```

---

## 📁 Installed Paths

| Item            | Path                                                    |
| --------------- | ------------------------------------------------------- |
| Cromite binary  | `~/.local/share/cromite/chrome`                         |
| CLI wrapper     | `~/.local/bin/cromite`                                  |
| Desktop entry   | `~/.local/share/applications/cromite.desktop`           |
| Icon            | `~/.local/share/icons/hicolor/256x256/apps/cromite.png` |
| Default profile | `~/.config/cromite/`                                    |

---

## 🔒 Security & Reliability

* Performs version check using GitHub’s `/releases/latest`
* Verifies downloads via embedded SHA‑256 checksums
* Aborts on invalid tags, failed downloads, or checksum mismatches
* Uses `set -euo pipefail`, trapping cleanup on exit

---

## ❓ Troubleshooting

* Ensure required tools are installed (notably `curl`, `sha256sum`, `tar`, `notify-send`)
* Check that `~/.local/bin` is in your `PATH`
* For failed checksum, clear temporary files and rerun
* On profile conflicts, use `--user-data-dir` to choose a custom directory

---

## ⚠️ Uninstall

Remove everything with:

```bash
rm -rf ~/.local/share/cromite \
       ~/.config/cromite \
       ~/.local/bin/cromite \
       ~/.local/share/applications/cromite.desktop \
       ~/.local/share/icons/hicolor/256x256/apps/cromite.png
```

---

## 📄 License

MIT License — see [LICENSE](https://github.com/Its-Satyajit/open-suse-tw-scripts/blob/main/LICENSE) for details.

---

## 🧠 Credits

* Script by **[Its-Satyajit](https://github.com/Its-Satyajit)**
* Inspired By [ghnbr](https://github.com/uazo/cromite/issues/771#issuecomment-2050103749)
* Based on Cromite browser project: [uazo/cromite](https://github.com/uazo/cromite)

