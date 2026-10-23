#!/usr/bin/env bash
# Install Root agent skills into the current repo.
#
# Usage (from inside a Root module repo):
#   curl -sSL https://raw.githubusercontent.com/RootBank/agent-assets/main/install.sh | bash
#   curl -sSL https://raw.githubusercontent.com/RootBank/agent-assets/main/install.sh | bash -s -- --dry-run
#
# What lands, and where:
#   SKILL.md          -> .claude/skills/<id>/SKILL.md
#   claude/<path>     -> .claude/<path>
#   cursor/<path>     -> .cursor/<path>
#   reference/<path>  -> <reference.installs_to>/<path>   (from index.json, never hardcoded)
#   a record of it    -> .root/agent-manifest.json
#
# Which skills land is decided by scripts/select-skills.sh from the catalog, which is the same
# selector CI tests. This installer calls it rather than carrying its own copy: two filters means
# two behaviours, and the one that drifts is the one that leaks collection-module context into a
# product module repo.
#
# There is no --all and no --force. A product module repo receives zero collection-module skills,
# and a repo whose kind cannot be established receives nothing and exits non-zero. A bypass that
# exists gets used, usually by someone in a hurry who is sure this once is fine.
#
# Re-running is idempotent: each skill's installed version is compared against index.json and only
# the ones that differ are rewritten.
#
# The whole catalog arrives as one tarball rather than file-by-file over the raw-GitHub or API
# endpoints. One request, no API rate limit, and index.json cannot arrive a version apart from the
# files it describes.
#
# AGENT_ASSETS_URL overrides the catalog tarball URL. The tests use it to run against a local
# build of this repo; there is no other reason to set it.

set -euo pipefail

CATALOG_REPO="https://github.com/RootBank/agent-assets"
CATALOG_URL="${AGENT_ASSETS_URL:-$CATALOG_REPO/archive/refs/heads/main.tar.gz}"
MANIFEST_REL=".root/agent-manifest.json"

DRY_RUN=0

usage() {
  cat <<'EOF'
Install Root agent skills into the current repo.

  install.sh [--dry-run]

  --dry-run   Print every file that would be written, and write nothing.
  --help      This.

Which skills install is decided by the repo's kind, read from .root-config.json. There is no
flag to install skills for a kind this repo is not.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    --all|--force)
      echo "ERROR: there is no $1." >&2
      echo "  A skill installs only because its kind matches this repo's kind. Handing a product" >&2
      echo "  module collection-module context teaches an agent to build against the wrong" >&2
      echo "  contracts, and the agent has no way to notice. See $CATALOG_REPO." >&2
      exit 2
      ;;
    *) echo "ERROR: unknown argument '$1'." >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for dep in curl tar jq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: '$dep' is required and is not on PATH." >&2; exit 1; }
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ERROR: not inside a git repository. cd into your Root module repo and re-run." >&2
  exit 1
}

# Everything this installer writes is relative to the repo root, but the config that names the
# repo's kind is not necessarily there. `rp` reads .root-config.json from the module directory it
# is run in, and in a repo cloned from blank_starter_template_v2 that directory is
# collection_module/ — verified against the template at main, which ships
# collection_module/.root-config.json.sample while keeping .claude/, .cursor/ and
# collection_module/docs/ at the root. So look at the root first, then one level down.
#
# Exactly one config, or none. Two module directories means the repo's kind is not established,
# and an unestablished kind installs nothing.
CONFIG_DIR="$REPO_ROOT"
if [ ! -f "$REPO_ROOT/.root-config.json" ]; then
  NESTED=$(find "$REPO_ROOT" -mindepth 2 -maxdepth 2 -name .root-config.json \
    -not -path "$REPO_ROOT/.*" -not -path "$REPO_ROOT/node_modules/*" 2>/dev/null | sort)
  if [ "$(grep -c . <<<"$NESTED")" -gt 1 ]; then
    echo "ERROR: this repo has more than one .root-config.json, so its kind is not established." >&2
    echo "  Nothing was installed. Found:" >&2
    sed "s|^$REPO_ROOT/|    |" <<<"$NESTED" >&2
    exit 1
  fi
  if [ -n "$NESTED" ]; then CONFIG_DIR=$(dirname "$NESTED"); fi
fi
CONFIG="$CONFIG_DIR/.root-config.json"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
CATALOG="$WORK/catalog"
mkdir -p "$CATALOG"

if ! curl -fsSL "$CATALOG_URL" -o "$WORK/catalog.tar.gz"; then
  echo "ERROR: could not fetch the catalog from $CATALOG_URL" >&2
  echo "  Check your network, then re-run. Nothing was written." >&2
  exit 1
