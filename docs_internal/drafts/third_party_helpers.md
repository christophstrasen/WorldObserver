# Proposal: third-party helper sets (QoE like built-in helpers)

Goal: let modders bring their own helper sets (or share them as “helper mods”) and get a similar experience to built-in helpers:
- chainable stream methods (optional, low boilerplate)
- safe namespacing to avoid collisions (`stream.helpers.<family>`)
- works for **derived streams** (multi-family) and base streams
- “last one wins” is acceptable (no complex merge semantics)

Non-goals (for this proposal):
- no dependency solver / explicit versioning
- no multi-mod conflict resolution beyond “last wins”
- no new “capability system” beyond enabling a helper family + target schema key

---

## 1) Current state (today)

### What works today
- Built-in streams declare `enabled_helpers` on the **producer side** (WO stream authors), and WO attaches:
  - fluent stream methods (e.g. `:squareHasCorpse()`)
  - helper namespaces (e.g. `stream.helpers.square:squareHasCorpse(...)`)
- Derived streams (built via `WorldObserver.observations:derive`) automatically union helper families from their input streams and attach `stream.helpers.<family>`.
- Mods can override existing helpers by patching `WorldObserver.helpers.<family>.stream.<name>` / `.record.<name>` (patch seams already exist), but this doesn’t retroactively add fluent methods to already-built streams.

### Pain points
- There is no clean “attach my helper set to this stream” API.
- If a helper needs a schema key override, it’s currently possible only via `stream.helpers.<family>:helper("<schemaKey>", ...)` (advanced and easy to misuse because base streams use pre-`selectSchemas` internal keys).
- There is no public “register helper family” mechanism that updates WO’s helper registry and makes it easy to reuse across streams.

---

## 2) Proposed UX: two ways to use third-party helpers

### A) Namespaced (recommended default)

Always available, minimal risk of collisions:

```lua
local WorldObserver = require("WorldObserver")
local UnicornHelpers = require("YourMod/helpers/unicorns")

local stream = WorldObserver.observations:squares()
  :withHelpers({
    helperSets = { unicorns = UnicornHelpers },
    enabled_helpers = { unicorns = "square" },
  })

-- Call helpers via namespace.
stream.helpers.unicorns:unicorns_nearPlayer(10)
```

### B) Fluent chainable methods (also available)

We attach helper methods as direct stream methods by default. If the helper author
follows the “family prefix” convention (`unicorns_*`, `time_*`, …), collisions
should be rare and the chain reads naturally:

```lua
local stream = WorldObserver.observations:squares()
  :withHelpers({
    helperSets = { unicorns = UnicornHelpers },
    enabled_helpers = { unicorns = "square" },
  })

-- Calls `UnicornHelpers.stream.unicorns_nearPlayer(stream, <schemaKey>, 10)`
stream:unicorns_nearPlayer(10)
```

If a method name collides, **last wins** (explicitly acceptable in this proposal).

---

## 3) Proposed public API

### 3.1 `ObservationStream:withHelpers(opts)`

Returns a new stream that shares the same underlying LQR builder but has extra helper families attached.

```lua
---@param opts table|nil
--- opts.helperSets: table<string, table>|nil -- { familyName = helperSet, ... }
--- opts.enabled_helpers: table<string, boolean|string>
function ObservationStream:withHelpers(opts) end
```

Semantics:
- Always attaches `stream.helpers.<family>` namespace proxies.
- Always attaches fluent stream methods (same QoE as built-in helpers).
- `opts.enabled_helpers` controls what schema key each helper family reads from.
- Collisions are “last wins”.

### 3.2 `enabled_helpers` value resolution (reduce boilerplate)

Today, `enabled_helpers.<family>` ultimately needs a schema key (the key LQR uses inside `where` predicates).

Proposal: allow these values:
- `true`: “use the family’s default” (same as today for built-in streams).
- `"<schemaKey>"`: explicit schema key (advanced).
- `"<otherFamily>"`: alias to another family’s schema key mapping (simple and usually what modders want).

Example:

```lua
-- “unicorn helpers operate on the same record as square helpers”
enabled_helpers = { unicorns = "square" }
```

This avoids forcing modders to know internal keys like `"SquareObservation"` for base streams.

### 3.3 `WorldObserver.observations:registerHelperFamily(family, helperSet)`

Sugar for “helper mods” that want to publish a family globally (so other code can reference it by family name):

```lua
WorldObserver.observations:registerHelperFamily("unicorns", UnicornHelpers)
```

Semantics:
- Registers the helper set in the internal observation registry (`helperSets[family] = helperSet`, last wins).
- Does not attempt to mutate already-built streams; use `:withHelpers(...)` for per-stream attachment.
- Optionally (implementation choice): also sets `WorldObserver.helpers[family] = helperSet` as a discoverability convenience.

