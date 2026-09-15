#!/bin/sh
# CLI contract tests: exit codes and refusals.
#
# None of these touch the live desktop. They deliberately never pass --apply,
# because the behaviour under test is precisely whether a malformed command can
# reach the live-write path by accident.
set -u
cd "$(dirname "$0")"

BIN=${BIN:-../warrange}
pass=0
fail=0

# check <name> <expected exit> <command...>
check() {
    name=$1
    want=$2
    shift 2
    out=$("$@" 2>&1)
    got=$?
    if [ "$got" = "$want" ]; then
        echo "ok   $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name  (exit $got, wanted $want)"
        printf '       %s\n' "$(printf '%s' "$out" | head -2)"
        fail=$((fail + 1))
    fi
}

# A value-taking flag with no value must be a usage error. Silently treating it
# as "flag absent" means `--apply --plan-from` collapses to a LIVE rearrange that
# looks like a replay. See issue #4.
check "--plan-from with no value is a usage error" 2 "$BIN" --plan-from

# An out-of-range minSize must not crash. It is measured from live AX queries and
# cached, so a single bad measurement would otherwise brick every later run for that
# app. Exit 133 is SIGTRAP. See issue #5.
check "absurd minSize does not crash (human output)" 0 "$BIN" --plan-from cli-cases/absurd-minsize.json
check "absurd minSize does not crash (json output)"  0 "$BIN" --plan-from cli-cases/absurd-minsize.json --json

# --json must always emit machine-readable output, including on the paths that
# previously printed human text and exited early. See issue #14.
check "empty windows still exits 0" 0 "$BIN" --plan-from cli-cases/empty-windows.json --json
if "$BIN" --plan-from cli-cases/empty-windows.json --json 2>/dev/null | jq -e . >/dev/null 2>&1; then
    echo "ok   empty windows emits valid json"
    pass=$((pass + 1))
else
    echo "FAIL empty windows emits valid json"
    fail=$((fail + 1))
fi

# A typo must not be indistinguishable from a correct command on a tool that moves
# windows. See issue #16.
check "unknown flag is rejected" 2 "$BIN" --plan-from cli-cases/empty-windows.json --nope

# Claiming a hero that is not present tells the user one thing and does another.
# See issue #15.
check "--hero naming an absent app is rejected" 2 \
    "$BIN" --plan-from cases/single-window-fits.json --hero NoSuchApp

# Malformed input must be rejected, not silently coerced to zero. See issue #19.
check "minSize as strings is rejected" 2 "$BIN" --plan-from cli-cases/string-minsize.json
check "duplicate window ids are rejected" 2 "$BIN" --plan-from cli-cases/duplicate-ids.json

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
