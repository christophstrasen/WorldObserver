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
  :maxDistanceTo(playerIsoObject, 20)
  :withBlood()

-- Act on each matching observation as it is discovered.
local subscription = bloodSquares:subscribe(function(obs)
  handleBloodSquare(obs)  -- user-defined action
end)

-- Optional: cancel early; underlying probes/listeners are unwired.
-- subscription:unsubscribe()
```

Notes:

- `squares()` exposes a base ObservationStream; `:maxDistanceTo(...)` and
  `:withBlood()` are helper‑based refinements attached to that stream.

---

## 8. Open questions / to refine

- TODO
