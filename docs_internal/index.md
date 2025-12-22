# `docs_internal/` index

Internal documentation for contributors and maintainers.

**Rule of thumb**
- Files at `docs_internal/` root are intended to stay useful over time (guidance, current architecture, history).
- Files under `docs_internal/drafts/` are proposals/plans and may be stale.

## Start here (most useful)

- `docs_internal/vision.md` — permanent intent and “why”; use to sanity-check decisions.
- `docs_internal/code_architecture.md` — current IS architecture and contributor guardrails.
- `docs_internal/runtime_dynamics.md` — how runtime shaping works today (budgets, probes, draining).
- `docs_internal/fact_layer.md` — current fact layer implementation notes and boundaries.

## Workflow and support

- `docs_internal/development.md` — dev workflow, tests, workshop sync, smoke tests.
- `docs_internal/interest_combinations.md` — supported `type/scope/target` combinations (what code should accept).

## History and raw notes

- `docs_internal/logbook.md` — chronological decisions, changes, and lessons learned.
- `docs_internal/research.md` — API/event research scratchpad and links.

## Drafts (may be stale)

All proposal/design documents live in `docs_internal/drafts/`:

- `docs_internal/drafts/api_proposal.md` — public API proposal (MVP-era).
- `docs_internal/drafts/mvp.md` — MVP planning doc.
- `docs_internal/drafts/fact_interest.md` — interest declaration design brief.
- `docs_internal/drafts/runtime_controller.md` — runtime controller design draft.
- `docs_internal/drafts/using_ingest_system.md` — ingest integration plan (historical).
- `docs_internal/drafts/zombie_observations.md` — next-slice plan (zombies).
- `docs_internal/drafts/refactor_interest_definitions_and_sensors.md` — refactor runway brief.

