# Lifecycle: subscriptions and interest leases

WorldObserver is streaming and long-running by design. That means you need to manage two things explicitly:

1. **Subscriptions** (what you receive)
2. **Interest leases** (what WO should spend work on)

## 1. Subscriptions: always unsubscribe

When you call:

```lua
local sub = WorldObserver.observations.squares():subscribe(function(observation) ... end)
```

you must later call:

```lua
sub:unsubscribe()
```

Rule of thumb:
- Subscribe when your feature turns on.
- Unsubscribe when your feature turns off (UI closed, situation resolved, mode toggled, etc.).

## 2. Interest leases: renew and stop

When you call:

```lua
local lease = WorldObserver.factInterest:declare("YourModId", "someKey", {
  type = "squares",
  scope = "near",
  target = { player = { id = 0 } },
})
```

you should do two things:

### 2.1 Renew the lease

Interest declarations are leases and can expire. If they expire, WO may reduce or stop probing and your observation stream may go quiet.
No lease usually means WO does no probing/listening work for that area/type, so streams can be silent even if you subscribed.

Default lease time is **10 minutes**.

Time note: lease TTL uses the in-game clock (same clock as `getGameTime():getTimeCalendar():getTimeInMillis()`), not real-time seconds.

For long-running features, periodically call:

```lua
lease:renew()
```

You can also request a shorter or longer lease when declaring:

```lua
local lease = WorldObserver.factInterest:declare("YourModId", "someKey", {
  type = "squares",
  scope = "near",
  target = { player = { id = 0 } },
}, {
  ttlSeconds = 60, -- default is longer; set shorter if you want faster “auto-off”
})
```

You can also specify milliseconds:

```lua
local lease = WorldObserver.factInterest:declare("YourModId", "someKey", {
  type = "squares",
  scope = "near",
  target = { player = { id = 0 } },
}, {
  ttlMs = 2 * 60 * 1000, -- 2 minutes
})
```

Important: do **not** put `lease:renew()` inside your subscription callback. That makes renewal depend on how many observations happen to arrive, which is usually not what you want.

Make a conscious choice:

- **Keep-alive mode (recommended):** renew on a fixed cadence while the feature is enabled (independent of observation volume).
- **Auto-disable-on-silence mode (sometimes useful):** don’t renew; let the lease expire if the world is quiet or if WO can’t satisfy it.

### 2.2 Stop the lease

When your feature turns off, call:

```lua
lease:stop()
```

This removes your interest so WO can reduce work when nobody needs it.

## 3. Minimal “managed handle” pattern

This keeps the lifecycle in one place:

```lua
local handle = {
  sub = nil,
  lease = nil,
  _lastRenewMs = nil,
}

function handle:start()
  if self.sub then return end
  self.lease = WorldObserver.factInterest:declare("YourModId", "featureKey", {
    type = "squares",
    scope = "near",
    target = { player = { id = 0 } },
  })
  self.sub = WorldObserver.observations.squares():subscribe(function(observation) ... end)
end

function handle:tick()
  if not self.lease then return end

  -- Keep-alive: renew on a low cadence (not per tick, and not in the subscribe callback).
  local nowMs = (require("WorldObserver/helpers/time").gameMillis() or 0)
  local renewEveryMs = 60 * 1000
  if self._lastRenewMs == nil or (nowMs - self._lastRenewMs) >= renewEveryMs then
    self.lease:renew()
    self._lastRenewMs = nowMs
  end
end

function handle:stop()
  if self.sub then self.sub:unsubscribe(); self.sub = nil end
  if self.lease then self.lease:stop(); self.lease = nil end
  self._lastRenewMs = nil
end
```

Wire `handle:tick()` into your own tick loop if you need renewal, and call `handle:stop()` when the feature shuts down.

Next:
- [Stream basics](../observations/stream_basics.md)
