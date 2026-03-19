#!/bin/bash

# Get full path for SwitchAudioSource
SWITCHAUDIOSOURCE_FULL_PATH=$(which SwitchAudioSource)
if [ -z "$SWITCHAUDIOSOURCE_FULL_PATH" ]; then
    echo "Error: SwitchAudioSource is not installed. Run 'brew install switchaudio-osx' first."
    exit 1
fi

# Copy the bluetooth_mic_switch.sh script to the user's home directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cp "$SCRIPT_DIR/bluetooth_mic_switch.sh" "$HOME/bluetooth_mic_switch.sh"
chmod +x "$HOME/bluetooth_mic_switch.sh"
echo "Copied bluetooth_mic_switch.sh to $HOME/bluetooth_mic_switch.sh"

# Create the LaunchAgent plist
plist_file="$HOME/Library/LaunchAgents/com.user.bluetooth-mic-switch.plist"

cat << EOF > "$plist_file"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.bluetooth-mic-switch</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HOME/bluetooth_mic_switch.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/bluetooth-mic-switch.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/bluetooth-mic-switch.log</string>
</dict>
</plist>
EOF

echo "Created LaunchAgent plist file at $plist_file"

# Reload the LaunchAgent
launchctl bootout gui/$(id -u) "$plist_file" 2>/dev/null
launchctl bootstrap gui/$(id -u) "$plist_file"
launchctl kickstart gui/$(id -u)/com.user.bluetooth-mic-switch
echo "Loaded LaunchAgent"

echo "Setup complete. The script will check every 5 seconds and force input to MacBook Air Microphone."
