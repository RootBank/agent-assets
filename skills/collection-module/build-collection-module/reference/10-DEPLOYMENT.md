# Deployment

## Prerequisites

- `.root-config.json` with `collectionModuleKey`, `organizationId`, `host`
- `.root-auth` with your Root Platform API key
- `code/env.ts` populated with live credentials

## Commands

```bash
# Validate config before deploying
npm run validate

# Deploy to sandbox
npm run deploy:sandbox

# Deploy to production
npm run deploy:production

# Dry run (no actual deploy)
npm run deploy:dry-run:sandbox
npm run deploy:dry-run:production
```

## Predeploy checklist

`npm run predeploy` automatically runs: validate → test → build.

## CI/CD

Use `npm run test:ci` in CI pipelines — it adds `--coverage` and `--maxWorkers=2`.

## Related

- `../scripts/deploy.sh` — Deployment script (in repo root `scripts/`)
- `../scripts/validate-config.sh` — Pre-deploy validation (in repo root `scripts/`)

## You've understood this if…

- You can list the three files that must be present before `npm run deploy:sandbox`.
- You can name the predeploy check that runs automatically.
- You know which command targets sandbox vs production.
