#!/usr/bin/env bash
# The catalog must never hand collection-module context to a product module. These tests
# pin that, and pin that the filter still passes the skills it should, so a selector that
# simply returned nothing could not pass them.
set -uo pipefail

cd "$(dirname "$0")/.."
SELECT=./scripts/select-skills.sh
pass=0; fail=0

check() { # check <name> <fixture> <expected ids> [expected kind]
  local name=$1 fixture=$2 expected=$3 want_kind=${4-} actual got_kind err
  err=$(mktemp)
  actual=$("$SELECT" "tests/fixtures/$fixture" 2>"$err" || true)
  got_kind=$(sed -n 's/^kind: //p' "$err")
  rm -f "$err"

  if [ "$actual" != "$expected" ]; then
    echo "  FAIL  $name" >&2
    echo "          expected skills: [${expected//$'\n'/, }]" >&2
    echo "          actual skills:   [${actual//$'\n'/, }]" >&2
    fail=$((fail + 1)); return
  fi
  # An empty result is only meaningful if we know which kind produced it.
  if [ -n "$want_kind" ] && [ "$got_kind" != "$want_kind" ]; then
    echo "  FAIL  $name" >&2
    echo "          expected kind: [$want_kind]" >&2
    echo "          actual kind:   [${got_kind:-<none detected>}]" >&2
    fail=$((fail + 1)); return
  fi
  echo "  PASS  $name"; pass=$((pass + 1))
}

# The one this repo exists to guarantee. The kind is asserted too: a product module that yields
# nothing because it was correctly identified is the guarantee; one that yields nothing because
# the detector failed is a bug wearing the guarantee's clothes.
check "a product module is detected, and gets ZERO skills" product-module "" "product-module"

# Without this, a selector that always returned nothing would pass the test above.
check "a collection module gets its skills" collection-module "build-collection-module" "collection-module"

# Fail closed: no kind established means nothing installs, and no kind is reported.
check "a repo with no .root-config.json gets nothing" no-config ""
check "a repo claiming both kinds gets nothing" both-keys ""

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
