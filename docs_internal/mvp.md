# WorldObserver – MVP plan

Internal planning doc for the first concrete WorldObserver implementation
slice. This complements `docs_internal/vision.md`, `docs_internal/api_proposal.md`,
and `docs_internal/fact_layer.md` and is allowed to be more opinionated and
pragmatic.

The guiding idea: **ship one high-quality vertical slice for squares only**,
then grow outwards.

---

## 1. MVP scope and goals

### 1.1 Scope (what MVP includes)

- **World type coverage**
  - Facts and observations for **squares only**.
  - No first-class facts/streams for rooms, zombies, vehicles, etc. yet
    (examples in other docs remain aspirational for later slices).

- **Fact layer**
  - A concrete, runnable **fact plan for squares** using:
    - Event listener(s) for `OnLoadGridsquare`.
    - One “balanced” probe strategy near players (see section 4).
  - Strategy selection exists only for squares and only supports a `"balanced"`
    strategy in MVP.

- **ObservationStreams**
  - `WorldObserver.observations.squares()` returning a stream of square
    observations (`SquareObservation` payload under `observation.square`).
  - A minimal **square helper set**, wired via `enabled_helpers`, that is
    actually implemented in MVP (for example):
    - `:squareHasBloodSplat()`
    - `:squareNeedsCleaning()`
  - Core stream methods:
    - `:subscribe(function(observation) ...)`
    - `:distinct(dimensionName, seconds)`
    - `:filter(function(observation) ...)`
    - `:getLQR()` (advanced escape hatch, thin wrapper over LQR).

- **Config & debug surface**
  - `WorldObserver.config.facts.squares.strategy` with only `"balanced"`
    supported.
  - A minimal debug/logging hook surface (even if only stubs) consistent with
    `api_proposal.md` (e.g. `WorldObserver.debug.describeFacts("squares")` is
    allowed to be a simple logger in MVP).

- **Documentation & typing**
  - Internal docs in `docs_internal/*` updated to match what is actually
    implemented for squares.
  - EmmyLua annotations for the public MVP API surface so mod authors get
    decent completion/hover help.

### 1.2 Non-goals for MVP

See section 7 (“Must-nots and guardrails”) for an explicit list. In short:
no Situation layer, no GUI, no multi-type streams beyond what’s strictly
needed to support the squares slice.

---

## 2. Module and file layout (MVP)

MVP keeps the existing `WorldObserver` entry point but introduces a structured
module tree under the shared Lua path.

Paths are relative to the mod’s shared Lua root:
`Contents/mods/WorldScanner/42/media/lua/shared/`.

```text
WorldObserver.lua                  -- single public entry; require("WorldObserver")
WorldObserver/
  config.lua                       -- WorldObserver.config defaults & validation

  facts/
    registry.lua                   -- fact-type registry & scheduler wiring
    squares.lua                    -- fact plan for squares (listeners + probes)

  observations/
    core.lua                       -- ObservationStream type + register() logic
    squares.lua                    -- registration for observations.squares()

  helpers/
    square.lua                     -- square helper set (squareHasBloodSplat, etc.)

  debug.lua                        -- domain-level debug helpers (describeFacts/describeStream) built on LQR logging
```

Notes:

- `WorldObserver.lua` is the only public façade for `require("WorldObserver")`
  and is responsible for constructing and returning the WorldObserver table.
- `facts/registry.lua` owns:
  - registering fact types (starting with `squares`);
  - wiring listeners/probes into a central scheduler; and
  - exposing a minimal API used by `observations/*` to subscribe to fact
    streams.
  - `observations/core.lua` owns:
    - the internal `ObservationStream` type;
    - `WorldObserver.observations.register(name, opts)`; and
    - attaching helper sets based on `enabled_helpers`.
- `helpers/*` modules are **pure sugar** over streams; they do not own any
  fact generation or schema registration.
- `debug.lua` provides domain-level debug helpers on `WorldObserver.debug` and
  may call into `LQR.util.log` and other LQR utilities internally; other
  modules should usually log through `WorldObserver.debug` rather than
  talking to LQR directly.

MVP should not introduce additional modules beyond this outline without
explicit discussion (see must-nots).

---

## 3. Observation schemas (squares only)

