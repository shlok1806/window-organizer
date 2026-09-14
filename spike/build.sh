#!/bin/sh
# Build all three spike tools.
set -e
cd "$(dirname "$0")"
swiftc -O dump.swift -o wdump
swiftc -O probe.swift -o wprobe
swiftc -O main.swift priority.swift -o warrange   # main.swift = warrange entry point
echo "built: wdump wprobe warrange"
