# /build-from-spec

Build a collection module from a provider spec, API doc, PDF, or URL.

> **Single source of truth for the steps:** [`collection_module/docs/13-BUILD-FROM-SPEC.md`](../../collection_module/docs/13-BUILD-FROM-SPEC.md). The [`build-from-spec` skill](../skills/build-collection-module/SKILL.md) carries the compact step skeleton. This command is just the entry point — don't restate the step detail here.

---

## Entry

`$ARGUMENTS` is an optional URL or path to the provider's API docs / spec.

1. **Pre-flight** (must pass before writing any code):
   ```bash
   cd collection_module && npm install
   [ -f code/env.ts ] || cp code/env.sample.ts code/env.ts
   cd collection_module && npm test && npm run build
   ```
2. **Follow the six steps in `13-BUILD-FROM-SPEC.md`:** get a spec (extract from `$ARGUMENTS` if given → `docs/<provider>-spec.md`) → scaffold (8 files) → implement stubs → wire in → verify → self-review.
3. **Seed your todos** from the Status Checklist in `13-BUILD-FROM-SPEC.md` and tick them off as you go.

## The two gates that must pass before shipping

- `npm run validate:provider` — deterministic self-review (auto-detects the provider).
- `/review-implementation` — fresh-context semantic review; confirms fixes with you before applying them.

Show the user the scaffold and gate output as you go.
