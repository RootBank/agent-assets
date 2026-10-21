# Clients

Clients wrap the payment provider API. They implement `PaymentProviderClient` and are registered as `ServiceToken.PROVIDER_CLIENT`. Two patterns exist — choose based on whether the provider ships an SDK.

## Decision: SDK vs HTTP

| Use SDK client when... | Use HTTP client when... |
|---|---|
| Provider has an official npm TypeScript SDK | Provider is REST-only (no SDK) |
| SDK handles auth, retries, type safety | You need full control over request shape |
| Examples: Stripe, GoCardless Node | Examples: PayFast, Peach Payments |

---

## Pattern 1 — SDK Client (preferred)

```typescript
// code/clients/myprovider-client.ts
import { getConfigService } from '../services/config-instance';
import { PaymentProviderClient, WebhookRequest } from '../interfaces/provider.interfaces';
import MyProviderSDK from 'myprovider-nodejs'; // npm install myprovider-nodejs

/**
 * MyProviderClient — wraps the MyProvider SDK.
 * Registered as ServiceToken.PROVIDER_CLIENT in container.setup.ts.
 */
export default class MyProviderClient implements PaymentProviderClient {
  public readonly sdk: MyProviderSDK;

  constructor() {
    const config = getConfigService();
    this.sdk = new MyProviderSDK(config.get('providerSecretKey'));
  }

  verifyWebhookSignature(request: WebhookRequest, secret: string): boolean {
    // Use the SDK's built-in webhook verification
    try {
      this.sdk.webhooks.constructEvent(
        request.body,
        request.headers['x-myprovider-signature'],
        secret,
      );
      return true;
    } catch {
      return false;
    }
  }
}
```

---

## Pattern 2 — HTTP Client (no SDK)

```typescript
// code/clients/myprovider-client.ts
import { BaseHttpClient } from './base-http-client';
import { getConfigService } from '../services/config-instance';
import { PaymentProviderClient, WebhookRequest } from '../interfaces/provider.interfaces';
import * as crypto from 'crypto';

/**
 * MyProviderClient — wraps the MyProvider REST API.
 * Registered as ServiceToken.PROVIDER_CLIENT in container.setup.ts.
 */
export default class MyProviderClient implements PaymentProviderClient {
  public readonly sdk: BaseHttpClient;

  constructor() {
    const config = getConfigService();
    this.sdk = new BaseHttpClient({
      baseUrl: 'https://api.myprovider.com/v1',
      apiKey: config.get('providerSecretKey'),
      headers: {
        Authorization: `Bearer ${config.get('providerSecretKey')}`,
        'Content-Type': 'application/json',
      },
    });
  }

  verifyWebhookSignature(request: WebhookRequest, secret: string): boolean {
    const sig = request.headers['x-myprovider-signature'];
    if (!sig) return false;

    const expected = crypto
      .createHmac('sha256', secret)
      .update(request.body)
      .digest('hex');

    try {
      return crypto.timingSafeEqual(
        Buffer.from(sig, 'hex') as unknown as Uint8Array,
        Buffer.from(expected, 'hex') as unknown as Uint8Array,
      );
    } catch {
      return false;
    }
  }
}
```

Then use in the service:
```typescript
// In MyProviderService:
const payment = await this.providerClient.sdk.post<PaymentResponse>('/payments', {
  amount: params.amount,
  currency: params.currency,
});
```

---

## Registration in container.setup.ts

```typescript
container.register(
  ServiceToken.PROVIDER_CLIENT,
  () => new (require('../clients/myprovider-client').default)(),
  ServiceLifetime.SINGLETON
);
```

> The scaffold script prints this exact block to your terminal — copy and paste it.

---

## Related

- `code/clients/base-http-client.ts` — BaseHttpClient source (GET, POST, PUT, DELETE methods)
- `code/interfaces/provider.interfaces.ts` — `PaymentProviderClient` contract
- `docs/STRIPE-REFERENCE.md` — Full SDK client implementation
- `docs/08-WEBHOOKS.md` — Signature verification patterns

## You've understood this if…

- You can decide SDK vs HTTP for a new provider using the decision table.
- You can name two responsibilities `BaseHttpClient` already handles for you.
- You know where webhook signature verification lives and why it's on the client, not the service.
