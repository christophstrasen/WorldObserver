# Guide: derived streams (multi-family observations)

Goal: combine multiple WorldObserver observation streams into a single stream that carries **multiple observation families** at once (example: both `observation.square` and `observation.zombie`).

This is an advanced guide. If you haven’t built a working base subscription yet, start here: [Quickstart](../quickstart.md)

---

## 1) Multi-family observations (what you get)

A base observation stream emits one family (example: `observation.zombie` only). A derived stream can emit **multiple** families in the same observation that relate to each other (because you joined/grouped them).

**Important:** don’t assume all families are present.

- In your `:subscribe(...)` callback, a missing family is usually `nil` (example: `observation.zombie == nil`). In some grouped/enriched queries the “row view” shape can leak through (schemas are tables), so the safest guard is still “by id field”.
- Inside an LQR predicate (`:where(...)`, `:groupBy(...)`, `:having(...)`), you use the **row view** where missing schemas are empty tables (`row.zombie` is `{}`), so you can guard by id fields (`row.zombie.zombieId ~= nil`) without lots of nil checks.

---

## 2) `:derive(...)` (how to read it)

Derived streams are built using the LQR streaming query system, but you usually don’t need to “learn LQR first”.

The key points:

1. **Interest declarations stay separate.** `:derive(...)` does not declare interest for you; facts only flow if at least one lease exists for the involved fact types.
2. **You provide input streams by name.** Those names become the schema keys you’ll see in LQR row views (`row.square`, `row.zombie`, ...).
3. **The build function receives LQR builders.** Inside `function(lqr) ... end`, `lqr.square`, `lqr.zombie`, etc. are join-ready LQR `QueryBuilder`s.
4. **Return a query; don’t subscribe inside `buildFn`.** Work only starts once you subscribe to the derived stream.

### 2.1 Going lower-level (optional): `:getLQR()` and `:asRx()`

Most of the time, `:derive(...)` is the cleanest way to use LQR.

If you need it:
- Every WorldObserver stream supports `:getLQR()` (advanced). It returns an LQR `QueryBuilder` rooted at the stream’s **visible output schemas** (e.g. `"square"`, `"zombie"`), so joins behave like you expect.
- For “classic ReactiveX operators” like `map`, `filter`, `scan`, `buffer`, etc., use `:asRx()` and follow the [ReactiveX primer](../observations/reactivex_primer.md).

Minimal shape:

```lua
local WorldObserver = require("WorldObserver")

local derived = WorldObserver.observations:derive({
  -- Tip: use the schema keys you want to join/group on (usually singular: square/zombie/sprite/...).
  square = WorldObserver.observations:squares(),
  zombie = WorldObserver.observations:zombies(),
}, function(lqr)
  return lqr.square
    :innerJoin(lqr.zombie)
    :using({ square = "squareId", zombie = "squareId" })
    :joinWindow({ time = 5 * 1000 }) -- milliseconds
end)

local sub = derived:subscribe(function(observation)
  -- use observation.square / observation.zombie
end)
```

---

## 3) Example: join squares + zombies by `squareId`

This joins the square stream with the zombie stream so you can react to zombies *with context about the square they are currently on*.

```lua
local WorldObserver = require("WorldObserver")

-- Interest declarations: keep them separate and explicit.
local squaresLease = WorldObserver.factInterest:declare("YourModId", "derived.squares", {
  type = "squares",
  scope = "near",
  -- . . . 
})

local zombiesLease = WorldObserver.factInterest:declare("YourModId", "derived.zombies", {
  type = "zombies",
  scope = "allLoaded",
  -- . . . 
})

local joined = WorldObserver.observations:derive({
  square = WorldObserver.observations:squares(),
  zombie = WorldObserver.observations:zombies(),
}, function(lqr)
  return lqr.square
    :leftJoin(lqr.zombie)
    :using({ square = "squareId", zombie = "squareId" })
    :joinWindow({ time = 5 * 1000 }) -- milliseconds
end)

local sub = joined:subscribe(function(observation)
  local square = observation.square
  local zombie = observation.zombie

  -- Left join: `square` is always present; `zombie` may be nil (no match).
  if zombie ~= nil and zombie.zombieId ~= nil then
    print(("[WO derived] zombieId=%s on square x=%s y=%s z=%s corpse=%s"):format(
      tostring(zombie.zombieId),
      tostring(square.x),
      tostring(square.y),
      tostring(square.z),
      tostring(square.hasCorpse)
    ))
  end
end)

-- don't forget to clean up: stop both subscriptions and both leases when your feature turns off.
-- . . .

```

