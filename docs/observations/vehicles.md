# Observation: vehicles

Goal: react to what WorldObserver observes about vehicles (stable-ish ids, tile location, basic metadata).

Quickstart first (recommended):
- [Quickstart](../quickstart.md)

## Declare interest (required)

WorldObserver does no vehicle probing/listening unless at least one mod declares interest.

```lua
local WorldObserver = require("WorldObserver")

local lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
  type = "vehicles",
  scope = "allLoaded",       -- default today (and only supported scope)
  staleness = { desired = 5 }, -- how often the probe should sweep (seconds)
  cooldown = { desired = 10 }, -- per-vehicle re-emit gate (seconds)
  highlight = true,            -- highlight the floor square under an emitted vehicle
})
```

## Subscribe

```lua
local sub = WorldObserver.observations:vehicles()
  :distinct("vehicle", 10)
  :subscribe(function(observation)
    local v = observation.vehicle
    if not v then return end

    print(("[WO] sqlId=%s vehicleId=%s script=%s tile=%s,%s,%s source=%s"):format(
      tostring(v.sqlId),
      tostring(v.vehicleId),
      tostring(v.scriptName),
      tostring(v.tileX),
      tostring(v.tileY),
      tostring(v.tileZ),
      tostring(v.source)
    ))
  end)
```

Remember to stop:
- `sub:unsubscribe()`
- and your interest lease: `lease:stop()` (see [Lifecycle](../guides/lifecycle.md))

## Record fields (what `observation.vehicle` contains)

Common fields on the vehicle record:
- `sqlId` (preferred identity key when present; stability across save/load is not guaranteed yet)
- `vehicleId` (fallback identity key; typically session-scoped)
- `x`, `y`, `z` (currently equal to tile coords; integer)
- `tileX`, `tileY`, `tileZ` (tile coords, integers)
- `name` (best-effort via `getObjectName()`)
- `scriptName` (best-effort via `getScriptName()`)
- `skin` (best-effort via `getSkin()`)
- `type` (best-effort via `getVehicleType()`)
- status flags (best-effort): `isDoingOffroad`, `hasPassenger`, `isSirening`, `isStopped`
- `source` (which producer saw it: `probe` and potentially `event`)
- `sourceTime` (ms, in-game clock)

Engine object:
- `IsoGridSquare` is attached best-effort when available (from `vehicle:getSquare()`). Treat it as short-lived.

## Extending the record (advanced)

If you need extra fields on `observation.vehicle`, register a record extender:
- [Guide: extending record fields](../guides/extending_records.md)

## Built-in stream helpers

```lua
local stream = WorldObserver.observations:vehicles()
  :vehicleFilter(function(v)
    return v and v.scriptName == "Base.CarNormal"
  end)
  :distinct("vehicle", 10)
```

Available today:
- `:vehicleFilter(fn)` (keep only observations where `fn(observation.vehicle, observation) == true`)

Record wrapping (optional):
- `WorldObserver.helpers.vehicle:wrap(vehicleRecord)` adds `:getIsoGridSquare()`, `:highlight(durationMs, opts)`; see [Helpers: record wrapping](../guides/helpers.md#record-wrapping-optional).

## Supported interest configuration (today)

Supported combinations for `type = "vehicles"`:

| scope     | target key | target shape | Notes |
|-----------|------------|--------------|-------|
| allLoaded | n/a        | n/a          | Probe via `IsoCell:getVehicles()` plus best-effort spawn events. |

Meaningful settings: `staleness`, `cooldown`, `highlight`.
