# Build From Spec

> End-to-end workflow: go from a provider spec, API doc, PDF, or URL to a working collection module.

## Table of Contents

| Step | What happens |
|---|---|
| [Prerequisites](#prerequisites) | What you need before starting |
| [Step 0 — Pre-flight setup](#step-0--pre-flight-setup) | Install deps, create env.ts, confirm tests pass |
| [Step 1 — Prepare your spec](#step-1--prepare-your-spec) | Fill SPEC-TEMPLATE.md or run `extract:spec` |
| [Step 2 — Scaffold the provider](#step-2--scaffold-the-provider) | Generate 8 files in one command |
| [Step 3 — Implement the stubs](#step-3--implement-the-stubs) | Fill in the provider-specific logic |
| [Step 4 — Wire into the module](#step-4--wire-into-the-module) | DI container, webhooks, lifecycle hooks, config |
| [Step 5 — Test](#step-5--test) | Run tests and validate config |
| [Step 6 — Self-review](#step-6--self-review) | Run `/review-implementation` before shipping |
| [Status checklist](#status-checklist) | Quick done/not-done reference |
| [Common errors](#common-errors) | Troubleshooting table |

---

## Prerequisites

- Node ≥ 18, npm ≥ 8
- `cd collection_module && npm install`
- Provider API docs — URL, PDF, or OpenAPI file

---

## Step 0 — Pre-flight setup

Run these before writing any code. They ensure the environment is ready and baseline tests pass.

1. Install dependencies (once):
   ```bash
   cd collection_module && npm install
   ```
2. Ensure `code/env.ts` exists:
   ```bash
   cp code/env.sample.ts code/env.ts  # only if env.ts doesn't exist
   ```
3. Confirm baseline tests pass:
   ```bash
   npm test
   ```
   If tests fail here, fix the environment before proceeding.

---

## Step 1 — Prepare your spec

You have two paths:

### Path A — Extract from docs automatically (recommended)

```bash
# From a URL
npm run extract:spec -- --input=https://docs.provider.com/api-reference --output=docs/<provider>-spec.md

# From a PDF
npm run extract:spec -- --input=./provider-api-docs.pdf --output=docs/<provider>-spec.md

# From an OpenAPI file
npm run extract:spec -- --input=./openapi.json --output=docs/<provider>-spec.md
```

If `ANTHROPIC_API_KEY` is set, Claude fills the template automatically. Otherwise the script falls back to passthrough mode — it outputs the template with the raw source content appended so you can fill it in manually. You can also force passthrough with `--no-ai`. Review the output and fill in any gaps.

### Path B — Fill the template manually

Open `docs/SPEC-TEMPLATE.md` and fill in all sections:

| Section | Required fields |
|---|---|
| Provider Overview | Name, API type (sdk/http), base URL or SDK package |
| Authentication | Header name, header format |
| Webhook Configuration | Signature header, signature algorithm |
| Webhook Events | Event names + what Root Platform action to take |
| Data Shapes | Payment object shape, customer object shape |
| Status Mapping | Provider status → Root `PaymentStatus` |

---

## Step 2 — Scaffold the provider

### Option A — From spec file

```bash
npm run scaffold:provider -- --from-spec=docs/<provider>-spec.md --reason="Adding GoCardless for ZA direct debit"
```

The `--from-spec` flag reads your filled spec and auto-populates `--provider`, `--api-type`, `--base-url`, `--auth-header`, `--webhook-header`.

### Option B — Direct flags

```bash
# HTTP provider
npm run scaffold:provider -- \
  --provider=GoCardless \
  --api-type=http \
  --base-url=https://api.gocardless.com \
  --auth-header=Authorization \
  --webhook-header=Webhook-Signature \
  --reason="Direct debit for ZA market"

# SDK-based provider
npm run scaffold:provider -- \
  --provider=MyProvider \
  --api-type=sdk \
  --sdk-package=myprovider-nodejs \
  --webhook-header=X-MyProvider-Signature \
  --reason="SDK-based integration"
```

### What gets created

| File | Purpose |
|---|---|
| `code/clients/{provider}-client.ts` | SDK/HTTP wrapper + webhook verification |
| `code/services/{provider}.service.ts` | Business logic stubs |
| `code/adapters/{provider}-to-root-adapter.ts` | Status mapping + data shape transforms |
| `code/interfaces/{provider}-events.ts` | Webhook event name constants |
| `__tests__/clients/{provider}-client.test.ts` | Client tests |
| `__tests__/services/{provider}.service.test.ts` | Service tests |
| `__tests__/adapters/{provider}-to-root-adapter.test.ts` | Adapter tests |
| `__tests__/helpers/{provider}-factories.ts` | Mock factories for the provider's API response shapes |

---

## Step 3 — Implement the stubs

Read each generated file and fill in the `// TODO` sections. Use `docs/STRIPE-REFERENCE.md` as the working example for every pattern.

### Service (`code/services/{provider}.service.ts`)

| Method | What to implement | Reference |
|---|---|---|
| `createCustomer` | POST to provider's customer endpoint | [STRIPE-REFERENCE.md § Service → Create customer](./STRIPE-REFERENCE.md#service) |
| `createPaymentIntent` | POST to payment/charge endpoint | [STRIPE-REFERENCE.md § Service → Create payment intent](./STRIPE-REFERENCE.md#service) |
| `attachPaymentMethod` | Attach method to customer + set as default | [STRIPE-REFERENCE.md § Service → Attach payment method](./STRIPE-REFERENCE.md#service) |
| `cancelSubscription` | DELETE/cancel subscription | [STRIPE-REFERENCE.md § Service → Cancel subscription](./STRIPE-REFERENCE.md#service) |

Rules:
- Wrap all API calls in `retryWithBackoff()`
- Log at the start of every method: `this.logService.info('Creating customer', 'ProviderService', params)`
- Throw `ModuleError` on failures, not raw errors

### Adapter (`code/adapters/{provider}-to-root-adapter.ts`)

Fill in `statusMap` with the provider's payment statuses mapped to Root's `PaymentStatus`:

```typescript
const statusMap: Record<string, string> = {
  'provider_success_status': PaymentStatus.Successful,
  'provider_pending_status': PaymentStatus.Pending,
  'provider_failed_status':  PaymentStatus.Failed,
  'provider_cancel_status':  PaymentStatus.Cancelled,
};
```

See `docs/SPEC-TEMPLATE.md § 5 Status Mapping` for the provider's status values.

### Events (`code/interfaces/{provider}-events.ts`)

Replace placeholder event names with the real ones from the provider docs:

```typescript
export const PROVIDER_EVENTS = {
  PAYMENT_COMPLETED: 'actual.event.name',   // from spec
  PAYMENT_FAILED:    'actual.event.failed',  // from spec
} as const;
```

---

## Step 4 — Wire into the module

Four files to update. Read each one before editing — the Stripe entries show the exact pattern.

### 4a. DI container

**File:** `code/core/container.setup.ts`

Register the client and service under the provider-agnostic tokens:

```typescript
container.register(ServiceToken.PROVIDER_CLIENT, {
  useClass: MyProviderClient,
  lifetime: Lifetime.SINGLETON,
});
container.register(ServiceToken.PROVIDER_SERVICE, {
  useClass: MyProviderService,
  lifetime: Lifetime.SINGLETON,
});
```

### 4b. Webhooks

**File:** `code/webhook-hooks.ts`

1. Verify signature using `providerClient.verifyWebhookSignature()`
2. Parse event body
3. Add `case` entries for each event in `PROVIDER_EVENTS`

```typescript
case MYPROVIDER_EVENTS.PAYMENT_COMPLETED: {
  const ctrl = container.resolve(ServiceToken.INVOICE_PAID_CONTROLLER);
  await ctrl.handle(parsed.data.object);
  break;
}
```

See [STRIPE-REFERENCE.md § Webhook Routing](./STRIPE-REFERENCE.md#webhook-routing) for the full pattern.

### 4c. Lifecycle hooks

**File:** `code/lifecycle-hooks/policy.hooks.ts`, `payment.hooks.ts`, `payment-method.hooks.ts`

| Hook | What to call |
|---|---|
| `afterPolicyIssued` | `providerService.createCustomer(...)` then update `policy.app_data` |
| `afterPolicyCancelled` | `providerService.cancelSubscription(...)` if applicable |
| `afterPolicyPaymentMethodAssigned` | `providerService.attachPaymentMethod(...)` |
| `afterPaymentCreated` | `providerService.createPaymentIntent(...)` |

See [STRIPE-REFERENCE.md § Lifecycle Hooks](./STRIPE-REFERENCE.md#lifecycle-hooks) for exact implementations.

### 4d. Config (4 files to update)

When adding provider-specific configuration, check these files:

1. **`code/env.sample.ts`** — add env var placeholders
2. **`code/services/config.service.ts`** — add to `EnvironmentConfig` interface if needed (or use `providerExtraConfig`)
3. **`__tests__/setup.ts`** — add mock values for new env exports
4. **`__tests__/test-helpers.ts`** — add to `createMockConfigService()` config map

Add the provider's config keys to `code/env.sample.ts`:

```typescript
PROVIDER_SECRET_KEY_LIVE:             '',
PROVIDER_SECRET_KEY_TEST:             '',
PROVIDER_WEBHOOK_SIGNING_SECRET_LIVE: '',
PROVIDER_WEBHOOK_SIGNING_SECRET_TEST: '',
PROVIDER_PRODUCT_ID_LIVE:             '',
PROVIDER_PRODUCT_ID_TEST:             '',
```

See [STRIPE-REFERENCE.md § Config Fields](./STRIPE-REFERENCE.md#config-fields) for the full config table and how `ConfigurationService` resolves live vs test.

---

## Step 5 — Test

Run the deterministic provider gate first — it hard-fails the mechanizable self-review checks (DI registration, no leftover stubs, retry/error/logging discipline) before you spend time on the semantic review:

```bash
npm run validate:provider   # auto-detects the provider; exits non-zero on any Critical/Major miss
```

Then run the test suite as a bounded loop rather than a single pass:

```bash
npm test
```

1. Run `npm test`, read the failures, fix them, re-run.
2. Repeat until green, capping at ~3 iterations.
3. If it's still red after that, stop and surface the remaining failures rather than churning — the cause is usually a wiring gap from Step 4, not a flaky test.

Finally, config shape and lint:

```bash
npm run validate   # config shape
npm run lint
```

Fix all failures before moving to Step 6.

---

## Step 6 — Self-review

Run the self-review command before shipping:

```
/review-implementation
```

This checks [docs/14-SELF-REVIEW.md](./14-SELF-REVIEW.md) criteria: critical blockers, major issues, minor issues, and enhancement suggestions.

---

## Status Checklist

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
[ ] Config validates (npm run validate)
[ ] Self-review complete (/review-implementation)
```

---

## Common Errors

| Error | Cause | Fix |
|---|---|---|
| `--provider is required` | Missing flag | Add `--provider=ProviderName` |
| `--base-url is required` | `--api-type=http` but no URL | Add `--base-url=https://...` |
| `file already exists — not overwriting` | Scaffold run twice | Delete file or use `--dry-run` to preview |
| `Cannot resolve PROVIDER_CLIENT` | DI registration missing | Add registration in `container.setup.ts` |
| `Webhook signature invalid` | Wrong header name or secret | Check `--webhook-header` and `providerWebhookSigningSecret` config |
| `extract:spec running in passthrough mode` | API key not set | This is normal — review the output and fill in the template sections manually |
| `PDF parse error` | Scanned/image PDF | Use a text-based PDF or paste content into SPEC-TEMPLATE.md manually |
| `fetch error on URL` | JS-rendered page | Save page as PDF and use `--input=./page.pdf` |

---

## Related Docs

- [docs/SPEC-TEMPLATE.md](./SPEC-TEMPLATE.md) — spec input template
- [docs/STRIPE-REFERENCE.md](./STRIPE-REFERENCE.md) — working reference implementation
- [docs/03-PROVIDER-INTERFACE.md](./03-PROVIDER-INTERFACE.md) — contracts you must implement
- [docs/14-SELF-REVIEW.md](./14-SELF-REVIEW.md) — self-review criteria

## You've understood this if…

- You can name the six steps in the SOP without re-reading it.
- You know when to use Path A (extract from docs) vs Path B (fill template manually).
- You can identify the pre-flight check that must pass before scaffolding.
