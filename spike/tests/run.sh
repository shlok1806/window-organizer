#!/bin/sh
# Golden-file tests at the CLI seam.
#
# Each case is a recorded desktop. We plan against it and compare the emitted plan
# to a committed expectation. Nothing here touches a live window, so these run
# anywhere, including on a Space with no windows on it.
#
# Capture a new case from a real desktop with:  wdump --json > cases/<name>.json
set -u
cd "$(dirname "$0")"

BIN=${BIN:-../warrange}
pass=0
fail=0

for case_file in cases/*.json; do
    name=$(basename "$case_file" .json)
    expected="expected/$name.json"

    if [ ! -f "$expected" ]; then
        echo "FAIL $name  (no expected/$name.json)"
        fail=$((fail + 1))
        continue
    fi

    # A case may carry extra flags in a sibling .flags file, so behaviour that only
    # appears under --spill or --master can be asserted like any other plan.
    flags=""
    [ -f "cases/$name.flags" ] && flags=$(cat "cases/$name.flags")

    # shellcheck disable=SC2086
    got=$("$BIN" --plan-from "$case_file" $flags --json 2>&1)
    # Normalise key order so formatting changes do not masquerade as failures.
    got_n=$(printf '%s' "$got" | jq -S -c . 2>/dev/null)
    exp_n=$(jq -S -c . < "$expected" 2>/dev/null)

    if [ -n "$got_n" ] && [ "$got_n" = "$exp_n" ]; then
        echo "ok   $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name"
        echo "       expected: $exp_n"
        echo "       got:      ${got_n:-$got}"
        fail=$((fail + 1))
    fi
done

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