fi
if ! tar -xzf "$WORK/catalog.tar.gz" -C "$CATALOG" --strip-components=1; then
  echo "ERROR: the catalog downloaded from $CATALOG_URL is not a readable tarball." >&2
  exit 1
fi

INDEX="$CATALOG/index.json"
SELECT="$CATALOG/scripts/select-skills.sh"
[ -f "$INDEX" ] || { echo "ERROR: the catalog has no index.json. Nothing was written." >&2; exit 1; }
[ -f "$SELECT" ] || { echo "ERROR: the catalog has no scripts/select-skills.sh. Nothing was written." >&2; exit 1; }
if ! jq empty "$INDEX" 2>/dev/null; then
  echo "ERROR: the catalog's index.json is not valid JSON. Nothing was written." >&2
  jq empty "$INDEX" || true
  exit 1
fi

# The selector decides the kind and prints the matching skill ids on stdout, reporting the kind it
# established on stderr. No kind reported means it could not establish one.
SELECT_ERR="$WORK/select.err"
SKILL_IDS=$(bash "$SELECT" "$CONFIG_DIR" 2>"$SELECT_ERR" || true)
KIND=$(sed -n 's/^kind: //p' "$SELECT_ERR")

if [ -z "$KIND" ]; then
  # Diagnosis only — the selector above already made the decision, and this must never second-guess
  # it. All three branches lead to the same outcome: nothing installs.
  echo "ERROR: could not establish this repo's kind, so nothing was installed." >&2
  if [ ! -f "$CONFIG" ]; then
    echo "  No .root-config.json at $REPO_ROOT or one level below it. This is not a Root module repo." >&2
  elif ! jq empty "$CONFIG" 2>/dev/null; then
    echo "  $CONFIG is not valid JSON." >&2
  else
    echo "  $CONFIG must carry exactly one of \"collectionModuleKey\" or \"productModuleKey\"." >&2
    echo "  Keys present: $(jq -r 'keys | join(", ")' "$CONFIG")" >&2
  fi
  exit 1
fi

echo "repo:    $REPO_ROOT"
echo "config:  ${CONFIG#"$REPO_ROOT/"}"
echo "kind:    $KIND"
echo "catalog: $CATALOG_URL"

if [ -z "$SKILL_IDS" ]; then
  echo
  echo "No skills in the catalog apply to a $KIND repo. Nothing installed."
  exit 0
fi

