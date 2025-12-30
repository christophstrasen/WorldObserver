# WorldObserver – Testing patterns

This document captures the de-facto testing patterns used in `tests/unit/` so contributors can add new tests without inventing new styles.

WorldObserver tests are written in Lua (5.1 compatible) using `busted` and run headless (no Project Zomboid engine).

## Running tests

From the repo root: 

```bash
busted tests
```

See `docs_internal/development.md` for tooling setup and the workshop smoke test (`pz_smoke.lua`).

## Where tests live

- Unit tests: `tests/unit/*_spec.lua`
- Engine-simulation smoke test: `pz_smoke.lua` (run via `./dev/smoke.sh`)

## Standard test bootstrap

Most specs start by expanding `package.path` so `require("WorldObserver/...")`, `require("LQR/...")`, and `require("reactivex")` resolve in plain Lua:

```lua
package.path = table.concat({
  "Contents/mods/WorldObserver/42/media/lua/shared/?.lua",
  "Contents/mods/WorldObserver/42/media/lua/shared/?/init.lua",
  "external/LQR/?.lua",
  "external/LQR/?/init.lua",
  "external/lua-reactivex/?.lua",
  "external/lua-reactivex/?/init.lua",
  package.path,
}, ";")
```

When a test loads WorldObserver or any facts that may log engine-related warnings, we set:

```lua
_G.WORLDOBSERVER_HEADLESS = true
_G.LQR_HEADLESS = true
```

If you are explicitly testing logging or engine-guard behavior, you can omit or override these (but keep it intentional and restore globals afterward).

## Common patterns (copy these)

### 1) “Pure” module tests (no engine stubs)

Examples: interest merging/policy, ingest scheduler behavior, helper edge cases.

Pattern:
- Require the module under test directly.
- Feed it plain Lua tables.
- Prefer deterministic inputs (no wall clock).

### 2) Record builder tests (`facts/<type>/record.lua`)

Goal: validate stable keys, required fields, and optional hydration fields.

Pattern:
- Stub the minimum “Iso*” surface as plain Lua tables with methods.
- Call `Record.makeXRecord(...)` with the minimum options required for the record shape.
- Assert key fields. `sourceTime` is stamped at ingest, so record builders should usually leave it `nil` unless explicitly overridden.

Examples in the suite:
- `tests/unit/items_record_spec.lua`
- `tests/unit/dead_bodies_record_spec.lua`
- `tests/unit/sprites_record_spec.lua`

### 3) Collector tests (square sweep collectors)

Goal: verify filtering + cooldown/dedup behavior without running probes or real events.

Pattern:
- Require the fact module (`WorldObserver/facts/<type>`).
- Build a `ctx` table with:
  - `state = {}` (collector state)
  - `emitFn = function(record) ... end` (capture emissions)
  - `headless = true`
  - any per-type `recordOpts`
- Call the collector directly via `_internal`:

```lua
Facts._internal.<collectorName>(ctx, cursor, square, playerIndexOrNil, nowMs, effective)
```

Examples:
- `tests/unit/items_collector_spec.lua`
- `tests/unit/dead_bodies_collector_spec.lua`
- `tests/unit/sprites_collector_spec.lua`

Notes:
- “Cooldown” tests typically call the collector twice with the same `nowMs` and expect no new emissions on the second call.
- Squares often provide `getX/getY/getZ/getID` and an object list getter (e.g. `getObjects`, `getWorldObjects`).

### 4) Observation stream tests (`observations/<type>.lua`)

Goal: validate that facts are wrapped into observations correctly, and helper sugar methods behave.

Pattern:
- Reload `WorldObserver` per test to isolate state:

```lua
local function reload(name)
  package.loaded[name] = nil
  return require(name)
end
```

- Subscribe to the observation stream:

```lua
local stream = WorldObserver.observations:<type>()
stream:subscribe(function(row) ... end)
```

- Push facts into the system using the test-only internal emit:

```lua
WorldObserver._internal.facts:emit("<type>", { ...record... })
```

- When testing `whereX(...)` helpers, assert that:
  - the predicate receives the raw record; and
  - the same record is attached as `observation.<SchemaName>` (e.g. `SquareObservation`, `ZombieObservation`, `SpriteObservation`).

Examples:
- `tests/unit/squares_spec.lua`
- `tests/unit/zombies_observations_spec.lua`
- `tests/unit/sprites_observations_spec.lua`

### 5) Record extender tests

Goal: ensure `register...Extender()` hooks are invoked and cleanly unregistered.

Pattern:
- Register an extender with a unique id.
- Call `makeXRecord(...)` and assert your extension fields exist.
- Unregister at the end of the test.

Example:
- `tests/unit/record_extenders_spec.lua`

### 6) Patch seam tests (override-friendly modules)

WorldObserver modules are designed to be patchable (functions defined behind `if <field> == nil then ... end`, and event handlers dispatch through module fields).

Pattern:
- Stub engine globals (`_G.Events`, `_G.getWorld`, etc.) before requiring the module (or use `reload()`).
- Replace a module field (e.g. `Facts.makeSquareRecord = function(...) ... end`) and assert the event path uses the patched function.
- Restore globals and patched fields in `after_each`.

Example:
- `tests/unit/patching_spec.lua`

### 7) Engine global stubbing (hydration, events, LuaEvents)

Some tests simulate engine entry points:
- `_G.Events.OnTick.Add` capture to invoke ticks manually.
- `_G.getWorld()` / `_G.getCell()` / `_G.getSpecificPlayer()` stubs for hydration.
- `_G.triggerEvent(ev, payload)` stubs to capture status reporting.

Pattern:
- Save the old global in `before_each`.
- Set your stub.
- Restore it in `after_each` (even when the test fails).

Examples:
- `tests/unit/runtime_spec.lua` (stubs `triggerEvent`)
- `tests/unit/rooms_player_change_spec.lua` (stubs `getSpecificPlayer`)
- `tests/unit/squares_spec.lua` and `tests/unit/patching_spec.lua` (stubs `getWorld`, `Events`)

## What to test when adding a new fact/observation type

When you add a new `type` (e.g. `sprites`), the usual expectation is to add/adjust:

- Record test: `tests/unit/<type>_record_spec.lua`
- Collector test (if it has a collector): `tests/unit/<type>_collector_spec.lua`
- Observation stream test: `tests/unit/<type>_observations_spec.lua`
- Record extender coverage: extend `tests/unit/record_extenders_spec.lua` if the record supports extenders
- Contract test should keep passing: `tests/unit/interest_definitions_contract_spec.lua` (ensures facts + observations are wired for all declared types)

If you change interest normalization/merging semantics, add or update:
- `tests/unit/interest_registry_spec.lua`

## Conventions / gotchas

- Keep tests deterministic: pass `nowMs = ...` instead of relying on `os.time()` whenever the code supports it.
- Prefer minimal stubs: only implement the methods your code calls.
- Always clean up: restore `_G` changes and patched module fields in `after_each` or at the end of the test.
- Internal APIs are fair game in unit tests: calling `._internal.*` is normal here, but treat it as unstable outside tests.
