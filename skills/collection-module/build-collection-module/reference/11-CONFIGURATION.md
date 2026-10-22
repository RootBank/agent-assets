# Configuration

## Overview

Configuration is managed by `ConfigurationService` in `code/services/config.service.ts`. All values come from `code/env.ts`, which is populated by the setup script.

## Key fields

| Field | Description |
|---|---|
| `providerSecretKey` | Provider API secret key (live / sandbox) |
| `providerPublishableKey` | Provider publishable key if applicable |
| `providerWebhookSigningSecret` | Webhook signing secret for signature verification |
| `providerProductId` | Provider product/plan ID if applicable |
| `rootApiKey` | Root Platform API key |
| `rootBaseUrl` | Root Platform API base URL |
| `rootCollectionModuleKey` | Collection module key (matches `.root-config.json`) |

## Usage

```typescript
// In services (prefer DI injection):
const config = container.resolve<ConfigurationService>(ServiceToken.CONFIG_SERVICE);
const secretKey = config.get('providerSecretKey');

// Outside DI (e.g. in clients):
const config = getConfigService();
```

## Setup

```bash
npm run setup -- --cm-key=cm_yourprovider_yourco --org-id=your-org-id
```

## Related

- `code/env.sample.ts` — All required fields with descriptions
- `code/services/config.service.ts` — Full implementation

## You've understood this if…

- You can name every provider-agnostic config field the template ships with.
- You know which command bootstraps a new module's config.
- You can explain why config fields are named `providerSecretKey` rather than `stripeSecretKey`.
