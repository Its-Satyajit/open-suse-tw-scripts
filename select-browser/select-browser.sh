#!/usr/bin/env bash
# open-with-browser-with-icons.sh
set -euo pipefail

progname="$(basename "$0")"
url=""
choose_label=""
dry_run=false
debug=false
list_only=false
BROWSER_CHOICES_FILE="${BROWSER_CHOICES_FILE:-}"

print_help() {
  cat <<EOF
Usage: $progname [options] <url>

Options:
  --list               Print available browser labels and exit
  --choose "Label"     Non-interactively choose a browser by label
  --dry-run            Print the command that would be executed (don't run)
  --debug              Print debug info
  --help               Show this help
Choice format (builtin or in BROWSER_CHOICES_FILE):
  command|Label|icon    # 'icon' is optional: either an icon-name or a path to an image file
Examples:
  "/usr/bin/brave-browser-stable|Brave|/usr/share/icons/hicolor/48x48/apps/brave.png"
  "/usr/bin/vivaldi-stable|Vivaldi|browser"
EOF
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) print_help; exit 0;;
    --list) list_only=true; shift ;;
    --choose) choose_label="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --debug) debug=true; shift ;;
    --) shift; break ;;
    -*)
      echo "Unknown option: $1" >&2; print_help; exit 2;;
    *)
      url="$1"; shift ;;
  esac
done

if [ -z "$url" ] && ! $list_only && [ -z "$choose_label" ]; then
  echo "No URL provided" >&2
  print_help
  exit 1
fi

# normalize URL
if [ -n "$url" ] && [[ "$url" != *"://"* ]]; then
  url="http://$url"
fi

# Default choices (command | label | optional icon-name-or-path)
default_choices=(
  "/home/its-satyajit/scripts/helium-chromium/update-helium-chromium.sh|Helium|/usr/share/pixmaps/helium.png"
  "/usr/bin/vivaldi-stable|Vivaldi|/usr/share/icons/hicolor/48x48/apps/vivaldi.png"
  "/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=launch-script.sh --file-forwarding app.zen_browser.zen|Zen Browser|🧘"
  "/home/its-satyajit/scripts/cromite/update-cromite.sh|Cromite|🧪"
  "/usr/bin/brave-browser-stable|Brave|/usr/share/icons/hicolor/48x48/apps/brave.png"
)

# load choices from file if provided
choices=()
if [ -n "$BROWSER_CHOICES_FILE" ] && [ -r "$BROWSER_CHOICES_FILE" ]; then
  while IFS= read -r line; do
    [[ -z "$line" || "${line:0:1}" = "#" ]] && continue
    choices+=("$line")
  done < "$BROWSER_CHOICES_FILE"
else
  choices=("${default_choices[@]}")
fi

# helpers
emoji_for_label() {
  case "$1" in
    Brave*)  echo "🦁";;
    Vivaldi*) echo "🧭";;
    Chromium*|Chrome*|Helium*) echo "🌐";;
    Zen*) echo "🌀";;
    Cromite*) echo "🧪";;
    *) echo "🔗";;
  esac
}

available_cmds=()
available_labels=()
available_icons=()

for entry in "${choices[@]}"; do
  # split into 3 parts (cmd|label|icon)
  IFS='|' read -r cmd label icon <<< "$entry"
  cmd_base="${cmd%% *}"
  if command -v "$cmd_base" >/dev/null 2>&1 || [ -x "$cmd_base" ]; then
    available_cmds+=("$cmd")
    available_labels+=("$label")
    # normalize icon: if empty, map an emoji
    if [ -z "${icon:-}" ]; then
      available_icons+=("$(emoji_for_label "$label")")
    else
      available_icons+=("$icon")
    fi
  else
    $debug && echo "[debug] skipping '$label' (missing $cmd_base)" >&2
  fi
done

