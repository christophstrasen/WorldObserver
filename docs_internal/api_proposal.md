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
- **Per‑observation naming:** whenever we talk about a single emission from an
  ObservationStream or LQR query, we treat it as **one observation** and name
  the per‑emission table `observation` (singular). Nested fields use singular
  schema names as well (for example `observation.square`, `observation.room`,
  `observation.zombie`, `observation.vehicle`).
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

## 2. Facts layer

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
  surface, for example:

  ```lua
  WorldObserver.config.facts.squares.strategy  = "balanced"
  WorldObserver.config.facts.rooms.strategy    = "gentle"
  WorldObserver.config.facts.zombies.strategy  = "intense"
  WorldObserver.config.facts.vehicles.strategy = "balanced"
  ```

  ObservationStream semantics remain “stream of observations over time”;
  strategies only affect timeliness and coverage. The base streams for these
  facts are the ones exposed as `WorldObserver.observations.<name>()`
  (for example `squares()`, `rooms()`, `zombies()`, `vehicles()`).

### Event time and observation IDs (implementation notes)

- Core fact sources (squares in the MVP, later rooms/zombies/vehicles) stamp
  each record with a domain-level timestamp field (for example
  `observedAtTimeMS` on `SquareObservation`, derived from
  `getTimeCalendar():getTimeInMillis()`), as close as possible to when the
  fact is created.
- When tagging these records with LQR schemas via `LQR.Schema.wrap`, the
  WorldObserver fact layer uses two options:
  - an `idSelector` that produces a cheap, monotonically increasing numeric
    identifier per observation (rather than reusing a square/room/zombie ID);
  - a `sourceTimeField` that tells LQR to copy the chosen payload field into
    `record.RxMeta.sourceTime` for use by time-based windows and grouping.
- In practice this means:
  - domain schemas such as `SquareObservation` carry fields like
    `squareId` (semi-stable identity of the square) and `observedAtTimeMS`
    (domain timestamp visible to mod authors); while
  - LQR sees `RxMeta.id` (per-observation ID) and `RxMeta.sourceTime`
    (event time) derived from those payload fields via `Schema.wrap`.

---

## 3. ObservationStreams
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
- When defining custom ObservationStreams that do not have a natural stable
  identifier on their payload, advanced users may reuse
  `WorldObserver.nextObservationId()` as an `idSelector` when calling
  `LQR.Schema.wrap`. This helper returns a monotonically increasing integer
  that is unique within the current Lua VM, giving those records the same
  per-observation ID guarantees that WorldObserver’s own fact sources use.
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
  `vehicle`, `spatial`, `time`, …). The value controls which per‑observation
  field the helper set should look at:
  - `true` means “use the default field name for this type”, e.g.
    `observation.square` for `square`, `observation.room` for `room`.
  - a `string` value (for example `"nearbySquares"`) means “attach this helper
    set, but have it read from `observation[<that string>]` instead”.
  - This allows custom or derived streams to reuse existing helper sets even
    when they expose a type under a different per‑observation field name.
  - Stream methods are thin delegators that always dispatch through the helper
    tables, so helpers remain patch‑able:
  updating `WorldObserver.helpers.square.squareNeedsCleaning` is enough for
  all streams with `enabled_helpers.square` to see the new behavior.

### Shape of `subscribe` callbacks

- `subscribe` callbacks always receive a **single observation table** called
  `observation`.
- `observation` is a plain Lua table with one field per world type (schema)
  that the stream exposes, for example `observation.square`,
  `observation.room`, `observation.zombie`, or `observation.vehicle`.
- Each of these fields is the schema‑tagged instance table (with its own
  `RxMeta`), following LQR’s row‑view conventions; missing sides of joins
  appear as empty tables rather than `nil`.
- Advanced users may also access `observation._raw_result` as an escape hatch
  to the underlying LQR `JoinResult`, but typical mod code should work only
  with the typed fields on `observation`.

### Core vs. custom observation schemas

- **Core WorldObserver schemas** (owned by this project) are **structured and
  curated**:
  - they use explicit schema names such as `SquareObservation`;
  - their fields and semantics are documented in internal docs; and
  - we provide EmmyLua annotations for them where it helps mod authors.
- **Custom/modded observation types** (for example streams that expose
  `observation.gun` or `observation.wildlife`) are treated as **opaque but
  honest**:
  - each emission is still “one observation over time”, passed as the
    `observation` table into callbacks;
  - field names and shapes are self‑consistent within that stream; and
  - authors may document and type them however they like, but WorldObserver
    does not impose naming or typing style on those domains.
