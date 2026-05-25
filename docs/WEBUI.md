# WebUI

SSH Drop Dispatcher includes a lightweight `webroot` for WebUI-capable module managers and an `action.sh` fallback for managers that expose a module action button.

The WebUI is intentionally small and public-safe. It can run status/doctor/config-list when the manager exposes a root exec bridge. If root exec is not available, use Termux:

```sh
dispatch-config
```
