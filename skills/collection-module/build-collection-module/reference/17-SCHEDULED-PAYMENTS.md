# Scheduled Payments

> How a collection module plans a policy's future payments and collects them automatically. Source of truth: [Root Platform — Scheduled payments](https://docs.rootplatform.com/docs/scheduled-payments). Read `07-LIFECYCLE-HOOKS.md` and `11-CONFIGURATION.md` first — scheduled payments are driven from hooks and configured in `root.config.json`.

## Overview

Scheduled payments let your module forecast a policy's upcoming payments and have Root Platform collect them on the due date — without you calling a billing API or writing to a billing table directly. You return **actions** from lifecycle hooks; the platform owns the schedule, the conversion to a real payment, and (for file-based providers) the submission.

The lifecycle has three stages:

1. **Schedule** — a lifecycle hook returns a `schedule_payment` action. Root records a forecast of a future payment. Nothing is collected yet.
2. **Create** — on the due date, or `submissionLeadTime` days before it, Root converts the schedule into a real payment with status `pending`.
3. **Submit** — Root sends the `pending` payment to the provider. **File-based** providers are handled by the platform batcher (no code). **API-based** providers implement a submission hook that charges each payment and returns a per-payment result.

```
hook returns                Root, on/before due date            Root batcher or your hook
schedule_payment   ──────►  pending payment created   ──────►  submitted to provider
   (forecast)                  (collection_attempted)            (collection_submitted)
```

## Provider type decides how much you write

| Provider type | `batching.enabled` | Submission code |
|---|---|---|
| **File-based** (debit-order / EFT file) | `false` | None — the platform batcher builds and submits the file. |
| **API-based** (charge over an API) | `true` | Implement the submission hook named in `submitPaymentsFunction`. |

This mirrors the SDK-vs-HTTP split in `15-PROVIDER-PATTERNS.md`: file-based ≈ the platform owns the I/O; API-based ≈ you own the call.

## Actions

Actions are returned **as an array** from a lifecycle hook. Return `[]` to schedule nothing, or several actions at once. The platform applies them — you never write to a schedule directly.

Which hook returns which action is up to your billing logic (see `07-LIFECYCLE-HOOKS.md`):

- `afterPolicyIssued` — schedule the first payment when the policy activates.
- `afterPaymentSucceeded` — schedule the next recurring payment. **Recurrence is driven entirely by your hooks** — Root does not auto-repeat a schedule.
- `afterPolicyCancelled` / payment-method removal — `unschedule_payment` to cancel future collections.

> **Don't invent the recurrence cadence.** If the spec doesn't state the billing frequency, anchor date, or pro-rata rule, leave a `TODO(human):` per `16-WHEN-TO-DEVIATE.md` rather than guessing.

### `schedule_payment`

Records a forecast of a future payment.

