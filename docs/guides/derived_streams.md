# Guide: derived streams (multi-family observations)

Goal: combine multiple WorldObserver observation streams into a single stream that carries **multiple families** at once (example: both `observation.square` and `observation.zombie`).

This is an advanced guide. If you haven’t built a working base subscription yet, start here:
- [Quickstart](../quickstart.md)

## 1) What “multi-family” means (in practice)

A normal base observation stream emits one family:
- squares: `observation.square`
- zombies: `observation.zombie`

A derived stream can emit multiple families in the same observation table.

Important: **don’t assume all families are present**. In joins, a “missing side” typically shows up as an empty table (`{}`), so check for an id field (example: `observation.zombie.zombieId ~= nil`) before using it.

## 2) Example: join squares + zombies by `squareId`

This joins the square stream with the zombie stream so you can react to zombies *with context about the square they are currently on*.

```lua
local WorldObserver = require("WorldObserver")
local LQR = require("LQR")
local Query = LQR.Query
local Time = require("WorldObserver/helpers/time")

-- Interest declarations: keep them separate and explicit.
-- (If you forget these leases, the streams may be silent.)
local squaresLease = WorldObserver.factInterest:declare("YourModId", "derived.squares", {
  type = "squares",
  scope = "near",
  target = { player = { id = 0 } }, -- v0: singleplayer local player
  radius = { desired = 10 },
  staleness = { desired = 5 },
  cooldown = { desired = 2 },
})

local zombiesLease = WorldObserver.factInterest:declare("YourModId", "derived.zombies", {
  type = "zombies",
  scope = "allLoaded",
  radius = { desired = 25 },
  zRange = { desired = 0 },
  staleness = { desired = 2 },
  cooldown = { desired = 2 },
})

-- Turn base observation streams into record streams (one record per emission),
-- by plucking the family record out of each observation.
-- The records still carry LQR metadata (RxMeta) so they can participate in joins.
local squares = WorldObserver.observations.squares()
  :distinct("square", 1)
  :asRx()
  :pluck("square")

local zombies = WorldObserver.observations.zombies()
  :distinct("zombie", 1)
  :asRx()
  :pluck("zombie")

-- NOTE: WorldObserver uses millisecond timestamps internally (in-game clock).
-- For low-level LQR interval windows, `time` is therefore milliseconds here.
local joined = Query.from(squares, "square")
  :leftJoin(zombies, "zombie")
  :using({ square = "squareId", zombie = "squareId" })
  :joinWindow({ time = 5 * 1000, field = "sourceTime", currentFn = Time.gameMillis })

local sub = joined:subscribe(function(observation)
  local square = observation.square
  local zombie = observation.zombie

  -- Left join: square is always present, zombie may be missing (empty table).
  if zombie.zombieId ~= nil then
    print(("[WO derived] zombieId=%s on square x=%s y=%s z=%s corpse=%s"):format(
      tostring(zombie.zombieId),
      tostring(square.x),
      tostring(square.y),
      tostring(square.z),
      tostring(square.hasCorpse)
    ))
  end
end)

-- Cleanup: stop both subscriptions and both leases when your feature turns off.
_G.WODerived = {
  stop = function()
    if sub then sub:unsubscribe(); sub = nil end
    if squaresLease then squaresLease:stop(); squaresLease = nil end
    if zombiesLease then zombiesLease:stop(); zombiesLease = nil end
  end,
}
```

## 3) Keeping multi-family logic readable

Guidelines that help avoid “nil-check soup”:
- Guard by id: `if observation.zombie.zombieId ~= nil then ... end`.
- Keep family-local logic in helpers: use `WorldObserver.helpers.square.record` / `WorldObserver.helpers.zombie.record` inside your predicates.
- Bound your windows: keep join windows short and use `:distinct(...)` upstream to limit join multiplicity.

Next:
- [Stream basics](../observations/stream_basics.md)
