#!/usr/bin/env bash
# Print the ids of the skills that install into the repo at $1 (default: cwd).
#
# A skill installs only because its kind matches the target repo's kind. There is no flag
# that installs everything: a bypass that exists gets used, and delivering collection-module
# context into a product module is the failure this catalog exists to prevent.
#
# Unknown or undetectable kind yields nothing. Failing closed is the only safe default when
# the thing being decided is what context an agent gets handed.
set -euo pipefail

CATALOG="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${1:-$PWD}"
CONFIG="$REPO/.root-config.json"

[ -f "$CONFIG" ] || exit 0
jq empty "$CONFIG" 2>/dev/null || exit 0

# The repo kind comes from the key present in .root-config.json. Exactly one must match.
kind=""
has_cm=$(jq -r 'has("collectionModuleKey")' "$CONFIG")
has_pm=$(jq -r 'has("productModuleKey")' "$CONFIG")
if [ "$has_cm" = "true" ] && [ "$has_pm" = "false" ]; then
  kind="collection-module"
elif [ "$has_pm" = "true" ] && [ "$has_cm" = "false" ]; then
  kind="product-module"
else
  # Neither key, or both: the kind is not established, so nothing installs.
  exit 0
fi

# A skill's kind is the path segment under skills/. Nothing else decides it.
jq -r --arg kind "$kind" '
  .skills[]
  | select((.path | split("/")) as $p | ($p | length) == 3 and $p[0] == "skills" and $p[1] == $kind)
  | .id
' "$CATALOG/index.json"
