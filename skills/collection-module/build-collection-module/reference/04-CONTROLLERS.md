# Controllers

Controllers are thin orchestrators — one per webhook event type. They resolve services from the DI container, coordinate the call sequence, and return. They contain **no business logic** and are **always under 100 lines**.

## Conventions

- One controller per webhook event (e.g. `PaymentCompletedController`, `PaymentFailedController`).
- Constructor-injected dependencies only — no `getContainer()` inside the class.
- Registered as `ServiceLifetime.TRANSIENT` (new instance per request).
- Delegate all logic to services (`ProviderService`, `RootService`) and adapters.

## Complete Example

```typescript
// code/controllers/payment-completed.controller.ts
import { LogService } from '../services/log.service';
import { RootService } from '../services/root.service';
import { GoCardlessService } from '../services/gocardless.service';
import { GoCardlessToRootAdapter } from '../adapters/gocardless-to-root-adapter';

export class PaymentCompletedController {
  constructor(
    private readonly logService: LogService,
    private readonly providerService: GoCardlessService,
    private readonly rootService: RootService,
    private readonly adapter: GoCardlessToRootAdapter,
  ) {}

  async handle(event: any): Promise<void> {
    this.logService.info('Handling payment completed', 'PaymentCompletedController', {
      eventId: event.id,
    });

    // 1. Look up the Root payment from event metadata
    const rootPaymentId = event.links?.payment;

    // 2. Convert provider event → Root update shape
    const update = this.adapter.convertPaymentToRootUpdate(event, { status: 'successful' });

    // 3. Update Root Platform
    await this.rootService.updatePaymentStatus({ paymentId: rootPaymentId, ...update });

    this.logService.info('Payment marked successful', 'PaymentCompletedController', {
      rootPaymentId,
    });
  }
}
```

## Registration in container.setup.ts

```typescript
// In createContainer() — after PROVIDER_SERVICE registration:
container.register(
  ServiceToken.PAYMENT_COMPLETED_CONTROLLER,
  (c) => {
    const logService = c.resolve<LogService>(ServiceToken.LOG_SERVICE);
    const providerService = c.resolve(ServiceToken.PROVIDER_SERVICE);
    const rootService = c.resolve(ServiceToken.ROOT_SERVICE);
    const { GoCardlessToRootAdapter } = require('../adapters/gocardless-to-root-adapter');
    return new PaymentCompletedController(
      logService,
      providerService,
      rootService,
      new GoCardlessToRootAdapter(),
    );
  },
  ServiceLifetime.TRANSIENT
);
```

## Resolving in webhook-hooks.ts

```typescript
case GOCARDLESS_EVENTS.PAYMENT_COMPLETED: {
  const controller = container.resolve<PaymentCompletedController>(
    ServiceToken.PAYMENT_COMPLETED_CONTROLLER
  );
  await controller.handle(event);
  break;
}
```

## Test Pattern

```typescript
// __tests__/controllers/payment-completed.controller.test.ts
import { PaymentCompletedController } from '../../code/controllers/payment-completed.controller';
import { createMockLogService, createMockRootService } from '../test-helpers';

describe('PaymentCompletedController', () => {
  const mockLogService = createMockLogService();
  const mockProviderService = { createPaymentIntent: jest.fn() };
  const mockRootService = createMockRootService();
  const mockAdapter = { convertPaymentToRootUpdate: jest.fn().mockReturnValue({ status: 'successful', amount: 5000 }) };

  const controller = new PaymentCompletedController(
    mockLogService as any,
    mockProviderService as any,
    mockRootService as any,
    mockAdapter as any,
  );

  it('calls updatePaymentStatus with successful status', async () => {
    mockRootService.updatePaymentStatus.mockResolvedValue({});

    await controller.handle({ id: 'ev_123', links: { payment: 'pay_abc' } });

    expect(mockRootService.updatePaymentStatus).toHaveBeenCalledWith(
      expect.objectContaining({ status: 'successful' })
    );
  });
});
```

## Related

- `docs/08-WEBHOOKS.md` — Webhook routing
- `docs/02-ARCHITECTURE.md` — DI container and ServiceToken
- `docs/STRIPE-REFERENCE.md` — Full working example
- `code/interfaces/provider.interfaces.ts` — Service contracts

## You've understood this if…

- You know why controllers register as `TRANSIENT` rather than `SINGLETON`.
- You can name the size limit on a controller and why it exists.
- You can sketch a one-event controller from memory.
