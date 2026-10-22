# Provider Interface -- Implementing a New Payment Provider

> The provider abstraction layer: interfaces, contracts, and a step-by-step guide to adding a new provider.

## Overview

The collection module defines three interfaces in `code/interfaces/provider.interfaces.ts` that any payment provider must implement to integrate with Root Platform:

1. **PaymentProviderClient** -- SDK or API client wrapper.
2. **PaymentProviderService** -- Business logic for provider operations.
3. **ProviderToRootAdapter** -- Data transformation between provider and Root formats.

Stripe is the reference implementation. All three interfaces are designed to be provider-agnostic.

## Key Concepts

### PaymentProviderClient

Defined in `code/interfaces/provider.interfaces.ts`. Wraps the provider SDK or HTTP client.

```typescript
export interface PaymentProviderClient {
  /** The underlying SDK instance or API client */
  readonly sdk: any;

  /**
   * Verify a webhook request's authenticity
   */
  verifyWebhookSignature(request: WebhookRequest, secret: string): boolean;
}
```

The Stripe reference implementation is at `code/clients/stripe-client.ts`. It exposes the Stripe SDK as `sdk`.

### PaymentProviderService

Business logic layer that wraps the client with logging, error handling, and domain methods.

```typescript
export interface PaymentProviderService {
  createCustomer(params: CreateCustomerParams): Promise<ProviderCustomer>;
  getCustomer(customerId: string): Promise<ProviderCustomer>;
  updateCustomer(customerId: string, params: UpdateCustomerParams): Promise<ProviderCustomer>;
  createPaymentIntent(params: CreatePaymentIntentParams): Promise<ProviderPaymentIntent>;
  getPaymentMethod(paymentMethodId: string): Promise<ProviderPaymentMethod>;
  attachPaymentMethod(params: AttachPaymentMethodParams): Promise<ProviderPaymentMethod>;
  cancelSubscription(subscriptionId: string): Promise<ProviderSubscription>;
}
```

The Stripe reference implementation is at `code/services/stripe.service.ts`.

### ProviderToRootAdapter

Pure data transformation. Converts provider-specific data structures to Root Platform format. No API calls allowed.

```typescript
export interface ProviderToRootAdapter {
  convertPaymentToRootUpdate(
    providerPayment: any,
    params: ConvertPaymentParams
  ): RootPaymentUpdate;

  convertCustomerToAppData(providerCustomer: any): Record<string, any>;
}
```

The Stripe reference implementation is at `code/adapters/stripe-to-root-adapter.ts`.

### Common Data Types

The interfaces use normalized types that abstract away provider-specific shapes:

```typescript
export interface ProviderCustomer {
  id: string;
  email: string | null;
  name: string | null;
  metadata?: Record<string, string>;
}

export interface ProviderPaymentIntent {
  id: string;
  status: string;
  amount: number;
  currency: string;
}

export interface ProviderPaymentMethod {
  id: string;
  type: string;
}

export interface ProviderSubscription {
  id: string;
  status: string;
}
```

## Patterns

### Step-by-Step: Implementing a New Provider

This example uses "PayFast" as a hypothetical new provider.

**Step 1: Create the client** at `code/clients/payfast-client.ts`:

```typescript
// code/clients/payfast-client.ts
import { BaseHttpClient } from './base-http-client';
import { getConfigService } from '../services/config-instance';

export default class PayFastClient {
  public sdk: BaseHttpClient;

  constructor() {
    const config = getConfigService();
    this.sdk = new BaseHttpClient({
      baseUrl: 'https://api.payfast.co.za',
      apiKey: config.get('providerSecretKey'),
    });
  }

  verifyWebhookSignature(request: any, secret: string): boolean {
    // Implement PayFast signature verification
    return true;
  }
}
```

**Step 2: Create the service** at `code/services/payfast.service.ts`:

```typescript
// code/services/payfast.service.ts
import { LogService } from './log.service';
import PayFastClient from '../clients/payfast-client';

export class PayFastService {
  constructor(
    private readonly logService: LogService,
    private readonly payfastClient: PayFastClient
  ) {}

  async createCustomer(params: { email: string; name?: string }) {
    this.logService.info('Creating PayFast customer', 'PayFastService', params);
    return this.payfastClient.sdk.post('/customers', params);
  }

  // Implement remaining PaymentProviderService methods...
}
```

**Step 3: Create the adapter** at `code/adapters/payfast-to-root-adapter.ts`:

```typescript
// code/adapters/payfast-to-root-adapter.ts
export default class PayFastToRootAdapter {
  convertPaymentToRootUpdate(payfastPayment: any, params: any) {
    return {
      status: params.status,
      amount: payfastPayment.amount_gross,
      currency: 'ZAR',
      externalId: payfastPayment.pf_payment_id,
    };
  }

  convertCustomerToAppData(payfastCustomer: any) {
    return {
      payfast_customer_id: payfastCustomer.id,
      payfast_email: payfastCustomer.email,
    };
  }
}
```

**Step 4: Register in the DI container** at `code/core/container.setup.ts`:

```typescript
// Replace the Stripe registrations with PayFast

container.register(
  ServiceToken.PROVIDER_CLIENT,
  () => {
    const PayFastClient = require('../clients/payfast-client').default;
    return new PayFastClient();
  },
  ServiceLifetime.SINGLETON
);

container.register(
  ServiceToken.PROVIDER_SERVICE,
  (c) => {
    const logService = c.resolve<LogService>(ServiceToken.LOG_SERVICE);
    const payfastClient = c.resolve(ServiceToken.PROVIDER_CLIENT);
    return new (require('../services/payfast.service').PayFastService)(
      logService,
      payfastClient
    );
  },
  ServiceLifetime.SINGLETON
);
```

**Step 5: Update webhook-hooks.ts** to verify and route provider-specific events.

**Step 6: Update env.sample.ts** with provider-specific placeholder values.

## Service implementation patterns

Services contain business logic. Each provider ships with a `{Provider}Service` class registered under `ServiceToken.PROVIDER_SERVICE`. The shared infrastructure services (`RootService`, `RenderService`, `ConfigurationService`, `LogService`) are always present.

### Conventions

- Constructor-injected via DI — never instantiate services directly.
- Use `LogService` only — no `console.log`.
- Wrap external calls in `retryWithBackoff` from `utils/`.
- Throw `ModuleError` (or a subclass from `utils/error-types.ts`) for business errors; see `12-ERROR-HANDLING.md`.
- Keep services focused — one provider, one service class.
- Map provider-specific errors to the closest `EnhancedModuleError` subclass at the service boundary.

### Pattern

```typescript
import { LogService } from './log.service';
import { ModuleError } from '../utils/error';
import { retryWithBackoff } from '../utils/retry';
import type { PaymentProviderService, CreateCustomerParams, ProviderCustomer } from '../interfaces/provider.interfaces';

export class {Provider}Service implements PaymentProviderService {
  constructor(
    private readonly logService: LogService,
    private readonly providerClient: {Provider}Client,
  ) {}

  async createCustomer(params: CreateCustomerParams): Promise<ProviderCustomer> {
    this.logService.info('Creating customer', '{Provider}Service', params);
    try {
      return await retryWithBackoff(() => this.providerClient.sdk.customers.create(params));
    } catch (err: any) {
      throw err instanceof ModuleError
        ? err
        : new ModuleError('Failed to create customer', { cause: err?.message });
    }
  }
  // ... other methods
}
```

Register in `container.setup.ts` under `ServiceToken.PROVIDER_SERVICE`. The DI token is provider-agnostic — only the registration changes when swapping providers.

## Common Tasks

### Check which provider is registered

```typescript
const container = getContainer();
const client = container.resolve(ServiceToken.PROVIDER_CLIENT);
console.log(client.constructor.name); // 'StripeClient' or 'PayFastClient'
```

### Use BaseHttpClient for providers without SDKs

For providers that lack a TypeScript SDK, use `code/clients/base-http-client.ts` which provides typed HTTP methods with retry logic and timeouts.

### Provider config field mapping

| Generic Config Field | Stripe Example | PayFast Example |
|---|---|---|
| `providerSecretKey` | `sk_live_xxx` | `merchant_key_xxx` |
| `providerPublishableKey` | `pk_live_xxx` | (not applicable) |
| `providerWebhookSigningSecret` | `whsec_xxx` | `passphrase_xxx` |
| `providerProductId` | `prod_xxx` | (not applicable) |

## Related Docs

- [02-ARCHITECTURE.md](./02-ARCHITECTURE.md) -- DI container and registration
- [STRIPE-REFERENCE.md](./STRIPE-REFERENCE.md) -- Working reference for all patterns
- [13-BUILD-FROM-SPEC.md](./13-BUILD-FROM-SPEC.md) -- End-to-end spec-to-implementation workflow

## You've understood this if…

- You can name the three provider interfaces and which file each lives in.
- You can explain why services are wrapped in `retryWithBackoff` and what `ModuleError` adds over raw `Error`.
- You can describe Step 4 (DI registration) without re-reading it.