If you see “too many” joined emissions, jump to section 5 (`distinct` and join multiplicity).

---

## 4) Windows, time, and “freshness” (the nuance that matters)

Streaming joins/grouping are all about time windows. In WorldObserver, every fact record carries a `sourceTime` timestamp (milliseconds, in-game clock). LQR uses that as `RxMeta.sourceTime` internally, which is what time windows operate on.

### 4.1 Units cheat sheet

WorldObserver has both “seconds settings” and “milliseconds settings”:

| Setting | Where | Unit |
|------|-------|------|
| `interest.staleness`, `interest.cooldown` | `factInterest:declare(...)` | seconds |
| `ObservationStream:distinct(dimension, seconds)` | WorldObserver stream sugar | seconds |
| `joinWindow({ time = ... })` | inside `:derive(..., function(lqr) ...)` | **milliseconds** |
| `groupWindow({ time = ... })` | inside `:derive(..., function(lqr) ...)` | **milliseconds** |
| LQR `distinct(..., window={ time=... })` | inside `:derive(..., function(lqr) ...)` | **milliseconds** |

Rule of thumb: if you are inside the LQR chain (`lqr.*:innerJoin(...):joinWindow(...):groupWindow(...)`), `time` is in **milliseconds**.

### 4.2 Join window = “relationship availability”

`joinWindow` controls how long LQR keeps recent records around to form matches.

- **Too small:** you can miss matches when the two sources don’t emit close together.
- **Too large:** you can match against stale context (and you can increase join multiplicity).

This is not your “gameplay rule window”. It’s the “can these two streams still be paired?” window.

### 4.3 Group window = “domain rule window”

`groupWindow` controls how long past rows remain inside a group for aggregation (“within the last N seconds”).

Example: “at least 2 distinct zombies have been on this tile in the last 10 seconds”.

This is a different question than joining. It’s totally reasonable to have:

- a **larger join window** so you can still join a fresh zombie with a slightly old sprite/square context, and
- a **smaller group window** so only recent zombie presence counts toward your rule.

The important detail: a time-based group window uses the timestamp field you specify (example: `field = "zombie.sourceTime"`). Rows that arrive “late” with an old `zombie.sourceTime` won’t contribute to the current sliding window (they are already “in the past”).

---

## 5) Join multiplicity (and when to use `distinct` / `oneShot`)

It is common that both sides of a streaming join emit multiple observations for the same underlying fact, even within a short period of time.

Every time a new record streams in from one side, it tries to match against all records of the other side that are still inside the join window. That can produce a surprisingly large amount of joined emissions.

Two common sources of multiplicity:

1) **Many-to-one is real** (domain reality)  
One square can legitimately match many zombies (N zombies currently on that square). That is useful: you will get one joined observation per zombie.

2) **Repeated observations multiply** (stream behavior)  
If both streams emit repeated updates for the same ids within the join window, the join can produce a cross-product of those updates.

There are two places you can deduplicate, and they solve slightly different problems:

- **Upstream distinct** (WorldObserver sugar): reduces how many repeated observations ever reach your join/group logic.
  - Example: `WorldObserver.observations:zombies():distinct("zombie", 2)` (seconds)
