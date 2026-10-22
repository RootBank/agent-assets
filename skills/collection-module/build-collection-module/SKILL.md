---
name: build-from-spec
description: Build a collection module from a provider spec, API doc, PDF, or URL. Use when the user wants to add a new payment provider, integrate a payment gateway, or build from API documentation.
argument-hint: [url-or-path-to-spec]
allowed-tools: Read Grep Glob Bash Edit Write WebFetch Agent
---

# Build From Spec

Build a collection module from a provider spec, API doc, PDF, or URL.

> Full SOP: `collection_module/docs/13-BUILD-FROM-SPEC.md`
> Reference implementation: `collection_module/docs/STRIPE-REFERENCE.md`

---

## Step 0 — Pre-flight check

BEFORE writing any provider files:
1. Run `cd collection_module && npm install` once (do NOT run npm install more than once unless it fails)
2. Ensure `code/env.ts` exists — if not, run `cp code/env.sample.ts code/env.ts`
3. Run `cd collection_module && npm test` to confirm a green baseline
4. Run `cd collection_module && npm run build` to confirm clean compilation

If any of these fail, fix the issue before proceeding to Step 1.

---

## Step 1 — Get a spec

If the user provided a URL, PDF, or OpenAPI file, **always run extract:spec** — it does NOT require an API key. Without `ANTHROPIC_API_KEY` it runs in passthrough mode, outputting the template with raw source content appended for you to fill in. This is the expected workflow.

```bash
cd collection_module && npm run extract:spec -- --input=$ARGUMENTS --output=docs/<provider>-spec.md
```

If the user already has a filled `docs/SPEC-TEMPLATE.md`, skip to Step 2.

If the user provided raw API documentation (pasted text, a webpage), read it and fill `docs/SPEC-TEMPLATE.md` manually. The required sections are:

| Section | Required fields |
|---|---|
| Provider Overview | Name, API type (sdk/http), base URL or SDK package |
| Authentication | Header name, header format |
| Webhook Configuration | Signature header, signature algorithm |
| Webhook Events | Event names + what Root Platform action to take |
| Data Shapes | Payment object shape, customer object shape |
| Status Mapping | Provider status → Root `PaymentStatus` |

## Step 2 — Scaffold the provider

```bash
cd collection_module && npm run scaffold:provider -- --from-spec=docs/<provider>-spec.md --reason="<why>"
```

Or with explicit flags:

```bash
cd collection_module && npm run scaffold:provider -- \
  --provider=<Name> \
  --api-type=<sdk|http> \
  --base-url=<url> \
  --auth-header=<header> \
  --webhook-header=<header> \
  --reason="<why>"
```

Run the scaffold script rather than writing provider files by hand — it generates consistent
boilerplate with correct imports, DI tokens, and TODO markers. Only write files from scratch if
the scaffold fails or produces incorrect output.

Show the user the CLI output. **8 files** should be created:
- `code/clients/{provider}-client.ts`
- `code/services/{provider}.service.ts`
- `code/adapters/{provider}-to-root-adapter.ts`
- `code/interfaces/{provider}-events.ts`
- `__tests__/clients/{provider}-client.test.ts`
- `__tests__/services/{provider}.service.test.ts`
- `__tests__/adapters/{provider}-to-root-adapter.test.ts`
- `__tests__/helpers/{provider}-factories.ts`

## Step 3 — Implement stubs

Read each generated file and implement the `// TODO` sections, using `docs/STRIPE-REFERENCE.md` as the pattern for every method. Full method-by-method detail, the `statusMap` shape, and the events snippet are in [`13-BUILD-FROM-SPEC.md` § Step 3](../../collection_module/docs/13-BUILD-FROM-SPEC.md#step-3--implement-the-stubs) — the single source of truth. Don't restate them here.

Core rules (these hold everywhere):
- Wrap API calls in `retryWithBackoff()`.
- Log at the start of each method via `LogService` — no `console.log`.
- Throw a `ModuleError`, not a raw `Error`.
- Resolve services in hooks via `container.resolve(ServiceToken.PROVIDER_SERVICE)` typed as `PaymentProviderService` — never import provider classes into hooks.

**Optional — fan out with subagents.** The four generated files are independent, so you *may* implement them in parallel with one read-only subagent per file (`code/clients/…`, `code/services/…`, `code/adapters/…`, `code/interfaces/…`), each given the spec + its Stripe-reference section. Keep it sequential for a small provider. Do **not** parallelize Step 4 — those files are shared and parallel writes conflict.

## Step 4 — Wire into the module

Update the DI container, webhooks, lifecycle hooks, and config — sequentially (shared files). The exact snippets and the hook-to-method table live in [`13-BUILD-FROM-SPEC.md` § Step 4](../../collection_module/docs/13-BUILD-FROM-SPEC.md#step-4--wire-into-the-module). Read each target file first; the Stripe entries show the pattern.

## Step 5 — Verify

```bash
cd collection_module && npm run validate:provider   # deterministic gate — mechanized self-review
cd collection_module && npm test                    # bounded loop: run → fix → re-run (see 13 § Step 5)
```

Fix failures, then run `/review-implementation` for the fresh-context semantic review.

## Status Checklist

Seed your todos from this list at the start of the build and tick them off as you go (this is the canonical copy — [`13-BUILD-FROM-SPEC.md`](../../collection_module/docs/13-BUILD-FROM-SPEC.md#status-checklist) mirrors it):

```
[ ] Spec filled (docs/<provider>-spec.md or docs/SPEC-TEMPLATE.md)
[ ] Scaffold run — 8 files created
[ ] Service methods implemented (no TODO stubs remaining)
[ ] Adapter statusMap filled
[ ] Events constants use real event names
[ ] DI container registrations added
[ ] Webhooks: signature verification + event routing
[ ] Lifecycle hooks: policy, payment, payment-method
[ ] Config placeholders added to env.sample.ts
[ ] Provider gate passes (npm run validate:provider)
[ ] All tests pass (npm test)
[ ] Self-review complete (/review-implementation)
```
