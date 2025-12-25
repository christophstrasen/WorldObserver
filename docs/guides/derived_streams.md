# Guide: derived streams (multi-family observations)

Goal: combine multiple WorldObserver observation streams into a single stream that carries **multiple observation families** at once (example: both `observation.square` and `observation.zombie`).

This is an advanced guide. If you haven’t built a working base subscription yet, start here: [Quickstart](../quickstart.md)


## 1) What “multi-family” means (in practice)

Where a base observation stream emits one family a derived stream can emit _multiple_ families in the same observation that _relate_ to each other.

**Important:** don’t assume all families are present.

- In your `:subscribe(...)` callback, a missing family is usually `nil` (example: `observation.zombie == nil`).
- Inside an LQR Query `:where(function(row) ...)`, you access a row-view where missing schemas are empty tables (`row.zombie` is `{}`), so you can guard by id fields (`row.zombie.zombieId ~= nil`) without nil-check soup.

## 2) Example: join squares + zombies by `squareId`

This joins the square stream with the zombie stream so you can react to zombies *with context about the square they are currently on*.

```lua
local WorldObserver = require("WorldObserver")

-- Interest declarations: keep them separate and explicit.
-- If you manage them globally in your mod you don't need to repeat them before every subscribe!
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

-- Derived ObservationStreams:
local joined = WorldObserver.observations:derive({
  -- `:distinct(...)` is optional, but helps keep join output leaner when you have very busy fact sources (see section 3).
  squares = WorldObserver.observations:squares()
    :distinct("square", 10),
  zombies = WorldObserver.observations:zombies()
    :distinct("zombie", 10),
}, function(lqr)
   -- Note: For LQR interval windows, `time` is milliseconds here.
  return lqr.squares
    :leftJoin(lqr.zombies)
    :using({ square = "squareId", zombie = "squareId" })
    :joinWindow({ time = 5 * 1000, field = "sourceTime" })
end)

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

Deriving streams are built using the LQR streaming query system. If you want to learn more about LQR itself (joins/windows/grouping etc.), start here: [LQR Github](https://github.com/christophstrasen/LQR)

@TODO explain the API better


## 3) Join multiplicity (and when to use `:distinct`)

It is common that both sides of a streaming join emits multiple observations for the same underlying fact, even within a short period of time.

Every time a new record streams in from one side, it tries to match against all records of the other side that are in the join window.

Depending on the number of valid records on each side and the match-criteria this can cause a initially maybe surprings amount of "seemingly duplicate" joined observation records.
However it important to stress that:

1. This is perfectly normal in streaming joins
2. Each joined observation record is in-fact unique as it expresses "a different pair". 

> Think speed-dating - the longer the Evening and the more participants, the more unique pairs appear.

Two common sources of multiplicity:

1) **Many-to-one is real** (domain reality)

One square can legitimately match many zombies (N zombies currently on that square). That is useful: you will get one joined observation per zombie.

2) **Repeated observations multiply** (stream behavior)  

If both streams emit repeated updates for the same ids within the join window, the join can produce a cross-product of those updates. Example (within the join window):

- square `#123` observed 2 times
- zombie `#9` observed 3 times (same `squareId`)
- join output can be 6 emissions for that one logical “zombie on square” situation

`WorldObserver.observations:<type>():distinct(dimension, seconds)` is the simplest lever to keep output leaner:

- `:distinct("square", 1)` limits repeated square observations per `squareId`.
- `:distinct("zombie", 1)` limits repeated zombie observations per `zombieId`.

When to skip `:distinct`:

- If you intentionally want every update (example: you want to react to zombie movement or changing targets), do not deduplicate away those events.
