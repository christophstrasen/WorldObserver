# WorldObserver

[![CI](https://github.com/christophstrasen/WorldObserver/actions/workflows/ci.yml/badge.svg)](https://github.com/christophstrasen/WorldObserver/actions/workflows/ci.yml)

*A shared observation layer for **Project Zomboid (Build 42)** mods written in Lua.*

WorldObserver helps mods **observe what is happening in the world — safely, fairly, and over time** — without each mod re‑implementing fragile scan loops, throttling logic, and ad‑hoc state tracking.

**30-second overview**

WorldObserver is a cooperative “world sensing engine” for Project Zomboid mods. Instead of hand-rolling `OnTick` scan batches, multiple interweaving event-listeners, and your own cache-invalidation, you **declare interest** (“what should we watch, and how fresh do you need it?”) and then subscribe to ready-made **observation streams**.

This makes “world watching” code feel compact and declarative: you chain readable operations (helpers, `distinct`, joins) and let the engine do the looping, scheduling, and throttling. The result is **signal above noise**: instead of processing raw world state, you subscribe to fewer, more actionable observations can more easily express “what you really care about”.

Use it for features like “corpse squares near the player”, “chef zombies in kitchens”, or “cars under attack” — and other more advanced situations.

The player-facing payoff is smoother FPS: when several mods would otherwise run heavy scanning in parallel, WorldObserver makes them cooperate by merging overlapping interests, sharing the probing work enforcing budgets and fairness and thus keeping frame time predictable.

Start here: [Quickstart](docs/quickstart.md), then follow the [docs index](docs/index.md).

---

## Quickstart (hello observation)

This is the smallest end-to-end usage:
1) declare an interest lease (so WorldObserver knows what facts to gather)  
2) subscribe to a base observation stream  
3) stop cleanly (unsubscribe + stop lease)

Full walkthrough:
- [Quickstart](docs/quickstart.md)

```lua
local WorldObserver = require("WorldObserver")

local MOD_ID = "YourModId"

-- NOTE: time knobs use the in-game clock (seconds), not real-time seconds.
local lease = WorldObserver.factInterest:declare(MOD_ID, "quickstart.squares", {
  type = "squares",
  scope = "near",
  target = { player = { id = 0 } }, -- v0: singleplayer local player
  radius = { desired = 8 },
  staleness = { desired = 5 },
  cooldown = { desired = 2 },
})

local sub = WorldObserver.observations.squares()
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

    -- Optional: brief visual feedback (client-only).
    WorldObserver.highlight(s, 750, { color = { 1.0, 0.2, 0.2 }, alpha = 0.9 })
  end)

_G.WOHello = {
  stop = function()
    if sub then sub:unsubscribe(); sub = nil end
    if lease then lease:stop(); lease = nil end
  end,
}
```

## The model (facts → observations → your logic)

- **Facts** are discovered by WorldObserver (listeners + probes).
- Your mod declares an **interest** (“what to focus on, and how fresh”), which returns a **lease**.
- **Observation streams** emit plain Lua tables (“observations”) such as `observation.square` or `observation.zombie`.
- Your mod turns observations into **situations** and **actions** (WorldObserver intentionally stops at observation).

Canonical definitions:
- [Glossary](docs/glossary.md)

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
