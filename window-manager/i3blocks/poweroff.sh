#!/bin/bash
echo "⏻ Power"

# Handle click
case $BLOCK_BUTTON in
    1) systemctl poweroff ;;
esac
