# ReactiveX primer (for WorldObserver modders)

This page is a gentle introduction to “ReactiveX thinking” for working with WorldObserver observation streams.

You do **not** need to learn all of ReactiveX to use WorldObserver. But learning a few core operators could help you make your mod code smaller and clearer.

## When to use this

Read this page if:

- You already read [The Quickstart](../quickstart.md)
- you already have a working subscription, but your code is getting “state-y” and hard to follow
- You are simply curious and want to learn more about some simple reactive building blocks like `map`, `filter`, `scan`, `buffer`, `distinctUntilChanged`, …


## The basic idea (in one paragraph)

ReactiveX treats “events over time” as a stream:

- a stream emits values over time
- you chain small operators (map/filter/scan/…) to shape the data in the stream
- you subscribe once at the end

This can help to replaces “tick loops + state tables” with small, explicit pipelines.

One important rule: **order matters**. For example, doing `distinct` before `map` can behave very differently than doing it after.

## Two ways to work with observation streams

### 1) Use the built-in WorldObserver stream methods

WorldObserver gives you a few common operators directly on streams:

```lua
WorldObserver.observations:squares()
  :squareHasCorpse()
  :distinct("square", 10)
  :subscribe(function(observation) ... end)
```

### 2) Use lua-reactivex operators via `:asRx()` to access more operators

lua-reactivex provides lots of useful operators like `:map()`, `:filter()`, `:scan()`, `:buffer()`, `:distinctUntilChanged()`, …

WorldObserver streams expose `:asRx()` to get a lua-reactivex Observable:

```lua
local WorldObserver = require("WorldObserver")
local rxStream = WorldObserver.observations:squares():asRx()

rxStream
  :map(function(observation) return observation.square.squareId end)
  :subscribe(print)
```

## Recommended integration pattern

When you want to use `:asRx()` a useful pipeline can look like this:

1) start with a WorldObserver stream  
2) apply WorldObserver helpers (like `squareHasCorpse`, `distinct`)  
3) switch to lua-reactivex via `asRx()`  
4) apply Rx operators (like `map`, `filter`, `scan`)  
5) subscribe and keep the returned `sub` so you can stop later

```lua
local WorldObserver = require("WorldObserver")

local stream = WorldObserver.observations:squares()
  :squareHasCorpse()
  :distinct("square", 10)

local sub = stream
  :asRx()
  :pluck("square", "squareId")
  :distinctUntilChanged()
  :subscribe(function(squareId)
    print(("[WO] corpse on squareId=%s"):format(tostring(squareId)))
  end)

-- later, when your feature turns off:
-- sub:unsubscribe()
```

## A small but important note about `distinct`

WorldObserver’s `:distinct("<dimension>", seconds)` is dimension- and time-window-aware (e.g. “once per square every 10 seconds”).

ReactiveX docs (distinct): https://reactivex.io/documentation/operators/distinct.html

lua-reactivex also has `:distinct()`, but it is **not** the same:

- it is **raw deduplication**: once a value was seen, it will never be emitted again for the lifetime of that subscription
- there is **no time window**
- it has no idea about WorldObserver dimensions like `"square"` or `"zombie"`

As value from the first `:asRx()` is multi-dimensional table that will usually be unique, it is not a good candidate for many of the reactiveX functions that are better suited for scalar values.

In practice, you usually want to `:map(...)` / `:pluck(...)` to a scalar first before using operators like:

- `distinct` / `distinctUntilChanged` (need a stable scalar to compare)
- `groupBy` (needs a key; otherwise you create “groups of tables” that never match)
- `scan` / `reduce` style accumulators (need a small, intentional state shape)
- time/window operators like `debounce` / `throttle` (usually meant for “user intent” signals, not full observation tables)

Rule of thumb: 