- Structure only becomes important for custom streams when they explicitly opt
  into WorldObserver helper sets or debug tooling:
  - if a stream sets `enabled_helpers.square = "nearbySquares"`, it must
    provide an `observation.nearbySquares` field shaped in the way the square
    helper docs describe;
  - similarly, any debug or describe helpers that assume certain fields only
    work when those fields are present as documented.
- Beyond these explicit contracts, WorldObserver treats custom observation
  payloads as first‑class but opaque data carried along by the stream.

@TODO explore if instead of subscribe we could could also offer to emit a Starlit LuaEvent

### Predicate-based filtering

- ObservationStreams expose a `filter` method:
  `stream:filter(function(observation) return ... end)`.
- This is a thin, advanced escape hatch that behaves like lua‑reactivex
  `filter` applied to the underlying observable of per‑emission `observation`
  tables: the predicate runs once per emission and decides whether that
  observation should be kept or dropped.
- The predicate receives the same `observation` shape as `subscribe`
  (`observation.square`, `observation.room`, `observation.zombie`, etc.),
  making it easy to express custom conditions without introducing new helpers.
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
## 4. Debugging and logging

- WorldObserver reuses LQR’s logging infrastructure (`LQR.util.log`) for its
  internal logging. Fact plans, ObservationStream registration, and serious
  errors are logged under WorldObserver‑specific categories (e.g. `WO.FACTS`,
  `WO.STREAM`, `WO.ERROR`) so engine behavior can be inspected without adding
  ad‑hoc prints.
- Everyday debugging for mod authors should start with simple `print` calls
  inside `subscribe` callbacks, using the `observation` table shape:
  `stream:subscribe(function(observation) print(observation.square.x, observation.square.y) end)`.
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

## 5. Use cases

