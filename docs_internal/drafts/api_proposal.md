# WorldObserver – API proposal (MVP)

> **Stage:** Proposal & design

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
- **Helpers don't add rows:** helpers attached to ObservationStreams may filter,
  reshape, or de‑duplicate observations, but they never introduce new schemas
  or perform joins/enrichment. Joins live inside ObservationStream `build`
  functions or advanced LQR usage.
- **Helper “promise”:** helper methods should be easy to reason about:
  - Most helpers return a new refined stream (filter/dedup/reshape).
  - Helpers should not have surprising side effects (no global state, no hidden subscriptions).
  - If a helper performs caching/hydration (best-effort), it must be called out in its docstring or user docs.
- **Per‑observation naming:** whenever we talk about a single emission from an
  ObservationStream or LQR query, we treat it as **one observation** and name
  the per‑emission table `observation` (singular). Nested fields use singular
  schema names as well (for example `observation.square`, `observation.room`,
  `observation.zombie`, `observation.vehicle`).
- **Helper naming conventions:** keep helper names semantic and consistent:
  - spatial constraints use `near*` (`nearIsoObject(...)`, `nearTilesOf(...)`, …);
  - stream helpers should read well in a chain and **default to fluent predicate names**:
    - prefer `squareHasCorpse()`, `zombieHasTarget()`, `roomIsSafe()` over `whereSquareHasCorpse()`-style names;
    - assume helpers return a refined stream unless clearly stated otherwise.
  - use `<family>Filter(...)` for the generic “accept a predicate” helpers; avoid `where*` naming.
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
  performance, with intensity shaped by merged interest declarations
  (`staleness`, `radius`, `cooldown`) rather than preset strategy names.
  ObservationStream semantics remain “stream of observations over time”;
  interest only affects timeliness and coverage. The base streams for these
  facts are the ones exposed as `WorldObserver.observations.<name>()`
  (for example `squares()`, `rooms()`, `zombies()`, `vehicles()`).

### Event time and observation IDs (implementation notes)