1. Use WorldObserver `:distinct(...)` _before_ calling `:asRx()` when you want “once per X per time window”.
2. Use Rx native `:distinct` when _after_ you alreaded `:map`ed to more simple shape and just want to suppress duplicates.


## A short look at some operator use-cases

All examples below assume you have `WorldObserver` required.

### 1) `map`: transform an observation into the value you actually care about

ReactiveX docs (map): https://reactivex.io/documentation/operators/map.html

Example: “turn square observations into just `squareId`”:

```lua
local sub = WorldObserver.observations:squares()
  :asRx()
  :map(function(observation)
    return observation.square.squareId
  end)
  :subscribe(function(squareId)
    print(("[WO] squareId=%s"):format(tostring(squareId)))
  end)
```

Important: `map` changes what flows downstream.

- If you map from a rich `observation` table → scalar  `squareId`, you no longer have access to `observation.square.x` later in the pipeline.
- If you still need multiple fields, map to a *smaller table* instead of a single value:

```lua
local sub = WorldObserver.observations:squares()
  :asRx()
  :map(function(observation)
    local square = observation.square
    return {
      squareId = square.squareId,
      x = square.x,
      y = square.y,
      z = square.z,
      hasCorpse = square.hasCorpse,
    }
  end)
  :subscribe(function(square)
    print(("[WO] squareId=%s corpse=%s"):format(tostring(square.squareId), tostring(square.hasCorpse)))
  end)
```

### 2) `filter`: keep only the observations you want

ReactiveX docs (filter): https://reactivex.io/documentation/operators/filter.html

Example: “only zombies that currently have a target”:

```lua
local sub = WorldObserver.observations:zombies()
  :asRx()
  :filter(function(observation)
    return observation.zombie.hasTarget == true
  end)
  :subscribe(function(observation)
    print(("[WO] zombieId=%s has a target"):format(tostring(observation.zombie.zombieId)))
  end)
```

### 3) `pluck`: pull a field out of a table without writing a custom map

lua-reactivex operator: `external/lua-reactivex/reactivex/operators/pluck.lua`

Example: “get `observation.square.squareId`”:

```lua
local sub = WorldObserver.observations:squares()
  :asRx()
  :pluck("square", "squareId")
  :subscribe(function(squareId)
    print(("[WO] squareId=%s"):format(tostring(squareId)))
  end)
```

### 4) `distinctUntilChanged`: react only when a value changes

ReactiveX docs (distinctUntilChanged): https://reactivex.io/documentation/operators/distinctuntilchanged.html

Example: “only log when `squareId` changes” (no manual `lastSquareId` variable):

```lua
local sub = WorldObserver.observations:squares()
  :asRx()
  :pluck("square", "squareId")
  :distinctUntilChanged()
  :subscribe(function(squareId)
    print(("[WO] moved to squareId=%s"):format(tostring(squareId)))
  end)
```

This is often what you want when you have repeated updates but only care about changes.

### 5) `scan`: keep small “running state” as events arrive

ReactiveX docs (scan): https://reactivex.io/documentation/operators/scan.html

`scan` is a “running accumulator”.

- It keeps a `state` value that you define (the `seed`).
- For every incoming event, it calls your function `(state, value) -> newState`.
- It then emits that `newState` downstream.

This is useful when you want to remember a little bit of state (a counter, a mode flag, “the last X”, …) without writing your own update loop.

Important: observation streams usually don’t end, so you should keep scan state **small and bounded** (numbers, small tables). Avoid “append forever” lists.

Example: “count how many targeted-zombie observations we’ve seen” (a simple counter):

```lua
local sub = WorldObserver.observations:zombies()
  :zombieHasTarget()
  :asRx()
  :scan(function(count, _)
    return count + 1
  end, 0)
  :subscribe(function(count)
    print(("[WO] targeted zombie observations so far: %s"):format(tostring(count)))
  end)
```

Example: “track how many zombies currently have a target” (small in-memory state):

