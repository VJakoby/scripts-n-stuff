#!/bin/bash
# Filename: toggle-vm-resolution.sh
# Descriptiopm: Switching between two pre-defined resolutions in a Linux VM.

# Namnet på skärmen (kolla med `xrandr` i din VM)
SCREEN="Virtual1"

# Define your two different resolutions
RES1="1920x1080"
RES2="1366x768"

# Get current resoution
CURRENT_RES=$(xrandr | grep "^$SCREEN" | grep -oP "\d+x\d+" | head -n1)

# Växla upplösning
if [ "$CURRENT_RES" == "$RES1" ]; then
    echo "Byter från $RES1 till $RES2"
    xrandr --output $SCREEN --mode $RES2
else
    echo "Byter till $RES1"
    xrandr --output $SCREEN --mode $RES1
fi
