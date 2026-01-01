# Helpers (internal architecture)

This document describes how helpers work in WorldObserver: what they are for, how we classify them, how the built-in helper system is implemented, and how third parties extend it.

This is intentionally internal documentation for WO maintainers. User-facing guidance lives in `docs/observations/stream_basics.md` and the per-family observation docs.

## Conventions (read first)

These conventions exist to keep helpers predictable and to avoid “API headaches” as soon as we have derived streams (multiple payload families in one observation).

- **Prefer collision-safe calls in derived streams:** always use `stream.helpers.<family>:<fn>(...)` in derived-stream examples and internal docs. Flat stream methods share one namespace; collisions are “first wins”.
- **When adding a new helper, assume collisions are possible:** if a name could plausibly exist on multiple families (example: `hasOutfit`, `highlight`, `isInside`, `isAlive`), prefer providing a family-prefixed stream method (example: `zombieHasOutfit`) and treat any unprefixed alias (example: `hasOutfit`) as optional sugar.
- **Avoid “same thing twice”:** if a record contract already contains a boolean field (example: `squareRecord.hasCorpse`), do not ship a record helper that just returns that value.

## 1) Intent (modder UX)

Helpers exist to give modders **quick, easy access to high-leverage operations** on observations.

We want helpers to cover three core jobs:

1) **Filter / refine streams easily**
- Domain vocabulary over raw predicates: `:squareHasCorpse()`, `:spriteNameIs(...)`, `:distinct("sprite", seconds)`.
- Still composable: helpers should read well in chains and return refined streams by default.

1) **Understand an observation quickly**
- Provide small record-level predicates/utilities and (when necessary) best-effort hydration/caching so mod code can ask “what is this?” safely.

1) **Do a direct action when appropriate**
- Some helpers are intentionally effectful (e.g. removing an associated tile object, highlighting). These should be rare, explicit, best-effort, and safe to call even when prerequisites are missing.

Non-goals:

- Helpers should not introduce new schemas or “secret joins”. Joins/enrichment live in derived streams or direct LQR usage.
- Helpers should not hide subscriptions or start background work unexpectedly.
- Helpers should not require global flags or “magic configuration” to be useful; they should be obvious, local, and discoverable.

## 2) Helper taxonomy (classification)

### 2.1 Helper family (attachable unit)

A **helper family** is the attachable unit of helpers, identified by a string key like `square`, `zombie`, `sprite` (and third-party families like `unicorns`).

A family is a domain grouping, not a “kind” of helper: a single family typically contains stream helpers + record helpers + (sometimes) utilities.

Helper families are **not necessarily 1:1** with observation payload families.

- Built-in families are usually aligned with the payload family they operate on (`square` helpers operate on `observation.square`, etc.).
- But the system intentionally allows a helper family to target *any* record in an observation, via `enabled_helpers`. Example: a third-party `unicorns` family can operate on square records with `enabled_helpers = { unicorns = "square" }`.

The family key is used in:
- `enabled_helpers` (which families are attached and what observation field/schema key they should read)
- `WorldObserver.helpers.<family>` (built-in families that we ship)
- `WorldObserver.observations:registerHelperFamily(family, helperSet)` (third-party registration)
- `stream.helpers.<family>` (namespaced access to attached helpers)

### 2.2 Helper set (implementation)

A **helper set** is the Lua table that implements a family. By convention it can contain:

1) **Stream helpers** (`helperSet.stream.<fn>`)  
These are the functions WorldObserver attaches to `ObservationStream`s.

- Implementation signature: `helperSet.stream.<fn>(stream, fieldName, ...)`
  - `fieldName` is the observation field/schema key the helper should read from (bound by `enabled_helpers`).
- User-facing calls:
  - `stream:<fn>(...)` (flat, ergonomic chaining), and/or
  - `stream.helpers.<family>.<fn>(...)` (namespaced; avoids collisions).

2) **Record helpers** (`helperSet.record.<fn>`)  
These operate on the per-entity record table (e.g. `observation.sprite`, `observation.square`).

- Typical signature: `helperSet.record.<fn>(record, ...)`
- Intended usage:
  - inside `:squareFilter(...)` / `:zombieFilter(...)` / `:spriteFilter(...)` predicates
  - inside Rx `:filter(...)` after `:asRx()`
  - called by stream helpers internally

