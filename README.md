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
index.json                       # the catalog — the only file an installer must read
skills/<id>/
  SKILL.md                       # the skill itself
  claude/<path-under-.claude>    # files that install into the target repo's .claude/
  cursor/<path-under-.cursor>    # files that install into the target repo's .cursor/
scripts/validate-index.sh
```

`SKILL.md` is the skill. The `claude/` and `cursor/` subtrees mirror the path each file takes
in the repo it installs into, so an installer copies them across without a lookup table —
`skills/build-collection-module/claude/commands/build-from-spec.md` becomes
`.claude/commands/build-from-spec.md`. A skill only carries subtrees for the targets it lists.

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
      "path": "skills/build-collection-module",
      "targets": ["claude", "cursor"],
      "applies_to": "collection-module",
      "description": "Build a collection module from a provider spec, API doc, PDF, or URL."
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `version` (top level) | Schema version of the catalog itself. Bump only on a breaking change to the file's shape. |
| `id` | Stable identifier, and the skill's directory name. Never reuse an id for a different skill. |
| `version` (per skill) | Semver for the skill's content. Bump on every change so installers can tell what is new. |
| `path` | Repo-relative path to the skill directory. CI fails if it does not exist. |
| `targets` | Which agents the skill ships files for — `claude`, `cursor`. Each value must have a matching subtree in the skill directory. |
| `applies_to` | Which kind of repo the skill belongs in. See below. |
| `description` | One line, shown when listing available skills. |

## How `applies_to` scopes installs

A Root repo has a kind. The installer works out which kind it is standing in and installs
only the skills whose `applies_to` matches, plus everything marked `any`.

| Value | Installed into |
| --- | --- |
| `any` | Every repo. Use for skills that do not depend on a repo's structure. |
| `collection-module` | Collection module repos. |
| `product-module` | Product module repos. |

Scoping lives here, in the catalog — not in separate repos per module kind. Adding a kind
means adding a value, not a repo.

## Adding a skill

1. Create `skills/<your-id>/SKILL.md`. Open it with YAML frontmatter carrying at least `name`
   (matching the directory) and `description`. Write the `description` to say **when** an agent
   should reach for the skill, not only what it does — that line is what the agent reads to
   decide.
2. Add any target-specific files under `claude/` or `cursor/`, at the path they should take in
   the repo they install into.
3. Add an entry to `index.json`. Start the skill's `version` at `1.0.0`, and list only the
   targets you actually shipped a subtree for.
4. Run `./scripts/validate-index.sh`.
5. Open a PR. CI runs the same check.

Paths inside a skill's files are resolved in the **target** repo, not here. A skill that links
to `collection_module/docs/…` is pointing at the repo it installs into; those links will not
resolve when browsing this catalog, and that is expected.

## Changing a skill

Edit the files and bump the skill's `version` in `index.json` in the same commit. An installer
compares that number against what it recorded locally, so a change that does not bump it is a
change that never reaches anyone.
