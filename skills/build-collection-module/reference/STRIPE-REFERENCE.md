# Stripe Reference Implementation

> The working example. Read this before implementing any new provider — it shows every pattern in use.

## Table of Contents

| Section | What you'll find |
|---|---|
| [Client](#client) | SDK init, webhook verification |
| [Service](#service) | Customer, payment intent, payment method, subscription |
| [Adapter](#adapter) | Invoice → Root payment, customer → app_data |
| [Events](#events) | Webhook event constants |
| [Lifecycle Hooks](#lifecycle-hooks) | afterPolicyIssued, afterPolicyPaymentMethodAssigned, afterPaymentCreated |
| [Webhook Routing](#webhook-routing) | Signature verify + switch statement |
| [Config Fields](#config-fields) | env.ts keys used by Stripe |
| [Status Mapping](#status-mapping) | Stripe statuses → Root statuses |

---

## Client

**File:** `code/clients/stripe-client.ts`

```typescript
import Stripe from 'stripe';
import { getConfigService } from '../services/config-instance';
import { PaymentProviderClient, WebhookRequest } from '../interfaces/provider.interfaces';

export default class StripeClient implements PaymentProviderClient {
  public readonly sdk: Stripe;

  constructor() {
    const config = getConfigService();
    this.sdk = new Stripe(config.get('providerSecretKey'), {
      apiVersion: '2023-10-16',
    });
  }

  verifyWebhookSignature(request: WebhookRequest, secret: string): boolean {
    try {
      this.sdk.webhooks.constructEvent(request.body, request.headers['stripe-signature'], secret);
      return true;
    } catch {
      return false;
    }
  }
}
```

Key points:
- `providerSecretKey` resolves to `sk_test_xxx` (sandbox) or `sk_live_xxx` (production) via `ConfigurationService`
- `verifyWebhookSignature` uses `stripe.webhooks.constructEvent` — throws on invalid, so wrap in try/catch
- Expose the raw SDK as `sdk` — services call `stripeClient.sdk.customers.create(...)` directly

---

## Service

**File:** `code/services/stripe.service.ts`

### Create customer

```typescript
async createCustomer(params: CreateCustomerParams): Promise<ProviderCustomer> {
  this.logService.info('Creating customer', 'StripeService', params);
  try {
    const customer = await retryWithBackoff(() =>
      this.providerClient.sdk.customers.create({
        email: params.email,
        name: params.name,
        metadata: params.metadata,
      })
    );
    return {
      id: customer.id,
      email: customer.email,
      name: customer.name,
      metadata: customer.metadata,
    };
  } catch (err) {
    this.logService.error('Failed to create customer', 'StripeService', err);
    throw new ModuleError('Failed to create customer', { cause: err });
  }
}
```

### Create payment intent

```typescript
async createPaymentIntent(params: CreatePaymentIntentParams): Promise<ProviderPaymentIntent> {
  this.logService.info('Creating payment intent', 'StripeService', params);
  const intent = await retryWithBackoff(() =>
    this.providerClient.sdk.paymentIntents.create({
      amount: params.amount,
      currency: params.currency,
      customer: params.customerId,
      payment_method: params.paymentMethodId,
      confirm: true,
      off_session: true,
      metadata: { root_payment_id: params.metadata?.rootPaymentId },
    })
  );
  return { id: intent.id, status: intent.status, amount: intent.amount, currency: intent.currency };
}
```

### Attach payment method

```typescript
async attachPaymentMethod(params: AttachPaymentMethodParams): Promise<ProviderPaymentMethod> {
  const pm = await this.providerClient.sdk.paymentMethods.attach(params.paymentMethodId, {
    customer: params.customerId,
  });
  await this.providerClient.sdk.customers.update(params.customerId, {
    invoice_settings: { default_payment_method: params.paymentMethodId },
  });
  return { id: pm.id, type: pm.type };
}
```

### Cancel subscription

```typescript
async cancelSubscription(subscriptionId: string): Promise<ProviderSubscription> {
  const sub = await this.providerClient.sdk.subscriptions.cancel(subscriptionId);
  return { id: sub.id, status: sub.status };
}
```

---

## Adapter

**File:** `code/adapters/stripe-to-root-adapter.ts`

### Invoice → Root payment update

```typescript
convertPaymentToRootUpdate(invoice: Stripe.Invoice, params: ConvertPaymentParams) {
  return {
    status: params.status,
    failure_reason: params.failureReason ?? invoice.last_finalization_error?.message,
    failure_action: FailureAction.BlockRetry,
  };
}
```

Used in: `invoice.paid` controller (pass `PaymentStatus.Successful`) and `invoice.payment_failed` controller (pass `PaymentStatus.Failed` + failure reason).

### Customer → app_data

```typescript
convertCustomerToAppData(customer: Stripe.Customer): Record<string, any> {
  return {
    stripe_customer_id: customer.id,
    stripe_email: customer.email,
    stripe_default_payment_method: customer.invoice_settings?.default_payment_method,
    stripe_created_at: new Date(customer.created * 1000).toISOString(),
  };
}
```

Used in: `afterPolicyIssued` and `afterPolicyPaymentMethodAssigned` to store Stripe customer data on the Root policy.

---

## Events

**File:** `code/interfaces/stripe-events.ts`

```typescript
export const STRIPE_EVENTS = {
  INVOICE_PAID:                    'invoice.paid',
  INVOICE_PAYMENT_FAILED:          'invoice.payment_failed',
  INVOICE_CREATED:                 'invoice.created',
  PAYMENT_INTENT_SUCCEEDED:        'payment_intent.succeeded',
  PAYMENT_INTENT_FAILED:           'payment_intent.payment_failed',
  CHARGE_REFUNDED:                 'charge.refunded',
  CHARGE_DISPUTE_CREATED:          'charge.dispute.created',
  SUBSCRIPTION_SCHEDULE_UPDATED:   'subscription_schedule.updated',
} as const;
```

---

## Lifecycle Hooks

**File:** `code/lifecycle-hooks/`

### afterPolicyIssued

```typescript
export async function afterPolicyIssued({ policy }): Promise<void> {
  const container = getContainer();
  const providerService = container.resolve<StripeService>(ServiceToken.PROVIDER_SERVICE);
  const rootClient = container.resolve(ServiceToken.ROOT_CLIENT);
  const adapter = new StripeToRootAdapter();

  const customer = await providerService.createCustomer({
    email: policy.policyholder.email,
    name: `${policy.policyholder.first_name} ${policy.policyholder.last_name}`,
    metadata: { root_policy_id: policy.policy_id },
  });

  await rootClient.SDK.updatePolicy({
    policyId: policy.policy_id,
    body: { app_data: adapter.convertCustomerToAppData(customer) },
  });
}
```

### afterPolicyPaymentMethodAssigned

```typescript
export async function afterPolicyPaymentMethodAssigned({ policy }): Promise<void> {
  const container = getContainer();
  const providerService = container.resolve<StripeService>(ServiceToken.PROVIDER_SERVICE);
  const rootClient = container.resolve(ServiceToken.ROOT_CLIENT);

  const paymentMethod = await rootClient.SDK.getPolicyPaymentMethod({ policyId: policy.policy_id });
  const stripePaymentMethodId = paymentMethod.module.payment_method;
  const customerId = policy.app_data?.stripe_customer_id;

  await providerService.attachPaymentMethod({ paymentMethodId: stripePaymentMethodId, customerId });
}
```

### afterPaymentCreated

```typescript
export async function afterPaymentCreated({ policy, payment }): Promise<void> {
  const container = getContainer();
  const providerService = container.resolve<StripeService>(ServiceToken.PROVIDER_SERVICE);

  await providerService.createPaymentIntent({
    amount: payment.amount,
    currency: policy.currency ?? 'ZAR',
    customerId: policy.app_data.stripe_customer_id,
    paymentMethodId: policy.app_data.stripe_payment_method_id,
    metadata: { rootPaymentId: payment.payment_id, rootPolicyId: policy.policy_id },
  });
}
```

---

## Webhook Routing

**File:** `code/webhook-hooks.ts`

```typescript
export async function processWebhookRequest(event: any): Promise<any> {
  const container = getContainer();
  const config = container.resolve<ConfigurationService>(ServiceToken.CONFIG_SERVICE);
  const providerClient = container.resolve<StripeClient>(ServiceToken.PROVIDER_CLIENT);
  const logService = container.resolve<LogService>(ServiceToken.LOG_SERVICE);

  // 1. Verify signature
  const isValid = providerClient.verifyWebhookSignature(
    { body: event.body, headers: event.headers },
    config.get('providerWebhookSigningSecret'),
  );
  if (!isValid) {
    logService.warn('Webhook signature invalid', 'WebhookHandler');
    return { statusCode: 400, body: JSON.stringify({ error: 'Invalid signature' }) };
  }

  // 2. Parse event
  const parsed = JSON.parse(event.body);
  logService.info(`Webhook received: ${parsed.type}`, 'WebhookHandler', { id: parsed.id });

  // 3. Route
  switch (parsed.type) {
    case STRIPE_EVENTS.INVOICE_PAID: {
      const ctrl = container.resolve(ServiceToken.INVOICE_PAID_CONTROLLER);
      await ctrl.handle(parsed.data.object);
      break;
    }
    case STRIPE_EVENTS.INVOICE_PAYMENT_FAILED: {
      const ctrl = container.resolve(ServiceToken.INVOICE_PAYMENT_FAILED_CONTROLLER);
      await ctrl.handle(parsed.data.object);
      break;
    }
    default:
      logService.info(`Unhandled event type: ${parsed.type}`, 'WebhookHandler');
  }

  return { statusCode: 200, body: JSON.stringify({ received: true }) };
}
```

---

## Config Fields

Fields used by the Stripe implementation in `code/env.ts` / `code/env.sample.ts`:

| Config key (via `config.get(...)`) | env.ts export | Example value |
|---|---|---|
| `providerSecretKey` | `PROVIDER_SECRET_KEY_LIVE` / `_TEST` | `sk_live_...` / `sk_test_...` |
| `providerPublishableKey` | `PROVIDER_PUBLISHABLE_KEY_LIVE` / `_TEST` | `pk_live_...` / `pk_test_...` |
| `providerWebhookSigningSecret` | `PROVIDER_WEBHOOK_SIGNING_SECRET_LIVE` / `_TEST` | `whsec_...` |
| `providerProductId` | `PROVIDER_PRODUCT_ID_LIVE` / `_TEST` | `prod_...` |
| `rootCollectionModuleKey` | `ROOT_COLLECTION_MODULE_KEY` | `cm_stripe` |
| `rootApiKey` | `ROOT_API_KEY_LIVE` / `ROOT_API_KEY_SANDBOX` | `production_...` |
| `rootBaseUrl` | `ROOT_BASE_URL_LIVE` / `ROOT_BASE_URL_SANDBOX` | `https://api.rootplatform.com/v1/insurance` |
| `environment` | `NODE_ENV` | `production` or `development` |

`ConfigurationService.get()` resolves live vs test/sandbox based on the `environment` value automatically.

---

## Status Mapping

| Stripe invoice status | Root `PaymentStatus` |
|---|---|
| `paid` | `PaymentStatus.Successful` |
| `open` | `PaymentStatus.Pending` |
| `void` | `PaymentStatus.Cancelled` |
| `uncollectible` | `PaymentStatus.Failed` |

| Stripe payment intent status | Root `PaymentStatus` |
|---|---|
| `succeeded` | `PaymentStatus.Successful` |
| `processing` | `PaymentStatus.Pending` |
| `requires_payment_method` | `PaymentStatus.Failed` |
| `canceled` | `PaymentStatus.Cancelled` |

---

## Related Docs

- [03-PROVIDER-INTERFACE.md](./03-PROVIDER-INTERFACE.md) — contracts you must implement for a new provider
- [13-BUILD-FROM-SPEC.md](./13-BUILD-FROM-SPEC.md) — end-to-end spec-to-implementation workflow

## You've understood this if…

- You can map every method on `StripeService` to a `PaymentProviderService` interface method.
- You can name which file in Stripe's implementation handles webhook signature verification.
- You can identify which Stripe events the reference subscribes to and which it ignores.
