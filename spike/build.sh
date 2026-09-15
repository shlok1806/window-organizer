#!/bin/sh
# Build all three spike tools.
set -e
cd "$(dirname "$0")"
swiftc -O dump.swift -o wdump
swiftc -O probe.swift -o wprobe
swiftc -O main.swift priority.swift recency.swift -o warrange   # main.swift = warrange entry point
swiftc -O focus/main.swift recency.swift -o wfocus   # focus/main.swift = wfocus entry point
echo "built: wdump wprobe warrange wfocus"
