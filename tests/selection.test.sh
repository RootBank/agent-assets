#!/usr/bin/env bash
# The catalog must never hand collection-module context to a product module. These tests
# pin that, and pin that the filter still passes the skills it should, so a selector that
# simply returned nothing could not pass them.
set -uo pipefail

cd "$(dirname "$0")/.."
SELECT=./scripts/select-skills.sh
pass=0; fail=0

check() { # check <name> <fixture> <expected ids, newline separated>
  local name=$1 fixture=$2 expected=$3 actual
  actual=$("$SELECT" "tests/fixtures/$fixture" 2>/dev/null || true)
  if [ "$actual" = "$expected" ]; then
    echo "  PASS  $name"; pass=$((pass + 1))
  else
    echo "  FAIL  $name" >&2
    echo "          expected: [${expected//$'\n'/, }]" >&2
    echo "          actual:   [${actual//$'\n'/, }]" >&2
    fail=$((fail + 1))
  fi
}

# The one this repo exists to guarantee.
check "a product module gets ZERO skills" product-module ""

# Without this, a selector that always returned nothing would pass the test above.
check "a collection module gets its skills" collection-module "build-collection-module"

# Fail closed: no kind established means nothing installs.
check "a repo with no .root-config.json gets nothing" no-config ""
check "a repo claiming both kinds gets nothing" both-keys ""

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
