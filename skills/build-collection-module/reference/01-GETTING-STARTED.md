# Getting Started

> Prerequisites, environment setup, first build, and running tests.

## Overview

This guide walks you through setting up the collection module template for local development. The template ships with a Stripe reference implementation. You will configure environment variables, install dependencies, build the project, and run the test suite.

## Prerequisites

| Requirement | Minimum Version | Check Command |
|---|---|---|
| Node.js | 18.0.0+ | `node --version` |
| npm | 8.0.0+ | `npm --version` |
| TypeScript | (bundled via devDependencies) | `npx tsc --version` |
| Root Platform account | -- | [rootplatform.com](https://rootplatform.com) |
| Payment provider account | -- | e.g., [stripe.com](https://stripe.com) |

## Key Concepts

- **env.ts**: Runtime configuration file. Never committed to version control. Created from `env.sample.ts`.
- **Provider-agnostic naming**: Config fields use `PROVIDER_*` prefixes (e.g., `PROVIDER_SECRET_KEY_LIVE`) so the same template works for any payment provider.
- **Sandbox vs Production**: The module supports two environments. Set the `ENVIRONMENT` variable to `sandbox` or `production`.

## Setup Steps

### 1. Clone and Install

```bash
# Navigate to the collection module directory
cd collection_module

# Install dependencies
npm install
```

### 2. Configure Environment Variables

Copy the sample environment file and fill in your values.

```bash
cp code/env.sample.ts code/env.ts
```

Open `code/env.ts` and replace the placeholder values. The file uses provider-agnostic naming:

```typescript
// code/env.ts

// Payment Provider Configuration
export const PROVIDER_WEBHOOK_SIGNING_SECRET_LIVE = 'whsec_your_live_secret';
export const PROVIDER_WEBHOOK_SIGNING_SECRET_TEST = 'whsec_your_test_secret';

export const PROVIDER_PUBLISHABLE_KEY_LIVE = 'pk_live_your_key';
export const PROVIDER_PUBLISHABLE_KEY_TEST = 'pk_test_your_key';

export const PROVIDER_SECRET_KEY_LIVE = 'sk_live_your_key';
export const PROVIDER_SECRET_KEY_TEST = 'sk_test_your_key';

export const PROVIDER_PRODUCT_ID_LIVE = 'prod_your_live_id';
export const PROVIDER_PRODUCT_ID_TEST = 'prod_your_test_id';

// Root Platform Configuration
export const ROOT_COLLECTION_MODULE_KEY = 'my_collection_module';
export const ROOT_API_KEY_LIVE = 'production_your_key';
export const ROOT_API_KEY_SANDBOX = 'sandbox_your_key';
export const ROOT_BASE_URL_LIVE = 'https://api.rootplatform.com/v1/insurance';
export const ROOT_BASE_URL_SANDBOX = 'https://sandbox.rootplatform.com/v1/insurance';

export const TIME_DELAY_IN_MILLISECONDS = '10000';
```

### 3. Validate Configuration

Run the validation script to verify your config is complete:

```bash
npm run validate
```

### 4. Build the Project

```bash
npm run build
```

This compiles TypeScript from `code/` to `dist/` using `tsconfig.build.json`. The build output is the deployable artifact.

### 5. Run Tests

```bash
# Run all tests
npm test

# Run only unit tests
npm run test:unit

# Run with coverage
npm run test:coverage

# Watch mode for development
npm run test:watch
```

### 6. Lint and Format

```bash
# Check linting
npm run lint

# Auto-fix lint + format
npm run format
```

## Common Tasks

### Build and Watch

During development, use watch mode to auto-rebuild on changes:

```bash
npm run build:watch
```

### Deploy to Sandbox

```bash
# Dry run first
npm run deploy:dry-run:sandbox

# Deploy
npm run deploy:sandbox
```

### Deploy to Production

```bash
# Dry run first
npm run deploy:dry-run:production

# Deploy
npm run deploy:production
```

### Full Pre-deploy Check

```bash
npm run predeploy
```

This runs validation, tests, and build in sequence.

## Patterns

### Project Scripts Reference

```json
{
  "validate": "bash ../scripts/validate-config.sh",
  "lint": "eslint code --ext .js,.jsx,.ts,.tsx",
  "format": "npm run prettier-write && npm run lint:fix",
  "build": "rm -rf ./dist && tsc --project tsconfig.build.json",
  "test": "jest --forceExit",
  "test:unit": "jest --forceExit --testPathPattern='__tests__/(services|core|utils)'",
  "test:coverage": "jest --forceExit --coverage",
  "scaffold:provider": "node ../scripts/scaffold-provider.js",
  "extract:spec": "node ../scripts/extract-spec.js",
  "log:action": "node ../scripts/log-action.js",
  "deploy:sandbox": "bash ../scripts/deploy.sh sandbox",
  "deploy:production": "bash ../scripts/deploy.sh production"
}
```

### AI Tool Setup Hints

If you are using AI-assisted development tools (Cursor, Claude Code, Copilot, etc.):

1. Point the tool at the `collection_module/` directory as the workspace root.
2. Key files to index for context:
   - `code/core/container.ts` -- DI tokens and container class
   - `code/interfaces/provider.interfaces.ts` -- provider contracts
   - `code/services/config.service.ts` -- configuration shape
   - `code/webhook-hooks.ts` -- webhook routing pattern
3. The `docs/` directory contains structured documentation for each layer.
4. Test files in `__tests__/` mirror the `code/` directory structure and demonstrate usage patterns.
5. When implementing a new provider, start with `code/interfaces/provider.interfaces.ts` for the contracts you must implement.

## Related Docs

- [00-OVERVIEW.md](./00-OVERVIEW.md) -- Architecture overview and directory layout
- [02-ARCHITECTURE.md](./02-ARCHITECTURE.md) -- DI container deep dive
- [03-PROVIDER-INTERFACE.md](./03-PROVIDER-INTERFACE.md) -- Implementing a new provider
- [13-BUILD-FROM-SPEC.md](./13-BUILD-FROM-SPEC.md) -- End-to-end spec-to-implementation workflow

## You've understood this if…

- You can run the pre-flight check (`npm install && npm test && npm run build`) and have it pass.
- You know where `env.ts` lives and which fields are required vs optional.
- You can name the script you'd run first to scaffold a new provider.