- **Post-join distinct** (LQR distinct inside the chain): keeps the join/group results lean and is especially important if downstream work is effectful (spawn/remove/log once).

Side note: join-side `oneShot` is a different setting than `distinct`. It controls join multiplicity by giving each cached record a single “match ticket” on a specific join step (consume-on-match), which can be useful for lookup/dimension-style joins. For the deeper LQR explanation of `distinct` (and how it relates to `oneShot`), see: https://github.com/christophstrasen/LQR/blob/main/docs/concepts/distinct_and_dedup.md

---

## 6) Advanced example: “trample a hedge tile”

This is the core pattern for “something interesting”:

1. Join two families by a shared key (`tileLocation`).
2. Group per tile.
3. Count distinct zombies in a sliding time window.
4. Use `having(...)` to only emit “actionable” rows.
5. Do the effect once (remove the tile object).

Compact sketch:

```lua
local WorldObserver = require("WorldObserver")

local stream = WorldObserver.observations:derive({
  zombie = WorldObserver.observations:zombies(),
  sprite = WorldObserver.observations:sprites(),
}, function(lqr)
  return lqr.zombie
    :innerJoin(lqr.sprite)
    :using({ zombie = "tileLocation", sprite = "tileLocation" })
    :joinWindow({ time = 50 * 1000 }) -- ms: allow slightly stale sprites to still match
    :distinct("zombie", { by = "zombieId", window = { time = 300 } }) -- ms: reduce spam
    :distinct("sprite", { by = "spriteKey", window = { time = 300 } })
    :groupByEnrich("tileLocation_grouped", function(row)
      return row.zombie.tileLocation
    end)
    :groupWindow({ time = 10 * 1000, field = "zombie.sourceTime" }) -- ms: rule window
    :aggregates({
      row_count = false,
      count = {
        {
          path = "zombie.zombieId",
          distinctFn = function(row)
            local zombieId = row and row.zombie and row.zombie.zombieId
            return zombieId ~= nil and tostring(zombieId) or nil
          end,
        },
      },
    })
    :having(function(row)
      return (row._count and row._count.zombie or 0) >= 2
    end)
end)

stream:subscribe(function(obs)
  if obs.sprite and obs.sprite.IsoGridSquare and obs.sprite.IsoObject then
    obs.sprite.IsoGridSquare:RemoveTileObject(obs.sprite.IsoObject)
  end
end)
```

Notes:
- The distinct zombie count is available at `row._count.zombie` (per-schema total) and at `row.zombie._count.zombieId` (per-field); in this example they are the same.
- In an inner join on the same key, `row.zombie.tileLocation` and `row.sprite.tileLocation` are the same; either works as the group key.

Full runnable example (with interests and safe unsubscribe): `Contents/mods/WorldObserver/42/media/lua/shared/examples/hedge_trample.lua`

---

## 7) Keeping multi-family logic readable

Guidelines that help avoid “nil-check soup”:

- Guard by presence: `if observation.zombie and observation.zombie.zombieId ~= nil then ... end`.
- Keep family-local logic in helpers: use `WorldObserver.helpers.square.record` / `WorldObserver.helpers.zombie.record` inside your predicates.
- Prefer stream-attached helper namespaces (avoids collisions across families):
  - `joined.helpers.square:squareHasCorpse()` / `joined.helpers.zombie:zombieHasTarget()`
- Use `:distinct(...)` upstream when you want calmer inputs, and use post-join distinct/having when you want to protect effectful actions.

Want to go deeper into LQR concepts used by derived streams:
- Join windows and multiplicity: https://github.com/christophstrasen/LQR/blob/main/docs/concepts/joins_and_windows.md
- Row view and `where`: https://github.com/christophstrasen/LQR/blob/main/docs/concepts/where_and_row_view.md
- Grouping and `having`: https://github.com/christophstrasen/LQR/blob/main/docs/concepts/grouping_and_having.md