```lua
local sub = WorldObserver.observations:zombies()
  :asRx()
  :scan(function(state, observation)
    local z = observation.zombie
    if type(z) ~= "table" then
      return state
    end

    local zombieId = z.zombieId
    local nowHasTarget = z.hasTarget == true
    local hadTarget = state.targets[zombieId] == true

    if nowHasTarget ~= hadTarget then
      state.targets[zombieId] = nowHasTarget
      state.count = state.count + (nowHasTarget and 1 or -1)
    end

    return state
  end, { targets = {}, count = 0 })
  :map(function(state) return state.count end)
  :distinctUntilChanged()
  :subscribe(function(count)
    print(("[WO] zombies with a target right now: %s"):format(tostring(count)))
  end)
```

When `scan` is not the right tool:

- If you need “group by X” style aggregation with time windows, prefer a windowed/grouping approach from WorldObserver’s query tools. Those handle the bookkeeping for you (per-key state, window eviction), so the state stays naturally bounded.
- `scan` is lower-level and more flexible, but you must implement pruning/reset logic yourself; otherwise its state can grow forever.

### 6) `buffer`: batch events (useful when you want to process in chunks)

ReactiveX docs (buffer): https://reactivex.io/documentation/operators/buffer.html

Example: “process 5 square observations at once”:

```lua
local sub = WorldObserver.observations:squares()
  :asRx()
  :buffer(5)
  :pack() -- turns varargs into a table: batch[1..batch.n]
  :subscribe(function(batch)
    print(("[WO] batch size=%s"):format(tostring(batch.n)))
  end)
```

### 7) `tap`: debug without changing the stream

ReactiveX docs note: in many implementations this operator is called `do`: https://reactivex.io/documentation/operators/do.html

`tap` lets you run a function “in the middle” of a pipeline without changing what flows downstream.

- It is great for `print` debugging.
- You can also use it to count events or add temporary instrumentation.
- It does not filter or transform values (unlike `map`/`filter`).

```lua
local sub = WorldObserver.observations:squares()
  :asRx()
  :tap(function(observation)
    print(("[WO debug] squareId=%s"):format(tostring(observation.square.squareId)))
  end)
  :filter(function(observation) return observation.square.hasCorpse == true end)
  :subscribe(function(_) end)
```

### 8) `share`: avoid accidentally subscribing twice

ReactiveX docs note: `share()` is commonly `publish().refCount()` in other implementations:
- https://reactivex.io/documentation/operators/publish.html
- https://reactivex.io/documentation/operators/refcount.html

Most mods only need **one** `:subscribe(...)`. If that’s you, skip this section.

But sometimes you want *two listeners* for the same stream:
- one prints debug,
- the other updates UI,
- or you want to feed two separate features.

If you do:

- `pipeline:subscribe(...)`
- `pipeline:subscribe(...)`

…then the whole pipeline (everything before `subscribe`) runs twice and you may see duplicated side effects.

`share()` turns “one pipeline” into “one shared source with many listeners”:

```lua
local squaresShared = WorldObserver.observations:squares()
  :asRx()
  :pluck("square", "squareId")
  :share()

local subA = squaresShared:subscribe(function(id) print("[A] " .. tostring(id)) end)
local subB = squaresShared:subscribe(function(id) print("[B] " .. tostring(id)) end)
```

Simpler alternative (often better): do both actions in a single subscription.

## Further reading

- Official ReactiveX docs: https://reactivex.io/
- Operator overview (good for “what should I use?”): https://reactivex.io/documentation/operators.html
- lua-reactivex fork used by WorldObserver: https://github.com/christophstrasen/lua-reactivex
- Local copy in this repo: [external/lua-reactivex/README.md](../../external/lua-reactivex/README.md)
  - Full API list: [external/lua-reactivex/doc/README.md](../../external/lua-reactivex/doc/README.md)

ReactiveX operator deep links are included inline where each operator is introduced above.
