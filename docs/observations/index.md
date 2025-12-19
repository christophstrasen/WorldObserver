# Observations

Observations are the main thing you consume from WorldObserver.

- You subscribe to an observation stream (example: `WorldObserver.observations.squares()`).
- Each stream emits **observation records** (Lua tables), not “live” game objects.
- You react to those records.

If you haven’t run the first working example yet, start here:
- [Quickstart](../quickstart.md)

## What you get in a callback

You subscribe like this:

```lua
local sub = WorldObserver.observations.squares():subscribe(function(observation)
  -- observation.square is a record table (a snapshot).
end)
```

Important:
- Records are snapshots. Treat engine userdata (`Iso*`) as best-effort and in doubt as short-lived.
- Prefer stable fields like ids/coords (`squareId`, `x`, `y`, `z`, `zombieId`).

## Time units (seconds vs ms)

WorldObserver uses the **in-game clock** for timestamps and time windows (same clock as `getGameTime():getTimeCalendar():getTimeInMillis()`).

You’ll see this in a few places:
- Record timestamps like `sourceTime` / `observedAtTimeMS` are **milliseconds**.
- Many knobs in docs are **seconds** (internally converted to ms), e.g. `staleness`, `cooldown`, `:distinct(..., seconds)`.
- Interest lease TTL is also measured on the in-game clock; see [Lifecycle](../guides/lifecycle.md).

## Available streams

Current base streams:
- [Squares](squares.md)
- [Zombies](zombies.md)

General stream usage (subscribe, distinct, stop/unsubscribe):
- [Stream basics](stream_basics.md)

ReactiveX primer (optional, but helpful):
- [ReactiveX primer](reactivex_primer.md)
