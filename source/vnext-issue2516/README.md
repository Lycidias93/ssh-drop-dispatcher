# Dispatcher tool synchronization candidate

Source-only follow-up to Heimnetz issue #2516. Derived from the published
v4.14.2 service, SHA-256 c1a54cd7fb0ceafc973adccc195494b41ae577131e04a9ee406424f58165b583.
The original release source and existing release builders are deliberately
unchanged.

The candidate skips writes when a module-owned runtime tool is byte-identical
and mode 0755. Missing, changed or wrong-mode regular files are copied to a
same-directory temporary file and renamed atomically. Symlink and directory
destinations are rejected; failures preserve the previous destination and are
logged. No SSH/trust configuration, dispatch cadence, or delivery semantics
are changed by this candidate.

Run the isolated tests with:
`python3 -m unittest discover -s tests -p verify_guarded_module_tool_sync.py -v`.

Not a published or installed release. A future versioned builder and live
delivery/latency acceptance are separate gates.
