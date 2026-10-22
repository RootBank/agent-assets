# Architecture -- Dependency Injection Container

> Deep dive into the DI container, ServiceToken symbols, service registration, lifetimes, and extensibility.

## Overview

The collection module uses a lightweight, custom dependency injection (DI) container instead of a full framework like InversifyJS or tsyringe. The container is defined in `code/core/container.ts` and wired in `code/core/container.setup.ts`. It supports singleton and transient lifetimes, factory-based registration, and easy service replacement for testing.

## Key Concepts

### Container Class

The `Container` class at `code/core/container.ts` stores service descriptors in a `Map` keyed by `string | symbol`. Each descriptor holds a factory function, a lifetime policy, and a cached instance (for singletons).

### ServiceToken Symbols

`ServiceToken` is a `const` object of `Symbol` values used as type-safe DI keys. Using symbols prevents accidental collisions with string-based keys.

```typescript
// code/core/container.ts

export const ServiceToken = {
  // Core Services
  LOG_SERVICE: Symbol('LogService'),
  CONFIG_SERVICE: Symbol('ConfigService'),

  // API Clients (provider-agnostic tokens)
  PROVIDER_CLIENT: Symbol('ProviderClient'),
  ROOT_CLIENT: Symbol('RootClient'),

  // Business Services (provider-agnostic tokens)
  ROOT_SERVICE: Symbol('RootService'),
  PROVIDER_SERVICE: Symbol('ProviderService'),
  RENDER_SERVICE: Symbol('RenderService'),
} as const;
```

The tokens `PROVIDER_CLIENT` and `PROVIDER_SERVICE` are intentionally generic. The default template registers Stripe implementations under these tokens. To swap providers, register different implementations under the same tokens.

### Service Lifetimes

```typescript
// code/core/container.ts

export enum ServiceLifetime {
  SINGLETON = 'singleton',  // One instance for the lifetime of the container
  TRANSIENT = 'transient',  // New instance every time resolve() is called
}
```

| Lifetime | Use Case | Example |
|---|---|---|
| `SINGLETON` | Stateful services, SDK clients, config | LogService, StripeClient, ConfigurationService |
| `TRANSIENT` | Request-scoped or stateless handlers | Controllers (one per event processing) |

## Patterns

### Registering a Service

Services are registered in `code/core/container.setup.ts` using factory functions. The factory receives the container so it can resolve dependencies.

```typescript
// code/core/container.setup.ts
import { Container, ServiceToken, ServiceLifetime } from './container';
import { LogService } from '../services/log.service';
import { ConfigurationService } from '../services/config.service';

export function createContainer(): Container {
  const container = new Container();

  // Register ConfigurationService first (other services depend on it)
  container.register(
    ServiceToken.CONFIG_SERVICE,
    () => new ConfigurationService(),
    ServiceLifetime.SINGLETON
  );

  // Register LogService (depends on ConfigurationService)
  container.register(
    ServiceToken.LOG_SERVICE,
    (c) => {
      const config = c.resolve<ConfigurationService>(ServiceToken.CONFIG_SERVICE);
      return new LogService({ environment: config.get('environment') });
    },
    ServiceLifetime.SINGLETON
  );

  // Register provider client under the generic PROVIDER_CLIENT token
  container.register(
    ServiceToken.PROVIDER_CLIENT,
    () => {
      const StripeClient = require('../clients/stripe-client').default;
      return new StripeClient();
    },
    ServiceLifetime.SINGLETON
  );

  return container;
}
```

### Resolving a Service

```typescript
import { getContainer } from './core/container.setup';
import { ServiceToken } from './core/container';
import { LogService } from './services/log.service';

const container = getContainer();
const logService = container.resolve<LogService>(ServiceToken.LOG_SERVICE);
logService.info('Container initialized', 'Main');
```

### Global Container Access

The module maintains a global singleton container. `getContainer()` creates it lazily on first call.

```typescript
// code/core/container.setup.ts

let globalContainer: Container | null = null;

export function getContainer(): Container {
  if (!globalContainer) {
    globalContainer = createContainer();
  }
  return globalContainer;
}

export function setContainer(container: Container): void {
  globalContainer = container;
}

export function resetContainer(): void {
  globalContainer = null;
}
```

### Replacing a Service (Testing)

The container provides `replace()` and `unregister()` methods for test isolation.

```typescript
import { createContainer } from '../../code/core/container.setup';
import { ServiceToken, ServiceLifetime } from '../../code/core/container';

const container = createContainer();

// Replace the real Stripe client with a mock
container.replace(
  ServiceToken.PROVIDER_CLIENT,
  () => ({
    sdk: {
      customers: { create: jest.fn(), retrieve: jest.fn() },
      paymentIntents: { create: jest.fn() },
    },
  }),
  ServiceLifetime.SINGLETON
);
```

### Adding a New Service

Step-by-step process to add a new service:

1. **Define the service token** in `code/core/container.ts`:

```typescript
export const ServiceToken = {
  // ... existing tokens
  MY_NEW_SERVICE: Symbol('MyNewService'),
} as const;
```

2. **Create the service class** in `code/services/my-new.service.ts`:

```typescript
import { LogService } from './log.service';

export class MyNewService {
  constructor(private readonly logService: LogService) {}

  async doSomething(): Promise<void> {
    this.logService.info('Doing something', 'MyNewService');
  }
}
```

3. **Register in the container** in `code/core/container.setup.ts`:

```typescript
container.register(
  ServiceToken.MY_NEW_SERVICE,
  (c) => {
    const logService = c.resolve<LogService>(ServiceToken.LOG_SERVICE);
    return new MyNewService(logService);
  },
  ServiceLifetime.SINGLETON
);
```

4. **Resolve where needed**:

```typescript
const myService = container.resolve<MyNewService>(ServiceToken.MY_NEW_SERVICE);
```

## Common Tasks

### Check registered services

```typescript
const tokens = container.getRegisteredTokens();
console.log('Registered:', tokens.map(String));
```

### Clear container state (between tests)

```typescript
import { resetContainer } from '../../code/core/container.setup';

afterEach(() => {
  resetContainer();
});
```

### Register order matters

ConfigurationService must be registered before any service that depends on it. LogService depends on ConfigurationService. Business services depend on LogService and clients. Register in dependency order.

## Related Docs

- [00-OVERVIEW.md](./00-OVERVIEW.md) -- Architecture overview
- [03-PROVIDER-INTERFACE.md](./03-PROVIDER-INTERFACE.md) -- Provider contracts
- [13-BUILD-FROM-SPEC.md](./13-BUILD-FROM-SPEC.md) -- End-to-end implementation workflow

## You've understood this if…

- You can list every symbol on `ServiceToken` and what each is for.
- You can explain when to use `SINGLETON` vs `TRANSIENT`.
- You know how to register a service in `container.setup.ts` without reading the file.
