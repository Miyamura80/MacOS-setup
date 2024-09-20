#!/bin/bash

# Prompt the user for the Bluetooth device name
echo "Please enter the name of your Bluetooth device:"
read BLUETOOTH_DEVICE_NAME

# Validate input
if [ -z "$BLUETOOTH_DEVICE_NAME" ]; then
    echo "Error: Bluetooth device name cannot be empty."
    exit 1
fi

# Get full paths for blueutil and SwitchAudioSource
BLUEUTIL_FULL_PATH=$(which blueutil)
SWITCHAUDIOSOURCE_FULL_PATH=$(which SwitchAudioSource)

# Save the device name and full paths to a configuration file
config_file="$HOME/.bluetooth_mic_switch_config"

echo "BLUETOOTH_DEVICE_NAME=\"$BLUETOOTH_DEVICE_NAME\"" > "$config_file"
echo "BLUEUTIL_FULL_PATH=\"$BLUEUTIL_FULL_PATH\"" >> "$config_file"
echo "SWITCHAUDIOSOURCE_FULL_PATH=\"$SWITCHAUDIOSOURCE_FULL_PATH\"" >> "$config_file"

echo "Bluetooth device name and tool paths have been saved to $config_file"


# Find the full file path for bluetooth_mic_switch.sh
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BLUETOOTH_MIC_SWITCH_PATH="$SCRIPT_DIR/bluetooth_mic_switch.sh"
# Copy the bluetooth_mic_switch.sh script to the user's home directory
cp "$BLUETOOTH_MIC_SWITCH_PATH" "$HOME/bluetooth_mic_switch.sh"
echo "Copied bluetooth_mic_switch.sh to $HOME/bluetooth_mic_switch.sh"
# Update the BLUETOOTH_MIC_SWITCH_PATH in the config file to reflect the new location
BLUETOOTH_MIC_SWITCH_PATH="$HOME/bluetooth_mic_switch.sh"
# Add the full path to the configuration file
echo "BLUETOOTH_MIC_SWITCH_PATH=\"$BLUETOOTH_MIC_SWITCH_PATH\"" >> "$config_file"
echo "Full path to bluetooth_mic_switch.sh has been added to $config_file"


# Make the bluetooth_mic_switch.sh script executable
chmod +x "$BLUETOOTH_MIC_SWITCH_PATH"
echo "Made bluetooth_mic_switch.sh executable"

# Create the plist file
# Modify ~/Library/LaunchAgents/com.user.bluetooth-mic-switch.plist
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
        <string>$BLUETOOTH_MIC_SWITCH_PATH</string>
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

# Load the LaunchAgent
launchctl unload "$plist_file"
launchctl load "$plist_file"
echo "Loaded LaunchAgent"

echo "Setup complete. The script will now run automatically at login and stay active."
