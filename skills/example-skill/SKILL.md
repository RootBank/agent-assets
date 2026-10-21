---
name: example-skill
description: Worked example of a catalog skill. Use it as the starting point when adding a new skill to agent-assets — copy the directory, rewrite the frontmatter and body, and add an entry to index.json.
allowed-tools: Read Grep Glob
---

# Example Skill

This skill exists so the catalog is never empty and so there is one file to copy when
adding a new skill. It teaches the shape, not a task.

## Anatomy of a skill

A skill is a directory under `skills/` containing a `SKILL.md`:

```
skills/<id>/
  SKILL.md          # required — frontmatter + instructions
  <anything else>   # optional — reference docs, templates, scripts
```

`SKILL.md` opens with YAML frontmatter:

| Field | Required | Purpose |
| --- | --- | --- |
| `name` | yes | Must match the directory name and the `id` in `index.json`. |
| `description` | yes | One or two sentences. The agent reads this to decide whether the skill applies, so say *when to use it*, not just what it does. |
| `argument-hint` | no | Placeholder shown when the skill is invoked as a command. |
| `allowed-tools` | no | Space-separated tool names the skill may use. Omit to allow all. |

Everything after the frontmatter is the instruction body — plain Markdown, written as
directions to an agent.

## Writing the body

- Address the agent directly, in the imperative.
- Number the steps when order matters, and say what to do when a step fails.
- Point at files in the target repo by path rather than restating their contents, so the
  skill does not drift when those files change.
- Keep it short enough that an agent reads the whole thing.

## Adding it to the catalog

A skill is not installable until `index.json` lists it. See the README for the field
reference and for how `applies_to` scopes which repos receive the skill.
