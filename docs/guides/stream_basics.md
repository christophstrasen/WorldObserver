# Guide: stream basics

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
See: [Derived streams (multi-family observations)](derived_streams.md)

Lifecycle details (renewal, TTL override):
- [Lifecycle](lifecycle.md)

## 1.1 Observation keys (`WoMeta.key`)

WorldObserver attaches a stable-ish domain key to every emission:

- Each record has `record.woKey` (string), computed in the record builder.
- Each observation has `observation.WoMeta.key`, built from those record keys.
- Multi-family observations use compound keys (example: `#square(x1y2z0)#zombie(4512)`).
- If a key can’t be computed, a warning is logged and `WoMeta.key` is left missing.
  - Downstream should treat `WoMeta.key` as **best-effort** and handle `nil`.

Overview (what each base family uses as `woKey` + stability notes):
- [Base observable facts](../observations/base_observable_facts.md)

## 2. Filtering

Filtering means: “only keep the observations I actually care about”.

For most mods, filtering has a simple learning path:

There is a learning curve starting with simple inbuilt filtering to custom queries Rx. 

1) try a built-in helper (easy, readable)  
2) apply your own per-record logic (boolean AND/OR etc), use `:squareFilter(...)` / `:zombieFilter(...)`  
3) only if you want more operators:
   - for joins/windows/grouping: use `WorldObserver.observations:derive(...)` (see [Derived streams](derived_streams.md))
   - for ReactiveX operators: use `:asRx()` (see [ReactiveX primer](../observations/reactivex_primer.md))

### 2.1 Easiest: use a built-in *stream* helper

Example: “only squares that have a corpse”:

```lua
local stream = WorldObserver.observations:squares()
  :squareHasCorpse()
```

Note: These helpers are attached directly to a stream and can act as short-hand filters.

[To read more on Helpers click here](helpers.md)

### 2.2 Your own per-record filter logic via `:squareFilter(...)` / `:zombieFilter(...)`

These methods call your function with the record you care about (the square record or zombie record).

Within the closure you can run any logic and inspect the given record.
Additonally you may use *record* helpers as shown below. Unlike the *stream* helpers above, these don't attach directly in order to keep records pure lua data tables.


```lua
local SquareHelper = WorldObserver.helpers.square.record

local stream = WorldObserver.observations:squares()
  :squareFilter(function(squareRecord)
    return SquareHelper.squareHasCorpse(squareRecord) and (squareRecord.z or 0) < 0 -- example: basement corpses
  end)
```


### 2.3 Attach third-party helpers (optional)

If you have a helper set from another mod (or your own), you can attach it to any stream:

```lua
local UnicornHelpers = require("YourMod/helpers/unicorns")

local stream = WorldObserver.observations:squares()
  :withHelpers({
    helperSets = { unicorns = UnicornHelpers },
    enabled_helpers = { unicorns = "square" },
  })

-- Fluent call (helpers attach as stream methods by default):
stream:unicorns_squareIdIs(123)

-- Or namespaced:
stream.helpers.unicorns:unicorns_squareIdIs(123)
```

If a helper family is registered globally, you can attach it without passing the helper set table:

```lua
WorldObserver.observations:registerHelperFamily("unicorns", UnicornHelpers)

local stream = WorldObserver.observations:squares()
  :withHelpers({
    enabled_helpers = { unicorns = "square" },
  })
```

## 3. De-duplicating with `:distinct(dimension, seconds)`

If you are interested to observe "Unique" facts this one way to achieve it is `:distinct` to avoid repeats for the same underylying fact within a window.

Note: This version of `:distinct` is a high-level stream helper which uses the stream’s dimension mapping (“primary key”) to establish uniqueness. If you need join-aware deduplication or custom distinct keys, use `WorldObserver.observations:derive(...)` (see [Derived streams](derived_streams.md)).

Example: “at most once per square every 10 seconds”:

```lua
local stream = WorldObserver.observations:squares()
  :distinct("square", 10) 
```

## 4. More operators with `:asRx()`

If you want more stream operators (map/filter/scan/…), use lua-reactivex via `:asRx()`:

```lua
local rxStream = WorldObserver.observations:squares():asRx()
-- Now you can use lua-reactivex operators:
rxStream:map(function(o) return o.square.squareId end):subscribe(print)
```

More examples: [ReactiveX primer](../observations/reactivex_primer.md)