---

## 4) Schema-key correctness (base vs derived streams)

Core issue:
- Base streams run helper predicates *before* `selectSchemas`, so schema keys look like `"SquareObservation"`.
- Derived streams built from `:getLQR()` are rooted at post-`selectSchemas` aliases, so schema keys are `"square"`, `"zombie"`, etc.

The alias resolution above (`enabled_helpers.unicorns = "square"`) is intended to make this “just work”:
- on base streams it resolves to the correct internal schema key
- on derived streams it stays on the public alias

This also keeps the “advanced escape hatch” valid:

```lua
-- Advanced: force a schema key explicitly.
stream.helpers.unicorns:unicorns_nearPlayer("SquareObservation", 10)
```

---

## 5) Helper authoring conventions (minimal rules)

Helper set table shape:
- `HelperSet.stream.<fnName>(stream, schemaKey, ...) -> ObservationStream`
- `HelperSet.record.<fnName>(record, ...) -> any`
- `HelperSet.<fnName>` for effects/utility (not attached to streams)

Recommended naming (to avoid collisions when fluent methods are attached by default):
-- Prefix every stream helper with the family name, e.g. `unicorns_nearPlayer`, `time_recent`, `sprite_isHedge`, …

---

## 6) Open questions / decisions

1) Direct helper attachment (fluent methods)
  Decision: helpers are always attached as fluent methods; no opt-out knob.
2) Do we want `:withHelpers(...)` on **all** streams (base + derived) or only derived at first?
  Answer: Of course it should be possible to attach entirely new and different helpers also to base streams
3) Do we want to expose `WorldObserver.observations:registerHelperFamily(...)` instead of `WorldObserver.helpers:registerFamily(...)` (or both)?
  Answer: Only one version `registerHelperFamily`

---

## 7) Implementation plan (incremental)

### Step 0: runway (avoid code duplication)

We already have helper attachment logic in `WorldObserver/observations/core.lua`:
- build direct helper methods (delegators)
- build helper namespaces (`stream.helpers.<family>`)

Before adding any new API surface, extract a single internal “attach helpers to stream” function that:
- takes `helperSets` + `enabled_helpers`
- returns `{ helperMethods, helperNamespaces, resolved_enabled_helpers }`

This keeps `register(...)`, `derive(...)`, and the new `withHelpers(...)` all sharing the same codepath.

### Step 1: represent helper compatibility on streams (already mostly done)

Ensure every ObservationStream carries:
- `_helperSets` (registry of helper families available)
- `_enabled_helpers` (mapping family -> schema key used for predicates)

Derived streams should keep the “output schema alias” behavior for `_enabled_helpers` (e.g. `zombie = "zombie"`), while base streams keep the internal schema key mapping (e.g. `square = "SquareObservation"`).

### Step 2: implement `ObservationStream:withHelpers(...)`

Add `withHelpers` as a normal stream method (colon-style) that returns a new ObservationStream:
- merge/override helper sets (`last wins`)
- resolve `opts.enabled_helpers` (see Step 3)
- rebuild direct helper methods + namespaces from the merged config
- keep the same `_builder`, `_factRegistry`, `_factDeps`, `_dimensions`

### Step 3: implement `enabled_helpers` alias resolution (smooth UX)

Allow `opts.enabled_helpers.<family> = "<otherFamily>"` to mean:
“use whatever schema key `<otherFamily>` is already mapped to on this stream”.

Example:
- base squares stream has `_enabled_helpers.square = "SquareObservation"`
- mod attaches unicorn helpers with `enabled_helpers.unicorns = "square"`
- resolved mapping becomes `_enabled_helpers.unicorns = "SquareObservation"` (correct for LQR where predicates)

For derived streams, the same alias resolves to `"square"` (also correct).

### Step 4: add `WorldObserver.observations:registerHelperFamily(...)`

Implement as a method on the observations API table (colon-only):
- stores `helperSets[family] = helperSet` in the underlying observation registry (last wins)
- optional: also mirror to `WorldObserver.helpers[family]` for discoverability

This enables “helper mods” that publish helper families for other mods to consume without passing the table around.

### Step 5: tests

Add unit tests that cover:
- attaching a brand-new helper family to a base stream via `:withHelpers(...)` and calling it fluently
- alias resolution (`enabled_helpers.unicorns = "square"`) works for base streams and derived streams
- `registerHelperFamily` makes a family usable by name (for subsequent `withHelpers` calls that reference it)

### Step 6: documentation

User-facing docs should describe:
- preferred usage: `stream.helpers.<family>:...` (multi-family-safe)
- fluent methods are available by default (but recommend family-prefixed naming for helper authors)
- how to ship a helper family as a helper-mod using `registerHelperFamily`
