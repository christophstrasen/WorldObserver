# New Base Observation Stream Checklist (Template)

Copy this file per new observation family/type and fill in the placeholders.

---

## Metadata

- Observation goal (1 sentence): `[...]`
- Interest `type`: `[...]` (example: `squares`, `deadBodies`)
- Observation payload family key: `[...]` (example: `square`, `deadBody`)
- Helper family key (if different): `[...]`
- Primary consumer(s) / situations enabled: `[...]`

---

## Implementation Status

- Status: ☐ idea ☐ prototyping ☐ in progress ☐ test-complete ☐ documented ☐ shipped
- Last updated (date): `[...]`
- Open tasks / blockers:
  - `[...]`
- Known risks (perf/correctness/staleness/hydration):
  - `[...]`

---

## 0) Problem Statement + Modder UX

- What does the modder want to accomplish (not implementation): `[...]`
- “Smallest useful” copy/paste example (declare interest + subscribe): `[...]`
- One intended derived stream / “situation” this base stream should enable (name it): `[...]`
- Non-goals / explicitly out of scope for v0: `[...]`

---

## 1) Naming + Vocabulary (get this right early)

- Interest `type` name rationale (plural, stable): `[...]`
- Payload family key rationale (singular, stable): `[...]`
- Avoided names (and why): `[...]`
- Glossary impact:
  - ☐ No new terms
  - ☐ New term added to `docs/glossary.md` (only if unavoidable)

---

## 2) Interest Surface (type / scope / target)

Define the supported combinations and settings first (data-driven truth).

- Supported `scope` list: `[...]`
- Per-scope acquisition mode:
  - `scope = "..."`: ☐ listener-driven ☐ probe-driven ☐ mixed
- Target rules (if applicable):
  - Allowed target keys: `[...]` (example: `player`, `square`)
  - Default target (if omitted): `[...]`
  - Merge/bucket behavior (what merges together, what does not): `[...]`
- Settings and semantics (per scope):
  - `radius` (tiles): `[...]`
  - `staleness` (seconds, in-game clock): `[...]`
  - `cooldown` (seconds, in-game clock): `[...]`
  - other settings (example: `spriteNames`, `zRange`): `[...]`
  - `highlight` support: ☐ yes ☐ no ☐ partial (notes: `[...]`)
- Surface updates (definitions/docs/tests): `[...]`

---

## 3) Fact Acquisition Plan (probes, listeners, sensors)

Key rule: produce *small records* and call `ctx.ingest(record)` (don’t do downstream work in engine callbacks).

- Listener sources (engine callbacks / LuaEvents): `[...]`
- Probe sources (active scans): `[...]` (driver/sensor + scan focus)
- Time-slicing + caps (how work is bounded): `[...]`
- Failure behavior (missing APIs, nil/stale engine objects): `[...]`

---

## 4) Record Schema (fields to extract)

Design constraints:
- Records are snapshots (primitive fields + best-effort hydration handles).
- Avoid retaining live engine userdata long-term.

- Required fields (must exist on every record):
  - Identity: `[...]` (example: `vehicleId`, `zombieId`)
  - Spatial anchor (if applicable): `[...]` (example: `x/y/z`, tile coords)
  - Timing: `sourceTime` (ms, in-game clock)
  - Provenance: `source` (string, producer/lane)
- Optional fields (cheap, high leverage): `[...]`
- Best-effort hydration fields (may be missing/stale): `[...]`
- Record extenders (if needed): `[...]` (extender name + namespacing guidance)

---

## 5) Primary Key / ID and Stability Contract

- Primary key field name: `[...]`
- Stability:
  - Stable within session? ☐ yes ☐ no (notes: `[...]`)
  - Stable across save/load? ☐ yes ☐ no (notes: `[...]`)
  - Stable in MP? ☐ yes ☐ no (notes: `[...]`)
- Dedup/cooldown key:
  - Which field defines “same underlying fact” for cooldown? `[...]`
  - Any alternate stable anchor to prefer (example: `x/y/z` vs `squareId`): `[...]`

---

## 6) Relation Fields + Hydration Strategy

Bias towards capturing enough identifying data to rehydrate, not storing engine objects.

- Relations to capture (examples: square, room, target player, container):
  - Relation: `[...]` → fields: `[...]`
- Hydration helpers (best-effort, safe `nil`):
  - Helper API location: `WorldObserver.helpers.<family>.record.*` or `[...]`
  - Caching behavior on record (if any): `[...]`
- Staleness strategy for relations:
  - When relation can be outdated, what do we do? `[...]`

---

## 7) Stream Behavior Contract (emissions + dimensions)

Keep this section compact. It should summarize what the acquisition plan (section 3) implies for subscribers.

- Sources → emissions (per scope): `[...]` (probe cadence via `staleness`, event bursts, both gated by `cooldown` where applicable)
- Primary stream dimension(s): `distinct("<dimension>", seconds)` → dedup key field(s): `[...]`
- Freshness + buffering: best-effort; may be delayed by ingest buffering; under load the effective settings may degrade (example: higher effective `staleness` / `cooldown`)
- Payload guarantees: base stream emits `observation.<family>`; hydration fields are best-effort and may be `nil`/stale

---

## 8) Minimum Useful Helpers

Keep helpers small, composable, and discoverable. Prefer record predicates + thin stream sugar.

- Required on every base observation stream:
  - `:<family>Filter(fn)` (example: `:vehicleFilter(fn)`) as the generic “custom predicate” escape hatch.
  - `:distinct("<dimension>", seconds)` with a documented base dimension (usually the family name) so dedup is predictable.

- Record helpers (predicates + hydration): `[...]`
- Stream helpers (chainable sugar): `[...]`
- Effectful helpers (rare): `[...]`
- Listed in docs: `[...]` (where)

---

## 9) Debugging + Highlighting

- Interest-level `highlight` behavior (what gets highlighted): `[...]`
- Optional marker/label support (if applicable): `[...]`
- “How to verify it works” steps for modders: `[...]`

---

## 10) Verification: Tests (headless) + Engine Checks

- Unit tests added/updated: `[...]` (record, acquisition, stream, contract)
- Headless test run command: `busted tests`
- Engine verification checklist: `[...]` (API confirmed, nil-safe, bounded per tick)

---

## 11) Documentation (user-facing + internal)

- User-facing docs updated: `[...]`
- Internal docs updated: `[...]`

---

## 12) Showcase + Smoke Test

- Example script added/updated (where): `Contents/mods/WorldObserver/42/media/lua/shared/examples/...`
- Minimal smoke scenario (“how to see it in action quickly”): `[...]`
- Smoke test notes: `[...]` (PZ `require` paths, headless compatibility)

---

## Research & Brown Bag (keep at bottom)

### Research notes (sources + findings)

- PZWiki links consulted: `[...]`
- ProjectZomboidLuaDocs classes/methods used: `[...]`
- Events/hooks used (and exact payload shape if non-obvious): `[...]`
- Empirical checks run (console snippets / in-game test steps): `[...]`
- Open questions / uncertainties (and proposed minimal tests): `[...]`

### Brown bag session (internal sharing)

- Audience: ☐ WO contributors ☐ mod authors ☐ mixed
- Duration: `[...]` minutes
- Agenda (3–5 bullets):
  - `[...]`
- Live demo script / save setup: `[...]`
- “Gotchas” to highlight (staleness vs cooldown, id stability, hydration pitfalls): `[...]`
- Performance notes (what costs, what mitigations, recommended defaults): `[...]`
