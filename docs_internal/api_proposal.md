# WorldObserver – API proposal (MVP)

This document describes the intended **public WorldObserver Lua API** for the MVP.
Anything not mentioned here (internal fact plans, probe implementations, LQR query
builders, etc.) is considered implementation detail and may change without notice.

---

## 1. Principles and constraints

- **Audience & scope:** same as `docs_internal/vision.md` – Lua‑coding PZ mod
  authors, with WorldObserver as the main entry point and LQR/Rx as optional
  advanced tools.
- **Facts are owned by WorldObserver:** core world facts (squares, rooms,
  zombies, etc.) come from WorldObserver’s Event Listeners and Active Probes.
  Mods do not wire `OnTick` / `OnLoadGridsquare` directly for these concerns.
- **ObservationStreams are event streams:** they carry all observations over
  time, including multiple observations for the same entity. There is no
  implicit per‑key de‑duplication; any “once per X” behavior is opt‑in.
- **Helpers only reduce:** helpers attached to ObservationStreams may filter,
  reshape, or de‑duplicate observations, but they never introduce new schemas
  or perform joins/enrichment. Joins live inside ObservationStream `build`
  functions or advanced LQR usage.
- **Helper naming conventions:** keep helper names semantic and consistent:
  - spatial constraints use `near*` (`nearIsoObject(...)`, `nearTilesOf(...)`, …);
  - entity‑specific predicates are prefixed with the entity, e.g.
    `squareHasBloodSplat()`, `roomIsSafe()`, `zombieIsFast()`;
  - `*Is*` is used for simple flags/enums on that entity, `*Has*` for lookups
    into collections/relationships (loot, decals, tags, outfit tags, etc.).
- **LQR windows are internal:** join/group/distinct windows are tuned inside
  built‑in streams and helpers. The public API exposes only semantic options
  (for example a generic `distinct(<dimension>, seconds)` helper), with a
  dedicated escape hatch for full LQR control.
- **Custom observations via registration:** new ObservationStreams are defined
  by registering a `build` function plus `enabled_helpers`; they integrate into
  the same helper and Fact infrastructure as built‑in streams.

---

## 3. Facts layer

- WorldObserver owns **fact generation** for core world elements (squares,
  rooms, etc.); mods do not need to wire `OnTick` / `OnLoadGridsquare` directly for
  these concerns.
- For each element type, the engine defines an internal **fact plan** that
  combines Event Listeners (e.g. `OnLoadGridsquare`) and Active Probes
  (periodic or focused scans) to balance freshness, completeness, and
  performance.
- Example strategies for squares (illustrative only):
  - listen to all `OnLoadGridsquare` events;
  - probe squares within a small radius around players frequently;
  - probe squares in a wider radius less often, possibly with patterns
    (odd/even rows) to reduce load.
- Strategy selection is an **advanced knob**, exposed via a small config
  surface (e.g. `WorldObserver.config.facts.squares.strategy = "balanced" |
  "low_traffic"`). ObservationStream semantics remain “stream of observations
  over time”; strategies only affect timeliness and coverage.

---

## 4. ObservationStreams
@TODO consolidate what we say about LRQ/Rx here

- ObservationStreams are exposed under `WorldObserver.observations.<name>()`.
- New ObservationStreams are registered with a small config table, e.g.
  `register("my_mod_gardenZombies", { build = …, enabled_helpers = { square = true, zombie = true } })`.
- The `build` function (details TBD) is free to use LQR/Rx; its only contract is
  that the produced observations contain the row fields referenced in
  `enabled_helpers`. For ObservationStreams that support `:withConfig(...)`,
  `build` receives an `opts` table with the merged configuration for that
  stream instance.
- Some ObservationStreams expose a small, semantic configuration helper
  (e.g. `vehiclesUnderAttack():withConfig({ minZombies = 3 })`); these options
  only tune domain semantics (thresholds, filters) and never expose fact
  strategies or raw LQR knobs. Use such configuration sparingly to avoid
  “thick” builders – advanced users are encouraged to drop down to LQR
  directly when they need more control.
