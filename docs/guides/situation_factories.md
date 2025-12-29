# Guide: situation factories (named situations)

Situation factories let you name and parameterize reusable “situations".

They are **optional**. If you don’t need reuse or a stable name for a pipeline, just subscribe to `WorldObserver.observations:*` directly.

## 1) What a situation factory is (in one sentence)

A situation factory is a function you register under a name that returns a **hot, subscribable stream** that emits **WorldObserver observations**.

## 2) Why use it

Use situation factories when you want:

- A reusable, named pipeline (so you can subscribe in multiple places without copy/pasting the builder code).
- A way to make "small variations of more complex builder code" work on the fly without too much boilerplate
- A stable “handle” (`namespace + situationId + args`) that other systems can reference.

## 3) The API (namespaced facade)

WorldObserver assumes that situations are specific to your mod so always start by selecting a namespace (your mod id can be a good default):

```lua
local WorldObserver = require("WorldObserver")
local situations = WorldObserver.situations.namespace("MyModId")
```

Then you can:

- `situations.define(situationId, factoryFn[, opts])`
- `situations.get(situationId[, args])` → returns a stream (not subscribed yet)
- `situations.subscribeTo(situationId[, args], onNext)` → shorthand for `get(...):subscribe(...)`
- `situations.list()` → returns "situations" you registered under their `situationId` this namespace
- `situations.listAll()` → returns fully-qualified keys across all namespaces, from all mods

Notes:
- `situationId` must be a non-empty string.
- `args` may be `nil` (treated as `{}`).
- Redefining the same `situationId` overwrites the previous definition (expected).

## 4) Example: a named zombie outfit situation

This is a minimal “define + subscribe + stop” pattern.
It also shows the important boundary: **fact interest is still separate**.

```lua
local WorldObserver = require("WorldObserver")

local MOD_ID = "MyModId"
local situations = WorldObserver.situations.namespace(MOD_ID)

-- Define once (typically at load time).
situations.define("zombiesWithOutfit", function(args)
  args = args or {}
  return WorldObserver.observations:zombies()
    :hasOutfit(args.outfitName)
end)

-- Later: subscribe when your feature is enabled.
local lease = WorldObserver.factInterest:declare(MOD_ID, "zombiesWithOutfit", {
  type = "zombies",
  scope = "allLoaded",
})

local sub = situations.subscribeTo("zombiesWithOutfit", { outfitName = "Biker" }, function(observation)
  local zombie = observation.zombie
  print(("[WO] zombieId=%s outfit=%s"):format(
    tostring(zombie.zombieId),
    tostring(zombie.outfitName)
  ))
end)

_G.MySituationHandle = {
  stop = function()
    if sub then sub:unsubscribe(); sub = nil end
    if lease then lease:stop(); lease = nil end
  end,
}
```

### Occurrance key override (optional)

If a downstream system wants a different “act once per …” key, you can opt in per situation:

```lua
situations.define("zombiesWithOutfit", function(args)
  args = args or {}
  return WorldObserver.observations:zombies()
    :hasOutfit(args.outfitName)
    :withOccurrenceKey("zombie")
end)
```

Notes:
- The override sets `observation.WoMeta.occurranceKey`.
- If the override yields `nil`, the emission still flows and a warning is logged.

## 5) Stream semantics (important)

- `situations.get(...)` returns a stream that is **not subscribed** yet.
- Subscribing is **hot by default**: you observe “from now on” (no replay unless the factory implements it explicitly).
- Multiple subscribers attach to the live stream; later subscribers do not “start at the beginning”.

## 6) Errors and safety

- Missing definition: `situations.get("missing")` is a hard error.
- If a factory throws during `get(...)`, that error is propagated.

For durable consumers (for example systems restoring persisted work), wrap `get(...)` + `subscribe(...)` in an error envelope:
- Always log the error.
- Only rethrow when `getDebug()` is true.

## 7) Advanced note: derived streams inside factories

Factories should usually return an `ObservationStream` (from `WorldObserver.observations:*`) or a derived stream built via `WorldObserver.observations:derive(...)`.

Avoid subscribing to raw LQR queries unless you know what you’re doing; it can bypass WorldObserver’s lifecycle wiring.
