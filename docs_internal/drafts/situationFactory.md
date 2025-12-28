# WorldObserver – Situation Factories (RFC)

> **Stage:** Draft / proposal

WorldObserver “situations” are currently *real* only once we subscribe (everything before that is builder logic). This RFC proposes a small, explicit way to define **named, parameterized situation factories** so complex situation streams can be recreated on demand (especially after reload) without serializing reactive graphs (LQR/Rx pipelines).
The goal is to make defining situations more DRY and give modders a simple default way to parameterize if they wish.
Using situation factories is _optional_. If you do use them, the namespaced facade is the intended public API.

---

## Problem this solves

- **Durable wiring:** PromiseKeeper (or any “keeper”) can persist *which* situation a mod intended to use, then recreate the live subscription after reload.
- **Avoid variant explosions:** WO’s flexibility can lead to many slightly different builder pipelines, so a situation factory can provide reusable “templates”.
- **Avoid serializing pipelines:** we do not want to serialize “WO build plans”, LQR plans, or Rx operator chains; that explodes complexity and versioning pain.
- **Collision-free mod ecosystem:** situation names like `nearPlayer`, `kitchensWithinDistance`, etc. will collide across mods unless we provide namespacing.
- **Debuggability:** being able to list “known situations” and their parameter shapes makes it much easier to reason about what is active.

---

## Proposal: Situation factories (named + parameterized)

Add a small registry to WorldObserver:

- A **situation factory** is a function that, given a serializable `args` table, returns a *live* **situation stream**.
- Mods register factories once (typically on load) under a stable id.
- Creating a “situation” means calling the factory again and subscribing.

This keeps “rich builder logic” inside code, but gives it a stable name + parameter surface that can be persisted and rehydrated.

### Situation stream (precise meaning)

In this RFC, a “situation stream” is an abstract **subscribable**:

- It supports `subscribe(onNext)` and returns a **subscription** that can later be unsubscribed.
- The stream is **hot by default**: subscribing observes “from now on” (no replay unless the implementation explicitly does it).
- Multiple subscribers share the same live stream position by default: a later subscriber does not “start at the beginning” or receive past events.
  - If a modder wants replay semantics, they must implement that explicitly inside the factory (for example by buffering/replaying) or define a separate `situationId` that documents replay.

We intentionally do not specify whether it is Rx/LQR/WO-native under the hood, only that it can be subscribed and unsubscribed.

In other words: the stream is “subscribable”, and the returned subscription supports `:unsubscribe()`.

### Emission shape (recommendation)

Situation factories are intended to compose naturally with the rest of WorldObserver.
We recommend that situation streams emit **observations** (tables shaped like WorldObserver observations), so downstream code can treat each emission as “one observation”.

---

## Namespacing

Facts / observation families can remain intentionally global vocabulary. Situations are “recipes” and are much more collision-prone, so they should be namespaced.

Internal key shape (implementation detail):

- `"<namespace>/<situationId>"` (recommended to use your mod id as `<namespace>`)

The registry should treat this fully-qualified key as the canonical identity internally, but the public API should make it hard to forget the namespace.

Public API note:
- We intentionally do not expose a “fully-qualified key” API for define/get/subscribe; you always go through a namespaced facade to reduce accidental collisions.

How a modder specifies the namespace:

1) **Namespaced helper facade (required)**
   - `WorldObserver.situations.namespace("MyMod")` returns a small situations-only table with the namespace baked in:
     - `situations.define(situationId, factoryFn)` → registers under `"MyMod/<situationId>"`
     - `situations.get(situationId, args)` → returns the live stream for `"MyMod/<situationId>"`
     - `situations.subscribeTo(situationId, args, onNext)` → subscribes and returns a subscription
     - `situations.list()` → lists `"MyMod/*"`
     - `situations.listAll()` → convenience passthrough; lists across all namespaces

Recommendation:
- Use your mod id namespace for your own situations.
- Overwriting another mod’s situation key can be powerful, but it is intentionally sharp: load order matters and you own the risk.

---

## Proposed API (WorldObserver)

### Registering factories

- `situations.define(situationId, factoryFn[, opts])`
  - `situations` is returned from `WorldObserver.situations.namespace("<namespace>")`
  - Example: `situations.define("kitchensWithinDistance", ...)`
  - `factoryFn(args)` must return a situation stream (subscribable)
  - `args` must be serializable (numbers/strings/booleans/tables of same); no functions, userdata, or engine objects.
    - Whether `args` are stable across reloads is the modder’s responsibility.
  - `situationId` must be a non-empty string (nil/empty is a hard error).
  - Redefining an existing key is allowed and overwrites the old definition (expected).
    - Logging: `info` on define; and if overwriting, an extra `info` log line.
  - `opts.describe` (optional) can describe expected args (for diagnostics).

### Creating a live situation

- `situations.get(situationId, args)`
  - Calls the registered factory and returns the live stream (not yet subscribed, if your stream type supports that distinction).
  - Lookup failure is a hard error.
  - `situationId` must be a non-empty string; `args` may be nil (treated as `{}`).

### Subscribe convenience (suggested)

- `situations.subscribeTo(situationId, args, onNext)`
  - Equivalent to `situations.get(...):subscribe(onNext)`.
  - Returns the same subscription object that `subscribe(...)` returns (no wrapping).

### Diagnostics helpers (suggested)

- `situations.list()`
  - Returns known `situationId` values within the namespace of `situations` (not fully-qualified).
- `situations.listAll()`
  - Returns fully-qualified situation keys across all namespaces.
  - This is a convenience passthrough for `WorldObserver.situations.listAll()`.

### Namespaced helper (suggested)

- `WorldObserver.situations.namespace(namespace)`
  - Returns a convenience wrapper for that namespace (no global state).
