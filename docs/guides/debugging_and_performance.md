# Guide: debugging and performance

Goal: understand what WorldObserver is doing (or not doing), and tune your interest so your mod stays correct without wasting budget.

If you haven’t run a working example yet:
- [Quickstart](../quickstart.md)

## 1) First: confirm WO is actually doing work

WorldObserver does **no** probing/listening work unless at least one mod declares interest.

Use the debug API to sanity-check that the basics are wired:

```lua
local WorldObserver = require("WorldObserver")

WorldObserver.debug.describeFacts("squares")
WorldObserver.debug.describeFacts("zombies")
WorldObserver.debug.describeFacts("rooms")
WorldObserver.debug.describeFacts("items")
WorldObserver.debug.describeFacts("deadBodies")
WorldObserver.debug.describeStream("squares")
WorldObserver.debug.describeStream("zombies")
WorldObserver.debug.describeStream("rooms")
WorldObserver.debug.describeStream("items")
WorldObserver.debug.describeStream("deadBodies")
```

If streams are registered but you see no emissions, double-check that you declared interest and that your lease did not expire:
- [Guide: declaring interest](interest.md)
- [Lifecycle](lifecycle.md)

## 2) Visual debugging: `highlight`

The simplest way to confirm “WO is looking where I think it is” is to turn on `highlight` on your interest:

```lua
local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "squares",
  scope = "near",
  target = { player = { id = 0 } }, -- v0: singleplayer
  radius = { desired = 8 },
  staleness = { desired = 5 },
  cooldown = { desired = 2 },
  highlight = true,
})
```

Notes:
- `highlight` is best-effort and is meant for local debugging.
- It is intentionally not part of the “quality ladder” and does not merge deterministically across mods.

## 3) Inspect merged interest (what WO *thinks* is active)

When multiple mods declare interest, WO merges them. The result is “merged bands”, not yet the final runtime-adjusted effective values.

To inspect the merged buckets:

```lua
local buckets = WorldObserver.factInterest:effectiveBuckets("squares")
for _, entry in ipairs(buckets) do
  local merged = entry.merged or {}
  local radius = merged.radius and merged.radius.desired
  local staleness = merged.staleness and merged.staleness.desired
  print(entry.bucketKey, merged.scope, radius, staleness)
end
```

What to expect (today):
- Squares merge per `scope` + target identity.
  - `target = { player = ... }` is WO-owned and merges across mods.
  - `target = { square = ... }` is mod-owned and intentionally does **not** merge across mods (even if coords match).

Supported combinations per interest type:
- [Squares](../observations/squares.md)
- [Zombies](../observations/zombies.md)
- [Rooms](../observations/rooms.md)
- [Items](../observations/items.md)
- [Dead bodies](../observations/dead_bodies.md)

## 4) Turn on runtime diagnostics (budget + backlog + drops)

WorldObserver can emit periodic diagnostics logs (tag: `WO.DIAG`). These are printed only when log level includes `info`.

In the in-game console you can enable info logging like this:

```lua
require("LQR/util/log").setLevel("info")
```

Then attach diagnostics (engine-only; requires `Events.*`):

```lua
local handle = WorldObserver.debug.attachRuntimeDiagnostics({
  factTypes = { "squares", "zombies", "rooms", "items", "deadBodies" },
})
-- later:
-- handle.stop()
```

What you’ll see:
- A periodic `[runtime] ...` line describing controller pressure (CPU/backlog/drops) and tick costs.
- Per-fact compact metrics like `[squares] pending=... fill=... dropped=... rate15(in/out)=...`.

If you see nothing:
- you may be running headless (busted) or without a functioning `Events` system;
- or your log level is still `warn` (default).

## 5) One-off metrics (when you don’t want a heartbeat)

```lua
WorldObserver.debug.describeFactsMetrics("squares")
WorldObserver.debug.describeFactsMetrics("zombies")
WorldObserver.debug.describeIngestScheduler()
```

## 6) Making probe logs more verbose (optional)

Square sweep probes support live console toggles for their logging knobs.

```lua
_G.WORLDOBSERVER_CONFIG_OVERRIDES = {
  facts = { squares = { probe = { infoLogEveryMs = 1000, logEachSweep = true } } },
}
```

Notes:
- This is meant for short-lived local debugging (expect lots of output).
- Not all config is live-reloaded; treat this as a debug convenience, not a stable “tuning API”.

### Collector/fan-out stats (Step 8)

If you want to see how much each interest type contributes (collector calls + emitted records), enable:

```lua
_G.WORLDOBSERVER_CONFIG_OVERRIDES = {
  facts = {
    squares = { probe = { logCollectorStats = true, logCollectorStatsEveryMs = 2000 } },
  },
}
```

If you’re only running `items`/`deadBodies` (no `squares` stream), set it on `items` instead:

```lua
_G.WORLDOBSERVER_CONFIG_OVERRIDES = {
  facts = {
    items = { probe = { logCollectorStats = true, logCollectorStatsEveryMs = 2000 } },
  },
}
```

You’ll see periodic lines like:
- `[probe collectors] tickScan=... tickVisit=... tickVisible=... items calls=... records=... | squares calls=... records=...`

Notes:
- The square sweep sensor is shared: when you only run `items` / `deadBodies`, the probe cfg can come from those types instead of `squares`.
- If you don’t see the collector line, ensure you enabled it on the type that is currently driving the sweep (typically the highest “probePriority” among active consumers).

## 7) Tuning: what actually reduces work vs reduces spam

Think in two layers:

1) **Upstream cost (WO work):** how much probing/listening WO must do.
2) **Downstream cost (your mod work):** how much you process in your subscription.

Practical rules:
- Use `cooldown` to avoid re-emitting the same key too frequently (reduces downstream spam and some probe overhead).
- Use `:distinct("<dimension>", seconds)` to reduce downstream work in your subscription pipeline.
- Increase `staleness` if you can accept older information (lets WO probe less often).
- Reduce `radius` when you can focus spatially (reduces square probing work).

Items note:
- Observing items can “fan out” because WO can optionally include direct container contents (depth=1).
- If you don’t need container contents, set `facts.items.record.includeContainerItems = false`.
- If you do need them but want a guardrail, use `facts.items.record.maxContainerItemsPerSquare` to cap work per square.

Zombie note:
- For `type = "zombies", scope = "allLoaded"`, the probe still has to scan the loaded zombie list.
  `radius` makes emissions leaner (and reduces downstream work), but does not avoid the baseline “iterate zombies” cost.