# index.json decides where files are written, so the paths it carries are a trust boundary.
safe_rel_path() { # safe_rel_path <path> <what>
  case "$1" in
    ""|/*|*..*) echo "ERROR: $2 is '$1', which is not a safe repo-relative path." >&2; exit 1 ;;
  esac
}

# Emit "<absolute source>\t<repo-relative destination>" for every file a skill installs.
# Called with stdout redirected to a file, never inside $(...), so a failure here exits the script
# rather than a subshell.
plan_skill() { # plan_skill <id>
  local id=$1 entry path src target dest ref installs_to f
  entry=$(jq -c --arg id "$id" '.skills[] | select(.id == $id)' "$INDEX")
  [ -n "$entry" ] || { echo "ERROR: '$id' was selected but is not in index.json." >&2; exit 1; }

  case "$id" in *[!A-Za-z0-9._-]*|.*) echo "ERROR: skill id '$id' is not a safe directory name." >&2; exit 1 ;; esac
  path=$(jq -r '.path' <<<"$entry")
  safe_rel_path "$path" "the path of skill '$id'"
  src="$CATALOG/$path"
  [ -d "$src" ] || { echo "ERROR: index.json puts '$id' at $path, which the catalog does not have." >&2; exit 1; }
  [ -f "$src/SKILL.md" ] || { echo "ERROR: '$id' has no SKILL.md." >&2; exit 1; }

  printf '%s\t%s\n' "$src/SKILL.md" ".claude/skills/$id/SKILL.md"

  while IFS= read -r target; do
    [ -n "$target" ] || continue
    case "$target" in
      claude) dest=".claude" ;;
      cursor) dest=".cursor" ;;
      *) echo "ERROR: '$id' declares target '$target', which this installer does not know how to place." >&2; exit 1 ;;
    esac
    [ -d "$src/$target" ] || { echo "ERROR: '$id' declares target '$target' but ships no $target/ subtree." >&2; exit 1; }
    while IFS= read -r f; do
      printf '%s\t%s\n' "$f" "$dest/${f#"$src/$target/"}"
    done < <(find "$src/$target" -type f | sort)
  done < <(jq -r '.targets[]?' <<<"$entry")

  ref=$(jq -r '.reference.path // ""' <<<"$entry")
  [ -n "$ref" ] || return 0
  installs_to=$(jq -r '.reference.installs_to // ""' <<<"$entry")
  [ -n "$installs_to" ] || { echo "ERROR: '$id' has a reference tree but no reference.installs_to." >&2; exit 1; }
  safe_rel_path "$ref" "the reference path of '$id'"
  safe_rel_path "$installs_to" "reference.installs_to of '$id'"
  [ -d "$src/$ref" ] || { echo "ERROR: '$id' names reference '$ref', which the catalog does not have." >&2; exit 1; }
  while IFS= read -r f; do
    printf '%s\t%s\n' "$f" "$installs_to/${f#"$src/$ref/"}"
  done < <(find "$src/$ref" -type f | sort)
}

MANIFEST="$REPO_ROOT/$MANIFEST_REL"
installed_version() { # installed_version <id>
  [ -f "$MANIFEST" ] || { echo ""; return; }
  jq -r --arg id "$1" '(.skills // [])[] | select(.id == $id) | .version' "$MANIFEST" 2>/dev/null | head -1
}

NEW=0; UPDATED=0; CURRENT=0
TODO=()
echo
while IFS= read -r id; do
  [ -n "$id" ] || continue
  want=$(jq -r --arg id "$id" '.skills[] | select(.id == $id) | .version' "$INDEX")
  have=$(installed_version "$id")
  if [ "$have" = "$want" ]; then
    echo "  up to date  $id  $want"
    CURRENT=$((CURRENT + 1))
    continue
  fi
  if [ -z "$have" ]; then
    echo "  install     $id  $want"
    NEW=$((NEW + 1))
  else
    echo "  update      $id  $have -> $want"
    UPDATED=$((UPDATED + 1))
  fi
  TODO+=("$id")
done <<<"$SKILL_IDS"

for id in ${TODO+"${TODO[@]}"}; do
  plan_skill "$id" > "$WORK/plan.$id.tsv"
done

if [ "$DRY_RUN" = "1" ]; then
  echo
  if [ ${#TODO[@]} -eq 0 ]; then
    echo "Nothing to write."
  else
    for id in "${TODO[@]}"; do
      echo "$id would write:"
      cut -f2 "$WORK/plan.$id.tsv" | sed 's/^/  /'
    done
    echo "  $MANIFEST_REL"
  fi
  echo
  echo "$NEW to install · $UPDATED to update · $CURRENT up to date  (--dry-run: nothing written)"
  exit 0
fi

if [ ${#TODO[@]} -gt 0 ]; then
  # Files are overwritten, never deleted first: reference trees install alongside a repo's own
  # files (collection_module/docs holds the module's docs too), so clearing a target directory
  # would destroy work that is not ours.
  for id in "${TODO[@]}"; do
    while IFS=$'\t' read -r src rel; do
      dir="$REPO_ROOT/$(dirname "$rel")"
      if ! mkdir -p "$dir" 2>/dev/null || ! cp "$src" "$REPO_ROOT/$rel" 2>/dev/null; then
        echo "ERROR: could not write $REPO_ROOT/$rel — check permissions." >&2
        echo "  The install is incomplete. Fix the permission and re-run." >&2
        exit 1
      fi
    done < "$WORK/plan.$id.tsv"
  done

  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  ENTRIES=$(for id in "${TODO[@]}"; do
    jq -c -n \
      --arg id "$id" \
      --arg version "$(jq -r --arg id "$id" '.skills[] | select(.id == $id) | .version' "$INDEX")" \
      --arg source "$CATALOG_REPO/tree/main/$(jq -r --arg id "$id" '.skills[] | select(.id == $id) | .path' "$INDEX")" \
      --arg installed_at "$NOW" \
      '{id: $id, version: $version, source: $source, installed_at: $installed_at}'
  done | jq -s '.')

  if ! mkdir -p "$(dirname "$MANIFEST")" 2>/dev/null; then
    echo "ERROR: could not create $(dirname "$MANIFEST") — check permissions." >&2
    exit 1
  fi
  [ -f "$MANIFEST" ] || echo '{}' > "$MANIFEST"
  jq --argjson new "$ENTRIES" --arg catalog "$CATALOG_REPO" '
      {
        catalog: $catalog,
        skills: (
          ((.skills // []) | map(select(.id as $i | ($new | map(.id) | index($i)) | not)))
          + $new
          | sort_by(.id)
        )
      }
    ' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
fi

echo
echo "$NEW installed · $UPDATED updated · $CURRENT up to date"
echo "recorded in $MANIFEST_REL"
