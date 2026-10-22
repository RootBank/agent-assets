# Glossary

> Template-specific and Root-specific terms used across the docs. Each entry: definition + the doc where it's used in depth.

## A

**Adapter** — A pure data-transformation class (e.g. `StripeToRootAdapter`) that converts provider-shaped data into Root Platform shapes. No API calls, no side effects. See `06-ADAPTERS.md`.

## B

**`BaseHttpClient`** — Shared HTTP client (`code/clients/base-http-client.ts`) for providers that lack a TypeScript SDK. Provides typed methods, retry, and timeout. See `05-CLIENTS.md`.

**`billingSettings`** — Block in `root.config.json` that configures scheduled-payment behaviour: `batching` (submission timing, batch size, lead time, API-vs-file provider) and an optional `retry` policy. See `17-SCHEDULED-PAYMENTS.md`.

## C

**Collection Module** — The deployable unit produced by this template. A collection module integrates one payment provider with Root Platform, exposing lifecycle hooks and webhooks. See `00-OVERVIEW.md`.

**`ConfigurationService`** — Singleton DI service that reads typed config from `env.ts` (provider keys, webhook secrets, environment). Resolve via `ServiceToken.CONFIG_SERVICE`. See `11-CONFIGURATION.md`.

## D

**DEVIATION comment** — Convention for marking code that intentionally departs from template patterns: `// DEVIATION: <reason>`. See `16-WHEN-TO-DEVIATE.md`.

**DI Container** — Lightweight dependency-injection container (`code/core/container.ts`) used for constructor injection across the module. Two lifetimes: `SINGLETON`, `TRANSIENT`. See `02-ARCHITECTURE.md`.

## E

**`EnhancedModuleError`** — Categorised error base class (`code/utils/error-types.ts`) with `retryable`, `statusCode`, and request-tracking. Subclasses: `ValidationError`, `NotFoundError`, `NetworkError`, `TimeoutError`, `RateLimitError`, `ServerError`. See `12-ERROR-HANDLING.md`.

**Error Category** — `ErrorCategory` enum in `code/utils/error-types.ts`: `validation`, `not_found`, `authentication`, `authorization`, `network`, `server_error`, `timeout`, `rate_limit`, `unknown`. Drives `isRetryableError`. See `12-ERROR-HANDLING.md`.

## L

**Lifecycle Hook** — A function exported from `code/main.ts` that Root Platform invokes at a specific policy or payment milestone (e.g. `afterPolicyIssued`, `afterPaymentCreated`). See `07-LIFECYCLE-HOOKS.md`.

**`LogService`** — Singleton DI service for structured logging. The only allowed logging mechanism — `console.log` is banned. Resolve via `ServiceToken.LOG_SERVICE`. See `00-OVERVIEW.md`.

## M

**`ModuleError`** — Base error class (`code/utils/error.ts`) that auto-prefixes environment and caller frame. Use for ad-hoc business errors without a categorised subclass. See `12-ERROR-HANDLING.md`.

## P

**Provider** — A payment gateway integrated through this module (Stripe, GoCardless, PayFast, etc.). Always referred to generically in interfaces and DI tokens. See `03-PROVIDER-INTERFACE.md`.

**Provider-Agnostic Naming** — Convention that interfaces, DI tokens, and config field names never mention a specific provider: `PROVIDER_CLIENT`, `PROVIDER_SERVICE`, `providerSecretKey`. Swapping providers should be a registration change, not a rename. See `00-OVERVIEW.md`.

**`PROVIDER_CLIENT`** — DI token (`ServiceToken.PROVIDER_CLIENT`) under which the provider's SDK or HTTP client is registered. See `02-ARCHITECTURE.md`.

**`PROVIDER_SERVICE`** — DI token (`ServiceToken.PROVIDER_SERVICE`) under which the provider's business-logic service is registered. Always typed as `PaymentProviderService` at the call site. See `03-PROVIDER-INTERFACE.md`.

## R

**`RENDER_SERVICE`** — DI token for the singleton `RenderService` that produces HTML for payment-method capture and view hooks. See `07-LIFECYCLE-HOOKS.md`.

**`retryWithBackoff`** — Async retry helper (`code/utils/retry.ts`). Defaults: 3 retries, exponential backoff, jitter via `retryWithJitter`. Pair with `isRetryableError`. See `12-ERROR-HANDLING.md`.

**Root Platform** — The insurance platform the collection module integrates with. Issues policies, creates payments, calls lifecycle hooks, consumes webhooks. See `00-OVERVIEW.md`.

## S

**Scaffolder** — The CLI (`npm run scaffold:provider`) that generates client/service/adapter/hook stubs for a new provider from flags or a spec. See `13-BUILD-FROM-SPEC.md`.

**Scheduled Payment** — A forecast of a future policy payment, created by returning a `schedule_payment` action from a lifecycle hook. Root converts it into a `pending` payment on/before the due date, then submits it. See `17-SCHEDULED-PAYMENTS.md`.

**`submitPaymentsFunction`** — Name (in `billingSettings.batching`) of the exported hook Root calls to submit a batch of pending payments for an API-based provider. Required when `batching.enabled` is `true`; file-based providers leave it unset. See `17-SCHEDULED-PAYMENTS.md`.

**Service Lifetime** — `SINGLETON` (one instance per container) or `TRANSIENT` (new instance per resolve). Defined in `code/core/container.ts`. See `02-ARCHITECTURE.md`.

**`ServiceToken`** — `const` map of `Symbol`s in `code/core/container.ts` used as DI keys. Includes `LOG_SERVICE`, `CONFIG_SERVICE`, `PROVIDER_CLIENT`, `PROVIDER_SERVICE`, `ROOT_CLIENT`, `ROOT_SERVICE`, `RENDER_SERVICE`, `WEBHOOK_PARSER`. See `02-ARCHITECTURE.md`.

**Spec** — A provider integration specification — either authored from `SPEC-TEMPLATE.md` or extracted from API docs via `npm run extract:spec`. Drives the scaffolder. See `13-BUILD-FROM-SPEC.md`.

**Status Mapping** — The provider-specific `mapStatus(providerStatus): RootStatus` function inside each adapter that normalises provider payment states (e.g. Stripe `succeeded` → Root `successful`). See `06-ADAPTERS.md`.

## T

**`TODO(human):`** — Convention for marking points where the agent could not determine the correct semantics from source or spec. A human must answer before the code is shipped. See `16-WHEN-TO-DEVIATE.md`.

## W

**`WebhookParser`** — Singleton registered under `ServiceToken.WEBHOOK_PARSER` that selects the right provider payload format and verifies signatures. See `08-WEBHOOKS.md`.

**`WEBHOOK_PARSER`** — DI token for `WebhookParser`. See `08-WEBHOOKS.md`.

## You've understood this if…

- You can name the DI token under which a new provider's service is registered.
- You can explain why error subclasses (`NetworkError`, `RateLimitError`) are preferred over raw `ModuleError`.
- You know which file in `code/` to open to read the canonical definition of a `ServiceToken`.
