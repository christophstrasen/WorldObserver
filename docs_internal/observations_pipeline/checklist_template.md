# Observation Family Checklist (Template v2)

Copy this file per new observation family/type and fill in the placeholders.

Goal of this checklist: lock down the *modder-facing contract* (interest surface + record schema + key stability), while keeping producer details and research optional.

---

## 1) Identity

- Observation goal (1 sentence): `[...]`
- Interest `type` (plural, stable): `[...]` (example: `vehicles`, `deadBodies`)
- Payload family key (singular, stable): `[...]` (example: `vehicle`, `deadBody`)
- Naming notes (why this name; avoided names): `[...]`
- Glossary impact:
  - ☐ No new terms
  - ☐ New term added to `docs/glossary.md` (only if unavoidable)

---

## 2) Implementation Status

- Status: ☐ idea ☐ prototyping ☐ in progress ☐ test-complete ☐ documented ☐ shipped
- Last updated (date): `[...]`
- Open tasks / blockers:
  - `[...]`
- Known risks / unknowns (perf/correctness/key-stability/hydration):
  - `[...]`

---

## 3) Modder UX (v0 contract)

- What does the modder want to accomplish (not implementation): `[...]`
- “Smallest useful” copy/paste example (declare interest + subscribe): `[...]`
- One intended derived stream / “situation” this base stream should enable (name it): `[...]`
- Non-goals / explicitly out of scope for v0:
  - `[...]`

---

## 4) Interest Surface (data-driven truth)

Define supported combinations and defaults first. This is the contract surface.

- Supported `scope` list: `[...]`
- Per-scope acquisition mode:
  - `scope = "..."`: ☐ listener-driven ☐ probe-driven ☐ mixed
- Targeting (only if applicable):
  - Allowed target keys: `[...]` (example: `player`, `square`)
  - Default target (if omitted): `[...]`
  - Merge/bucket behavior: `[...]`
- Settings and semantics (per scope):
  - `radius` (tiles): `[...]` (if applicable)
  - `staleness` (seconds, in-game clock): `[...]`
  - `cooldown` (seconds, in-game clock): `[...]`
  - other settings: `[...]`
  - `highlight` support: ☐ yes ☐ no ☐ partial (notes: `[...]`)
- Explicitly unsupported in v0 (so callers don’t guess): `[...]`

---

## 5) Fact Acquisition Plan (bounded)

Key rule: produce *small records* and call `ctx.ingest(record)` (don’t do downstream work in engine callbacks).

- Listener sources (engine callbacks / LuaEvents): `[...]`
- Probe sources (active scans): `[...]` (driver/sensor + scan focus)
- Bounding (how work is capped per tick / per sweep): `[...]`
- Failure behavior (missing APIs, nil/stale engine objects): `[...]`

---

## 6) Record Schema + Relations

Design constraints:
- Records are snapshots (primitive fields + best-effort hydration handles).
- Avoid relying on live engine userdata.

- Required fields (must exist on every record):
  - Identity: `[...]` (example: `vehicleId`, `zombieId`)
  - Spatial anchor (if applicable): `[...]` (example: `x/y/z`, tile coords)
  - Timing: `sourceTime` (ms, in-game clock; auto-stamped at ingest if omitted)
  - Provenance: `source` (string, producer/lane)
- Optional fields (cheap, high leverage): `[...]`
- Relations captured (just the identifying fields):
  - Relation: `[...]` → fields: `[...]`
- Hydration helpers used (reference existing helpers; don’t re-spec contracts here): `[...]`
- New helper(s) introduced (only if needed; contract in 3–6 bullets): `[...]`
- Record extenders (if any): `[...]` (extender name + namespacing guidance)

---

## 7) Key / ID and Stability Contract

- Primary key field(s): `[...]` (include fallback if needed)
- Stability:
  - Stable within session? ☐ yes ☐ no (notes: `[...]`)
  - Stable across save/load? ☐ yes ☐ no (notes: `[...]`)
  - Stable in MP? ☐ yes ☐ no (notes: `[...]`)
- Dedup/cooldown key:
  - Which field defines “same underlying fact” for cooldown? `[...]`
  - Any alternate stable anchor to prefer (example: `x/y/z` vs `squareId`): `[...]`

---

## 8) Stream Behavior (subscriber summary)

Keep this compact. It should summarize what section 5 implies for subscribers.

- Sources → emissions (per scope): `[...]`
- Primary stream dimension(s): `distinct("<dimension>", seconds)` → dedup key field(s): `[...]`
- Freshness + buffering: best-effort; may be delayed by ingest buffering; under load the effective settings may degrade
- Payload guarantees: base stream emits `observation.<family>`; hydration fields are best-effort and may be `nil`/stale

---

## 9) Helpers (minimum useful)

Keep helpers small, composable, and discoverable. Prefer record predicates + thin stream sugar.

- Required on every base observation stream:
  - `:<family>Filter(fn)` (example: `:vehicleFilter(fn)`) as the generic “custom predicate” escape hatch.
  - `:distinct("<dimension>", seconds)` with a documented base dimension so dedup is predictable.
- Record helpers (predicates/utilities + hydration): `[...]`
- Stream helpers (chainable sugar): `[...]`
- Effectful helpers (rare; clearly named): `[...]`
- Listed in docs (where): `[...]`

---

## 10) Debug + Verify (quick)

- `highlight` behavior (what gets highlighted): `[...]`
- “How to verify it works” steps (2–6 bullets):
  - `[...]`
- Example / smoke script path (if any): `Contents/mods/WorldObserver/42/media/lua/shared/examples/...`
- Smoke notes (PZ `require` paths, headless compatibility): `[...]`

---

## 11) Touchpoints (evidence you updated the system)

- Central truth (interest surface):
  - ☐ `WorldObserver/interest/definitions.lua` updated (if applicable)
  - ☐ `docs_internal/interest_combinations.md` updated (if applicable)
- Tests:
  - ☐ unit tests added/updated: `[...]`
  - ☐ headless command: `busted tests`
  - ☐ engine checks done (nil-safe, bounded per tick): `[...]`
- Documentation:
  - ☐ user-facing docs updated: `[...]`
  - ☐ internal docs updated: `[...]`
- Examples:
  - ☐ example / smoke script added/updated: `Contents/mods/WorldObserver/42/media/lua/shared/examples/...`
  - ☐ minimal smoke scenario described (1–3 bullets): `[...]`
- Logbook / lessons:
  - ☐ `docs_internal/logbook.md` entry added/updated (if meaningful): `[...]`

---

## Appendix (optional): Research notes

- PZWiki links consulted: `[...]`
- ProjectZomboidLuaDocs classes/methods used: `[...]`
- Events/hooks used (and exact payload shape if non-obvious): `[...]`
- Empirical checks run (console snippets / in-game test steps): `[...]`
- Open questions / uncertainties (and proposed minimal tests): `[...]`