```json
{
  "name": "schedule_payment",
  "scheduled_for": "2026-08-01",
  "expected_amount": 50000,
  "currency": "ZAR",
  "premium_type": "recurring",
  "billing_period_start": "2026-08-01",
  "billing_period_end": "2026-09-01",
  "payment_method_id": "optional-id"
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | Yes | Literal `"schedule_payment"`. |
| `scheduled_for` | Yes | Due date, ISO `YYYY-MM-DD` (no time). |
| `expected_amount` | Yes | Smallest currency unit (e.g. cents). |
| `currency` | Yes | ISO 4217, e.g. `"ZAR"`. |
| `premium_type` | Yes | One of: `recurring`, `pro_rata`, `arrears`, `ad_hoc`, `cover_period`, `collection_request`, `manual_eft`, `premium_refund`. |
| `billing_period_start` | Yes | ISO date — start of the period this payment covers. |
| `billing_period_end` | Yes | ISO date — end of the period this payment covers. |
| `payment_method_id` | No | Omit to use the policy's attached payment method. |

### `reschedule_payment`

Moves an existing schedule to a new date. Emits `collection_rescheduled`.

```json
{
  "name": "reschedule_payment",
  "scheduled_payment_id": "schedule-id",
  "new_scheduled_for": "2026-08-15",
  "reason": "policyholder requested a later date"
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | Yes | Literal `"reschedule_payment"`. |
| `scheduled_payment_id` | Yes | ID of the schedule to move. |
| `new_scheduled_for` | Yes | New due date, ISO. |
| `reason` | No | Free text, for the audit trail. |

### `unschedule_payment`

Cancels a schedule **before** the payment is created. Emits `collection_unscheduled`.

```json
{
  "name": "unschedule_payment",
  "scheduled_payment_id": "schedule-id",
  "reason": "policy_cancelled"
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | Yes | Literal `"unschedule_payment"`. |
| `scheduled_payment_id` | Yes | ID of the schedule to cancel. |
| `reason` | Yes | Fixed enum: `manual_admin`, `payment_method_revoked`, `policy_cancelled`. |

## Configuration

Scheduling is configured under `billingSettings` in `root.config.json` (not in `code/env.ts` — this is platform config, not provider secrets). Two sub-objects: `batching` and an optional `retry`.

```json
{
  "billingSettings": {
    "batching": {
      "enabled": true,
      "submitPaymentsFunction": "submitPayments",
      "submitBatchSize": 100,
      "scheduleTimeUtc": "05:00",
      "submissionLeadTime": 2,
      "latestSubmissionTimeUtc": "20:00"
    },
    "retry": {
      "maxAttempts": 3,
      "backoffDays": 1,
      "backoffMultiplier": 2
    }
  }
}
```

### `batching`

| Field | Type | Default | Notes |
|---|---|---|---|
| `enabled` | boolean | `false` | `true` → API submission via your hook. `false` → file-based debit via the platform batcher. |
| `submitPaymentsFunction` | string | — | Name of the submission hook. **Required when `enabled` is `true`**; must match an exported function (see below). |
| `submitBatchSize` | number | `100` | Payments per hook call. Range 1–500. |
| `scheduleTimeUtc` | string | `"05:00"` | UTC `HH:MM` at which submission runs. |
| `submissionLeadTime` | number | `0` | Days before `scheduled_for` to create the `pending` payment. Max 7. |
| `latestSubmissionTimeUtc` | string | `"00:00"` | UTC cutoff; `"00:00"` permits all-day submission. Set ahead of your provider's cutoff to avoid spilling to the next day. |

### `retry` (optional)

Omit the block to disable retries.

| Field | Type | Default |
|---|---|---|
| `maxAttempts` | number | `0` |
| `backoffDays` | number | `0` |
| `backoffMultiplier` | number | `1` |

`backoffMultiplier` compounds: the first retry waits `backoffDays`, the second waits `backoffDays × backoffMultiplier`, and so on.

### Formats

- **Dates** — ISO without time: `"2026-08-01"`.
- **Times** — UTC `HH:MM`: `"05:00"`.
- **Amounts** — smallest currency unit (cents).

## Submitting payments (API providers only)

When `batching.enabled` is `true`, Root invokes the function named in `submitPaymentsFunction`, passing a batch of `pending` payments. You charge each one and return a result per payment. Export it from `code/main.ts` alongside the other hooks, and resolve services via the DI container — do not import the provider class directly (see `07-LIFECYCLE-HOOKS.md`).

```typescript
// Exported from code/main.ts; name must match billingSettings.batching.submitPaymentsFunction
export const submitPayments = async ({ payments, organization, environment }) => {
  const container = getContainer();
  const providerService = container.resolve<PaymentProviderService>(ServiceToken.PROVIDER_SERVICE);
  const log = container.resolve<LogService>(ServiceToken.LOG_SERVICE);

  const results = [];
  for (const payment of payments) {
    try {
      // payment_id is the idempotency key — a redelivered batch must not double-charge.
      const charge = await providerService.charge({
        amount: payment.amount,
        currency: payment.currency,
        idempotencyKey: payment.payment_id,
      });
      results.push({
        payment_id: payment.payment_id,
        status: 'submitted',
        provider_reference: charge.id,
      });
    } catch (error) {
      log.error('Scheduled payment submission failed', { payment_id: payment.payment_id, error });
      results.push({
        payment_id: payment.payment_id,
        status: 'failed',
        failure_reason: error instanceof Error ? error.message : 'provider_submission_failed',
      });
    }
  }

  return { results };
};
```

**Input** — each payment in `payments` carries: `payment_id`, `policy_id`, `amount`, `currency`, `premium_type`, `billing_period_start`, `billing_period_end`, and the `policyholder` and `policy` objects. The call also receives `organization` and `environment` (`sandbox` | `production`).

**Return** — `{ results: [...] }` with one entry per input payment:

| Field | Required | Notes |
|---|---|---|
| `payment_id` | Yes | Must match the input payment. |
| `status` | Yes | `"submitted"` (provider accepted the request) or `"failed"` (the submission itself failed). |
| `provider_reference` | When submitted | Provider's transaction/charge ID. |
| `failure_reason` | When failed | Short reason string. |

`status` reflects **submission**, not settlement. Final settlement (success / failure / reversal) arrives later via webhook — route it through `webhook-hooks.ts` and your adapter as usual (`08-WEBHOOKS.md`, `06-ADAPTERS.md`).

### Idempotency

**Always pass `payment_id` as the provider idempotency key.** Batches can be redelivered; without an idempotency key a retry charges the policyholder twice. This is the same idempotency discipline required of every lifecycle hook (`07-LIFECYCLE-HOOKS.md` § Ordering and idempotency).

## Events

Root emits eight scheduled-payment lifecycle events. Use them for monitoring and to drive downstream hooks:

| Event | Fires when |
|---|---|
| `collection_scheduled` | A schedule is created from a `schedule_payment` action. |
| `collection_attempted` | A `pending` payment is created on/before the due date. |
| `collection_submitted` | The payment reaches the provider. |
| `collection_successful` | The provider confirms a successful payment. |
| `collection_failed` | Payment processing fails. |
| `collection_reversed` | A successful payment is reversed (refund / chargeback). |
| `collection_rescheduled` | A schedule's date is changed. |
| `collection_unscheduled` | A schedule is cancelled before the payment is created. |

## Troubleshooting

| Symptom | Check |
|---|---|
| Schedule never created | Hook returns a `schedule_payment` action with **all** required fields (`scheduled_for`, `expected_amount`, `currency`, `premium_type`, `billing_period_start`, `billing_period_end`). |
| Payment created but never submitted | `batching.enabled`, `submitPaymentsFunction`, and `scheduleTimeUtc`. For API providers, confirm the named function is exported and returns one result per input payment. |
| Submission lands after the provider's cutoff | Lower `latestSubmissionTimeUtc` so it sits well ahead of the provider window; otherwise submission rolls to the next day. |
| Policyholder charged twice | The provider call must use `payment_id` as the idempotency key. |

## Related

- `07-LIFECYCLE-HOOKS.md` — the hooks that return scheduling actions; idempotency rules.
- `11-CONFIGURATION.md` — config conventions (`billingSettings` lives in `root.config.json`).
- `08-WEBHOOKS.md` — settlement results arrive by webhook, not from the submission hook.
- `15-PROVIDER-PATTERNS.md` — file-based vs API-based provider patterns.
- `16-WHEN-TO-DEVIATE.md` — what to do when the billing cadence or a field doesn't map cleanly.
- [Root Platform — Scheduled payments](https://docs.rootplatform.com/docs/scheduled-payments) — upstream source of truth.

## You've understood this if…

- You can name the three stages (schedule → create → submit) and say which Root event marks each.
- You can explain why a file-based provider writes no submission code but an API-based provider must implement `submitPaymentsFunction`.
- You know why `payment_id` must be the provider idempotency key, and why submission `status` is not the same as settlement.
- You can point to the hook that schedules the *next* recurring payment and explain why recurrence won't happen on its own.
