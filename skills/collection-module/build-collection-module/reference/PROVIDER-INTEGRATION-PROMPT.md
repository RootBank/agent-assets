# Provider integration prompt template

Fill in every `{{PLACEHOLDER}}`. Hand the result to an agent in the repo.

---

I want to add **{{PROVIDER_NAME}}** ({{ONE_LINE_DESCRIPTION}}) to this project so we can {{PRIMARY_USE_CASE}}. Use the `/build-from-spec` command — it's set up to handle exactly this kind of job. Point it at the provider's API docs: {{API_DOCS_URL}}

## What it needs to do

1. **{{ONBOARDING_CAPABILITY}}** — let us register a {{ENTITY_TYPE}} with {{PROVIDER_NAME}} and complete the authorisation step they require ({{AUTHORISATION_ARTEFACT}}, e.g. mandate, consent, verified identity, signed agreement). If the provider offers a hosted flow, prefer it.
2. **{{CORE_TRANSACTION_CAPABILITY}}** — both {{ONE_OFF_VARIANT}} and {{RECURRING_OR_BATCH_VARIANT}}, if the provider supports both.
3. **Listen for updates from {{PROVIDER_NAME}}** — when a {{TRANSACTION_TYPE}} {{TERMINAL_STATES}}, the provider sends a webhook. Receive these, verify authenticity ({{SIGNATURE_SCHEME_IF_KNOWN}}), update our records.
4. **Handle failures** — retry policy: {{RETRY_POLICY}}. After exhausting retries, mark as {{TERMINAL_FAILURE_STATE}}.
5. **{{SANDBOX_NAME}} credentials only** — no production traffic, no real {{REAL_WORLD_SIDE_EFFECT}}.

## Before you start coding, show me

- **Which approach you're taking for {{ONBOARDING_CAPABILITY}}** — most providers offer at least two (hosted vs. API-direct, redirect vs. embedded, server-side vs. client-side). Pick one and justify it against the provider interface conventions in this repo.
- **Which webhook events you plan to subscribe to** — list them by name. Flag any documented events you're *not* subscribing to and explain why. Recommend any I didn't ask for.
- **Anything in the {{PROVIDER_NAME}} model that doesn't map cleanly** onto this template's provider interface. If you spot one, stop and ask before deviating. See `collection_module/docs/16-WHEN-TO-DEVIATE.md`.

## At the end, I want

- Working code that passes the project's tests, scaffolded via `/build-from-spec` and reviewed via `/review-implementation`.
- A short doc at `collection_module/docs/providers/{{PROVIDER_SLUG}}.md` explaining sandbox setup, how to run the test suite against the sandbox, and what to look for in logs.
- A flow diagram (Mermaid or ASCII) showing the happy path: {{HAPPY_PATH_FLOW}}.
- A summary of every `TODO(human):` you inserted and every assumption that wasn't directly supported by the provider's docs.

## Ground rules

- If anything in the {{PROVIDER_NAME}} docs is ambiguous, contradicts itself, or doesn't fit how this project is built — **stop and ask**. Do not guess. Do not paper over it with a comment.
- If the webhook signature scheme isn't documented clearly, do not invent verification logic. Ask.
- If the provider has a feature this template doesn't have a slot for (multi-currency, partial refunds, batching), flag it before writing code so we can decide whether to extend the interface or scope it out.

---

## Example: GoCardless filled in

For reference, here's what this template looks like fully filled in for a UK direct-debit provider:

- `{{PROVIDER_NAME}}` → GoCardless
- `{{ONE_LINE_DESCRIPTION}}` → the direct debit company
- `{{PRIMARY_USE_CASE}}` → collect payments from customers
- `{{API_DOCS_URL}}` → https://developer.gocardless.com/api-reference/
- `{{ONBOARDING_CAPABILITY}}` → set up customers
- `{{ENTITY_TYPE}}` → customer
- `{{AUTHORISATION_ARTEFACT}}` → mandate (bank details authorised)
- `{{CORE_TRANSACTION_CAPABILITY}}` → take payments
- `{{ONE_OFF_VARIANT}}` → one-off charges
- `{{RECURRING_OR_BATCH_VARIANT}}` → recurring subscriptions
- `{{TRANSACTION_TYPE}}` → payment
- `{{TERMINAL_STATES}}` → succeeds, fails, or gets charged back
- `{{SIGNATURE_SCHEME_IF_KNOWN}}` → HMAC (per GoCardless webhook docs)
- `{{RETRY_POLICY}}` → retry after 3 working days, up to 2 more times
- `{{TERMINAL_FAILURE_STATE}}` → uncollectable
- `{{SANDBOX_NAME}}` → sandbox
- `{{REAL_WORLD_SIDE_EFFECT}}` → money
- `{{PROVIDER_SLUG}}` → gocardless
- `{{HAPPY_PATH_FLOW}}` → customer signs up → bank details authorised → first payment taken → confirmation received
