# WorldObserver – API proposal (MVP)

Internal working draft for the public `WorldObserver` Lua API.

This file is a scaffold; details will be filled in as we design.

---

## 1. Anchors and constraints

- TODO

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
  `enabled_helpers`.
- For each key in `enabled_helpers` (e.g. `square`, `zombie`, `spatial`,
  `time`), WorldObserver attaches the corresponding helper set to the
  ObservationStream. Helper sets are thin, domain‑specific refinements that can
  be reused across streams and extended by third parties.
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

## 9. Use cases

### 9.1 Find squares with blood around the player

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
 --decorated Helpers specific to squares
  :distinctPerSquareWithin(10) -- if multiple observations hit the same square, we only use the first
  :maxDistanceTo(playerIsoObject, 20) --compare the live position of the object against the observations
  :hasBloodSplat() --tiny little helper

-- Act on each matching observation as it is discovered.
local subscription = bloodSquares:subscribe(function(obs)
  handleBloodSquare(obs)  -- user-defined action
end)

-- Later, if this Situation is no longer relevant, cancel the subscription.
-- WorldObserver can then relax or stop related probes/fact sources as needed.
subscription:unsubscribe()
```

Notes:

- `squares()` exposes a base ObservationStream; `:maxDistanceTo(...)` and
  `:hasBloodSplat()` are helper‑based refinements attached to that stream.
- `:distinctPerSquare()` (not shown above by default) would be the opt‑in
  helper to only see the first matching observation per square.
- Unsubscribing from the stream (via `subscription:unsubscribe()`) is the
  standard way to end this Situation; any underlying fact strategies are free
  to scale back related work once there are no interested subscribers.

---

## 8. Open questions / to refine

- TODO
