# Webhooks

> See `docs/STRIPE-REFERENCE.md` for a complete working example.

## Overview

`code/webhook-hooks.ts` exports `processWebhookRequest`, called by Root Platform when your provider sends a webhook.

## Implementation steps

1. **Verify signature** — use your provider client to verify the webhook payload.
2. **Parse event** — extract event type and payload.
3. **Route event** — match event type in a `switch`, resolve the correct controller from DI.
4. **Return response** — `{ response: { status: 200, headers: {...}, body: '{"received":true}' } }`.

## Signature verification

```typescript
const providerClient = container.resolve(ServiceToken.PROVIDER_CLIENT);
const isValid = providerClient.verifyWebhookSignature(
  { body: request.request.body, headers: request.request.headers },
  config.get('providerWebhookSigningSecret'),
);
if (!isValid) return { response: { status: 403, ... } };
```

## Security

- Always verify the signature before processing.
- Use `crypto.timingSafeEqual` for HMAC comparisons.
- Store signing secrets in `providerWebhookSigningSecret` (live) and the test equivalent.

## WebhookParser pattern

Different providers use different webhook payload structures:

| Provider | Structure |
|---|---|
| Stripe | Flat: `{ type, data: { object } }` |
| Adyen | Batched: `{ notificationItems: [{ NotificationRequestItem: { eventCode, ... } }] }` |
| GoCardless | Wrapped: `{ events: [{ resource_type, action, links }] }` |
| PayFast | Flat form-encoded: `payment_id=123&status=COMPLETE` |

To handle this variation, implement the `WebhookParser` interface (defined in `provider.interfaces.ts`):

```typescript
const parser = container.resolve<WebhookParser>(ServiceToken.WEBHOOK_PARSER);
const events: ParsedWebhookEvent[] = parser.verifyAndParse(headers, body, secret);

for (const event of events) {
  switch (event.eventType) {
    case PROVIDER_EVENTS.PAYMENT_COMPLETED:
      // handle...
      break;
  }
}
```

This keeps `webhook-hooks.ts` as a thin router and moves provider-specific parsing into the provider client/parser where it belongs.

## Related

- `code/webhook-hooks.ts` — Stub
- `docs/STRIPE-REFERENCE.md` — Full working example

## You've understood this if…

- You can trace a webhook from the HTTP entry point through verification, parsing, and routing.
- You can explain why `verifyWebhookSignature` must use a timing-safe compare.
- You know where `WebhookParser` is registered and which DI token it uses.