- For each key in `enabled_helpers` (e.g. `square`, `zombie`, `spatial`,
  `time`), WorldObserver attaches the corresponding helper set to the
  ObservationStream. Helper sets are thin, domain‑specific refinements that can
  be reused across streams and extended by third parties. Helpers are
  **reducing operators only**: they filter, reshape, or de‑duplicate existing
  observations but never introduce new schemas or join in additional sources.
- Internally, ObservationStreams and helpers use LQR windows directly:
  join windows for schema joins, group windows for aggregate‑style helpers, and
  `distinct` windows for “once per key” helpers. The public API should expose
  only semantic options (e.g. `scope`, `windowSeconds`) rather than raw LQR
  window configs. A generic, dimension‑aware helper
  `:distinct(<dimensionName>, seconds)` is a thin wrapper around LQR
  `distinct`, and can be applied wherever the named dimension (for example
  `square` or `zombie`) is present. Full LQR tuning remains available via an
  advanced escape hatch (e.g. `stream:getLQR()`).

### Helper namespacing and `enabled_helpers`

- Helpers are organized by world **type** under a shared namespace, e.g.
  `WorldObserver.helpers.square`, `WorldObserver.helpers.room`,
  `WorldObserver.helpers.zombie`, and so on.
- `enabled_helpers` is keyed by these types (`square`, `room`, `zombie`,
  `vehicle`, `spatial`, `time`, …). The value controls which row field the
  helper set should look at:
  - `true` means “use the default field name for this type”, e.g.
    `observed.square` for `square`, `observed.room` for `room`.
  - a `string` value (for example `"nearbySquares"`) means “attach this helper
    set, but have it read from `observed[<that string>]` instead”.
- This allows custom or derived streams to reuse existing helper sets even
  when they expose a type under a different row key.
- Stream methods are thin delegators that always dispatch through the helper
  tables, so helpers remain patch‑able:
  updating `WorldObserver.helpers.square.squareNeedsCleaning` is enough for
  all streams with `enabled_helpers.square` to see the new behavior.

### Shape of `subscribe` callbacks

- `subscribe` callbacks always receive a **row** called `observed`.
- `observed` is a plain Lua table with one field per world type (schema) that
  the stream exposes, for example `observed.square`, `observed.room`,
  `observed.zombie`, or `observed.vehicle`.
- Each of these fields is the schema‑tagged instance table (with its own
  `RxMeta`), following LQR’s row‑view conventions; missing sides of joins
  appear as empty tables rather than `nil`.
- Advanced users may also access `observed._raw_result` as an escape hatch to
  the underlying LQR `JoinResult`, but typical mod code should work only with
  the typed fields on `observed`.

### Predicate-based filtering

- ObservationStreams expose a `filter` method:
  `stream:filter(function(observed) return ... end)`.
- This is a thin, advanced escape hatch that behaves like lua‑reactivex
  `filter` applied to the underlying observable of `observed` rows:
  the predicate runs once per emission and decides whether that observation
  should be kept or dropped.
- The predicate receives the same `observed` row shape as `subscribe`
  (`observed.square`, `observed.room`, `observed.zombie`, etc.), making it
  easy to express custom conditions without introducing new helpers.
- Use `filter` for bespoke or complex logic; prefer named helpers for common,
  reusable predicates so that beginners can stay on helper chains.

### Advanced escape hatch: `getLQR`

- Every ObservationStream exposes `getLQR()`:
  `local lqrStream = stream:getLQR()`.
- `getLQR()` returns the underlying LQR observable / query pipeline **as built
  so far**, including any WorldObserver helpers you have already chained
  (`distinct`, `filter`, `squareNeedsCleaning`, etc.).
- The returned value is still “cold”: no probes or event listeners are
  activated until someone subscribes (either via WorldObserver’s `subscribe`
  or via LQR directly).
- This is an advanced escape hatch for users who want to continue building
  with raw LQR APIs (joins, grouping, custom windows, and so on) on top of an
  existing ObservationStream.

---
## 5. Debugging and logging

