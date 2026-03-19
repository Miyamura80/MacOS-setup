#!/bin/bash

SWITCHAUDIOSOURCE="/opt/homebrew/bin/SwitchAudioSource"
INPUT_DEVICE="MacBook Air Microphone"

while true; do
    current=$("$SWITCHAUDIOSOURCE" -t input -c)
    if [ "$current" != "$INPUT_DEVICE" ]; then
        echo "Input switched to '$current', resetting to '$INPUT_DEVICE'"
        "$SWITCHAUDIOSOURCE" -t input -s "$INPUT_DEVICE"
    fi
    sleep 5
done