# Lifecycle Hooks

> Reference for every hook Root Platform calls into the collection module. See `STRIPE-REFERENCE.md` for a complete worked example.

## Overview

Lifecycle hooks are functions exported from `code/main.ts` that Root Platform invokes at specific points in the policy and payment lifecycle. Stubs live in `code/lifecycle-hooks/`, grouped by domain:

| File | Hooks |
|---|---|
| `payment-method.hooks.ts` | `createPaymentMethod`, `renderCreatePaymentMethod`, `renderViewPaymentMethodSummary`, `renderViewPaymentMethod`, `afterPolicyPaymentMethodAssigned`, `afterPaymentMethodRemoved` |
| `payment.hooks.ts` | `afterPaymentCreated`, `afterPaymentUpdated` |
| `policy.hooks.ts` | `afterPolicyIssued`, `afterPolicyUpdated`, `afterPolicyCancelled`, `afterPolicyExpired`, `afterPolicyLapsed`, `afterAlterationPackageApplied` |

All hooks are re-exported from `code/lifecycle-hooks/index.ts` and surfaced via `code/main.ts`.

## Conventions

- **DI resolution only.** Resolve services via `getContainer()` and `ServiceToken.PROVIDER_SERVICE`. Never `import` provider classes (e.g. `StripeService`) directly in hooks — type as `PaymentProviderService` from `code/interfaces/provider.interfaces.ts`.
- **Logging via `LogService`.** No `console.log`.
- **Async when the hook touches a provider.** Hooks that call provider APIs return `Promise<void>`. Hooks that only log can be synchronous.
- **Render hooks return HTML strings.** Use `RenderService` and escape user-supplied values with `escapeHtml()`.
- **Errors propagate.** A thrown error rejects the hook; Root will retry per its own policy. Wrap external calls in `retryWithBackoff` first (see `12-ERROR-HANDLING.md`).
- **`app_data` is the persistence channel.** Store provider-side IDs (`provider_customer_id`, `provider_subscription_id`) on the policy via the Root client so subsequent hooks can read them.

## Hook reference

### Policy hooks (`policy.hooks.ts`)

#### `afterPolicyIssued({ policy }): Promise<void>`
Invoked once when a policy is first issued. Typical work: create a customer record at the provider, persist `provider_customer_id` to `policy.app_data` via `ROOT_CLIENT`. See `STRIPE-REFERENCE.md` § Lifecycle Hooks for the full implementation. Async.

#### `afterPolicyUpdated({ policy, updates }): void`
Invoked when any policy field changes. Synchronous by default — only call the provider if `updates` includes fields the provider needs to know about (e.g. policyholder email). Otherwise just log.

#### `afterPolicyCancelled({ policy }): Promise<void>`
Invoked on cancellation. Typical work: cancel the provider subscription using `policy.app_data?.provider_subscription_id`. Guard against missing IDs — cancellation must succeed even if the provider has no record. Async.

#### `afterPolicyExpired({ policy }): void`
Invoked when the policy reaches its end date. Most providers handle expiry implicitly; default behaviour is to log. Synchronous.

#### `afterPolicyLapsed({ policy }): void`
Invoked when payments fail beyond the grace period. Default behaviour: log. If the provider needs to halt collection attempts (e.g. pause a subscription), do it here. Synchronous unless you call out.

#### `afterAlterationPackageApplied({ policy, alteration_package, alteration_hook_key }): void`
Invoked when an alteration package is applied. Use `alteration_hook_key` to branch — different alterations may require different provider-side actions (e.g. premium change → update subscription amount). Synchronous unless you call out.

### Payment hooks (`payment.hooks.ts`)

#### `afterPaymentCreated({ policy, payment }): Promise<void>`
Invoked when Root creates a payment record. Typical work: create a payment intent at the provider tied to `policy.app_data.provider_customer_id`, attach `metadata.payment_id` for webhook correlation. The webhook handler later maps the provider's terminal status back via the adapter. Async.

#### `afterPaymentUpdated({ policy, payment }): Promise<void>`
Invoked when payment state changes from Root's side (e.g. amount adjusted before collection). Sync provider-side if relevant. Async.

### Payment-method hooks (`payment-method.hooks.ts`)

#### `createPaymentMethod({ data }): { module: any }`
Synchronous. Returns the `module` object stored on the Root payment method. Map provider payment-method data into the shape downstream hooks expect. No provider API call here — this fires after data is already captured.

#### `renderCreatePaymentMethod(): Promise<string>`
Returns the HTML form embedded in the Root dashboard for capturing payment details. Typical work: create a setup/payment intent on the provider, return the rendered form via `RenderService` with the `client_secret`. Async.

#### `renderViewPaymentMethodSummary({ payment_method }): Promise<string>`
Returns a compact HTML card (last4, brand). Fetch from the provider if the cached data is insufficient. Guard against `payment_method` being null. Async.

#### `renderViewPaymentMethod(): string`
Returns the detailed payment-method view. Often left as `''` if the dashboard doesn't need a separate detail page. Synchronous.

#### `afterPolicyPaymentMethodAssigned({ policy }): Promise<void>`
Invoked when a payment method is attached to a policy. Typical work: attach the provider payment-method to the provider customer (`providerService.attachPaymentMethod`). Async.

#### `afterPaymentMethodRemoved({ policy }): Promise<void>`
Invoked when a payment method is detached. Typical work: detach at the provider if required (most providers handle this implicitly). Async.

## Ordering and idempotency

Root may retry hooks on failure. Every hook must be **idempotent**:
- Check `policy.app_data` for existing IDs before creating provider-side records.
- Use deterministic idempotency keys when the provider supports them (e.g. Stripe's `Idempotency-Key` header keyed on `payment.payment_id`).
- A second invocation of `afterPolicyIssued` for the same policy must not create a second customer.

Hooks fire in policy/payment order — `afterPolicyIssued` precedes `afterPaymentCreated` for that policy. Don't rely on cross-policy ordering.

## Related

- `code/lifecycle-hooks/` — Stub implementations
- `03-PROVIDER-INTERFACE.md` — Service patterns invoked from hooks
- `12-ERROR-HANDLING.md` — Retry and error propagation
- `STRIPE-REFERENCE.md` — Full working example

## You've understood this if…

- You can name the three lifecycle hooks invoked during a refund or cancellation and the order they run in.
- You can explain why every hook must be idempotent.
- You know why hooks resolve `PROVIDER_SERVICE` rather than importing `StripeService` directly.
