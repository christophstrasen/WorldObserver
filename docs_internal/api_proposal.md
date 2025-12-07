# WorldObserver – API proposal (MVP)

Internal working draft for the public `WorldObserver` Lua API.

This file is a scaffold; details will be filled in as we design.

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
  (e.g. `distinctPerSquareWithin(seconds)`), with a dedicated escape hatch for
  full LQR control.
- **Custom observations via registration:** new ObservationStreams are defined
  by registering a `build` function plus `enabled_helpers`; they integrate into
  the same helper and Fact infrastructure as built‑in streams.

---

## 2. Mapping the “Before” lifecycle to WorldObserver

- TODO

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

- ObservationStreams are exposed under `WorldObserver.observations.<name>()`.
- New ObservationStreams are registered with a small config table, e.g.
  `register("my_mod.hedgeZombies", { build = …, enabled_helpers = { square = "SquareObs", zombie = "ZombieObs" } })`.
- The `build` function (details TBD) is free to use LQR/Rx; its only contract is
  that the produced observations contain the schemas referenced in
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
  window configs. Typical domain helpers are:
  - `:distinctPerSquare()` / `:distinctPerSquareWithin(seconds)` as thin
    wrappers around `distinct` for square‑keyed deduplication; and
  - analogous helpers for other domains (e.g. zombies) when needed.
  Full LQR tuning remains available via an advanced escape hatch
  (e.g. `stream:getLQR()`).

---

## 5. Situations

- TODO

---

## 6. Actions

- TODO

---

## 7. Debugging and tooling

- TODO

---

## 8. Use cases

### 8.1 Find squares with blood around the player

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
  :distinctPerSquareWithin(10)        -- only the first observation per square within 10s
  :nearIsoObject(playerIsoObject, 20) -- compare the live position of the IsoObject against the observation
  :squareHasBloodSplat()              -- tiny helper to keep only squares with blood

-- Act on each matching observation as it is discovered.
local subscription = bloodSquares:subscribe(function(obs)
  handleBloodSquare(obs)  -- user-defined action
end)

-- Later, if this Situation is no longer relevant, cancel the subscription.
-- WorldObserver can then relax or stop related probes/fact sources as needed.
subscription:unsubscribe()
```

Notes:

- `squares()` exposes a base ObservationStream; `:nearIsoObject(...)` and
  `:squareHasBloodSplat()` are helper‑based refinements attached to that stream.
- `:distinctPerSquare()` (not shown above by default) would be the opt‑in
  helper to only see the first matching observation per square.
- Unsubscribing from the stream (via `subscription:unsubscribe()`) is the
  standard way to end this Situation; any underlying fact strategies are free
  to scale back related work once there are no interested subscribers.

---

### 8.2 Chef zombie in kitchen (drive cooking sound)

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
  :roomIsKitchen()
  :zombieHasChefOutfit()
  :subscribe(function(obs)
    -- obs carries at least roomId and zombie info
    updateKitchenCookingSound(obs.roomId, obs)
  end)
```

Notes:

- Joins between zombies and rooms happen inside the `roomZombies`
  ObservationStream definition (LQR) and are not performed by helpers.
- Helpers like `:roomIsKitchen()` and `:zombieHasChefOutfit()` only reduce the
  stream (filtering) and do not introduce new data sources; the subscription
  can maintain its own “any chef zombie present?” state to start/stop sounds.

---

### 8.3 Cars under attack (custom multi-source ObservationStream)

Traditional intent:

- When at least three zombies are attacking the same car at (roughly) the same
  time, treat the car as “under attack” and shake it.

WorldObserver‑style usage (mod-facing API):

```lua
local WorldObserver = require("WorldObserver")

local vehiclesUnderAttackSubscription = WorldObserver.observations.vehiclesUnderAttack()
  :withConfig({ minZombies = 3 })
  :vehicleWeightBelow(1200)   -- don’t shake heavy vehicles
  :subscribe(function(obs)
    shakeVehicle(obs.vehicleId, obs)
  end)
```

Advanced definition (custom ObservationStream with three sources):

```lua
WorldObserver.observations.register("vehiclesUnderAttack", {
  enabled_helpers = { vehicle = "VehicleObs" },

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
  helpers (for example `vehicleWeightBelow(...)`) then operate on the attached
  `VehicleObs` schema.

---

## 10. Open questions / to refine

- TODO
