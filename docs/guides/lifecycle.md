# Lifecycle: subscriptions and interest leases

WorldObserver is streaming and long-running by design. That means you need to manage two things explicitly:

1. **Subscriptions** (what you receive)
2. **Interest leases** (what WO should spend work on)

## 1. Subscriptions: always unsubscribe

When you call:

```lua
local sub = WorldObserver.observations.squares():subscribe(function(row) ... end)
```

you must later call:

```lua
sub:unsubscribe()
```

Rule of thumb:
- Subscribe when your feature turns on.
- Unsubscribe when your feature turns off (UI closed, mode toggled, etc.).

## 2. Interest leases: renew and stop

When you call:

```lua
local lease = WorldObserver.factInterest:declare("YourModId", "someKey", { type = "squares.nearPlayer" })
```

you should do two things:

### 2.1 Renew the lease

Interest declarations are leases and can expire. If they expire, probing may reduce or stop and your observation stream may go quiet.

For long-running features, periodically call:

```lua
lease:touch()
```

Typical pattern: touch every ~60 seconds (or more often if you prefer).

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
}

function handle:start()
  if self.sub then return end
  self.lease = WorldObserver.factInterest:declare("YourModId", "featureKey", { type = "squares.nearPlayer" })
  self.sub = WorldObserver.observations.squares():subscribe(function(row) ... end)
end

function handle:tick()
  if self.lease then self.lease:touch() end
end

function handle:stop()
  if self.sub then self.sub:unsubscribe(); self.sub = nil end
  if self.lease then self.lease:stop(); self.lease = nil end
end
```

Wire `handle:tick()` into your own tick loop if you need renewal, and call `handle:stop()` when the feature shuts down.

