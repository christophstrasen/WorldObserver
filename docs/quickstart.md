# Quickstart (WorldObserver)

Goal: subscribe to a WorldObserver observation and get a visible/logged result in-game.

## 1. Prereqs

- Enable the `WorldObserver` mod (and its dependency `StarlitLibrary`) in your save.
- Ensure `WorldObserver` loads before your mod.

## 2. Add a tiny “hello observation” script

Create a file in your mod:

- `media/lua/client/WOQuickstart.lua`

Paste:

```lua
local WorldObserver = require("WorldObserver")

local MOD_ID = "YourModId"

-- Declare interest: tell WorldObserver what you want it to look at, and how often.
-- If you skip this, you may not get any observations at all
local lease = WorldObserver.factInterest:declare(MOD_ID, "quickstart.squares", {
  type = "squares.nearPlayer",
  radius = { desired = 8 },
  staleness = { desired = 5 },
  cooldown = { desired = 2 },
})

local sub = WorldObserver.observations.squares()
  :squareHasCorpse()          -- Only when at least one corpse is found
  :distinct("square", 10)     -- We don't want repeat observations more frequent than every 10 seconds
  :subscribe(function(observation)
    print(("[WO quickstart] Corpse observed on squareId=%s x=%s y=%s z=%s via fact source=%s"):format(
      tostring(observation.square.squareId),
      tostring(observation.square.x),
      tostring(observation.square.y),
      tostring(observation.square.z),
      tostring(observation.square.source)
    ))

    -- Optional: visual feedback (client-only). Highlights the square floor briefly.
    WorldObserver.highlight(square, 750, { color = { 1.0, 0.2, 0.2 }, alpha = 0.9 })
  end)

-- IMPORTANT: you should stop your subscription and lease when you no longer need them.
-- (Example: feature toggled off, UI closed, etc.). Code below is so you can stop via zomboid console
_G.WOQuickstart = {
  stop = function()
    if sub then
      sub:unsubscribe()
      sub = nil
    end
    if lease then
      lease:stop()
      lease = nil
    end
  end,
}
```

### Why declare interest?

- It tells WO *how far* to probe (`radius`) or what else to listen to and *how fresh* results should be (`staleness`/`cooldown`).

### Lease renewal and cleanup

- Interest declarations are leases and can expire if you don’t renew them.
- For long-running features, periodically call `lease:touch()` (for example once per minute).
- Always call `sub:unsubscribe()` and `lease:stop()` when your feature turns off.

See `docs/guides/lifecycle.md` for the recommended patterns.

## 3. Verify it works

- Load into a save (singleplayer is easiest for first verification).
- Walk around until you see log lines like `WO quickstart] Corpse observed ...`.
- If highlighting is available, affected squares should flash briefly.

If you see nothing, the most common causes:

- Your file isn’t being loaded (ensure it’s under `media/lua/client/` or required from an existing entrypoint).
- `WorldObserver` isn’t enabled / loads after your mod.
- You’re in an area with no squares matching the predicate (try removing `:squareHasCorpse()` temporarily).
