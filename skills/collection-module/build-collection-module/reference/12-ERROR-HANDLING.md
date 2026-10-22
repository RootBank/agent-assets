# Error Handling

> Reference for the error classes shipped in `code/utils/`, how they propagate across the provider boundary, and the retry/idempotency semantics expected of every external call.

## Overview

The template defines two error families:

- **`ModuleError`** (`code/utils/error.ts`) — a generic base error that auto-prefixes the current environment and caller frame. Use for ad-hoc business errors that don't fit a category.
- **`EnhancedModuleError`** (`code/utils/error-types.ts`) and its subclasses — categorised errors with a `retryable` flag, HTTP-shaped `statusCode`, and request-tracking (`requestId`, `correlationId`). Use these everywhere you can — they unlock `retryWithBackoff` + `isRetryableError` and produce structured logs via `formatErrorForLogging`.

All types are re-exported from `code/utils/index.ts`.

## Error code reference

| Class | Category | Status | Retryable | Typical cause | Recommended handling | Example log line |
|---|---|---|---|---|---|---|
| `ModuleError` | (uncategorised) | — | — | Generic business error, unknown failure mode | Throw at the service boundary when no specific subclass fits. Always include `metadata`. | `[sandbox \| StripeService.createCustomer] Failed to create customer {"cause":"…"}` |
| `EnhancedModuleError` | configurable | configurable | configurable | Direct use when you need full control of category + retryable + statusCode | Prefer a subclass below. Use this base class only when no subclass fits. | `{ "name":"EnhancedModuleError", "category":"unknown", ... }` |
| `ValidationError` | `validation` | 400 | false | Caller passed invalid input (missing required field, malformed shape) | Surface as-is to the caller; don't retry. Lifecycle hooks should not retry these. | `{ "name":"ValidationError", "category":"validation", "statusCode":400 }` |
| `NotFoundError` | `not_found` | 404 | false | Provider responded 404 for a resource we expected to exist | Treat as terminal. If the resource *should* exist (idempotency check), this is a real bug. | `{ "name":"NotFoundError", "statusCode":404 }` |
| `NetworkError` | `network` | 503 | true | `ECONNREFUSED`, `ENOTFOUND`, transient DNS/TCP failure | Wrap call in `retryWithBackoff`. `isRetryableError` returns `true`. | `{ "name":"NetworkError", "retryable":true, "statusCode":503 }` |
| `TimeoutError` | `timeout` | 504 | true | Provider exceeded the request timeout (see `code/utils/timeout.ts`) | Retry with backoff. If retries exhaust, propagate. | `{ "name":"TimeoutError", "statusCode":504 }` |
| `RateLimitError` | `rate_limit` | 429 | true | Provider returned 429 | Retry with backoff and jitter (`retryWithJitter`). Respect any `Retry-After` header in the retry policy. | `{ "name":"RateLimitError", "statusCode":429 }` |
| `ServerError` | `server_error` | 500 | true | Provider 5xx | Retry with backoff. After exhaustion, surface to the caller. | `{ "name":"ServerError", "statusCode":500 }` |
| `OperationTimeoutError` | — | — | — | Internal `withTimeout` helper in `code/utils/timeout.ts` | Treat as a `TimeoutError` for upstream consumers. | `OperationTimeoutError: Operation timed out after 30000ms` |

`categorizeError(error)` and `isRetryableError(error)` in `error-types.ts` map raw provider errors (by `statusCode` or `code`) to the categories above — use them whenever you receive an `unknown` shape.

## Propagation across the provider boundary

The flow is always **provider error → collection-module error → Root-level error**.

1. **Raw provider error** — whatever the SDK or HTTP layer throws (`StripeAPIError`, `axios.AxiosError`, etc.). Never let this leak past the client/service boundary.
2. **Service layer maps to `EnhancedModuleError`** — at the boundary, classify by HTTP status / network code and throw the closest subclass. Preserve the original message in `context` for logs.
3. **Lifecycle hook surfaces it** — a hook either returns successfully or throws. A thrown `EnhancedModuleError` with `retryable: true` signals to Root that another attempt is safe; a non-retryable error signals "give up".

