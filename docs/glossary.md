# Glossary

This glossary defines the core WorldObserver terms as they are used throughout the documentation.

## Fact layer (input side)

### Fact
A “thing that is (or was) true” in the game world, discovered by WorldObserver. Example: “this square had a corpse 0.5 in-game seconds ago.”

### Fact source
The mechanism that produces facts:
- **Listener (event-driven):** reacts to game events (example: squares `scope = "onLoad"`).
- **Probe (active scan):** periodically inspects world state (example: squares `scope = "near"` / `"vision"`, zombies `scope = "allLoaded"`).

### Fact acquisition (upstream)
The general act of producing facts (via fact sources). You will see “acquisition” used as shorthand for “upstream fact production” in internal docs.

### Sensor (shared probe driver)
An internal implementation pattern: a shared probe loop that scans parts of the world and can feed multiple fact types.

Example:
- `square_sweep` scans squares for `near`/`vision` and calls registered collectors.

### Collector (sensor callback)
An internal implementation pattern: a per-type extraction function invoked by a sensor (for example, “given a square, emit item facts and dead body facts”).

Collectors typically:

  - produce one or more fact records
  - Bias lean acquisituin and use `ctx.ingest(record)` (buffered) rather than doing downstream work directly.

### Fact type / Interest type
The top-level category of fact work WorldObserver can observe. In the interest API this is just called `type` (example: `"squares"`, `"zombies"`).

### Interest
Your mod’s declaration of what facts WorldObserver should gather, and with what constrained by what dimensions (e.g. scope/staleness/target etc.).

#### Scope (of a declared interest)
A sub-mode within an interest type. In the interest API this is `scope` (example: squares `near|vision|onLoad`, zombies `allLoaded`).

An interest is declared with `WorldObserver.factInterest:declare(modId, key, spec, opts)`.

#### Target (of a declared interest)
The anchor for some probe scopes. `target` must include exactly one kind key.

Examples:
- `target = { player = { id = 0 } }`
- `target = { square = { x = ..., y = ..., z = ... } }`

Not all scopes use a target (example: squares `scope = "onLoad"` ignores `target`).

#### Lease (of a declared interest)
The handle returned by `declare(...)`. It represents your active interest “lease”.

- `lease:renew()` keeps it alive.
- `lease:stop()` removes it.

#### Merging (of a declared interests)
An internal implementation pattern: When multiple mods declare interest, WorldObserver merges active leases into a single merged spec per interest type (and per bucket).

### Bucket (bucketKey)
An internal implementation pattern: The “merge group” for a type. For bucketed types like squares, merging happens per `scope + target identity` (same bucket only).

### Probe / listen work
The actual shared work WorldObserver does (scanning or listening). If nobody has an active lease for a type/bucket, that work usually does not run.

## Common settings and time

All time-based settings use the **in-game clock**.

### Staleness (seconds)
How fresh you want observations to be. Lower staleness implies more frequent probing.

### Cooldown (seconds)
How frequently the same key is allowed to re-emit. E.g. the same zombie, even if observed at high frequency, will not spam the stream).

### Radius (tiles)
How far around a target to observe.

Note: For some interest types such as zombies with `scope = "allLoaded"`, the `radius` mainly makes **emissions** leaner; it does not avoid the baseline cost of scanning the loaded zombie list.

### zRange (floors)
How many Z-levels above/below the target are included.

### Highlight
Best-effort debugging aid that may help you spot _some_ observations visually.

### TTL (lease ttlSeconds / ttlMs)
How long a lease stays valid without explicit renewal.

## Observation layer (output side)

### Observation
One emitted “event” you receive in a subscription callback: a Lua table that carries one or more record families (example: `observation.square`, `observation.zombie`).

Observations are snapshots, not live game objects.

### Observation stream (ObservationStream)
A stream of observations, as the name implies. Only when it is actively subscribe to will observations begin to stream. (example: `WorldObserver.observations:squares()`).

### Subscription
The handle returned by `stream:subscribe(fn)`. You stop receiving events by calling `sub:unsubscribe()`.

### Base observation stream
built-in streams fed directly by an a single interest type (example: squares, zombies).

### Derived observation stream
A stream you build from one or more other streams (example: joining squares + zombies).

Derived streams can emit **multi-family observations** (multiple families in one observation).

### Family (observation payload family)
A named record namespace inside an observation table (example: `observation.square`, `observation.zombie`,  `observation.InOfficeZombie`).

Important: “family” is about the **output payload shape**, not the interest type.
Also distinct from a **helper family**, which is an attachable set of helper methods that can be configured (via `enabled_helpers`) to operate on a particular payload family.

## Stream helpers and filtering

### Helper
WorldObserver-provided convenience methods for common filtering and readability (example: `:squareHasCorpse()`, `:zombieHasTarget()`).

### Helper family
An attachable helper set identified by a key like `square`, `zombie`, `sprite` (or third-party families like `unicorns`).

Helper families are often aligned with observation payload families, but not always: a helper family can be configured (via `enabled_helpers`) to operate on another payload family.

### distinct(dimension, seconds)
A WorldObserver stream operator that de-duplicates by a named dimension over an in-game time window (example: “once per square every 10 seconds”).

The “dimension” is stream-specific (example: `"square"`, `"zombie"`).

## Record and schema terms (advanced / internal)

### Record
The per-family table inside an observation (example: `observation.square`).

### RxMeta / schema
Metadata WorldObserver (via LQR) attaches to records so windowing/joining/dedup can work. Most modders do not need to interact with `RxMeta` directly.


## Taxonomy Hierarchy (Not data structure) 

```
Fact Type
├─Fact
  ├─Fact Fields

Observation Stream
├─Observation
  ├─Observation Family
  ├─Record
    ├─Observation Fields
    ├─RxMeta
```
 