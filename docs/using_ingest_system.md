# Using the ingest system (WorldObserver)

WorldObserver’s integration plan for `LQR/ingest` lives in `docs_internal/using_ingest_system.md`.

That document describes:
- why we route facts through `LQR/ingest` (ingest → buffer → drain);
- the current integration approach (per-type buffers + one global scheduler); and
- the remaining work items for expanding to more fact types.

