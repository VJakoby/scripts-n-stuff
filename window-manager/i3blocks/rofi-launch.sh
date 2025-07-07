#!/bin/bash

# Show icon
echo "🕹️"

# Handle click
if [ "$BLOCK_BUTTON" == "1" ]; then
    rofi -show drun
fi
