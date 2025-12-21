# Observations

Observations are the main thing you consume from WorldObserver.

- You subscribe to an observation stream (example: `WorldObserver.observations.squares()`).
- Each stream emits **observations** (Lua tables), not “live” game objects.
- Each observation can carry one or more **record families** (example: `observation.square`, `observation.zombie`).
- You react to those observations (and the records inside them).

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
- Record timestamps like `sourceTime` are **milliseconds**.
- Many knobs in docs are **seconds** (internally converted to ms), e.g. `staleness`, `cooldown`, `:distinct(..., seconds)`.
- Interest lease TTL is also measured on the in-game clock; see [Lifecycle](../guides/lifecycle.md).

## Available streams

Current base streams:
- [Squares](squares.md)
- [Rooms](rooms.md)
- [Zombies](zombies.md)

General stream usage (subscribe, distinct, stop/unsubscribe):
- [Stream basics](stream_basics.md)

ReactiveX primer (optional, but helpful):
- [ReactiveX primer](reactivex_primer.md)

Next steps (advanced):
- [Derived streams (multi-family observations)](../guides/derived_streams.md)
- [Troubleshooting](../troubleshooting.md)