### 3.1 Naming

- LQR schemas use full names:
  - `SquareObservation`
  - Future: `RoomObservation`, `ZombieObservation`, etc. (not implemented in MVP).
- Individual emissions in a stream are treated as a single **observation**
  and passed as a table named `observation` (singular) to callbacks.
  - `observation.square` is a `SquareObservation`.

### 3.2 `SquareObservation`

Initial schema for square facts, designed to support the MVP helpers and
examples. Fields may evolve in future slices, but MVP should implement at
least the following:

```lua
---@class SquareObservation
---@field squareId integer          -- semi-stable ID for the square (may be derived, may not survive a game reload)
---@field square IsoSquare          -- reference to the IsoSquare object. No guarantees that it remains loaded and accessible
---@field x integer                 -- world X coordinate
---@field y integer                 -- world Y coordinate
---@field z integer                 -- world Z level
---@field hasBloodSplat boolean?    -- true if any blood decal is present
---@field hasCorpse boolean?        -- true if a corpse is present
---@field hasTrashItems boolean?    -- true if items considered "trash" are present
---@field observedAtTimeMS number?  -- game time (timeCalendar:getTimeInMillis())
---@field source string?            -- optional: "event" | "probe" (diagnostic)
```

Notes:

- MVP does not need to fully define “trash items” yet; it is enough that the
  field is present and used by `squareNeedsCleaning()`.
- Additional derived fields (e.g. room IDs, zone tags) are deferred until we
  add more world types.

### 3.3 Per-emission observation shape

For the squares MVP, emissions from `WorldObserver.observations.squares()` are
tables of the form:

```lua
---@class Observation
---@field square SquareObservation
---@field _raw_result any?  -- optional LQR join result, advanced only
```

Callbacks see this as:

```lua
stream:subscribe(function(observation)
  -- observation.square is a SquareObservation
end)
```

Future multi-type streams will extend the emission shape with additional
fields (e.g. `observation.room`), but MVP implements only `square`.

---

## 4. Fact layer slice for squares

This section specializes the generic fact layer design for **squares** in the
MVP. Only the `"balanced"` strategy is implemented; others remain design
sketches.

### 4.1 Strategies (MVP)

- `WorldObserver.config.facts.squares.strategy`:
  - Supported in MVP: `"balanced"`.
  - Unsupported but reserved for later: `"gentle"`, `"intense"`.
- If an unsupported strategy is configured, MVP errors loudly during startup.
  Strategy selection remains an **advanced** surface, not heavily documented
  for users yet.

### 4.2 Events and probes (balanced strategy, squares)

High-level table for the `"balanced"` squares plan:

| Source type | Name                     | Included in `"balanced"` | Purpose                                                     |
|------------|--------------------------|--------------------------|-------------------------------------------------------------|
| Event      | `OnLoadGridsquare`       | Yes                      | Capture squares as they load into memory.                  |
| Probe      | `nearPlayers_closeRing`  | Yes                      | Periodically rescan squares in a small radius around players. |

Sketch of the `"balanced"` probes (aligned with `fact_layer.md` but minimal):

```lua
-- Inside facts/squares.lua (conceptual)

Fact.listener{
  name  = "OnLoadGridsquare:squares",
  event = "OnLoadGridsquare",

  handle = function(ctx, isoGridSquare)
    if not isoGridSquare then return end
    local record = ctx.makeSquareRecord(isoGridSquare) -- builds SquareObservation
    ctx.emit(record)
  end,
}

Fact.probe{
  name     = "nearPlayers_closeRing",
  schedule = {
    intervalTicks = 1,    -- every tick
    budgetPerTick = 200,  -- max squares per tick
  },

  run = function(ctx, budget)
    local processed = 0

    for _, player in ipairs(ctx.players:nearby()) do
      for square in ctx.iterSquaresInRing(player, 1, 8) do
        if processed >= budget then
          return
        end

        local record = ctx.makeSquareRecord(square)
        ctx.emit(record)
        processed = processed + 1
      end
    end
  end,
}
```

Notes:

- For the Build 42 MVP we only target single-player / server-side logic and do
  not yet adapt behavior for true multiplayer. In practice,
  `ctx.players:nearby()` will typically return at most a single player; using a
  plural helper here is primarily future-proofing for potential multi-player
  support.