- WorldObserver reuses LQR’s logging infrastructure (`LQR.util.log`) for its
  internal logging. Fact plans, ObservationStream registration, and serious
  errors are logged under WorldObserver‑specific categories (e.g. `WO.FACTS`,
  `WO.STREAM`, `WO.ERROR`) so engine behavior can be inspected without adding
  ad‑hoc prints.
- Everyday debugging for mod authors should start with simple `print` calls
  inside `subscribe` callbacks, using the `observed` row shape:
  `stream:subscribe(function(observed) print(observed.square.x, observed.square.y) end)`.
- Over time, WorldObserver may grow a small set of explicit debugging helpers
  that are thin wrappers around LQR’s logging, for example:
  - a mid‑pipeline tap operator on LQR streams (upstream in LQR);
  - a `WorldObserver.debug.describeFacts(type)` helper to print the active
    fact strategy and key parameters for a world type (e.g. how squares are
    probed and which events are used);
  - a `WorldObserver.debug.describeStream(name)` helper to summarize the
    pipeline and helper sets attached to a given ObservationStream.
- Detailed tap operators or visual debugging (for example, using Project
  Zomboid’s tile highlighting to show observed squares or rooms) are future
  extensions and will be designed on top of the same ObservationStreams and
  logging primitives described here.

---

## 6. Use cases

### 6.1 Find squares with blood around the player

Traditional approach (from `vision.md` “Before” section):

- Hook a scanner into `OnTick` / `OnPlayerUpdate`.
- On each tick, scan a range of squares around the player in batches to avoid blocking.
- For each square with blood, call a callback.
- Stop scanning once the full range has been covered, or when the caller cancels.

WorldObserver‑style API sketch:

```lua
local WorldObserver = require("WorldObserver")

-- Build an ObservationStream of squares with blood around any player.
local bloodSquares = WorldObserver.observations
  .squares()
  -- decorated with helpers specific to square observations
  :distinct("square", 10)             -- only the first observation per square within 10s
  :nearIsoObject(playerIsoObject, 20) -- compare the live position of the IsoObject against the observation
  :squareHasBloodSplat()              -- tiny helper to keep only squares with blood

-- Act on each matching observation as it is discovered.
local subscription = bloodSquares:subscribe(function(observed)
  handleBloodSquare(observed.square)  -- user-defined action using the square instance
end)

-- Later, if this Situation is no longer relevant, cancel the subscription.
-- WorldObserver can then relax or stop related probes/fact sources as needed.
subscription:unsubscribe()
```

Notes:

- `squares()` exposes a base ObservationStream; `:nearIsoObject(...)` and
  `:squareHasBloodSplat()` are helper‑based refinements attached to that stream.
- `:distinct("square", seconds)` is the opt‑in helper to only see the first
  matching observation per square within a given time window.
- Unsubscribing from the stream (via `subscription:unsubscribe()`) is the
  standard way to end this Situation; any underlying fact strategies are free
  to scale back related work once there are no interested subscribers.

---

### 6.2 Chef zombie in kitchen (drive cooking sound)

Traditional intent:

- Treat kitchens as rooms that can have a special “chef zombie” event in them.
- While at least one chef‑outfit zombie is in a kitchen, play or boost a
  “cooking” ambient sound; stop when no such zombies are present.

WorldObserver‑style API sketch:

```lua
local WorldObserver = require("WorldObserver")

-- Built-in or custom ObservationStream that already joins zombies with rooms.
local roomZombies = WorldObserver.observations.roomZombies()

roomZombies
  :roomTypeIs("Kitchen")
  :zombieHasChefOutfit()
  :subscribe(function(observed)
    -- observed.room and observed.zombie carry the joined instances
    updateKitchenCookingSound(observed.room.id, observed.zombie)
  end)
```

Notes:

- Joins between zombies and rooms happen inside the `roomZombies`
  ObservationStream definition (LQR) and are not performed by helpers.
- Helpers like `:roomIsKitchen()` and `:zombieHasChefOutfit()` only reduce the
  stream (filtering) and do not introduce new data sources; the subscription
  can maintain its own “any chef zombie present?” state to start/stop sounds.

