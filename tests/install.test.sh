#!/usr/bin/env bash
# Exercise install.sh against real module repos built from tests/fixtures/.
#
# The catalog is served from a tarball built out of the working tree, so these run offline and
# test the branch's own installer rather than whatever is on main. A second, synthetic skill is
# added to that copy: with one skill in the catalog there is no way to show that updating one
# leaves the others alone.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
pass=0; fail=0

ok()   { echo "  PASS  $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL  $1" >&2; shift; while [ $# -gt 0 ]; do echo "          $1" >&2; shift; done; fail=$((fail + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected: $3" "actual:   $2"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- the catalog under test, as a tarball ------------------------------------------------------
SECOND=zz-second-skill
build_catalog() { # build_catalog <tarball> [second-skill-version]
  local out=$1 v2=${2:-1.0.0} stage="$TMP/stage"
  rm -rf "$stage"; mkdir -p "$stage/agent-assets-main"
  tar -cf - --exclude=.git --exclude=tests/tmp . | tar -xf - -C "$stage/agent-assets-main"

  local dir="$stage/agent-assets-main/skills/collection-module/$SECOND"
  mkdir -p "$dir/claude/commands"
  printf -- '---\nname: %s\ndescription: A second skill, so updates can be told apart.\n---\n' "$SECOND" > "$dir/SKILL.md"
  echo "second skill command, version $v2" > "$dir/claude/commands/$SECOND.md"
  jq --arg id "$SECOND" --arg v "$v2" \
    '.skills += [{id: $id, version: $v, path: ("skills/collection-module/" + $id), targets: ["claude"], description: "second"}]' \
    "$stage/agent-assets-main/index.json" > "$stage/agent-assets-main/index.json.tmp"
  mv "$stage/agent-assets-main/index.json.tmp" "$stage/agent-assets-main/index.json"

  tar -czf "$out" -C "$stage" agent-assets-main
}

CATALOG_V1="$TMP/catalog-v1.tar.gz"
CATALOG_V2="$TMP/catalog-v2.tar.gz"
build_catalog "$CATALOG_V1" 1.0.0
build_catalog "$CATALOG_V2" 2.0.0

# --- module repos ------------------------------------------------------------------------------
# A real repo, not a directory inside this one: install.sh resolves its target with
# `git rev-parse --show-toplevel`, and a fixture nested here would resolve to this catalog.
make_repo() { # make_repo <name> [fixture]
  local dir="$TMP/repos/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  [ -n "${2:-}" ] && [ -f "tests/fixtures/$2/.root-config.json" ] && cp "tests/fixtures/$2/.root-config.json" "$dir/"
  echo "$dir"
}

run() { # run <repo> <catalog> [args...]; stdout+stderr to $OUT, status to $STATUS
  local repo=$1 catalog=$2; shift 2
  OUT="$TMP/out.txt"
  ( cd "$repo" && AGENT_ASSETS_URL="file://$catalog" bash "$ROOT/install.sh" "$@" ) >"$OUT" 2>&1
  STATUS=$?
}

echo "== a fresh collection module repo =="
CM=$(make_repo collection-module collection-module)
run "$CM" "$CATALOG_V1"
check "exits 0" "$STATUS" "0"
check "reports the kind" "$(grep -c '^kind:    collection-module$' "$OUT")" "1"
check "SKILL.md lands under .claude/skills/<id>/" \
  "$([ -f "$CM/.claude/skills/build-collection-module/SKILL.md" ] && echo yes)" "yes"
check "the claude/ subtree lands in .claude/" \
  "$([ -f "$CM/.claude/commands/build-from-spec.md" ] && echo yes)" "yes"
check "the cursor/ subtree lands in .cursor/" \
  "$([ -f "$CM/.cursor/rules/build-from-spec.mdc" ] && echo yes)" "yes"
# Honouring reference.installs_to rather than hardcoding it is the point of this one.
check "reference/ lands at reference.installs_to" \
  "$([ -f "$CM/collection_module/docs/13-BUILD-FROM-SPEC.md" ] && echo yes)" "yes"
check "every reference file lands" \
  "$(find "$CM/collection_module/docs" -type f | wc -l | tr -d ' ')" \
  "$(find skills/collection-module/build-collection-module/reference -type f | wc -l | tr -d ' ')"
check "the manifest records the version" \
  "$(jq -r '.skills[] | select(.id=="build-collection-module") | .version' "$CM/.root/agent-manifest.json")" "1.0.0"
check "the manifest records the source" \
  "$(jq -r '.skills[] | select(.id=="build-collection-module") | .source' "$CM/.root/agent-manifest.json")" \
  "https://github.com/RootBank/agent-assets/tree/main/skills/collection-module/build-collection-module"
check "the manifest records an install date" \
  "$(jq -r '.skills[] | select(.id=="build-collection-module") | .installed_at' "$CM/.root/agent-manifest.json" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')" "1"
check "reports what it installed" "$(grep -c '2 installed · 0 updated · 0 up to date' "$OUT")" "1"

echo
echo "== running it again, unchanged =="
touch "$TMP/marker"
run "$CM" "$CATALOG_V1"
check "exits 0" "$STATUS" "0"
check "reports up to date" "$(grep -c '0 installed · 0 updated · 2 up to date' "$OUT")" "1"
check "writes nothing" \
  "$(find "$CM" -path "$CM/.git" -prune -o -type f -newer "$TMP/marker" -print | wc -l | tr -d ' ')" "0"

echo
echo "== one skill's version bumped in the catalog =="
touch "$TMP/marker"
run "$CM" "$CATALOG_V2"
check "exits 0" "$STATUS" "0"
check "reports one update" "$(grep -c '0 installed · 1 updated · 1 up to date' "$OUT")" "1"
check "the bumped skill is rewritten" \
  "$(find "$CM/.claude/commands/$SECOND.md" -newer "$TMP/marker" | wc -l | tr -d ' ')" "1"
check "the bumped skill's new content landed" \
  "$(cat "$CM/.claude/commands/$SECOND.md")" "second skill command, version 2.0.0"
check "the unchanged skill is not rewritten" \
  "$(find "$CM/.claude" "$CM/.cursor" "$CM/collection_module" -type f -newer "$TMP/marker" -print | grep -vc "$SECOND")" "0"
check "the manifest carries the new version" \
  "$(jq -r --arg id "$SECOND" '.skills[] | select(.id==$id) | .version' "$CM/.root/agent-manifest.json")" "2.0.0"
check "the manifest keeps the untouched skill" \
  "$(jq -r '.skills[] | select(.id=="build-collection-module") | .version' "$CM/.root/agent-manifest.json")" "1.0.0"

echo
echo "== a collection module cloned from the template, config one level down =="
# blank_starter_template_v2 keeps .root-config.json inside collection_module/, while .claude/,
# .cursor/ and collection_module/docs/ live at the repo root. The installer has to read the kind
# from the one place and write to the other, or the acceptance case — a module repo cloned months
# ago — never works.
NESTED=$(make_repo nested-config)
mkdir -p "$NESTED/collection_module"
cp tests/fixtures/collection-module/.root-config.json "$NESTED/collection_module/"
run "$NESTED" "$CATALOG_V1"
check "exits 0" "$STATUS" "0"
check "reports where it read the kind from" \
  "$(grep -c '^config:  collection_module/\.root-config\.json$' "$OUT")" "1"
check "reports the kind" "$(grep -c '^kind:    collection-module$' "$OUT")" "1"
check "writes .claude/ at the repo root, not beside the config" \
  "$([ -f "$NESTED/.claude/commands/build-from-spec.md" ] && echo yes)" "yes"
check "nothing is written beside the config" \
  "$([ -e "$NESTED/collection_module/.claude" ] && echo wrote || echo clean)" "clean"
check "reference/ still lands at reference.installs_to" \
  "$([ -f "$NESTED/collection_module/docs/13-BUILD-FROM-SPEC.md" ] && echo yes)" "yes"

echo
echo "== two .root-config.json files: the kind is not established =="
AMBIG=$(make_repo ambiguous)
mkdir -p "$AMBIG/collection_module" "$AMBIG/other_module"
cp tests/fixtures/collection-module/.root-config.json "$AMBIG/collection_module/"
cp tests/fixtures/product-module/.root-config.json "$AMBIG/other_module/"
run "$AMBIG" "$CATALOG_V1"
check "exits non-zero" "$([ "$STATUS" -ne 0 ] && echo yes)" "yes"
check "says the kind is not established" "$(grep -c 'more than one .root-config.json' "$OUT")" "1"
check "writes nothing" "$([ -e "$AMBIG/.claude" ] && echo wrote || echo clean)" "clean"

echo
echo "== a product module repo gets ZERO collection-module skills =="
PM=$(make_repo product-module product-module)
run "$PM" "$CATALOG_V1"
check "exits 0 — zero skills is the correct outcome, not a failure" "$STATUS" "0"
check "reports it as a product module" "$(grep -c '^kind:    product-module$' "$OUT")" "1"
check "says so" "$(grep -c 'No skills in the catalog apply to a product-module repo' "$OUT")" "1"
# The guarantee the whole catalog exists for. Anything under .claude/ or collection_module/
# would be ~2,500 lines of the wrong contracts for an agent to read.
check "no .claude/ written" "$([ -e "$PM/.claude" ] && echo present || echo absent)" "absent"
check "no .cursor/ written" "$([ -e "$PM/.cursor" ] && echo present || echo absent)" "absent"
check "no collection_module/ written" "$([ -e "$PM/collection_module" ] && echo present || echo absent)" "absent"
check "no manifest written" "$([ -e "$PM/.root" ] && echo present || echo absent)" "absent"

echo
echo "== fail closed on an undetectable kind =="
for fixture in no-config both-keys; do
  R=$(make_repo "$fixture" "$fixture")
  run "$R" "$CATALOG_V1"
  check "$fixture: exits non-zero" "$([ "$STATUS" -ne 0 ] && echo yes)" "yes"
  check "$fixture: explains why" "$(grep -c 'could not establish this repo.s kind' "$OUT")" "1"
  check "$fixture: writes nothing" "$([ -e "$R/.claude" ] || [ -e "$R/.root" ] && echo wrote || echo clean)" "clean"
done

MALFORMED=$(make_repo malformed)
echo '{ this is not json' > "$MALFORMED/.root-config.json"
run "$MALFORMED" "$CATALOG_V1"
check "malformed config: exits non-zero" "$([ "$STATUS" -ne 0 ] && echo yes)" "yes"
check "malformed config: names the problem" "$(grep -c 'is not valid JSON' "$OUT")" "1"
check "malformed config: writes nothing" "$([ -e "$MALFORMED/.claude" ] && echo wrote || echo clean)" "clean"

echo
echo "== there is no bypass =="
BYPASS=$(make_repo bypass product-module)
for flag in --all --force; do
  run "$BYPASS" "$CATALOG_V1" "$flag"
  check "$flag: exits non-zero" "$([ "$STATUS" -ne 0 ] && echo yes)" "yes"
  check "$flag: says there is no such flag" "$(grep -c "there is no $flag" "$OUT")" "1"
  check "$flag: writes nothing" "$([ -e "$BYPASS/.claude" ] && echo wrote || echo clean)" "clean"
done

echo
echo "== --dry-run =="
DRY=$(make_repo dry-run collection-module)
run "$DRY" "$CATALOG_V1" --dry-run
check "exits 0" "$STATUS" "0"
check "lists the SKILL.md it would write" \
  "$(grep -c '^  \.claude/skills/build-collection-module/SKILL\.md$' "$OUT")" "1"
check "lists the reference destination" \
  "$(grep -c '^  collection_module/docs/13-BUILD-FROM-SPEC\.md$' "$OUT")" "1"
check "lists the manifest" "$(grep -c '^  \.root/agent-manifest\.json$' "$OUT")" "1"
check "writes nothing" \
  "$(find "$DRY" -path "$DRY/.git" -prune -o -type f ! -name .root-config.json -print | wc -l | tr -d ' ')" "0"

echo
echo "== an unreachable catalog =="
UNREACHABLE=$(make_repo unreachable collection-module)
run "$UNREACHABLE" "$TMP/no-such-catalog.tar.gz"
check "exits non-zero" "$([ "$STATUS" -ne 0 ] && echo yes)" "yes"
check "says the catalog could not be fetched" "$(grep -c 'could not fetch the catalog' "$OUT")" "1"
check "writes nothing" "$([ -e "$UNREACHABLE/.claude" ] && echo wrote || echo clean)" "clean"

echo
echo "== a malformed index =="
BADINDEX="$TMP/catalog-bad.tar.gz"
BADSTAGE="$TMP/badstage"; rm -rf "$BADSTAGE"; mkdir -p "$BADSTAGE/agent-assets-main/scripts"
echo '{ not json' > "$BADSTAGE/agent-assets-main/index.json"
cp scripts/select-skills.sh "$BADSTAGE/agent-assets-main/scripts/"
tar -czf "$BADINDEX" -C "$BADSTAGE" agent-assets-main
BADREPO=$(make_repo bad-index collection-module)
run "$BADREPO" "$BADINDEX"
check "exits non-zero" "$([ "$STATUS" -ne 0 ] && echo yes)" "yes"
check "names index.json" "$(grep -c "index.json is not valid JSON" "$OUT")" "1"
check "writes nothing" "$([ -e "$BADREPO/.claude" ] && echo wrote || echo clean)" "clean"

echo
echo "== a target it cannot write =="
RO=$(make_repo read-only collection-module)
mkdir -p "$RO/.claude"; chmod 500 "$RO/.claude"
run "$RO" "$CATALOG_V1"
chmod 700 "$RO/.claude"
check "exits non-zero" "$([ "$STATUS" -ne 0 ] && echo yes)" "yes"
check "names the file and the cause" "$(grep -c 'check permissions' "$OUT")" "1"
check "no manifest claims a completed install" "$([ -e "$RO/.root/agent-manifest.json" ] && echo wrote || echo clean)" "clean"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