if [ ${#available_labels[@]} -eq 0 ]; then
  echo "No browsers available." >&2
  exit 2
fi

if $list_only; then
  for i in "${!available_labels[@]}"; do
    printf "%s\t%s\n" "${available_labels[$i]}" "${available_icons[$i]}"
  done
  exit 0
fi

selection=""

# If --choose specified - validate
if [ -n "$choose_label" ]; then
  for lab in "${available_labels[@]}"; do
    if [ "$lab" = "$choose_label" ]; then
      selection="$lab"
      break
    fi
  done
  if [ -z "$selection" ]; then
    echo "Label not found among available browsers." >&2
    exit 3
  fi
else
  # prefer yad (supports per-row images), then kdialog, then rofi/dmenu, then terminal
  if command -v yad >/dev/null 2>&1; then
    # build argument list: alternating icon + label
    yad_args=()
    for i in "${!available_labels[@]}"; do
      icon="${available_icons[$i]}"
      label="${available_labels[$i]}"
      # if icon is a path and not present, fallback to emoji
      if [[ "$icon" = /* ]] && [ ! -e "$icon" ]; then
        icon="$(emoji_for_label "$label")"
      fi
      yad_args+=("$icon" "$label")
    done
    # --print-column=2 returns the selected Browser column
    selection=$(yad --list --column "Icon" --column "Browser" "${yad_args[@]}" --print-column=2 --height=320 --width=420 2>/dev/null || true)
  fi

  if [ -z "$selection" ] && command -v kdialog >/dev/null 2>&1; then
    # kdialog doesn't support per-row icons in radiolist; show names but keep icons for other backends
    kargs=()
    for lab in "${available_labels[@]}"; do
      kargs+=("$lab" "$lab" "off")
    done
    selection=$(kdialog --radiolist "Select browser to open link:" "${kargs[@]}" 2>/dev/null || true)
  fi

  if [ -z "$selection" ] && command -v rofi >/dev/null 2>&1; then
    # rofi: many setups support icons; but to be broadly compatible we prefix with emoji/glyph
    display_list=()
    for i in "${!available_labels[@]}"; do
      icon="${available_icons[$i]}"
      label="${available_labels[$i]}"
      # if icon is an absolute file, try to use a fallback glyph instead of file (rofi icon support varies)
      if [[ "$icon" = /* ]]; then
        glyph="$(emoji_for_label "$label")"
      else
        glyph="$icon"
      fi
      display_list+=("$glyph $label")
    done
    selection=$(printf "%s\n" "${display_list[@]}" | rofi -dmenu -i -p "Select browser:" 2>/dev/null || true)
    # strip leading glyph to recover the label
    if [ -n "$selection" ]; then
      # remove first token (glyph)
      selection="${selection#* }"
    fi
  fi

  if [ -z "$selection" ] && command -v dmenu >/dev/null 2>&1; then
    display_list=()
    for i in "${!available_labels[@]}"; do
      glyph="${available_icons[$i]}"
      label="${available_labels[$i]}"
      # if glyph is a path, fallback to emoji
      if [[ "$glyph" = /* ]]; then glyph="$(emoji_for_label "$label")"; fi
      display_list+=("$glyph $label")
    done
    selection=$(printf "%s\n" "${display_list[@]}" | dmenu -i -p "Select browser:" 2>/dev/null || true)
    if [ -n "$selection" ]; then selection="${selection#* }"; fi
  fi

  if [ -z "$selection" ]; then
    echo "Select browser (type number and Enter):"
    PS3="Choice> "
    # list with index and an emoji column
    options=()
    for i in "${!available_labels[@]}"; do
      glyph="${available_icons[$i]}"
      options+=("$glyph ${available_labels[$i]}")
    done
    options+=("Cancel")
    select opt in "${options[@]}"; do
      if [ "$opt" = "Cancel" ] || [ -z "$opt" ]; then
        echo "Cancelled."
        exit 0
      fi
      selection="${opt#* }"
      break
    done
  fi
fi

[ -z "$selection" ] && { echo "No selection made."; exit 0; }
$debug && echo "[debug] selected: $selection" >&2

# find command for the selection
selected_cmd=""
for i in "${!available_labels[@]}"; do
  if [ "${available_labels[$i]}" = "$selection" ]; then
    selected_cmd="${available_cmds[$i]}"
    break
  fi
done

if [ -z "$selected_cmd" ]; then
  echo "Could not find command for selection." >&2
  exit 4
fi

# split into array and append URL
read -r -a cmd_parts <<< "$selected_cmd"
cmd_parts_with_url=("${cmd_parts[@]}" "$url")

if $dry_run; then
  printf "DRY-RUN: %q" "${cmd_parts_with_url[0]}"
  for ((i=1;i<${#cmd_parts_with_url[@]};i++)); do
    printf " %q" "${cmd_parts_with_url[i]}"
  done
  printf "\n"
  exit 0
fi

$debug && {
  echo "[debug] executing:" >&2
  printf "  %q" "${cmd_parts_with_url[0]}"
  for ((i=1;i<${#cmd_parts_with_url[@]};i++)); do printf " %q" "${cmd_parts_with_url[i]}"; done
  echo >&2
}

# Launch detached
if command -v setsid >/dev/null 2>&1; then
  setsid "${cmd_parts_with_url[@]}" >/dev/null 2>&1 &
else
  nohup "${cmd_parts_with_url[@]}" >/dev/null 2>&1 &
fi
disown >/dev/null 2>&1 || true

exit 0
