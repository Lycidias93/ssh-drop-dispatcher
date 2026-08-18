# Return Channel v1 — RC2 implementation status

Status: repository candidate in verification; Pixel RC1 is installed but not accepted as final because the shared WebUI Core advanced after its build.

Candidate:

- version: `4.14.0-return-rc2`
- versionCode: `4140002`
- public stable remains `4.13.0` / `4130007`
- shared WebUI Core: `0.5.0`
- exact Core commit: `a365fea5049a1daa6e674eab27f81b0ebf4c878a`
- stable WebUI Core 0.3.0 lock remains unchanged

## Delta from RC1

RC2 deliberately does not change the Return Channel transport/schema contract. It rebuilds the already fixture-covered RC1 functionality against the current shared Core 0.5.0 and increments the candidate versionCode for a normal Magisk upgrade.

Core 0.5 contributes only generic browser-side observability primitives:

- session-local typed operation timeline;
- allowlisted/redacted safe diagnostics;
- global unsaved-area coordination;
- forward-compatible browser verification.

Core 0.5 adds no SDD remote execution path, no new adapter capability and no new server endpoint. Existing base-v1, v0.3 and v0.4 adapter contracts remain API-compatible.

The candidate must contain and pin the exact Core 0.5 assets `observability.js` and `observability.css`; floating `main` consumption is forbidden.

## RC1 runtime evidence carried forward

The first RC1 postboot run established exact candidate payload identity, healthy services/PIDs, CLI Return capability, Return retention safety, Core 0.4/v0.4 contract, Returns inventory, Sortify inventory, typed target collection, required-target readiness, ZeroPi2 intermittent handling, ntfy byte-preservation and standard-surface redaction.

That run is not treated as final installed-runtime acceptance because:

1. its sole failing assertion incorrectly required `ntfy-test` inside `capabilities-v03`; `ntfy-test` belongs to the base capability/action contract delegated through the v0.3 wrapper; and
2. the shared WebUI Core advanced from 0.4.0 to 0.5.0 after RC1 was built, which requires a rebuilt/reverified candidate under the shared sync policy.

The corrected postboot verifier must test ntfy configured-state/preservation separately from the base `ntfy-test` action declaration and must not send a notification during verification.

## Safety and compatibility

RC2 preserves all Return Channel v1 invariants from `RETURN_CHANNEL_V1.md` and `RETURN_CHANNEL_V1_RC1.md`:

- no host autoexecution;
- no arbitrary remote command transport or RPC;
- Pixel remains network initiator;
- outbound delivery state remains independent of Return/result state;
- exact origin/correlation/SHA verification remains mandatory;
- inbound data remains outside dispatch scan paths;
- stable v4.13.0 source/update lane remains untouched.

Repository CI must prove deterministic RC2 packaging, exact Core 0.5 pinning/assets, unchanged stable lane and the existing Return fixture matrix before any Pixel RC2 installation.
