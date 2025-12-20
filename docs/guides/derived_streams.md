# Guide: derived streams (multi-family observations)

Goal: combine multiple WorldObserver observation streams into a single stream that carries **multiple families** at once (example: both `observation.square` and `observation.zombie`).

This is an advanced guide. If you haven’t built a working base subscription yet, start here:
- [Quickstart](../quickstart.md)

This guide uses LQR joins. If you want to learn LQR itself (joins/windows/grouping), start here:
- https://github.com/christophstrasen/LQR

## 1) What “multi-family” means (in practice)

A normal base observation stream emits one family:
- squares: `observation.square`
- zombies: `observation.zombie`

A derived stream can emit multiple families in the same observation table.

Important: **don’t assume all families are present**.

- In your `:subscribe(...)` callback, a missing family is usually `nil` (example: `observation.zombie == nil`).
- Inside an LQR `:where(function(row) ...)`, LQR gives you a row-view where missing schemas are empty tables (`row.zombie` is `{}`), so you can guard by id fields (`row.zombie.zombieId ~= nil`) without nil-check soup.

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

-- Base observation streams already carry LQR metadata, so they can participate in joins directly.
-- `:distinct(...)` is optional, but helps keep join output leaner when you have very busy fact sources (see section 3).
local squares = WorldObserver.observations.squares()
  :distinct("square", 1)

local zombies = WorldObserver.observations.zombies()
  :distinct("zombie", 1)

-- NOTE: WorldObserver uses millisecond timestamps internally (in-game clock).
-- For low-level LQR interval windows, `time` is therefore milliseconds here.
local joined = Query.from(squares)
  :leftJoin(zombies)
  :using({ square = "squareId", zombie = "squareId" })
  :joinWindow({ time = 5 * 1000, field = "sourceTime", currentFn = Time.gameMillis })

local sub = joined:subscribe(function(observation)
  local square = observation.square
  local zombie = observation.zombie

  -- Left join: `square` is always present; `zombie` may be nil (no match).
  if zombie and zombie.zombieId ~= nil then
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
_G.WODerived = { -- e.g. in console call `WODerived.stop()`
  stop = function()
    if sub then sub:unsubscribe(); sub = nil end
    if squaresLease then squaresLease:stop(); squaresLease = nil end
    if zombiesLease then zombiesLease:stop(); zombiesLease = nil end
  end,
}
```

## 3) Join multiplicity (and when to use `:distinct`)

Streaming joins can emit “more than you expected” because both sides may emit multiple observations for the same underlying fact while the join window is open. This is how observations work. "Yup, the zombie is still there. Yup the square is still there."

Two common sources of multiplicity:

1) **Many-to-one is real** (domain reality)  
One square can legitimately match many zombies (N zombies currently on that square). That is useful: you will get one joined observation per zombie.

2) **Repeated observations multiply** (stream behavior)  
If both streams emit repeated updates for the same ids within the join window, the join can produce a cross-product of those updates. Example (within the join window):
- square `#123` observed 2 times
- zombie `#9` observed 3 times (same `squareId`)
- join output can be 6 emissions for that one logical “zombie on square” situation

`WorldObserver.observations.<type>():distinct(dimension, seconds)` is the simplest lever to keep output leaner:
- `:distinct("square", 1)` limits repeated square observations per `squareId`.
- `:distinct("zombie", 1)` limits repeated zombie observations per `zombieId`.

When to skip `:distinct`:
- If you intentionally want every update (example: you want to react to zombie movement or changing targets), do not deduplicate away those events.

## 4) Keeping multi-family logic readable

Guidelines that help avoid “nil-check soup”:
- Guard by presence: `if observation.zombie and observation.zombie.zombieId ~= nil then ... end`.
- Keep family-local logic in helpers: use `WorldObserver.helpers.square.record` / `WorldObserver.helpers.zombie.record` inside your predicates.
- Bound your windows: keep join windows short and use `:distinct(...)` upstream to limit join multiplicity.