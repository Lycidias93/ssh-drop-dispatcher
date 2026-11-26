# V4.14.4 strict-prefix scan candidate

Follow-up to Heimnetz #2516, derived from the exact V4.14.3 guarded-tools source. In strict-prefix mode only case-insensitive target-/targets-prefixed regular files enter the existing queue candidate checks; legacy mode keeps full enumeration. Both target-only scans use one directory traversal. The existing scan lock, queue validation, inflight, remote hash verification, retry/quarantine and trust configuration remain unchanged.

Cloud1 synthetic fixture: 1,000 unrelated text files plus valid, invalid, mixed-case, multi-target, partial, sidecar, directory and symlink cases. Strict and legacy candidate selection matched the baseline. This does not establish device latency, CPU savings or full delivery acceptance.

Build the exact candidate with `python3 tools/build_v4144_strict_scan.py --base BASE_V4143.zip --output CANDIDATE.zip`. Source SHA-256 db5cddbed700d41b55245dbe282a08375e3c83e4e50fb4b08875d17459a1f563. Candidate ZIP SHA-256 8107e07359cbb2d1513828a9ae2665bb700213bedd75223e071027882be0b575. The original V4.14.3 ZIP remains the immediate rollback baseline. Both base and candidate must be hash-verified. The 42-entry deterministic overlay changes only service.sh and module.prop.

Not installed or released. Exact owner install approval, postboot latency <=60 s, delivery integrity, WebUI release audit (dispatch-now adapter depends on scan behavior) and separate release approval remain required. No update-channel promotion.
