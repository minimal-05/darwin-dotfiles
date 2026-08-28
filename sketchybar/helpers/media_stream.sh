#!/bin/bash
# media_change is broken on macOS 15.4+; media-control works via its perl adapter.
# Each update lands in a temp file; a custom event tells the bar to re-read it.
# the stream runs as a perl adapter, so kill that; its parent scripts exit on pipe EOF
pkill -f "mediaremote-adapter.pl" 2>/dev/null
media-control stream --no-diff --no-artwork --debounce=250 | while IFS= read -r line; do
  # atomic swap so readers never see a half-written line
  printf '%s' "$line" > /tmp/sketchybar_media.json.tmp && mv /tmp/sketchybar_media.json.tmp /tmp/sketchybar_media.json
  sketchybar --trigger media_update
done
