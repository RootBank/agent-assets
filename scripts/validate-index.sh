#!/usr/bin/env bash
# Validate index.json: it must parse, and every path it names must exist.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! jq empty index.json 2>/dev/null; then
  echo "index.json is not valid JSON:" >&2
  jq empty index.json
  exit 1
fi
echo "index.json parses."

status=0
# Every path index.json names: the skill directory, and a reference subtree if declared.
while IFS= read -r path; do
  if [ -e "$path" ]; then
    echo "  ok      $path"
  else
    echo "  MISSING $path" >&2
    status=1
  fi
done < <(jq -r '.skills[] | .path, (select(.reference) | .path + "/" + .reference.path)' index.json)

if [ "$status" -ne 0 ]; then
  echo "index.json names paths that do not exist." >&2
fi
exit "$status"
