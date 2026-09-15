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

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
