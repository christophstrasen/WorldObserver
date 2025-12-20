# Troubleshooting

This page is organized by **symptoms** you might see while using WorldObserver.

## “I subscribed, but I see nothing”

Things to check:

- **You declared interest** (most common)  
  WorldObserver does no probing/listening work unless at least one mod declares interest. Declare interest *before* subscribing:
  - [Guide: declaring interest](guides/interest.md)

- **Your interest matches what you expect to see**
  - `type = "squares", scope = "onLoad"`: event-driven bursts only when squares load; can be quiet in already-loaded areas.
  - `type = "squares", scope = "near"`: probe-driven; keeps emitting as you move.
  - `type = "squares", scope = "vision"`: probe-driven; only emits squares you can currently see.

- **Your filters aren’t filtering everything away**  
  Temporarily remove helpers like `:squareHasCorpse()` to confirm the base stream emits at all.

## “It worked, then it stopped”

Most often, this is lease lifecycle:

- **Your interest lease expired**  
  Interest declarations are leases. If you don’t renew them, they can expire and streams can go quiet.
  Recommended patterns:
  - [Lifecycle](guides/lifecycle.md)

- **You unsubscribed (or replaced the handle)**
  Keep the returned `sub` and call `sub:unsubscribe()` only when your feature turns off.

## “`onLoad` goes quiet” / “`onLoad` misses changes”

`type = "squares", scope = "onLoad"` only emits when squares load (chunk streaming). It does not continuously re-check squares that are already loaded.

If you need ongoing freshness, use a probe scope (`near` or `vision`) and tune `staleness`/`cooldown`.

## “My time windows feel wrong” (too fast / too slow)

WorldObserver uses the **in-game clock**:
- Many knobs and helpers use **seconds** (e.g. `staleness`, `cooldown`, `:distinct(..., seconds)`).
- Record timestamps are usually **milliseconds** (`sourceTime`, `observedAtTimeMS`).

If you expected real-time seconds, your numbers will feel off.

## “I get `nil` or stale `Iso*` userdata”

WorldObserver streams are **observations, not entities**:
- Records are snapshots; engine objects (`Iso*`) are best-effort and may be missing/stale.
- Prefer stable anchors like ids/coords.

Square-specific: use `:squareHasIsoGridSquare()` before relying on `record.IsoGridSquare`.

## “Changing zombie `radius` doesn’t improve performance”

For `type = "zombies", scope = "allLoaded"`, the probe still has to scan the loaded zombie list.
`radius` mainly makes **emissions** (and downstream work) leaner; it does not avoid the baseline “iterate zombies” cost.
