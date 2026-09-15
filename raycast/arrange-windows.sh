#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Arrange Windows
# @raycast.mode compact
# @raycast.icon 🪟
# @raycast.packageName Window Organizer
# @raycast.description Pack every visible window with zero overlap. The app you are in
#   takes the master pane; anything that cannot fit is minimised.

# Absolute path: Raycast does not inherit your shell PATH.
exec "$HOME/.local/bin/warrange" --master 0.6 --spill --apply