---

### 6.3 Cars under attack (custom multi-source ObservationStream)

Traditional intent:

- When at least three zombies are attacking the same car at (roughly) the same
  time, treat the car as “under attack” and shake it.

WorldObserver‑style usage (mod-facing API):

```lua
local WorldObserver = require("WorldObserver")

local vehiclesUnderAttackSubscription = WorldObserver.observations.vehiclesUnderAttack()
  :withConfig({ minZombies = 3 })
  :filter(function(observed)  -- don’t shake very heavy vehicles
    return (observed.vehicle.weightKg or 0) <= 1200
  end)
  :subscribe(function(observed)
    shakeVehicle(observed.vehicle.id, observed)
  end)
```

Advanced definition (custom ObservationStream with three sources):

```lua
WorldObserver.observations.register("vehiclesUnderAttack", {
  enabled_helpers = { vehicle = true },

  build = function(opts)
    local minZombies = (opts and opts.minZombies) or 3 --from :WithConfig

    local Query    = require("LQR.Query")
    local vehicles = WorldObserver.observations.vehicles():getLQR()
    local players  = WorldObserver.observations.players():getLQR()
    local zombies  = WorldObserver.observations.zombies():getLQR()

    return
      Query.from(vehicles, "vehicles")
        :innerJoin(players, "players")
        :using({ vehicles = "id", players = "vehicleId" })
        :innerJoin(zombies, "zombies")
        :using({ players = "id", zombies = "targetPlayerId" })
        :where(function(row) -- only zombies currently attacking players in vehicles
          return row.zombies.isAttacking == true
        end)
        :groupBy("vehicle_attacks", function(row)
          return row.vehicles.id
        end)
        :groupWindow({ time = 1 })   -- “at the same time” ≈ within 1 second
        :aggregates({})
        :having(function(g)
          return (g._count.zombies or 0) >= minZombies
        end)
  end,
})
```

Notes:

- `:withConfig({ minZombies = 3 })` passes its table as `opts` into
  `build(opts)`, and `minZombies` is then read inside the LQR `:having`
  clause.
- This example shows how an advanced user (or WorldObserver itself) can define
  a multi‑source ObservationStream by combining existing streams via LQR.
- All join and grouping logic lives inside the `build` function; downstream
  helpers on `vehiclesUnderAttack()` must still be reducing only. Vehicle-level
  helpers and ad‑hoc `filter` predicates then operate on the attached
  `VehicleObs` schema.

---

### 6.4 Squares that need cleaning (custom helper on a single stream)

Traditional intent:

- Identify squares that “need cleaning” because they contain visible mess,
  such as blood splats, corpses, or trash items, and react whenever such
  squares are observed.

WorldObserver‑style usage (mod-facing API):

```lua
local WorldObserver = require("WorldObserver")

local dirtySquares = WorldObserver.observations
  .squares()
  :squareNeedsCleaning()

dirtySquares:subscribe(function(observed)
  -- observed.square carries the square instance
  promptPlayerToClean(observed.square)
end)
```

Custom helper definition (square helper set extension):

```lua
-- Somewhere in the square helper set definition:

function SquareHelpers.squareNeedsCleaning(stream)
  return stream:filter(function(observed)
    local square = observed.square or {}

    local hasBlood   = square.hasBloodSplat == true
    local hasCorpse  = square.hasCorpse == true
    local hasTrash   = square.hasTrashItems == true

    return hasBlood or hasCorpse or hasTrash
  end)
end
```

Notes:

- `squareNeedsCleaning()` is a thin, named wrapper around a `filter`
  predicate that operates on the `observed.square` instance; it does not add
  new schemas or perform joins.
- The helper can live in the same square helper set that attaches helpers
  like `squareHasBloodSplat()`; ObservationStreams that enable the square
  helpers automatically gain access to `squareNeedsCleaning()`.
- This pattern lets mod authors create and ship their own reusable
  ObservationStream helpers while keeping the core WorldObserver API small
  and focused.

