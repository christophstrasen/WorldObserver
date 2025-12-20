# Glossary

This glossary defines the core WorldObserver terms as they are used in the user-facing documentation.

## Fact layer (input side)

### Fact
A “thing that is (or was) true” in the game world, discovered by WorldObserver (example: “this square had a corpse 0.5 in-game seconds ago.”).

### Fact source
The mechanism that produces facts:
- **Listener (event-driven):** reacts to game events (example: squares `scope = "onLoad"`).
- **Probe (active scan):** periodically inspects world state (example: squares `scope = "near"` / `"vision"`, zombies `scope = "allLoaded"`).

### Fact type (fact plan type / interest type)
The top-level category of fact work WorldObserver can run and merge. In the interest API this is `type` (example: `"squares"`, `"zombies"`).

Note: in docs we call this **interest type** to avoid confusion with observation payload “families”.

### Scope
A sub-mode within an interest type. In the interest API this is `scope` (example: squares `near|vision|onLoad`, zombies `allLoaded`).

### Target
The anchor for some probe scopes (example: `target = { kind = "player", id = 0 }` or `target = { kind = "square", x = ..., y = ..., z = ... }`).

Not all scopes use a target (example: squares `scope = "onLoad"` ignores `target`).

### Interest
Your mod’s declaration of what facts WorldObserver should gather, and with what quality expectations (scope/target + knobs).

An interest is declared with `WorldObserver.factInterest:declare(modId, key, spec, opts)`.

### Lease
The handle returned by `declare(...)`. It represents your active interest “lease”.

- `lease:renew()` keeps it alive.
- `lease:stop()` removes it.

### Merge (merged interest)
When multiple mods declare interest, WorldObserver merges active leases into a single merged spec per type (and per bucket).

### Bucket (bucketKey)
The “merge group” for a type. For bucketed types like squares, merging happens per `scope + target identity` (same bucket only).

### Probe / listen work
The actual shared work WorldObserver does (scanning or listening). If nobody has an active lease for a type/bucket, that work usually does not run.

## Knobs and time (quality controls)

All time-based knobs use the **in-game clock**.

### Staleness (seconds)
How fresh you want observations to be. Lower staleness implies more frequent probing.

### Cooldown (seconds)
How often the same key is allowed to re-emit (example: the same square or the same zombie).

### Radius (tiles)
How far around a target to consider.

Note: for zombies `scope = "allLoaded"`, `radius` mainly makes **emissions** leaner; it does not avoid the baseline cost of scanning the loaded zombie list.

### zRange (floors)
Zombie-only: how many Z-levels above/below the player are included.

### Highlight
Best-effort visual debugging aid (not a stable contract, not merged deterministically across mods).

### TTL (lease ttlSeconds / ttlMs)
How long a lease stays valid without renewal.

## Observation layer (output side)

### Observation
One emitted “event” you receive in a subscription callback: a Lua table that carries one or more record families (example: `observation.square`, `observation.zombie`).

Observations are snapshots, not live game objects.

### Observation stream (ObservationStream)
A stream you can subscribe to, produced by WorldObserver (example: `WorldObserver.observations.squares()`).

### Subscription
The handle returned by `stream:subscribe(fn)`. You stop receiving events by calling `sub:unsubscribe()`.

### Base observation stream
A built-in stream fed directly by a fact type (example: squares, zombies).

### Derived observation stream
A stream you build from one or more other streams (example: joining squares + zombies).

Derived streams can emit **multi-family observations** (multiple families in one observation).

### Family (observation payload family)
A named record namespace inside an observation table (example: `observation.square`, `observation.zombie`).

Important: “family” is about the **output payload shape**, not the interest type.

## Stream helpers and filtering

### Helper
WorldObserver-provided convenience methods for common filtering and readability (example: `:squareHasCorpse()`, `:zombieHasTarget()`).

### whereSquare / whereZombie
Convenience operators that call your predicate with the record you care about (square record or zombie record).

### distinct(dimension, seconds)
A WorldObserver stream operator that de-duplicates by a named dimension over an in-game time window (example: “once per square every 10 seconds”).

The “dimension” is stream-specific (example: `"square"`, `"zombie"`).

## Record and schema terms (advanced / internal)

### Record
The per-family table inside an observation (example: `observation.square`).

### RxMeta / schema
Metadata WorldObserver (via LQR) attaches to records so windowing/joining/dedup can work. Most modders do not need to interact with `RxMeta` directly.

