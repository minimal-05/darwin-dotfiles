#!/usr/bin/env bash
# macOS: editors keep user settings under ~/Library/Application Support,
# and Qt's state location is ~/Library/Preferences/quickshell/State.
COLOR_FILE_PATH="${XDG_STATE_HOME:-$HOME/Library/Preferences}/quickshell/State/user/generated/color.txt"

# Define an array of possible VSCode settings file paths for various forks
settings_paths=(
    "$HOME/Library/Application Support/Code/User/settings.json"
    "$HOME/Library/Application Support/VSCodium/User/settings.json"
    "$HOME/Library/Application Support/Code - OSS/User/settings.json"
    "$HOME/Library/Application Support/Code - Insiders/User/settings.json"
    "$HOME/Library/Application Support/Cursor/User/settings.json"
    "$HOME/Library/Application Support/Antigravity/User/settings.json"
    "$HOME/Library/Application Support/Windsurf/User/settings.json"
    
    # Add more paths as needed for other forks
)

new_color=$(cat "$COLOR_FILE_PATH")

# Loop through each settings file path
for CODE_SETTINGS_PATH in "${settings_paths[@]}"; do
    if [[ -f "$CODE_SETTINGS_PATH" ]]; then
        # Try to update the key if it exists
        if grep -q '"material-code.primaryColor"' "$CODE_SETTINGS_PATH"; then
            sed -i -E \
                "s/(\"material-code.primaryColor\"\s*:\s*\")[^\"]*(\")/\1${new_color}\2/" \
                "$CODE_SETTINGS_PATH"
        else # If the key is not already there, add it
            sed -i '$ s/}/,\n  "material-code.primaryColor": "'${new_color}'"\n}/' "$CODE_SETTINGS_PATH"
            sed -i '$ s/,\n,/,/' "$CODE_SETTINGS_PATH"
        fi
    fi
done