- Core fact sources (squares in the MVP, later rooms/zombies/vehicles) stamp
  each record with a domain-level timestamp field (for example
  `sourceTime` on `SquareObservation`, derived from
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
    `squareId` (semi-stable identity of the square) and `sourceTime`
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
  strategies or raw LQR settings. Use such configuration sparingly to avoid
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
  tables, so helpers remain patch‑able.

Helper sets are intentionally split into “layers” so it’s clear what is a stream
method vs what is a record predicate vs what is an effect:

- `WorldObserver.helpers.<type>.stream.*` are **stream helpers** that become
  methods on ObservationStreams.
  - Signature: `fn(stream, fieldName, ...) -> ObservationStream`.
  - They refine streams (filter/dedup/reshape) and should stay reducing-only.
- `WorldObserver.helpers.<type>.record.*` are **record helpers** that operate on
  a single record table (one entity snapshot).
  - Predicates: `fn(record, ...) -> boolean` (meant for `stream:filter(...)`).
  - Hydration: `getIso*` style helpers return best-effort engine userdata.
- `WorldObserver.helpers.<type>.*` (top-level) are **utility/effect helpers**
  (e.g. `highlight(...)`) and are **not** attached as stream methods.

Patch seam: prefer patching the top-level helper function (e.g.
`WorldObserver.helpers.square.squareHasCorpse = function(stream, fieldName) ... end`),
so existing streams keep calling the patched logic via their delegators.

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

- ObservationStreams expose a low-level `filter` method:
  `stream:filter(function(rowView) return ... end)`.
- Important: this predicate runs as an LQR `Query.where` predicate, and sees
  LQR’s internal “row view”. Keys may be schema names (e.g. `"SquareObservation"`)
  rather than the post-rename fields modders see in `subscribe` callbacks.
- To keep modder code simple, WorldObserver also provides family sugar methods
  that hide these schema keys and pass the record directly:
  - `:squareFilter(function(squareRecord, observation) return ... end)`
  - `:zombieFilter(function(zombieRecord, observation) return ... end)`
- Use `:squareFilter(...)` / `:zombieFilter(...)` for mod-facing predicate
  composition (AND/OR); reserve raw `filter` for advanced/internal use.

### Advanced escape hatch: `getLQR`

- Every ObservationStream exposes `getLQR()`:
  `local lqrStream = stream:getLQR()`.
- `getLQR()` returns the underlying LQR observable / query pipeline **as built
  so far**, including any WorldObserver helpers you have already chained
  (`distinct`, `filter`, `squareHasCorpse`, etc.).
- The returned value is still “cold”: no probes or event listeners are
  activated until someone subscribes (either via WorldObserver’s `subscribe`
  or via LQR directly).
- This is an advanced escape hatch for users who want to continue building
  with raw LQR APIs (joins, grouping, custom windows, and so on) on top of an
  existing ObservationStream.

### ReactiveX bridge: `asRx`

- Every ObservationStream also exposes `asRx()`:
  `local rxStream = stream:asRx()`.
- `asRx()` returns a lua-reactivex `Observable` that mirrors the stream:
  subscriptions still trigger fact activation, and unsubscribing tears down
  the underlying stream subscription.
- Use this when you want general Rx operators like `map`, `filter`, `merge`,
  `scan`, `tap`, `distinctUntilChanged`, `buffer`, etc.
- Prefer WorldObserver’s dimension-aware `distinct("<dimension>", seconds)`
  before converting; lua-reactivex `distinct()` is global (no dimension/time
  awareness).
- As with `getLQR()`, this is an escape hatch: keep the default stream helpers
  for common cases and reach for Rx only when needed.

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

### 5.1 Find squares with corpses around the player

Traditional approach (from `vision.md` “Before” section):

- Hook a scanner into `OnTick` / `OnPlayerUpdate`.
- On each tick, scan a range of squares around the player in batches to avoid blocking.
- For each square with blood, call a callback.
- Stop scanning once the full range has been covered, or when the caller cancels.

WorldObserver‑style API sketch:

```lua
local WorldObserver = require("WorldObserver")

-- Build an ObservationStream of squares with corpses around any player.
local corpseSquares = WorldObserver.observations
  .squares()
  -- decorated with helpers specific to square observations
  :distinct("square", 10)             -- only the first observation per square within 10s
  :nearIsoObject(playerIsoObject, 20) -- compare the live position of the IsoObject against the observation
  :squareHasCorpse()                  -- tiny helper to keep only squares with corpses

-- Act on each matching observation as it is discovered.
local subscription = corpseSquares:subscribe(function(observation)
  handleCorpseSquare(observation.square)  -- user-defined action using the square instance
end)

-- Later, if this Situation is no longer relevant, cancel the subscription.
-- WorldObserver can then relax or stop related probes/fact sources as needed.
subscription:unsubscribe()
```

Notes:

- `squares()` exposes a base ObservationStream; `:nearIsoObject(...)` and
  `:squareHasCorpse()` are helper‑based refinements attached to that stream.
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

### 5.4 Squares that need cleaning (predicate composition + optional helper)

Traditional intent:

- Identify squares that “need cleaning” because they contain visible mess,
  such as corpses or trash items, and react whenever such
  squares are observed.

WorldObserver‑style usage (mod-facing API):

```lua
local WorldObserver = require("WorldObserver")
local Square = WorldObserver.helpers.square

	local dirtySquares = WorldObserver.observations
	  .squares()
	  :filter(function(observation)
	    local squareRecord = observation.square
	    return Square.record.squareHasCorpse(squareRecord)
	      or squareRecord.hasTrashItems == true -- example: your own field/predicate
	  end)

dirtySquares:subscribe(function(observation)
  -- observation.square carries the square instance
  promptPlayerToClean(observation.square)
end)
```

If you want to reuse this across mods or across multiple call sites, you can
optionally package it as a named helper.

Custom helper definition (square helper set extension):

```lua
-- Somewhere in the square helper set definition:

local SquareHelpers = require("WorldObserver/helpers/square")

SquareHelpers.record.squareIsDirty = SquareHelpers.record.squareIsDirty or function(squareRecord)
	return SquareHelpers.record.squareHasCorpse(squareRecord)
		or (type(squareRecord) == "table" and squareRecord.hasTrashItems == true)
end

SquareHelpers.squareIsDirty = SquareHelpers.squareIsDirty or function(stream, fieldName)
	local target = fieldName or "square"
	return stream:filter(function(observation)
		return SquareHelpers.record.squareIsDirty(observation[target])
	end)
end

-- Ensure the stream method is attached (streams attach helpers from `.stream`).
SquareHelpers.stream.squareIsDirty = SquareHelpers.stream.squareIsDirty or function(stream, fieldName, ...)
	return SquareHelpers.squareIsDirty(stream, fieldName, ...)
end
```

Notes:

- `squareIsDirty()` is a thin, named wrapper around a `filter` predicate; it
  does not add new schemas or perform joins.
- Higher-level helpers like this are a good fit when they express “domain truth”
  that many mod features want to share, but you don’t want to add every possible
  combination to the WorldObserver core API.
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