Record helpers are usually pure predicates, but they may also do best-effort hydration/caching (and mutate the record to cache engine references).

3) **Family utilities** (`helperSet.<fn>` at the top level)  
These are helper functions that are part of the family but are not attached to streams automatically (attachment prefers `helperSet.stream`).

Example: `WorldObserver.helpers.square.highlight(...)` is part of the `square` family but is not a stream method.

### 2.3 Utility modules (not families)

Some helper-like modules are internal utilities and are not attachable via `enabled_helpers`:
- `DREAMBase/time_ms.lua` (shared time helpers)
- `WorldObserver/helpers/safe_call.lua`
- `WorldObserver/helpers/java_list.lua`
- `WorldObserver/helpers/highlight.lua` (used by multiple families)

### 2.4 `enabled_helpers` (binding helpers to observation fields)

`enabled_helpers` maps helper family name to the schema key / field name that exists at predicate time (i.e. what LQR `:where(...)` predicates see when WO helpers add filters/distinct).

This is what lets the same helper family work across:
- base streams (which often start with internal schema keys, then `selectSchemas` into public aliases), and
- derived streams (which usually operate on already-aliased output schemas).

## 3) Built-in helpers (WorldObserver internals)

### 3.1 Where helpers live

- Built-in families live in `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/helpers/*.lua`.
- `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver.lua` exposes them as `WorldObserver.helpers.<family>`.

### 3.2 How helpers attach to streams

There are two “sides” that must line up:

- Producer side (WO stream authors)
  - Streams declare `enabled_helpers` at registration time.
  - The build function ensures the observation row contains the fields helpers will read (often via `:selectSchemas({ SpriteObservation = "sprite" })`).
- Consumer side (modders)
  - Mod code calls helpers on streams.

Attachment mechanism (implemented in `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/observations/core.lua`):

1) **Flat stream methods** (ergonomic chaining)
- Every function in `helperSet.stream` is available as `stream:<fn>(...)`.
- All families share one flat method namespace; collisions are “first wins”.

2) **Namespaced helpers** (explicit, no collisions)
- For each enabled family, WorldObserver also provides `stream.helpers.<family>.<fn>(...)`.
- These methods always target the correct field/schema key for that family.

### 3.3 Principles (behavior, hydration, logging)

Default behavior: helpers should be “reducing operators”.

- Return a new refined stream (filter/dedup/reshape).
- Avoid global state.
- Avoid hidden subscriptions.

Supported exceptions:

- **Hydration/caching (best-effort)**  
  Example: `SquareHelpers.record.getIsoGridSquare(record, opts)` validates and rehydrates, and may cache the result back onto the record.  
  Requirements:
  - never throw; use `pcall` where needed
  - document caching/hydration behavior

- **Effectful helpers (rare)**  
  Example: `SpriteHelpers.stream.removeSpriteObject()` calls `IsoGridSquare:RemoveTileObject(IsoObject)` as a side effect.  
  Requirements:
  - best-effort (`pcall`) and safe when prerequisites are missing
  - warnings should be actionable; if spam is likely, point users to `:distinct(...)`

Logging rule of thumb:
- `info` only for meaningful, low-volume successes (or when explicitly requested).
- `warn` for recoverable missing prerequisites (e.g. missing `IsoGridSquare` / missing `IsoObject`).

	### 3.4 Naming conventions (stream helpers)

	These conventions were originally captured in `docs_internal/drafts/api_proposal.md` and are treated as the intended direction:

	- Prefer fluent predicate names: `squareHasCorpse()`, `zombieHasTarget()`, `roomHasWater()`.
	- Use `<family>Filter(...)` for the generic “accept a predicate” helpers: `squareFilter(fn)`, `zombieFilter(fn)`, etc.
	- Use `*Is*` for simple flags/enums on an entity; use `*Has*` for relationships/lookups into collections.
	- **Naming by effect:**
	  - Read/filter helpers should follow `<family><PredicateOrReadAction>` (e.g. `spriteNameIs`, `squareHasCorpse`, `squareFilter`).
	  - Effectful helpers should lead with the verb/action and include the family noun (e.g. `removeSpriteObject`, `highlightSquare`).

	Naming reality:
	- Built-in families often omit the family prefix for ergonomics (`:spriteNameIs(...)` not `:sprite_spriteNameIs(...)`).
	- Because flat method names collide across families (especially in derived streams), `stream.helpers.<family>` is the preferred “no ambiguity” access path.
	- Internal docs and derived-stream docs should default to the namespaced form.

