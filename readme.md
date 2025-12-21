# WorldObserver

[![CI](https://github.com/christophstrasen/WorldObserver/actions/workflows/ci.yml/badge.svg)](https://github.com/christophstrasen/WorldObserver/actions/workflows/ci.yml)

*A shared observation layer for **Project Zomboid (Build 42)** mods.*

--- 

**WorldObserver** is a cooperative *world-sensing engine* for Project Zomboid mods. Instead of hand-rolling `OnTick` scan batches, stitching together event listeners, and managing your own cache invalidation, you **declare interest**—*what should we observe, what guarantees for scope and freshness do we need?*—and subscribe to ready-made **observation streams**.

This makes world-observation code compact and declarative. You compose readable pipelines and let the engine handle the execution.

The result is **signal over noise**: rather than processing raw world state, you consume fewer, more actionable observations that directly express *what you actually care about*.

### Tradeoffs

With "WO", as with most high-level frameworks, you sacrifice some control over scope and timing that hand-rolled world-sensing logic provides, in exchange for a more compact, convenient, and expressive way to work across many observations.

Use it for features like *“corpse squares near the player”*, *“chef zombies in kitchens”*, or *“cars under attack”*—and other situations that require richer data and can tolerate asynchronous behavior.

### Good for the players

When multiple mods would otherwise perform heavy scanning in parallel, WorldObserver can help them cooperate by merging overlapping interests, sharing the probing work, enforcing budgets and fairness, and keeping frame time predictable.

---

## Quickstart (hello observation)

This examples hows you how to

1) declare an interest lease (so WorldObserver knows what facts to gather)  
2) subscribe to a base observation stream  
3) stop cleanly (unsubscribe + stop lease)

Full walkthrough:

- [Quickstart](docs/quickstart.md)

```lua
local WorldObserver = require("WorldObserver")

local MOD_ID = "YourModId"

-- note: duration in ingame seconds
local lease = WorldObserver.factInterest:declare(MOD_ID, "quickstart.squares", {
  type = "squares",
  scope = "near",
  target = { player = { id = 0 } }, 
  radius = { desired = 8 },     --tiles
  staleness = { desired = 4 },  -- typical duration between refresh
  cooldown = { desired = 10 },   -- time window in which emmissions are suppressed
})

local corpseSquares = WorldObserver.observations.squares()
  :squareHasCorpse()          -- try removing this line if you see no output
  :distinct("square", 10)
  :subscribe(function(observation)
    local s = observation.square
    print(("[WO] squareId=%s x=%s y=%s z=%s source=%s"):format(
      tostring(s.squareId),
      tostring(s.x),
      tostring(s.y),
      tostring(s.z),
      tostring(s.source)
    ))

    -- Optional: brief visual feedback for the found square
    WorldObserver.highlight(s, 750, { color = { 1.0, 0.2, 0.2 }, alpha = 0.9 })
  end)

_G.WOHello = {
  stop = function()
    if corpseSquares then corpseSquares:unsubscribe(); corpseSquares = nil end
    if lease then lease:stop(); lease = nil end
  end,
}
```

## The model (facts → observations → your logic)

- **Facts** are discovered by WorldObserver (listeners + probes) into which your mod declared an **interest**.
- **Observation streams** then emit plain Lua tables (“observations”) such as `observation.square` or `observation.zombie` 
- These can be used as-is or further refines by your mod turns into a **situations** and **actions**



## What you get (that’s painful to hand-roll)

- **Shared work and fairness:** when multiple mods declare overlapping interest, WorldObserver merges leases and runs shared probing/listening work.
- **Safety knobs:** `radius`, `staleness`, `cooldown` let you express quality expectations while WorldObserver stays within budgets.
- **Signal over noise:** helpers + `distinct` let you compact raw updates into “interesting observations” your mod can act on.
- **Composability:** build derived streams by combining base streams (joins, windows, distinct). Start here: [Derived streams](docs/guides/derived_streams.md).

Under the hood, WorldObserver is powered by LQR + lua-reactivex, but you can ignore that until you need derived streams:

- https://github.com/christophstrasen/LQR

## Status and scope

- **Build:** Project Zomboid Build 42 only.
- **Scope:** v0 is singleplayer-first (player id `0`).
- **Stability:** approaching alpha; naming and shapes may still change.
- **Location in this repo:** `Contents/mods/WorldObserver/42/`.

## Documentation

Docs:

- [Docs index](docs/index.md) (start here)
- [Quickstart](docs/quickstart.md) (copy/paste first working example)
- [Observations overview](docs/observations/index.md) (what you can subscribe to)
- [Glossary](docs/glossary.md) (canonical terminology)
- [Troubleshooting](docs/troubleshooting.md)

---

## License

MIT
