# agent-assets

Installable agent skills for building on Root.

A **skill** is a folder of instructions that teaches a coding agent — Claude Code, Cursor —
how to do one thing in a Root repo. This repo is the catalog: skills live in `skills/`,
`index.json` lists them, and an installer fetches them into a module repo and records which
version landed. Re-running the installer updates them in place.

Before this repo, skills were copied into `blank_starter_template_v2` at clone time and never
updated again. Fetching from a catalog means an improvement reaches every repo that installs it.

## Layout

```
index.json                           # the catalog — the only file an installer must read
skills/<kind>/<id>/
  SKILL.md                           # the skill itself
  claude/<path-under-.claude>        # files that install into the target repo's .claude/
  cursor/<path-under-.cursor>        # files that install into the target repo's .cursor/
  reference/                         # optional: docs that install alongside the skill
scripts/select-skills.sh             # which skills install into a given repo
scripts/validate-index.sh            # the structural check CI runs
tests/selection.test.sh
tests/fixtures/<kind>/               # repo fixtures the selection test runs against
```

**`<kind>` is load-bearing.** A skill's position under `skills/` is the only thing that decides
which repos it installs into. There is no field to set and no flag to override.

`SKILL.md` is the skill. The `claude/` and `cursor/` subtrees mirror the path each file takes
in the repo it installs into, so an installer copies them across without a lookup table —
`skills/collection-module/build-collection-module/claude/commands/build-from-spec.md` becomes
`.claude/commands/build-from-spec.md`. A skill only carries subtrees for the targets it lists.

`reference/` holds documentation the skill points at. It installs to the path named by
`reference.installs_to`, so skill and reference land together as one versioned unit — a skill
whose steps cite a doc is only useful if that doc arrives with it.

`index.json` is served anonymously from raw GitHub:

```
https://raw.githubusercontent.com/RootBank/agent-assets/main/index.json
```

The repo is public precisely so this works without a token — partners clone
`blank_starter_template_v2` and need the skills too.

## index.json

```json
{
  "version": 1,
  "skills": [
    {
      "id": "build-collection-module",
      "version": "1.0.0",
      "path": "skills/collection-module/build-collection-module",
      "targets": ["claude", "cursor"],
      "description": "Build a collection module from a provider spec, API doc, PDF, or URL.",
      "reference": {
        "path": "reference",
        "installs_to": "collection_module/docs"
      }
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `version` (top level) | Schema version of the catalog itself. Bump only on a breaking change to the file's shape. |
| `id` | Stable identifier, and the skill's directory name. Never reuse an id for a different skill. |
| `version` (per skill) | Semver for the skill's content. Bump on every change so installers can tell what is new. |
| `path` | `skills/<kind>/<id>`. The `<kind>` segment is what decides which repos get the skill, so this field carries the scoping. CI fails if the shape is wrong, the kind is undeclared, or the directory does not exist. |
| `targets` | Which agents the skill ships files for — `claude`, `cursor`. Each value must have a matching subtree in the skill directory. |
| `description` | One line, shown when listing available skills. |
| `reference` | Optional. `path` is the subtree inside the skill directory; `installs_to` is where it lands in the target repo. CI fails if `path` does not exist. |

## How scoping works

A Root repo has a kind, read from the key in its `.root-config.json`:

| Key present | Kind |
| --- | --- |
| `collectionModuleKey` | `collection-module` |
| `productModuleKey` | `product-module` |

This is the same test the Root CLI applies, not a parallel invention:
`root-platform-cli/src/domain/root-config.ts:48` defines
`isProductModuleConfig = (config) => !!config.productModuleKey`, and `collectionModuleKey` is the
collection-module marker in that repo's fixture at
`test-modules/collection-modules/example_module/.root-config.json`.

One deliberate difference: `rp` keys off `productModuleKey` alone, so a config carrying both keys
reads as a product module there. Here it is undetermined and installs nothing, because guessing
wrong in that direction is exactly the misdelivery this catalog exists to stop.

`scripts/select-skills.sh <repo>` prints the skills that install into that repo: the ones whose
`<kind>` path segment matches, and nothing else.

**A skill is never installable just because it is in this repo.** It installs because its path says
which kind it is for. That is deliberate: shipping collection-module context into a product module
teaches an agent to build the wrong thing against the wrong contracts, and the agent has no way to
notice.

There is **no `--all` and no `--force`**. A bypass that exists gets used, usually by someone in a
hurry who is sure this once is fine.

Selection **fails closed**. A repo with no `.root-config.json`, with unreadable JSON, or claiming
both kinds at once gets nothing. An undetermined kind is not a reason to guess.

### Adding a kind

Add it to `kinds` in `index.json`, create `skills/<kind>/`, and teach `select-skills.sh` which key
in `.root-config.json` identifies it. CI fails if a declared kind has no directory, or if a
directory under `skills/` is not a declared kind.

## Adding a skill

1. Decide which repo kind it is for, and create `skills/<kind>/<your-id>/SKILL.md`. If it would
   suit two kinds, it is two skills: the guidance that differs is the whole value. Open the file
   with YAML frontmatter carrying at least `name` (matching the directory) and `description`. Write
   the `description` to say **when** an agent should reach for the skill, not only what it does —
   that line is what the agent reads to decide.
2. Add any target-specific files under `claude/` or `cursor/`, at the path they should take in
   the repo they install into. Put any docs the skill cites under `reference/` and declare
   where they install.
3. Add an entry to `index.json`. Start the skill's `version` at `1.0.0`, and list only the
   targets you actually shipped a subtree for. Do **not** write an `applies_to` field: the kind is
   derived from the path, and a second copy of the same fact is just a chance for the two to
   disagree. CI rejects one that disagrees.
4. Run `./scripts/validate-index.sh` and `./tests/selection.test.sh`.
5. Open a PR. CI runs both.

Paths inside a skill's files are resolved in the **target** repo, not here. A skill that links
to `collection_module/docs/…` is pointing at the repo it installs into; those links will not
resolve when browsing this catalog, and that is expected.

## `build-collection-module/reference/` is a snapshot

The 20 files under `skills/collection-module/build-collection-module/reference/` are a point-in-time copy of
`collection_module/docs/` from `RootBank/blank_starter_template_v2` at `main`. They are **not**
yet reconciled against [docs.rootplatform.com](https://docs.rootplatform.com), which is the
public source of truth for platform behaviour. Where the two disagree, the docs site wins.

Two files are deliberately absent — `SPEC-TEMPLATE.md` and `14-SELF-REVIEW.md` — because open
template PRs are rewriting them. Links to those two inside the snapshot do not resolve yet; they
arrive with the rest of the template promotion. Until then, read them in the template repo.

Treat the snapshot as read-only: fix the template first, then re-copy, so the two do not drift
in opposite directions.

## Changing a skill

Edit the files and bump the skill's `version` in `index.json` in the same commit. An installer
compares that number against what it recorded locally, so a change that does not bump it is a
change that never reaches anyone.