### 3.4.1 Record booleans vs record helpers (avoid “same thing twice”)

If a record already has a clear boolean field that is part of the record contract (example: `squareRecord.hasCorpse`), we should **not** also ship a record helper that returns the same value (example: `SquareHelpers.record.squareHasCorpse(squareRecord)`).

Rationale:
- It adds cognitive load (“is the helper doing anything extra?”) without adding value.
- It creates naming ambiguity and encourages style drift (field vs helper).
- It blocks future ergonomic options that depend on `__index` methods (field names shadow methods in Lua).

Rule of thumb:
- **Record fields** are the canonical, stable truth (“facts we already extracted”): use `record.hasCorpse == true` directly.
- **Record helpers** should exist only when they compute/derive/hydrate/normalize (example: `getIsoGridSquare`, `roomLocationFromIsoRoom`, `zombieHasOutfit` pattern matching).
- **Stream helpers** may still provide fluent filters that read those fields (example: `stream:squareHasCorpse()` filters on `square.hasCorpse == true`).

### 3.5 Built-in families we ship (today)

Registered on `WorldObserver.helpers`:
- `square` (`WorldObserver/helpers/square.lua`)
- `zombie` (`WorldObserver/helpers/zombie.lua`)
- `room` (`WorldObserver/helpers/room.lua`)
- `item` (`WorldObserver/helpers/item.lua`)
- `deadBody` (`WorldObserver/helpers/dead_body.lua`)
- `sprite` (`WorldObserver/helpers/sprite.lua`)

Utility modules used by families:
- `WorldObserver/helpers/highlight.lua`
- `DREAMBase/time_ms.lua`
- `WorldObserver/helpers/safe_call.lua`
- `WorldObserver/helpers/java_list.lua`

### 3.6 Patch seams (mod-friendly helpers)

Helper modules follow a “patch seam” convention:
- reuse `package.loaded[moduleName]` so reloads don’t clobber patches (useful for tests/console reloads)
- only assign exported functions when the field is currently `nil` (so other mods can override by reassignment)

This allows other mods to override helpers by reassigning function fields without metatables.

## 4) Extending helpers (3rd parties)

Third-party helper families should feel as close as possible to built-ins, but they differ in one key way: they must be attached/registered by user code.

### 4.1 Attaching a helper family to a stream (`:withHelpers`)

There are two supported attachment paths:

1) **Per-stream helperSets**

```lua
local stream = WorldObserver.observations:squares():withHelpers({
  helperSets = { unicorns = UnicornHelpers },
  enabled_helpers = { unicorns = "square" },
})
```

2) **Global registration + enable by name**

```lua
WorldObserver.observations:registerHelperFamily("unicorns", UnicornHelpers)
local stream = WorldObserver.observations:squares():withHelpers({
  enabled_helpers = { unicorns = "square" },
})
```

Notes:
- “Last same name wins” when helper sets are merged/registered.
- Flat method name collisions are still “first wins”; `stream.helpers.unicorns` avoids collisions entirely.

### 4.2 Alias resolution for `enabled_helpers`

To reduce boilerplate when attaching third-party families, `:withHelpers({ enabled_helpers = ... })` supports aliasing:

- `enabled_helpers.<family> = true` means: use this stream’s default schema key for `<family>` (or `<family>` itself if none exists yet).
- `enabled_helpers.<family> = "<otherFamily>"` means: target whatever schema key this stream uses for `<otherFamily>`.
  - Base stream example: `_enabled_helpers.square == "SquareObservation"` so `enabled_helpers.unicorns = "square"` resolves to `"SquareObservation"`.
  - Derived stream example: `_enabled_helpers.square == "square"` so the same config resolves to `"square"`.
- `enabled_helpers.<family> = "<schemaKey>"` means: use the explicit schema key directly (avoid unless you truly need it).

### 4.3 Naming guidance for third-party helpers

Because flat stream methods share a single namespace, third-party helpers should prefer either:
- names that include the family prefix (e.g. `unicorns_squareIdIs(...)`), or
- using `stream.helpers.<family>.<fn>(...)` in examples/docs to avoid collisions.

Third-party helpers should follow the same behavioral principles as built-ins (reducing operators by default, best-effort hydration only when necessary, effectful helpers only when clearly named and documented).
