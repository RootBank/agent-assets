# Adapters

Adapters are **pure data transformation functions** — they translate between provider data shapes and Root Platform data shapes. They make **no API calls**, have **no side effects**, and take **no service dependencies**.

## Conventions

- All methods are synchronous and pure.
- Input: raw provider event/object. Output: Root Platform data shape.
- No logging, no network calls, no DI container access.
- Instantiated directly — not registered in the DI container.
- Injected into controllers via constructor.

## Complete Example

```typescript
// code/adapters/gocardless-to-root-adapter.ts
import {
  ProviderToRootAdapter,
  ConvertPaymentParams,
} from '../interfaces/provider.interfaces';

/**
 * GoCardlessToRootAdapter — pure data transformation.
 * GoCardless shapes → Root Platform shapes.
 * No API calls. No side effects.
 */
export default class GoCardlessToRootAdapter implements ProviderToRootAdapter {

  convertPaymentToRootUpdate(
    providerPayment: any,
    params: ConvertPaymentParams,
  ) {
    return {
      status: this.mapStatus(providerPayment.status),
      amount: providerPayment.amount,
      currency: (providerPayment.currency ?? 'ZAR').toUpperCase(),
      externalId: providerPayment.id,
    };
  }

  convertCustomerToAppData(providerCustomer: any): Record<string, any> {
    return {
      gocardless_customer_id: providerCustomer.id,
      gocardless_email: providerCustomer.email ?? null,
      gocardless_mandate_id: providerCustomer.default_source ?? null,
    };
  }

  private mapStatus(status: string): string {
    const statusMap: Record<string, string> = {
      paid_out:  'successful',
      failed:    'failed',
      cancelled: 'failed',
      pending:   'pending',
      submitted: 'pending',
    };
    return statusMap[status] ?? 'pending';
  }
}
```

## Status Mapping Table

Always define a complete status map. Unknown statuses should default to `'pending'` — never silently drop them.

```typescript
// Pattern: provider status → Root Platform status
const statusMap: Record<string, string> = {
  // 'provider_status': 'root_status'
  'succeeded':  'successful',   // payment was collected
  'failed':     'failed',       // payment could not be collected
  'cancelled':  'failed',       // mandate/subscription cancelled
  'pending':    'pending',      // awaiting collection
  'processing': 'pending',      // in-flight
};
return statusMap[providerStatus] ?? 'pending'; // safe default
```

Valid Root Platform payment statuses: `'successful'` | `'failed'` | `'pending'`

## Test Pattern

```typescript
// __tests__/adapters/gocardless-to-root-adapter.test.ts
import GoCardlessToRootAdapter from '../../code/adapters/gocardless-to-root-adapter';

describe('GoCardlessToRootAdapter', () => {
  const adapter = new GoCardlessToRootAdapter();

  describe('convertPaymentToRootUpdate', () => {
    it('maps paid_out → successful', () => {
      const result = adapter.convertPaymentToRootUpdate(
        { id: 'pay_123', status: 'paid_out', amount: 5000, currency: 'gbp' },
        {} as any,
      );
      expect(result).toEqual({
        status: 'successful',
        amount: 5000,
        currency: 'GBP',
        externalId: 'pay_123',
      });
    });

    it('defaults unknown status to pending', () => {
      const result = adapter.convertPaymentToRootUpdate(
        { id: 'pay_456', status: 'some_unknown_status', amount: 0, currency: 'zar' },
        {} as any,
      );
      expect(result.status).toBe('pending');
    });
  });

  describe('convertCustomerToAppData', () => {
    it('extracts customer identifiers', () => {
      const result = adapter.convertCustomerToAppData({ id: 'cust_abc', email: 'test@example.com' });
      expect(result.gocardless_customer_id).toBe('cust_abc');
      expect(result.gocardless_email).toBe('test@example.com');
    });
  });
});
```

## Related

- `code/interfaces/provider.interfaces.ts` — `ProviderToRootAdapter` contract and `ConvertPaymentParams`
- `docs/04-CONTROLLERS.md` — How controllers use adapters
- `docs/STRIPE-REFERENCE.md` — Full working adapter example

## You've understood this if…

- You can state the one rule adapters must never break.
- You can sketch a `mapStatus` table from a provider's status enum to Root's three states.
- You know which provider statuses Root collapses to `successful`, `failed`, and `pending`.