Implementation decisions and deferred work:

- `squareId` is derived from the `IsoGridSquare` “ID” field (per the Java API
  docs) or an equivalent coordinate-based identifier. It is treated as a
  semi-stable identifier for the square itself, not as the unique identifier
  for individual observations.
- For MVP, `makeSquareRecord` will initially stub out the detection for
  `hasBloodSplat`, `hasCorpse`, and `hasTrashItems` (for example, always
  `false` or `nil`), and helpers such as `squareNeedsCleaning()` should be
  implemented with that limitation in mind. Richer heuristics for these
  fields are explicitly deferred.

### 4.3 Time stamping and integration with LQR

Event time is important for LQR’s time-based windows and grouping. MVP should
establish a clear, reusable pattern:

- **Fact-layer timestamping**
  - When a listener or probe creates a `SquareObservation`, it should:
    - read the current game time once from the engine (e.g.
      `getGameTime():getTimeCalendar():getTimeInMillis()`); and
    - write that value into `SquareObservation.observedAtTimeMS`.
  - This happens in the fact layer (e.g. inside `makeSquareRecord`), as close
    as possible to the “fact creation” moment.

- **Extending `LQR.Schema.wrap` for `sourceTime`**
  - MVP will extend LQR’s `Schema.wrap` with a clean, reusable option for
    event time, for example:
    - `opts.sourceTimeField` (string) – name of a field on the record whose
      numeric value should be copied into `record.RxMeta.sourceTime` if
      present; and/or
    - `opts.sourceTimeSelector` (function) – callback that derives a numeric
      event time from the record.
  - `Schema.wrap` remains the single place that normalizes `RxMeta`; the new
    option simply ensures that `RxMeta.sourceTime` is set to the chosen event
    time when provided and valid.

- **WorldObserver usage in MVP**
  - For `SquareObservation` sources, WorldObserver will:
    - populate `observedAtTimeMS` in the fact layer; then
    - call `Schema.wrap("SquareObservation", observable, { idSelector = nextObservationId, sourceTimeField = "observedAtTimeMS" })`
      so that:
      - `RxMeta.id` is a cheap, monotonically increasing observation identifier
        (via an internal `nextObservationId()` helper) rather than the
        `squareId`; and
      - `RxMeta.sourceTime` is automatically stamped from our payload.
  - Time-based LQR windows and helpers can then rely on `RxMeta.id` and
    `RxMeta.sourceTime` for behavior, while mod authors see
    `SquareObservation.squareId` and `SquareObservation.observedAtTimeMS` as
    the domain-level identifiers and timestamps.
  - For advanced users or custom fact sources that call `Schema.wrap`
    directly, WorldObserver exposes a `nextObservationId()` helper on the
    public module. It returns a monotonically increasing integer that is
    unique within the current Lua VM; passing it as `idSelector` lets custom
    schemas share the same ID guarantees as WorldObserver’s own facts.

---

## 5. Public API signature index (MVP)

This section lists the **intended MVP public API surface** and suggested
EmmyLua annotations. Nothing is hard-guaranteed; everything may change between
MVP and later versions, and we explicitly avoid shims/backward-compatibility.

### 5.1 Core types (EmmyLua sketches)

```lua
---@class SquareObservation
---@field squareId integer
---@field square IsoSquare
---@field x integer
---@field y integer
---@field z integer
---@field hasBloodSplat boolean?
---@field hasCorpse boolean?
---@field hasTrashItems boolean?
---@field observedAtTimeMS number?
---@field source string?

---@class Observation
---@field square SquareObservation
---@field _raw_result any|nil

---@class ObservationStream
local ObservationStream = {}

---@alias ObservationCallback fun(observation: Observation)
```

### 5.2 `WorldObserver` entry point

```lua
---@class Observations
local Observations = {}

---@class FactsSquaresConfig
---@field strategy string  -- "balanced" only in MVP

---@class FactsConfig
---@field squares FactsSquaresConfig

---@class Config
---@field facts FactsConfig

---@class Debug
local Debug = {}

---@class WorldObserver
---@field observations Observations
---@field config Config
---@field debug Debug
local WorldObserver = {}
```

### 5.3 Observations API (squares)

