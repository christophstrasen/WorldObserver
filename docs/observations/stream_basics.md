# Observation streams: basics

Goal: subscribe to a stream, optionally filter/deduplicate it, and stop cleanly.

If you want a complete copy/paste example first, see [Quickstart](../quickstart.md).

## 1. A minimal “start/stop” pattern

```lua
local WorldObserver = require("WorldObserver")

local MOD_ID = "YourModId"

local lease = nil
local sub = nil

local function start()
  if sub then return end

  lease = WorldObserver.factInterest:declare(MOD_ID, "featureKey", {
    type = "squares",
    scope = "near",
    target = { player = { id = 0 } },
  })

  sub = WorldObserver.observations:squares()
    :subscribe(function(observation)
      print(("[WO] squareId=%s source=%s"):format(
        tostring(observation.square.squareId),
        tostring(observation.square.source)
      ))
    end)
end

local function stop()
  if sub then sub:unsubscribe(); sub = nil end
  if lease then lease:stop(); lease = nil end
end
```

Note: one emitted `observation` is a Lua table and can carry multiple “families” at once (for example both `observation.square` and `observation.zombie`). The built-in base streams mostly emit one family, but derived streams can combine them.
See: [Derived streams (multi-family observations)](../guides/derived_streams.md)

Lifecycle details (renewal, TTL override):
- [Lifecycle](../guides/lifecycle.md)

## 2. Filtering

Filtering means: “only keep the observations I actually care about”.

For most mods, filtering has a simple learning path:

1) try a built-in helper (easy, readable)  
2) if you need custom logic (boolean AND/OR etc), use `:whereSquare(...)` / `:whereZombie(...)`  
3) only if you want more operators, switch to `:asRx()` (optional)

### 2.1 Easiest: use a built-in helper

Example: “only squares that have a corpse”:

```lua
local stream = WorldObserver.observations:squares()
  :squareHasCorpse()
```

### 2.2 Custom rules: use `:whereSquare(...)` / `:whereZombie(...)`

These methods call your function with the record you care about (the square record or zombie record).

Tip: create a short local alias once, so your code stays clean:

```lua
local SquareHelper = WorldObserver.helpers.square.record

local stream = WorldObserver.observations:squares()
  :whereSquare(function(squareRecord)
    return SquareHelper.squareHasCorpse(squareRecord) and SquareHelper.squareHasIsoGridSquare(squareRecord)
  end)
```

Zombie example:

```lua
local ZombieHelper = WorldObserver.helpers.zombie.record

local stream = WorldObserver.observations:zombies()
  :whereZombie(ZombieHelper.zombieHasTarget)
```

If you’re just getting started: ignore `stream:filter(...)` for now and stick to helpers + `whereSquare/whereZombie`.

## 3. De-duplicating with `:distinct(dimension, seconds)`

Use `:distinct` to avoid repeats for the same “thing” within a window.

Example: “at most once per square every 10 seconds”:

```lua
local stream = WorldObserver.observations:squares()
  :distinct("square", 10)
```

Notes:
- The `seconds` window uses the **in-game clock** (not real time).
- Dimensions are stream-specific (examples: `"square"`, `"zombie"`).

## 4. More operators with `:asRx()`

If you want more stream operators (map/filter/scan/…), use lua-reactivex via `:asRx()`:

```lua
local rxStream = WorldObserver.observations:squares():asRx()
-- Now you can use lua-reactivex operators:
rxStream:map(function(o) return o.square.squareId end):subscribe(print)
```

More examples:
- [ReactiveX primer](reactivex_primer.md)