### 5.1 Find squares with blood around the player

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
local subscription = bloodSquares:subscribe(function(observation)
  handleBloodSquare(observation.square)  -- user-defined action using the square instance
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

### 5.2 Chef zombie in kitchen (drive cooking sound)

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
  :subscribe(function(observation)
    -- observation.room and observation.zombie carry the joined instances
    updateKitchenCookingSound(observation.room.id, observation.zombie)
  end)
```

Notes:

- Joins between zombies and rooms happen inside the `roomZombies`
  ObservationStream definition (LQR) and are not performed by helpers.
- Helpers like `:roomIsKitchen()` and `:zombieHasChefOutfit()` only reduce the
  stream (filtering) and do not introduce new data sources; the subscription
  can maintain its own “any chef zombie present?” state to start/stop sounds.

---

### 5.3 Cars under attack (custom multi-source ObservationStream)

Traditional intent:

- When at least three zombies are attacking the same car at (roughly) the same
  time, treat the car as “under attack” and shake it.

WorldObserver‑style usage (mod-facing API):

```lua
local WorldObserver = require("WorldObserver")

local vehiclesUnderAttackSubscription = WorldObserver.observations.vehiclesUnderAttack()
  :withConfig({ minZombies = 3 })
  :filter(function(observation)  -- don’t shake very heavy vehicles
    return (observation.vehicle.weightKg or 0) <= 1200
  end)
  :subscribe(function(observation)
    shakeVehicle(observation.vehicle.id, observation)
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
      Query.from(vehicles, "vehicle")
        :innerJoin(players, "player")
        :using({ vehicle = "id", player = "vehicleId" })
        :innerJoin(zombies, "zombie")
        :using({ player = "id", zombie = "targetPlayerId" })
        :where(function(observation) -- only zombies currently attacking players in vehicles
          return observation.zombie.isAttacking == true
        end)
        :groupBy("vehicle_attacks", function(observation)
          return observation.vehicle.id
        end)
        :groupWindow({ time = 1 })   -- “at the same time” ≈ within 1 second
        :aggregates({})
        :having(function(group)
          return (group._count.zombie or 0) >= minZombies
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

### 5.4 Squares that need cleaning (custom helper on a single stream)

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

dirtySquares:subscribe(function(observation)
  -- observation.square carries the square instance
  promptPlayerToClean(observation.square)
end)
```

Custom helper definition (square helper set extension):

```lua
-- Somewhere in the square helper set definition:

function SquareHelpers.squareNeedsCleaning(stream)
  return stream:filter(function(observation)
    local square = observation.square or {}

    local hasBlood   = square.hasBloodSplat == true
    local hasCorpse  = square.hasCorpse == true
    local hasTrash   = square.hasTrashItems == true

    return hasBlood or hasCorpse or hasTrash
  end)
end
```

Notes:

- `squareNeedsCleaning()` is a thin, named wrapper around a `filter`
  predicate that operates on the `observation.square` instance; it does not add
  new schemas or perform joins.
- The helper can live in the same square helper set that attaches helpers
  like `squareHasBloodSplat()`; ObservationStreams that enable the square
  helpers automatically gain access to `squareNeedsCleaning()`.
- This pattern lets mod authors create and ship their own reusable
  ObservationStream helpers while keeping the core WorldObserver API small
  and focused.

---

### 5.5 Room alarm status from LuaEvents (external fact source, joined with zombies)

Traditional intent:

- Another mod already computes an alarm status for rooms (for example `"safe"`,
  `"warning"`, `"breached"`) and emits it as a Starlit LuaEvent. We want to
  consume those updates as an ObservationStream and, when a room is marked
  `"breached"` **but currently has no zombies in it**, automatically disable
  its alarm.

WorldObserver‑style usage (mod-facing API):

```lua
local WorldObserver = require("WorldObserver")

local roomAlarmStatusWithZombies = WorldObserver.observations.roomAlarmStatusWithZombies()

roomAlarmStatusWithZombies:subscribe(function(observation)
  local status = observation.roomAlarmStatus   -- status record from LuaEvent
  local zombie = observation.zombie            -- {} when no zombie in that room

  if status.status == "breached" and (zombie.id == nil) then
    disableAlarmForRoom(status.id)
  end
end)
```

Advanced definition (base stream from LuaEvent + derived join with zombies):

```lua
-- 1) _Base_ ObservationStream: roomAlarmStatus backed by a LuaEvent source

WorldObserver.observations.register("roomAlarmStatus", {
  enabled_helpers = {}, -- no helpers attached for this simple example

  build = function(opts)
    local rx     = require("reactivex")
    local LQR    = require("LQR")
    local Schema = LQR.Schema

    -- Turn a Starlit LuaEvent into a stream of roomAlarmStatus records.
    local rawEvents =
      rx.Observable.fromLuaEvent("RoomAlarms.OnRoomStatus")

    -- Tag with an LQR schema; use `id` as the room identifier.
    local roomAlarmStatus =
      Schema.wrap("roomAlarmStatus", rawEvents, { idField = "id" })

    return roomAlarmStatus
  end,
})

-- 2) _Derived_ ObservationStream: join roomAlarmStatus with zombies per room

WorldObserver.observations.register("roomAlarmStatusWithZombies", {
  enabled_helpers = {}, -- could enable room/zombie helpers in a real setup

  build = function(opts)
    local Query = require("LQR.Query")

    local roomAlarmStatusLqr = WorldObserver.observations.roomAlarmStatus():getLQR()
    local zombiesLqr         = WorldObserver.observations.zombies():getLQR()

    return
      Query.from(roomAlarmStatusLqr, "roomAlarmStatus")
        :leftJoin(zombiesLqr, "zombie")
        :using({ roomAlarmStatus = "roomId", zombie = "roomId" })
        -- row view: observation.roomAlarmStatus, observation.zombie ({} when no zombie in that room)
  end,
})
```

Notes:

- This pattern shows how an ObservationStream can be backed by a LuaEvent
  source instead of probes or engine events: the `roomAlarmStatus` stream
  turns the event into a lua‑reactivex observable and then uses LQR’s schema
  helpers to create a schema‑tagged base stream.
- A derived stream (`roomAlarmStatusWithZombies`) then uses LQR joins to
  combine room alarm status with zombie observations per room, so subscribers
  can reason about both “what status was reported” and “what is currently in
  the room”.
- From the modder’s perspective, `roomAlarmStatusWithZombies()` behaves like
  any other ObservationStream; they only need to know about
  `WorldObserver.observations.roomAlarmStatusWithZombies()`, not how the
  facts are produced or joined.
- LuaEvent‑backed streams are opt‑in and best suited for signals that are
  already computed by other mods; core world types (squares, rooms, zombies,
  vehicles, …) should continue to rely primarily on fact plans (events +
  probes) described in the fact layer.
