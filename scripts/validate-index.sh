#!/usr/bin/env bash
# Validate index.json. A skill installs only because its path says which repo kind it is for,
# so the path is the thing this script polices.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "  FAIL  $1" >&2; status=1; }
status=0

if ! jq empty index.json 2>/dev/null; then
  echo "index.json is not valid JSON:" >&2
  jq empty index.json
  exit 1
fi
echo "index.json parses."

KINDS=$(jq -r '.kinds[]' index.json | sort)
if [ -z "$KINDS" ]; then
  echo "index.json declares no kinds." >&2
  exit 1
fi
echo "kinds: $(echo "$KINDS" | tr '\n' ' ')"

# Every declared kind needs its directory, or a skill could never be filed under it.
while IFS= read -r kind; do
  [ -d "skills/$kind" ] || fail "declared kind '$kind' has no skills/$kind/ directory"
done <<< "$KINDS"

# Every directory under skills/ must be a declared kind. A stray directory is a skill that
# no repo kind can ever match, or worse, one someone expects to install.
for dir in skills/*/; do
  name=$(basename "$dir")
  grep -qx "$name" <<< "$KINDS" || fail "skills/$name/ is not a declared kind"
done

# Every skill directory on disk must be listed in index.json. An unlisted skill is dead weight
# at best; at worst someone assumes being in the repo is enough to ship it.
while IFS= read -r dir; do
  jq -e --arg p "$dir" '.skills[] | select(.path == $p)' index.json >/dev/null \
    || fail "$dir exists on disk but is not listed in index.json"
done < <(find skills -mindepth 2 -maxdepth 2 -type d | sort)

# Per-entry checks.
count=$(jq '.skills | length' index.json)
for i in $(seq 0 $((count - 1))); do
  entry=$(jq -c ".skills[$i]" index.json)
  id=$(jq -r '.id' <<< "$entry")
  path=$(jq -r '.path' <<< "$entry")

  # The path must be exactly skills/<kind>/<id>. Anything else leaves the kind undecidable.
  IFS='/' read -r -a seg <<< "$path"
  if [ "${#seg[@]}" -ne 3 ] || [ "${seg[0]}" != "skills" ]; then
    fail "$id: path '$path' is not skills/<kind>/<id>, so no kind can be derived from it"
    continue
  fi
  kind="${seg[1]}"

  grep -qx "$kind" <<< "$KINDS" || fail "$id: '$kind' in '$path' is not a declared kind"
  [ "${seg[2]}" = "$id" ] || fail "$id: path ends in '${seg[2]}', which is not the id"
  [ -e "$path" ] || fail "$id: path '$path' does not exist"
  [ -e "$path/SKILL.md" ] || fail "$id: $path/SKILL.md is missing"

  # applies_to is derived from the path and must not be hand-written. A second copy of the
  # same fact is a chance for the two to disagree, and the disagreement is what ships the
  # wrong context into the wrong repo.
  declared=$(jq -r '.applies_to // ""' <<< "$entry")
  if [ -n "$declared" ] && [ "$declared" != "$kind" ]; then
    fail "$id: declares applies_to '$declared' but its path says '$kind'"
  fi

  # Each declared target needs real files, or targets lies about what ships.
  while IFS= read -r target; do
    [ -d "$path/$target" ] || fail "$id: declares target '$target' but $path/$target/ is missing"
  done < <(jq -r '.targets[]?' <<< "$entry")

  ref=$(jq -r '.reference.path // ""' <<< "$entry")
  if [ -n "$ref" ]; then
    [ -e "$path/$ref" ] || fail "$id: reference path '$path/$ref' does not exist"
  fi

  [ "$status" -eq 0 ] && echo "  ok    $id  ($kind)"
done

if [ "$status" -ne 0 ]; then
  echo "index.json is invalid." >&2
fi
exit "$status"
