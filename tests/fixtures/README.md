# Fixtures

Repos the selection test runs `scripts/select-skills.sh` against. Each is the smallest thing that
exercises one branch of kind detection.

| Fixture | Stands for | Expected result |
| --- | --- | --- |
| `collection-module/` | A collection module repo | Gets the collection-module skills |
| `product-module/` | A product module repo | Detected as `product-module`, gets **zero** skills |
| `no-config/` | A repo that is neither | Nothing, kind undetermined |
| `both-keys/` | A config naming both kinds | Nothing, kind undetermined |

## Why the kind is asserted, not just the skill list

`product-module/` yielding nothing is only the guarantee if the repo was *recognised* as a product
module. A fixture that failed to parse would also yield nothing, and the test would pass while
proving the opposite of what it claims. So `select-skills.sh` reports the kind it detected on
stderr, and the test asserts on that too.

## Where the shapes come from

Both configs follow `root-platform-cli/src/domain/root-config.ts`:

- `RootConfigWrite` is the product module config. `productModuleKey`, `productModuleName`,
  `organizationId`, `host`, `stack`, `settings`, `scheduledFunctions`, `fulfillmentTypes`,
  `alterationHooks`, `applicationAlterationHooks`, `memberAlterationHooks` and `codeFileOrder` are
  its fields; the arrays and objects are empty here because kind detection does not read them.
- `isProductModuleConfig` at line 48 is `!!config.productModuleKey`, which is the test
  `select-skills.sh` mirrors.
- The collection-module fixture follows that repo's own
  `test-modules/collection-modules/example_module/.root-config.json`.

These are reduced fixtures, not real modules. They are sized for kind detection, which is all the
catalog needs to decide. Note that no real product module repo was available when they were
written, so the product-module shape comes from the CLI's type rather than from a live repo.