- `WorldObserver.situations.listAll()`
  - Returns fully-qualified situation keys across all namespaces.

Notes:
- Even if the underlying implementation is Rx/LQR/WO-native, the public contract is just “subscribable + unsubscribe”.

### Error handling (important)

`situations.get(...)` is allowed to raise a hard error (missing definition, factory throws).

But consumers that are intended to be durable in the mod ecosystem (for example a PromiseKeeper adapter that restores persisted promises) should wrap situation lookup + subscription in an error envelope:

- Always log an error (so it increments the game’s error count) and disable further resubscribe attempts until fixed.
- Only hard-crash (rethrow) when `getDebug()` is true.

---

## Example (conceptual)

```lua
local situations = WorldObserver.situations.namespace("MyMod")

situations.define("kitchensWithinDistance", function(args)
  local maxDistance = args.maxDistance
  local roomType = args.roomType

  -- Conceptual: this can be an arbitrarily rich WO builder pipeline.
  return WorldObserver.observations.squares()
    :squareRoomTypeIs(roomType)
    :withinDistanceOfPlayer(maxDistance)
end)

local stream = situations.get("kitchensWithinDistance", {
  roomType = "kitchen",
  maxDistance = 30,
})

local unsubscribe = stream:subscribe(function(observation)
  -- ...
end)
```

The point: the *recipe* is named and parameterized, but still free to be arbitrarily rich inside the factory.

---

## Relationship to PromiseKeeper (non-normative)

If PromiseKeeper stores promise definitions, it can store a reference to a WO situation without understanding its internals:

- `candidateFactoryId = "worldobserver"`
- `candidateArgs = { namespace = "MyMod", situationId = "kitchensWithinDistance", args = { ... } }`

On reload, the WorldObserver adapter recreates the stream by calling `WorldObserver.situations.namespace(namespace).get(situationId, ...)` again.

If the situation definition is missing or throws, the adapter should:
- log the error (and in debug, rethrow), and
- mark the PromiseKeeper promise as broken with a clear reason like “missing situation definition”.

---

## What we should decide / add before implementation planning

Decisions already made:
- **Override semantics:** redefining a key overwrites (expected) and logs `info` (and extra `info` if overwriting).
- **Args docs:** keep it simple via optional `opts.describe` (string or callback) for diagnostics.
- **Versioning:** no built-in versions/migrations/backwards-compatibility. If needed, modders encode `v2` in the situationId and manually migrate/forget.
- **Debug mode detection:** decided: use `getDebug()`; always log + disable resubscribe attempts, and only rethrow when debug is true.
- **Stream semantics:** hot by default; no replay by default; `subscribe(onNext)` returns a subscription with `:unsubscribe()`.

Still open (discussion later):
- Testing story (implementation + testing plan to be decided together).
- Hydration boundary guidance (we will document patterns, but not decide them fully here).

Follow-up docs (planned):
- Add a user-facing guidance document for common hydration/readiness patterns (factories vs downstream reshaping).
- Add a separate document describing how WorldObserver situations and PromiseKeeper promises work well together (once PromiseKeeper has progressed enough to be concrete).

---

## Implementation plan (draft)

1) **Add a situations registry module**
   - New file: `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver/situations/registry.lua`
   - Responsibilities:
     - Store definitions by namespace + situationId.
     - Enforce overwrite semantics (allow redefine; log info + extra info on overwrite).
     - Provide `define`, `get`, `subscribeTo`, `list`, `listAll`, and `namespace`.
   - Data shape:
     - `definitions[namespace][situationId] = { factory = factoryFn, describe = opts.describe }`
   - Namespace handles:
     - For simplicity, `namespace(...)` may return a lightweight facade per call (no caching required).
   - Listing behavior:
     - `list()` returns `situationId` values for the namespace.
     - `listAll()` returns fully-qualified keys.
   - Subscription shape:
     - `subscribe(onNext)` returns a subscription object with `:unsubscribe()`.
     - `subscribeTo(...)` is a convenience wrapper that returns the exact same subscription (no wrapping).
   - Error behavior:
     - `get(...)` hard-errors on missing definition (per RFC).
   - Naming + patchability:
     - No metatables; functions defined in a patchable-by-default style.

2) **Wire into the WorldObserver facade**
   - Update `Contents/mods/WorldObserver/42/media/lua/shared/WorldObserver.lua`:
     - `local SituationsRegistry = require("WorldObserver/situations/registry")`
     - Instantiate and attach: `WorldObserver.situations = situationsRegistry:api()` (or similar).
     - Expose the registry under `WorldObserver._internal.situations` for tests/debug.

3) **Busted tests (headless)**
   - New file: `tests/unit/situations_registry_spec.lua`
   - Cover:
     - `namespace(...).define/get` happy path.
     - `define` overwrites existing definitions (no error).
     - `get` hard-errors on missing definition.
     - `list` returns namespace-only keys; `listAll` returns all namespaces.
     - `subscribeTo` returns a subscription with `:unsubscribe()` and calls it when requested.
   - Why: ensures registry invariants and error semantics are stable outside PZ runtime.

4) **Prototype smoke test (engine)**
   - New file: `Contents/mods/WorldObserver/42/media/lua/shared/examples/smoke_situation_factory_squares.lua`
   - Behavior:
     - Create a namespaced facade: `situations = WorldObserver.situations.namespace("examples")`.
     - Define a situation `squaresNear` that returns `WorldObserver.observations:squares()` (optionally distinct).
     - Subscribe and print observations; provide `stop()` that unsubscribes and releases interest leases.
   - Why: validates the factory pipeline in real PZ runtime and exercises subscribe/unsubscribe + interest gating.
