# v4.14.2 WebUI static asset parity repair (2026-11-11)

## Confirmed blocker

The installed v4.14.2 WebUI referenced `sdd-ui.css` and `sdd-ui.js` in `webroot/index.html`, but the pinned WebUI Core static HTTP allowlist in `Lycidias93/android-root-module-webui-template@81678604122636ad87a0f6d48eac1262a67154a4` explicitly serves only `index.html`, `app.js` and `app.css` through its general static route. During an isolated, authenticated loopback HTTP audit, `GET /sdd-ui.css` returned 404 even though the file existed. The release gate correctly stopped. A successful template integration test, module self-test or ZIP integrity check cannot override a page-referenced 404.

## Narrow, reproducible fix

The WebUI application shipped by this module is composed of an existing Core IIFE (`app.js`) and a second SDD-specific IIFE (`sdd-ui.js`) plus two stylesheets (`app.css` and `sdd-ui.css`). The deterministic v4.14.2 ZIP builder now appends the SDD-specific JS and CSS bytes to `app.js` and `app.css`, respectively, and removes only the two now-unneeded HTML references. The already allowlisted static endpoints serve the combined assets without any new HTTP route, privilege, file path or template API change. The unreferenced source overlays remain in the ZIP for provenance and exact comparison. The normal `/v03.js`, `/v04.js`, race-guard and observability URLs remain unchanged.

This is intentionally **module-specific packaging**, not a generic Core change: it uses the pinned Core's existing static contract, retains `webui-core.lock` and needs no new shared API. Avoid widening an HTTP file-serving allowlist globally for one module's optional overlay files. A future generic template composition helper may be proposed separately; this release does not introduce new framework behavior.

## Security and release boundaries

- Source: `tools/build_v4142_hotfix.py`; expected changes in the new candidate: `service.sh`, `module.prop`, `tools/sdd-followup-coalesce.sh`, `webroot/index.html`, `webroot/app.js`, `webroot/app.css`.
- The builder checks original baseline ZIP identity, single insertion anchors, independent IIFEs, exact bundled output readbacks, and reproducible builds. Regression fixtures reject missing overlays and repeated application; GitHub CI validates the actual candidate's HTML references and runs JS syntax checking.
- **New ZIP SHA-256 differs from the old on-device canary**. No new candidate can be claimed installed, active or release-approved solely because the underlying service script is unchanged.
- Required before public v4.14.2 release: exact-candidate installation and postboot identity, then the full root-manager-equivalent WebUI audit with authenticated GET and page-asset HTTP 200s, APIs and safe Settings GET -> POST -> GET/effective-state plus browser Save/reload. Confirm no production config or active dispatcher state regression.
- Do not create an immutable public tag/release or promote `update.json` until those gates pass. The original Pixel v4.14.2 state is preserved until the user authorizes/executes the modified ZIP installation through the device UI.
