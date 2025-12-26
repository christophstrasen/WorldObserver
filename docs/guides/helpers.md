# Helpers (built-in and extending)

Helpers are optional sugar around ObservationStreams. They make common filtering and convenience operations reusable and compact.

This guide focuses on how to *use* helpers as a modder. For internal architecture details, see `docs_internal/helpers.md`.

## 1) Using built-in helpers

WorldObserver ships helper families under `WorldObserver.helpers`:
- `square`, `room`, `sprite`, `zombie`, `item`, `deadBody`

Streams can expose helper methods in two ways:

1) **As stream methods** (most common)

```lua
local stream = WorldObserver.observations:squares()
  :squareHasCorpse()
  :distinct("square", 10)
```

2) **As namespaced helpers** (explicit + avoids name collisions)

```lua
local stream = WorldObserver.observations:squares()
stream.helpers.square:squareHasCorpse()
```

Where do you find the available helpers?
- Each observation family doc lists its helpers, e.g. `docs/observations/squares.md`, `docs/observations/sprites.md`, `docs/observations/zombies.md`.

### Record helpers inside `where*` predicates

Some helpers are record-level predicates/utilities. You typically use them inside `:squareFilter(...)` / `:zombieFilter(...)` / `:spriteFilter(...)`:

```lua
local SquareHelper = WorldObserver.helpers.square.record

local stream = WorldObserver.observations:squares()
  :squareFilter(function(squareRecord)
    return SquareHelper.squareHasCorpse(squareRecord)
  end)
```

Note: a few record helpers perform best-effort hydration and may cache engine references back onto the record. Treat engine userdata (`Iso*`) as short-lived and always handle `nil` safely.

## 2) Extending helpers (advanced)

You can attach third-party helpers helper families by attaching them to a stream or registering them globally.

### Option A: attach a helper set directly

```lua
local UnicornHelpers = require("YourMod/helpers/unicorns")

local stream = WorldObserver.observations:squares():withHelpers({
  helperSets = { unicorns = UnicornHelpers },
  enabled_helpers = { unicorns = "square" },
})

stream:unicorns_squareIdIs(123)
-- or:
stream.helpers.unicorns:unicorns_squareIdIs(123)
```

### Option B: register globally, then enable by name

```lua
local UnicornHelpers = require("YourMod/helpers/unicorns")
WorldObserver.observations:registerHelperFamily("unicorns", UnicornHelpers)

local stream = WorldObserver.observations:squares():withHelpers({
  enabled_helpers = { unicorns = "square" },
})
```

### What does `enabled_helpers` do?

`enabled_helpers` tells WorldObserver which helpers to enabled and also which observation family the helper family should read.

Most of the time you want the “alias” form:
- `enabled_helpers = { unicorns = "square" }` means “my helpers operate on the same records as the built-in `square` helpers”.

### Naming tips for third-party helpers

Stream helper method names share a global namespace on the stream. To avoid collisions:
- Prefer prefixing third-party helpers with the family name (e.g. `unicorns_squareIdIs`), or
- Call them via `stream.helpers.<family>.<fn>(...)` in examples/docs.

## Related docs

- Stream lifecycle and start/stop: `docs/guides/stream_basics.md`
- Derived streams (multi-family observations): `docs/guides/derived_streams.md`
- Extending record fields (separate from helpers): `docs/guides/extending_records.md`
