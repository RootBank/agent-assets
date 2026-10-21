# When to Deviate

> Guidance for agents and humans extending the template when the provider doesn't fit the assumed shape. Read before changing any interface, DI token, or convention.

The template is a **strong default**, not a contract. Some providers genuinely don't fit. The rule: **deviate explicitly, document the reason, and never deviate without flagging it.**

## When to deviate

These are the situations where the template's defaults will not work and a deviation is appropriate:

- **Providers without webhooks.** If the provider only supports polling, skip `08-WEBHOOKS.md` entirely. Add a scheduled poller (under `code/services/`) and document why in the provider's `docs/providers/<slug>.md`.
- **OAuth-based onboarding.** If onboarding requires a redirect dance rather than a single API call, the `afterPolicyIssued` hook can't do it alone. Add a one-shot setup endpoint and have the hook trigger a notification or pending state.
- **Bulk-only / batch APIs.** Some providers (especially direct-debit gateways) only accept batched files daily. The per-payment `afterPaymentCreated` hook becomes a queue-and-flush rather than a direct call. Document the flush trigger.
- **Multi-currency settlements.** The default `ProviderPaymentIntent.currency` field is a string — that's fine. But if the provider returns *converted* amounts asynchronously, the adapter needs an extra field. Extend `ProviderPaymentIntent`, don't shoehorn into `metadata`.
- **Partial refunds.** The current interface assumes full refunds. If you need partial, add `refundPayment(paymentId, amount)` to `PaymentProviderService` — but discuss before doing it, since it's a contract change.

## When NOT to deviate

These look optional but aren't. Deviating here breaks compatibility silently:

- **Idempotency keys.** Every external write must be idempotent under retry. See `12-ERROR-HANDLING.md`. No exceptions.
- **Lifecycle hook ordering.** Don't assume hooks fire in any order other than what Root documents. If you need an action to happen after a specific hook, fire it from that hook — not from a "later" one you hope runs.
- **Error-code mapping.** Always map raw provider errors to an `EnhancedModuleError` subclass at the service boundary. Don't let `StripeAPIError` leak into `main.ts`.
- **Provider-agnostic DI tokens.** Never introduce `STRIPE_CLIENT` or `GOCARDLESS_SERVICE`. Use `PROVIDER_CLIENT` / `PROVIDER_SERVICE`. The whole point is that the rest of the module doesn't know which provider is wired.
- **Config field naming.** Use `providerSecretKey`, `providerWebhookSigningSecret`, etc. — not `stripeSecretKey`. Renaming breaks deployment configs.
- **`LogService` only.** No `console.log`. Ever.

## How to signal a deviation

When you have to deviate, mark it explicitly:

1. **In code** — add a comment immediately above the deviation:
   ```typescript
   // DEVIATION: Provider has no webhooks. Polling job at code/jobs/poll-charges.ts handles state reconciliation.
   ```
2. **In the provider doc** — every provider that ships has a `collection_module/docs/providers/<slug>.md`. Add a `## Deviations from template` section listing each `DEVIATION:` comment with file:line and one-sentence rationale.
3. **In the PR description** — call out the deviation in the summary so a reviewer can challenge it.

A deviation that isn't documented in all three places is a bug.

## Before deviating, ask

1. **Does any existing hook fit?** Read `07-LIFECYCLE-HOOKS.md` carefully. The render hooks in particular cover more ground than they look like they do.
2. **Can the adapter absorb it?** The adapter is pure transformation — many "provider quirks" disappear if you map them in the adapter rather than threading them through the service.
3. **Is the provider doc actually ambiguous, or am I guessing?** If you can't cite a specific page or section, you're guessing. Stop and ask the human instead. Use `TODO(human):` for the specific question.
4. **Have I checked `GLOSSARY.md` for an existing term?** Sometimes the "new concept" already has a name in the template.
5. **Is the deviation general (multiple providers will need this) or specific (only this one provider)?** General → propose extending the interface in `03-PROVIDER-INTERFACE.md`. Specific → keep it isolated in the provider's code.

If any answer is "I don't know," the answer is **don't deviate yet — ask first**.

## Related

- `00-OVERVIEW.md` — template philosophy
- `03-PROVIDER-INTERFACE.md` — the three interfaces a deviation might touch
- `GLOSSARY.md` — terms before you invent new ones

## You've understood this if…

- You can name two situations where deviating is appropriate and two where it isn't.
- You know the three places to document a deviation.
- You can recite the five questions to ask before deviating.
