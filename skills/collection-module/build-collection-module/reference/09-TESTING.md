# Testing

## Overview

Tests mirror the `code/` structure in `__tests__/`. Run with `npm test`.

## Conventions

- Mock the DI container with `jest.mock('../../code/core/container.setup')`.
- Use factories in `__tests__/helpers/factories.ts` for test data.
- Use mock services from `__tests__/test-helpers.ts`.
- Never hit real APIs in unit tests.

## Important: `resetMocks: true`

This project uses `resetMocks: true` in `jest.config.js`. This means **all mock implementations and return values are reset between tests**.

**Always set mock return values inside `beforeEach` or inside each `it` block — never at module scope or `describe` scope.**

```typescript
// ✗ DON'T — mock will be silently cleared before each test
describe('MyService', () => {
  const mockClient = { fetch: jest.fn().mockResolvedValue({ id: '123' }) }; // ← cleared!
  
  it('should work', async () => {
    // mockClient.fetch is now jest.fn() with no return value
  });
});

// ✓ DO — set mocks inside beforeEach
describe('MyService', () => {
  let mockClient: any;

  beforeEach(() => {
    mockClient = { fetch: jest.fn().mockResolvedValue({ id: '123' }) };
  });

  it('should work', async () => {
    // mockClient.fetch still returns { id: '123' }
  });
});
```

## Pattern for service tests

```typescript
jest.mock('../../code/core/container.setup');

describe('MyService', () => {
  let service: MyService;
  let mockLogService: ReturnType<typeof createMockLogService>;
  let mockProviderClient: ReturnType<typeof createMockProviderClient>;

  beforeEach(() => {
    mockLogService = createMockLogService();
    mockProviderClient = createMockProviderClient();
    service = new MyService(mockLogService, mockProviderClient);
  });

  it('should do something', async () => {
    mockProviderClient.someMethod.mockResolvedValue({ id: 'result_123' });
    const result = await service.doSomething({ id: 'input' });
    expect(result.id).toBe('result_123');
  });
});
```

## Coverage thresholds

`jest.config.js` enforces 70% branches/functions/lines/statements. Run `npm run test:coverage` to check.

## Related

- `__tests__/helpers/factories.ts` — Test data factories
- `__tests__/test-helpers.ts` — Mock service factories

## You've understood this if…

- You can explain the implications of `resetMocks: true` for between-test state.
- You know where shared test factories live and how to extend them.
- You can name the coverage threshold and which directories it applies to.
