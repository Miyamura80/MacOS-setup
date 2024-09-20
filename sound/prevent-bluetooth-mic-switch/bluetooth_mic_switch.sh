#!/bin/bash

# Read the configuration from the file
config_file="$HOME/.bluetooth_mic_switch_config"
if [ -f "$config_file" ]; then
    BLUETOOTH_DEVICE_NAME=$(grep BLUETOOTH_DEVICE_NAME "$config_file" | cut -d'=' -f2 | tr -d '"')
    BLUEUTIL_FULL_PATH=$(grep BLUEUTIL_FULL_PATH "$config_file" | cut -d'=' -f2 | tr -d '"')
    SWITCHAUDIOSOURCE_FULL_PATH=$(grep SWITCHAUDIOSOURCE_FULL_PATH "$config_file" | cut -d'=' -f2 | tr -d '"')
else
    echo "Error: Configuration file not found. Please run setup_script.sh first."
    exit 1
fi

# Check if Bluetooth headphones are connected using the full path to blueutil
if "$BLUEUTIL_FULL_PATH" --connected | grep -q "$BLUETOOTH_DEVICE_NAME"; then
    echo "Bluetooth headphones ($BLUETOOTH_DEVICE_NAME) connected."
        
    # Force set the input device to the built-in microphone using full path to SwitchAudioSource
    "$SWITCHAUDIOSOURCE_FULL_PATH" -t input -s "MacBook Air Microphone"
else
    echo "Bluetooth headphones ($BLUETOOTH_DEVICE_NAME) not connected."
    
    # Ensure the input device stays as the built-in mic
    "$SWITCHAUDIOSOURCE_FULL_PATH" -t input -s "MacBook Air Microphone"
fi