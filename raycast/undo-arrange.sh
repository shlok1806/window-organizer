#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Undo Arrange
# @raycast.mode compact
# @raycast.icon ↩️
# @raycast.packageName Window Organizer
# @raycast.description Put every window back exactly where it was before the last
#   arrange, including un-minimising anything that was stowed.

exec "$HOME/.local/bin/warrange" --undo