### Worked example (Stripe)

```typescript
// code/services/stripe.service.ts
import { retryWithBackoff } from '../utils/retry';
import {
  EnhancedModuleError,
  NetworkError,
  RateLimitError,
  ServerError,
  ValidationError,
  categorizeError,
  isRetryableError,
  ErrorCategory,
} from '../utils/error-types';

async createCustomer(params: CreateCustomerParams): Promise<ProviderCustomer> {
  this.logService.info('Creating Stripe customer', 'StripeService', params);

  try {
    return await retryWithBackoff(
      () => this.stripeClient.sdk.customers.create({
        email: params.email,
        name: params.name ?? undefined,
        metadata: params.metadata,
      }),
      { shouldRetry: (err) => isRetryableError(err) },
    );
  } catch (err: any) {
    if (err instanceof EnhancedModuleError) throw err;

    const category = categorizeError(err);
    const ctx = { providerMessage: err?.message, providerCode: err?.code };

    switch (category) {
      case ErrorCategory.VALIDATION:   throw new ValidationError('Invalid customer params', ctx);
      case ErrorCategory.RATE_LIMIT:   throw new RateLimitError('Stripe rate limit hit', ctx);
      case ErrorCategory.SERVER_ERROR: throw new ServerError('Stripe server error', ctx);
      case ErrorCategory.NETWORK:      throw new NetworkError('Stripe unreachable', ctx);
      default: throw new EnhancedModuleError('Stripe createCustomer failed', category, false, undefined, ctx);
    }
  }
}
```

The lifecycle hook (`afterPolicyIssued`) calls this without try/catch — it lets the typed error propagate so Root can apply its retry policy.

## Idempotency and retry semantics

### `retryWithBackoff`

Lives in `code/utils/retry.ts`. Defaults: `maxRetries: 3`, `initialDelay: 1000ms`, `backoffMultiplier: 2`, `maxDelay: 30000ms`. Pass `shouldRetry` to scope to retryable categories — usually `isRetryableError` from `error-types.ts`.

Variants:
- `retryWithJitter` — same, plus 0–50% jitter. Use for rate-limit-sensitive endpoints.
- `retryForErrors(op, codes, opts)` — retry only when `error.code` (or stringified `statusCode`) is in the allow-list.
- `retryForNetworkErrors(op, opts)` — pre-configured for network + 5xx + 429.

### Idempotency keys

Every external write should be idempotent under retry. Pattern:

- Use the provider's idempotency mechanism when available (Stripe `Idempotency-Key` header, GoCardless `Idempotency-Key`).
- Derive the key deterministically from the Root entity ID (`payment.payment_id`, `policy.policy_id`). Never `Date.now()` or `uuid()` at call time — both break retry safety.
- Before creating a provider-side record, read `policy.app_data` for an existing ID. If present, return that.

```typescript
await this.stripeClient.sdk.customers.create(
  { email, name, metadata: { policy_id: policy.policy_id } },
  { idempotencyKey: `customer:${policy.policy_id}` },
);
```

### Retry budget

`retryWithBackoff` defaults to 3 retries (4 total attempts). For lifecycle hooks Root may *also* retry, so the effective attempt count can be higher than what you configure here. Don't raise `maxRetries` above 5 without good reason — long retry chains worsen latency and obscure real failures.

TODO(human): document the Root-side retry policy and how it composes with `retryWithBackoff` defaults if/when that is published.

## Related

- `code/utils/error.ts` — `ModuleError`
- `code/utils/error-types.ts` — `EnhancedModuleError` and subclasses, `categorizeError`, `isRetryableError`, `formatErrorForLogging`
- `code/utils/retry.ts` — `retryWithBackoff`, `retryWithJitter`, `retryForErrors`, `retryForNetworkErrors`
- `code/utils/timeout.ts` — `withTimeout`, `OperationTimeoutError`
- `07-LIFECYCLE-HOOKS.md` — How thrown errors propagate to Root

## You've understood this if…

- You can name which error subclasses are retryable and which are not.
- You can describe the error-propagation flow from provider SDK to Root in three steps.
- You can write an idempotency key for a Stripe customer create from memory.
