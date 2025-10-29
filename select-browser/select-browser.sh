#!/usr/bin/env bash
# open-with-browser.sh
# Usage: open-with-browser.sh [--list] [--choose "Label"] [--dry-run] [--debug] URL
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
Env:
  BROWSER_CHOICES_FILE Path to a file that defines choices (overrides builtin)
                       File format: one entry per line with: command|Label
EOF
}

# parse args (simple)
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

# normalize URL: if doesn't contain :// assume http://
if [ -n "$url" ] && [[ "$url" != *"://"* ]]; then
  url="http://$url"
fi

# Default choices (command | display label)
default_choices=(
  "/home/its-satyajit/scripts/helium-chromium/update-helium-chromium.sh|Helium"
  "/usr/bin/vivaldi-stable|Vivaldi"
  "/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=launch-script.sh --file-forwarding app.zen_browser.zen|Zen Browser"
  "/home/its-satyajit/scripts/cromite/update-cromite.sh|Cromite"
  "/usr/bin/brave-browser-stable|Brave"
)

# load choices from file if provided
choices=()
if [ -n "$BROWSER_CHOICES_FILE" ] && [ -r "$BROWSER_CHOICES_FILE" ]; then
  while IFS= read -r line; do
    # ignore empty lines and comments
    [[ -z "$line" || "${line:0:1}" = "#" ]] && continue
    choices+=("$line")
  done < "$BROWSER_CHOICES_FILE"
else
  choices=("${default_choices[@]}")
fi

# Build arrays of available commands/labels
available_cmds=()
available_labels=()

for entry in "${choices[@]}"; do
  # split on last '|' to allow '|' in paths/args (unlikely but safer)
  cmd="${entry%%|*}"
  label="${entry#*|}"
  # base program is first token of cmd (used to test availability)
  cmd_base="${cmd%% *}"
  # check existence: either in PATH or explicitly executable
  if command -v "$cmd_base" >/dev/null 2>&1 || [ -x "$cmd_base" ]; then
    available_cmds+=("$cmd")
    available_labels+=("$label")
  else
    $debug && echo "[debug] skipping '$label' (missing $cmd_base)" >&2
  fi
done

# nothing available
if [ ${#available_labels[@]} -eq 0 ]; then
  echo "No browsers available." >&2
  exit 2
fi

# --list: print available labels and exit
if $list_only; then
  for label in "${available_labels[@]}"; do
    echo "$label"
  done
  exit 0
fi

# choose either via --choose or interactive menu
selection=""

if [ -n "$choose_label" ]; then
  # verify label exists (exact match)
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
  # try GUI menus in order: kdialog, zenity, rofi, dmenu; fallback to terminal select
  if command -v kdialog >/dev/null 2>&1; then
    # kdialog radiolist wants triples: <id> <text> <state>; we'll use label as id and text
    kargs=()
    for lab in "${available_labels[@]}"; do
      kargs+=("$lab" "$lab" "off")
    done
    selection=$(kdialog --radiolist "Select browser to open link:" "${kargs[@]}" 2>/dev/null || true)
  fi

  if [ -z "$selection" ] && command -v zenity >/dev/null 2>&1; then
    # zenity list: use --list --radiolist requires extra formatting; use simple list
    selection=$(printf "%s\n" "${available_labels[@]}" | zenity --list --column "Browser" --text="Select browser to open link:" --height=300 --width=400 2>/dev/null || true)
  fi

  if [ -z "$selection" ] && command -v rofi >/dev/null 2>&1; then
    selection=$(printf "%s\n" "${available_labels[@]}" | rofi -dmenu -p "Select browser:" 2>/dev/null || true)
  fi

  if [ -z "$selection" ] && command -v dmenu >/dev/null 2>&1; then
    selection=$(printf "%s\n" "${available_labels[@]}" | dmenu -i -p "Select browser:" 2>/dev/null || true)
  fi

  # terminal fallback
  if [ -z "$selection" ]; then
    echo "Select browser (type number and Enter):"
    PS3="Choice> "
    select opt in "${available_labels[@]}" "Cancel"; do
      if [ "$opt" = "Cancel" ] || [ -z "$opt" ]; then
        echo "Cancelled."
        exit 0
      fi
      selection="$opt"
      break
    done
  fi
fi

[ -z "$selection" ] && { echo "No selection made."; exit 0; }

$debug && echo "[debug] selected: $selection" >&2

# find command for the selection (first match)
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

# prepare to run: split command string into an array safely
# read -r -a will split on IFS; this handles simple cases (paths/args). If you need more complex quoting,
# consider moving choices into an array-of-arrays or a config script that sets arrays.
read -r -a cmd_parts <<< "$selected_cmd"

# append URL as final argument
cmd_parts_with_url=("${cmd_parts[@]}" "$url")

# show dry-run info or execute detached
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

# Launch detached so script doesn't block / get replaced. Use nohup if setsid missing.
if command -v setsid >/dev/null 2>&1; then
  setsid "${cmd_parts_with_url[@]}" >/dev/null 2>&1 &
else
  nohup "${cmd_parts_with_url[@]}" >/dev/null 2>&1 &
fi

# give the shell permission to exit without waiting for child
disown >/dev/null 2>&1 || true

exit 0