```lua
---@return ObservationStream  # stream of Observation rows (square field populated)
function Observations.squares() end
```

### 5.4 ObservationStream API (MVP subset)

```lua
---@param callback ObservationCallback
---@return any  # subscription-like object with :unsubscribe()
function ObservationStream:subscribe(callback) end

---@param dimension string  -- e.g. "square"
---@param seconds number
---@return ObservationStream
function ObservationStream:distinct(dimension, seconds) end

---@param predicate fun(observation: Observation): boolean
---@return ObservationStream
function ObservationStream:filter(predicate) end

---@return any  # underlying LQR observable/query pipeline
function ObservationStream:getLQR() end
```

### 5.5 Square helpers (MVP examples)

Helpers live under `WorldObserver.helpers.square` (implementation detail),
but are surfaced as methods on streams with `enabled_helpers.square`:

```lua
---@return ObservationStream
function ObservationStream:squareHasBloodSplat() end

---@return ObservationStream
function ObservationStream:squareNeedsCleaning() end
```

These helpers are part of the MVP but are not yet “hard stable”; they may be
renamed or refactored as we gain experience.

---

## 6. Testing strategy (MVP)

MVP focuses on **engine-independent** tests that can run under plain Lua with
LQR and lua-reactivex, plus stubs for game objects and events.

### 6.1 Engine-independent tests (priority)

- **Location & tooling**
  - Use `busted` (as for LQR) under `tests/unit/` for WorldObserver tests.
  - Follow LQR’s existing test style where reasonable.

- **What to cover in MVP**
  - `facts.squares`:
    - `makeSquareRecord` builds a `SquareObservation` with expected fields and
      semantics when given stub squares.
    - `nearPlayers_closeRing` honours the `budgetPerTick`, visits squares in
      a plausible pattern, and calls `ctx.emit` with proper records.
  - `observations.squares()`:
    - Emits `Observation` tables with `observation.square` shaped as per
      schema.
    - Plays well with `:distinct("square", seconds)` semantics.
  - Square helpers:
    - `:squareHasBloodSplat()` and `:squareNeedsCleaning()` filter emissions
      correctly for stubbed observations.

### 6.2 Engine-coupled tests (deferred)

- No automated engine-coupled tests are required for MVP.
- Manual/adhoc verification inside Project Zomboid is expected for:
  - basic performance sanity of the balanced squares plan;
  - confirming that observation timing feels reasonable for typical mod use.
- Future work may add engine-coupled tests or debug helpers, but they are out
  of scope for MVP.

---

## 7. Must-nots and guardrails (MVP)

The following constraints are **deliberate** for the MVP and should be treated
as hard guardrails unless explicitly revised in docs or during design chats:

- **No Situation/Action public API**
  - MVP exposes only Facts and ObservationStreams. Situations and Actions
    remain conceptual, not implemented surfaces.

- **No GUI / visual overlays / in-game debug UIs**
  - No tile highlighting, overlay windows, or interactive config UIs.
  - Debugging is via logging and simple `print` statements only.

- **No automatic self-tuning or dynamic strategy switching**
  - Fact strategies (even just `"balanced"` for squares) do not automatically
    change at runtime based on load or subscriber counts in MVP.
  - Any such behaviour is future work and requires explicit design.

- **No persistent config serialization**
  - `WorldObserver.config` is configured via Lua only.
  - MVP does not write config back to disk or manage config files.

- **No multiplayer-specific guarantees**
  - MVP is designed for single-player / server-side logic in principle, but
    makes no strong guarantees or special handling for multiplayer scenarios.

- **No extra config knobs without prior agreement**
  - MVP must **not add new configuration knobs** (especially user-facing
    ones) that have not:
    - either been discussed in existing docs (`vision.md`, `api_proposal.md`,
      `fact_layer.md`), or
    - been explicitly agreed while chatting during design.

- **No shims or backward-compatibility promises**
  - MVP may change APIs, types, and config names freely in later iterations.
  - We will not introduce backwards-compatibility layers or deprecation
    shims during the early evolution of WorldObserver.

These guardrails exist to keep the MVP small, understandable, and easy to
iterate on. Future revisions of this doc can relax them explicitly once the
core slice for squares has proven itself.
