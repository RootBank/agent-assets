# Provider Patterns — SDK vs HTTP

> Side-by-side reference for how the same provider concerns are implemented when the provider ships a TypeScript SDK (Stripe-style) vs when only a REST API is available (use `BaseHttpClient`).

When integrating a new provider, prefer the SDK path if a maintained TypeScript SDK exists. Use the HTTP path otherwise. See `05-CLIENTS.md` for the decision table.

---

## Client construction

**SDK (Stripe)** — wrap the SDK and expose it via `.sdk`:

```typescript
// code/clients/stripe-client.ts
import Stripe from 'stripe';
import { getConfigService } from '../services/config-instance';
import type { PaymentProviderClient } from '../interfaces/provider.interfaces';

export default class StripeClient implements PaymentProviderClient {
  public readonly sdk: Stripe;

  constructor() {
    const config = getConfigService();
    this.sdk = new Stripe(config.get('providerSecretKey'), {
      apiVersion: '2024-06-20',
      maxNetworkRetries: 0,
    });
  }

  verifyWebhookSignature(request: { body: string; headers: Record<string, string> }, secret: string): boolean {
    try {
      this.sdk.webhooks.constructEvent(request.body, request.headers['stripe-signature'], secret);
      return true;
    } catch {
      return false;
    }
  }
}
```

**HTTP (BaseHttpClient)** — instantiate the shared client:

```typescript
// code/clients/payfast-client.ts
import { BaseHttpClient } from './base-http-client';
import { getConfigService } from '../services/config-instance';
import type { PaymentProviderClient } from '../interfaces/provider.interfaces';

export default class PayFastClient implements PaymentProviderClient {
  public readonly sdk: BaseHttpClient;

  constructor() {
    const config = getConfigService();
    this.sdk = new BaseHttpClient({
      baseUrl: 'https://api.payfast.co.za',
      apiKey: config.get('providerSecretKey'),
      timeout: 30_000,
    });
  }

  verifyWebhookSignature(request: { body: string; headers: Record<string, string> }, secret: string): boolean {
    // See "Webhook verification" below.
    return false;
  }
}
```

---

## Auth

**SDK** — the SDK constructor accepts the secret. No further work.

**HTTP** — `BaseHttpClient` sets `Authorization: Bearer <apiKey>` on every request automatically. Override `defaultHeaders` if the provider uses a different scheme (e.g. `X-API-Key`):

```typescript
this.sdk = new BaseHttpClient({
  baseUrl: 'https://api.example.com',
  apiKey: config.get('providerSecretKey'),
  defaultHeaders: { 'X-API-Key': config.get('providerSecretKey') },
});
```

---

## Request signing

**SDK** — handled internally. Nothing to do.

**HTTP** — sign per-request when the provider requires it. Pass the signature in `headers`:

```typescript
import { createHmac } from 'crypto';

async createCustomer(params: CreateCustomerParams): Promise<ProviderCustomer> {
  const body = JSON.stringify(params);
  const signature = createHmac('sha256', this.signingSecret).update(body).digest('hex');
  return this.sdk.post<ProviderCustomer>('/customers', params, { 'X-Signature': signature });
}
```

---

## Pagination

**SDK** — most SDKs expose an async iterator:

```typescript
for await (const charge of this.stripeClient.sdk.charges.list({ limit: 100 })) {
  // process
}
```

**HTTP** — implement explicit pagination using the provider's cursor or page-number scheme:

```typescript
async listCharges(): Promise<Charge[]> {
  const all: Charge[] = [];
  let cursor: string | undefined;
  do {
    const page = await this.sdk.get<{ data: Charge[]; next_cursor?: string }>(
      `/charges?limit=100${cursor ? `&cursor=${cursor}` : ''}`,
    );
    all.push(...page.data);
    cursor = page.next_cursor;
  } while (cursor);
  return all;
}
```

---

## Webhook verification

**SDK** — delegate to the SDK helper (the example under "Client construction" already shows this for Stripe).

**HTTP** — verify manually using the provider's documented signing scheme. Reject on any failure; never default to `true`:

```typescript
import { createHmac, timingSafeEqual } from 'crypto';

verifyWebhookSignature(request: { body: string; headers: Record<string, string> }, secret: string): boolean {
  const provided = request.headers['x-webhook-signature'];
  if (!provided) return false;
  const expected = createHmac('sha256', secret).update(request.body).digest('hex');
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}
```

If the provider's signature scheme is undocumented or ambiguous, **stop and ask**. Do not invent verification logic. See `16-WHEN-TO-DEVIATE.md`.

---

## Error mapping

**SDK** — the SDK throws typed errors (e.g. `Stripe.errors.StripeAPIError`). Map at the service boundary:

```typescript
try {
  return await retryWithBackoff(() => this.stripeClient.sdk.customers.create(params));
} catch (err: any) {
  if (err.type === 'StripeRateLimitError') throw new RateLimitError('Stripe rate limit', { providerCode: err.code });
  if (err.type === 'StripeInvalidRequestError') throw new ValidationError('Bad request', { providerCode: err.code });
  throw new EnhancedModuleError('Stripe call failed', categorizeError(err), false, undefined, { providerMessage: err.message });
}
```

**HTTP** — `BaseHttpClient` throws plain `Error` with the HTTP status in the message. Use `categorizeError` to classify by `statusCode`:

```typescript
try {
  return await this.sdk.post<ProviderCustomer>('/customers', params);
} catch (err: any) {
  const status = Number(/HTTP \w+ \S+ failed: (\d+)/.exec(err.message)?.[1] ?? 0);
  const wrapped = Object.assign(err, { statusCode: status });
  throw new EnhancedModuleError(`PayFast createCustomer failed`, categorizeError(wrapped), isRetryableError(wrapped), status, { providerMessage: err.message });
}
```

See `12-ERROR-HANDLING.md` for the full propagation pattern.

---

## Retry / backoff

**SDK** — disable the SDK's own retries (`maxNetworkRetries: 0` for Stripe) and let `retryWithBackoff` own the policy so behaviour is uniform across providers.

**HTTP** — `BaseHttpClient.request` already wraps every call in `retryWithBackoff` with a sensible default `shouldRetry` (5xx + `ETIMEDOUT` + `ECONNRESET`). Avoid double-wrapping at the service layer; instead pass `{ maxRetries }` to override if needed.

```typescript
// Service-layer retry override (HTTP path)
return retryWithBackoff(
  () => this.sdk.post('/charges', body),
  { maxRetries: 5, shouldRetry: (err) => isRetryableError(err) },
);
```

---

## Related

- `05-CLIENTS.md` — choosing SDK vs HTTP, full client patterns
- `08-WEBHOOKS.md` — signature verification, routing
- `12-ERROR-HANDLING.md` — error categorisation and retry
- `STRIPE-REFERENCE.md` — the SDK-based reference implementation

## You've understood this if…

- You can decide SDK vs HTTP for a new provider in under a minute, using the decision table in `05-CLIENTS.md`.
- You can name two reasons we disable SDK-level retries.
- You can explain why `verifyWebhookSignature` must never `return true` on a missing header.
