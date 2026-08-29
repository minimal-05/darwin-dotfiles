#!/usr/bin/env bash
# The Linux original sources $ILLOGICAL_IMPULSE_VIRTUAL_ENV. There is no such
# venv on macOS; numpy and opencv-contrib-python-headless are installed for the
# user instead, so the script runs under the system interpreter.
#
# macOS also hands out wallpapers as .heic, which OpenCV cannot decode, so any
# .heic argument is converted with sips (a base-install tool) on the way past.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

args=()
for a in "$@"; do
    case "$a" in
        *.heic|*.HEIC|*.heif|*.HEIF)
            conv="${TMPDIR:-/tmp}/qs-$(basename "${a%.*}").png"
            [ -f "$conv" ] || sips -s format png "$a" --out "$conv" >/dev/null 2>&1
            args+=("$conv")
            ;;
        *) args+=("$a") ;;
    esac
done

exec python3 "$SCRIPT_DIR/text_color.py" "${args[@]}"
