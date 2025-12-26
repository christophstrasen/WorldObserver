# Guide: declaring interest

Goal: tell WorldObserver which facts to gather for your mod, where to focus, and how fresh those observations should be.

WorldObserver does **not** probe or listen for fact sources unless at least one mod declares an interest.
Declaring interest is also how multiple mods share probing fairly: 'WO' merges interest across mods and then chooses an effective strategy that fits inside runtime budgets so that the user framerate stays unaffected.

If you haven’t run the first working example yet, start here:
- [Quickstart](../quickstart.md)

## 1. The smallest useful interest declaration

This declaration asks WorldObserver to probe squares near the player:

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "squares",
  scope = "near",
  target = { player = { id = 0 } },
  radius = { desired = 8 },     -- tiles around player
  staleness = { desired = 5 },  -- target freshness (seconds, in-game clock)
  cooldown = { desired = 2 },   -- per-square re-emit limit (seconds, in-game clock)
})
```

Notes:
- `modId` + `key` identify your feature. Calling `declare` again for the same pair replaces your spec.
- The returned `lease` must be managed (renew/stop); see [Lifecycle](lifecycle.md).

## 2. Type, scope, target (what they mean)

- `type` (interest type): the fact plan that will run (probe/listener).
  - Example: `type = "squares"` or `type = "zombies"`.
- `scope`: a sub-mode within an interest type (used for grouping and merging).
  - For `type = "squares"`, the supported scopes today are `near`, `vision`, and `onLoad`.
  - For `type = "zombies"`, the supported scope today is `allLoaded`.
  - For `type = "rooms"`, the supported scopes today are `allLoaded`, `onSeeNewRoom`, and `onPlayerChangeRoom`.
  - For `type = "items"`, the supported scopes today are `playerSquare`, `near`, and `vision`.
  - For `type = "deadBodies"`, the supported scopes today are `playerSquare`, `near`, and `vision`.
- `target`: the anchor identity for the probe plan.
  - For `squares` probe scopes (`near`, `vision`), valid target keys are `player` and `square`.
  - `target` must contain exactly **one** kind key (example: `target = { player = { id = 0 } }`).
  - `scope = "onLoad"` ignores `target`.
  - `items` and `deadBodies` use the same target rules as `squares` for probe scopes.
  - `scope = "playerSquare"` for `items`/`deadBodies` requires a player target (defaults to `id = 0`).
  - `scope = "onPlayerChangeRoom"` uses a player target (defaults to `id = 0`).
  - v0 note: singleplayer assumes the local player is `id = 0`.

## 3. Interest types available today

Interest `type` selects the “fact plan” behind the scenes (listener vs probe and what it scans).

### Summary (types and scopes)

| type | scopes | acquisition | target |
|------|--------|-------------|--------|
| `squares` | `near`, `vision`, `onLoad` | probe + event | player/square (probe scopes) |
| `zombies` | `allLoaded` | probe | n/a |
| `rooms` | `allLoaded`, `onSeeNewRoom`, `onPlayerChangeRoom` | probe + event | player (onPlayerChangeRoom only) |
| `items` | `playerSquare`, `near`, `vision` | playerSquare driver + probe | player/square (probe scopes) |
| `deadBodies` | `playerSquare`, `near`, `vision` | playerSquare driver + probe | player/square (probe scopes) |

### Squares

- `type = "squares"` with `scope = "near"`
  - Probe-driven: scans squares near a target you define.
  - Target:
    - defaults to `target = { player = { id = 0 } }` if omitted
    - can also be a static anchor: `target = { square = { x = ..., y = ..., z = ... } }` (`z` defaults to 0)
  - Settings: `radius`, `staleness`, `cooldown`, `highlight`.
- `type = "squares"` with `scope = "vision"`
  - Probe-driven: like `scope = "near"` with a player target, but only emits squares that are currently visible to the player (line-of-sight / “can see”).
  - Target must be `target = { player = ... }` (defaults to `id = 0`).
  - Settings: `radius`, `staleness`, `cooldown`, `highlight`.
- `type = "squares"` with `scope = "onLoad"`
  - Event-driven: emits when squares load (chunk streaming).
  - Settings: `cooldown`, `highlight` (other settings are currently not meaningful for this scope).
  - Ignores `target`, `radius`, and `staleness`.

### Zombies

- `type = "zombies"` with `scope = "allLoaded"`
  - Probe-driven: scans the game’s zombie list in loaded areas (singleplayer uses the local player).
  - Settings: `radius`, `zRange`, `staleness`, `cooldown`, `highlight`.
  - Note: `radius` makes emissions leaner, but does not avoid the baseline cost of scanning the loaded zombie list.

### Rooms

- `type = "rooms"` with `scope = "allLoaded"`
  - Probe-driven: scans the room list in the active cell (singleplayer).
  - Settings: `staleness`, `cooldown`, `highlight`.
- `type = "rooms"` with `scope = "onSeeNewRoom"`
  - Event-driven: emits when the player sees a new room.
  - Settings: `cooldown`, `highlight`.
- `type = "rooms"` with `scope = "onPlayerChangeRoom"`
  - Event-driven: emits when the player changes rooms (only when a room is detected).
  - Settings: `cooldown`, `highlight`.

### Items

- `type = "items"` with `scope = "playerSquare"`
  - Player-driven: emits items on the square the player stands on.
  - Settings: `cooldown`, `highlight`.
- `type = "items"` with `scope = "near"`
  - Probe-driven: scans squares near a target.
  - Settings: `radius`, `staleness`, `cooldown`, `highlight`.
- `type = "items"` with `scope = "vision"`
  - Probe-driven: like `near`, but only emits items on squares visible to the player.
  - Settings: `radius`, `staleness`, `cooldown`, `highlight`.

### Dead bodies

- `type = "deadBodies"` with `scope = "playerSquare"`
  - Player-driven: emits dead bodies on the square the player stands on.
  - Settings: `cooldown`, `highlight`.
- `type = "deadBodies"` with `scope = "near"`
  - Probe-driven: scans squares near a target.
  - Settings: `radius`, `staleness`, `cooldown`, `highlight`.
- `type = "deadBodies"` with `scope = "vision"`
  - Probe-driven: like `near`, but only emits dead bodies on squares visible to the player.
  - Settings: `radius`, `staleness`, `cooldown`, `highlight`.

## 4. The settings (what they mean)

WorldObserver uses “bands” for most settings:
- `desired`: what you *want* when the runtime has headroom.
- `tolerable`: what you can *accept* when the runtime is under pressure.

Example:

```lua
staleness = { desired = 5, tolerable = 20 }
```

If you only provide `desired`, WO derives a `tolerable` value automatically from defaults for that interest type.

### `staleness` (seconds)

How fresh you want observations to be.

- Smaller `staleness` means: probe more often / work harder to keep up.
- Under load, WO may increase effective staleness (emit older observations) to protect frame time.

### `radius` (tiles)

How far around the player WO should look.

- Larger `radius` means more squares/zombies to consider.
- Under load, WO may reduce effective radius (scan fewer tiles).

### `cooldown` (seconds)

How often the *same key* is allowed to re-emit.

- For squares, the key is `squareId`.
- For zombies, the key is `zombieId`.
- For rooms, the key is `roomId`.
- For items, the key is `itemId`.
- For dead bodies, the key is `deadBodyId`.
- Larger `cooldown` means fewer repeats (lower cost + less spam).

### `zRange` (floors)

Zombie-only: how many Z-levels above/below the player are included.

Example: “same floor only”:

```lua
zRange = { desired = 0 }
```

### `highlight` (debug visual)

Optional, best-effort visual feedback. Useful while tuning.

- Squares: `highlight = true` highlights probed squares (near/vision use different colors).
- Zombies: `highlight = true` highlights the floor under the zombie; you can also pass a color table (example: `{ 1, 0.2, 0.2 }`).

Unlike most of the other parameters, `highlight` does not merge across different mods. 

Current behavior (today):
- `highlight` is taken from the first active lease (for that `type` + merged bucket) that provides it.
- Later leases do not override it.

Recommendation: treat `highlight` as a debugging setting. If you need reliable, per-mod visuals, use the highlight helpers directly in your subscription (see `docs/guides/debugging_and_performance.md`).

## 5. How WO merges multiple mods’ interest (what to expect)

All active leases are merged per interest type.

The merge is designed so that the system can satisfy everyone at once:

- `radius` / `zRange`: the merged `desired` tends toward the **largest** requested area.
- `staleness` / `cooldown`: the merged `desired` tends toward the **smallest** requested freshness/emit intervals.
- For `squares`, merging happens per scope + target identity (same target only).
  - `target = { player = ... }` is 'WO'-owned and merges across mods.
  - `target = { square = ... }` is mod-owned and does **not** merge across mods, even if coordinates match.

An adaptive policy picks the effective level based on runtime pressure:

- Degrade order is: **increase staleness → reduce radius → increase cooldown**.
- In “emergency” situations, WO may degrade beyond your `tolerable` bounds to protect the frame rate or disable some fact sources entirely.

## 6. Introspection: “what interest is currently active?”

You can inspect the current merged bands (active leases only):

```lua
local buckets = WorldObserver.factInterest:effectiveBuckets("squares")
for _, entry in ipairs(buckets) do
  print(entry.bucketKey, entry.merged and entry.merged.scope, entry.merged and entry.merged.radius and entry.merged.radius.desired)
end
```

This returns the merged bands, not the final runtime-adjusted “effective” values used in probing.

## 7. Cleanup (don’t leak work)

When your feature turns off, stop your lease:
- `lease:stop()`

Lifecycle patterns (renewal cadence, TTL overrides):
- [Lifecycle](lifecycle.md)
