# Fact layer – design draft

Internal design notes for how WorldObserver generates **Facts** via
Event Listeners and Active Probes before they become ObservationStreams.
This complements `docs_internal/vision.md` and `docs_internal/api_proposal.md`.

---

## 1. Purpose and scope

- Own all world‑level fact generation (squares, rooms, zombies, vehicles, …)
  so mods do not wire `OnTick`/`OnLoadGridsquare` directly.
- Provide a configurable but opinionated set of **fact plans** that balance
  freshness, completeness, and cost.
- Feed base ObservationStreams with schema‑tagged observations; everything
  above the fact layer should think only in terms of ObservationStreams.

---

## 2. Fact plans (per type)

- A **fact plan** describes how Facts for a world type are produced:
  - which engine events to listen to (Event Listeners);
  - which probes to run (Active Probes); and
  - how often / how deep to probe under different strategies.
- Plans are defined per type (`squares`, `rooms`, `zombies`, `vehicles`, …)
  and can be switched via `WorldObserver.config.facts.<type>.strategy`.
- Hybrid or multi‑type plans are allowed internally: for example, a square probe may
  also refresh room Facts for any rooms it touches. From the outside, squares
  and rooms still have distinct fact plans and configuration surfaces.
- Plans are internal; modders only see the resulting ObservationStreams plus
  a small, documented config surface for strategies.

---

## 3. Event Listeners

- Wrap Project Zomboid events (e.g. `OnLoadGridsquare`, `OnPlayerMove`,
  container/vehicle/room events) and normalize them into Facts.
- Responsibilities:
  - register/unregister handlers for engine events;
  - shape raw event payloads into schema‑ready records (with IDs, timestamps);
  - push records into the type’s fact stream in accordance with scheduler
    budgets.
- Mod code never subscribes to these events directly for core types; it goes
  through WorldObserver’s ObservationStreams instead.

---

## 4. Active Probes

- **Probes** initiate scans when events are insufficient or when periodic
  reconfirmation is required (“shine a light” on parts of the world).
- Example probes per type:
  - `squares`: near‑player rings at high frequency; wider rings at lower
    frequency; occasional full‑area sweeps split over many ticks.
  - `rooms`: rooms around players or areas of interest.
  - `zombies`/`vehicles`: probes near players or points of interest.
- Probes are scheduled and throttled centrally:
  - work is batched per tick to stay within a budget;
  - schedules can adapt based on strategy and subscriber demand.

---

## 5. Strategies and configuration

- For each type, a small set of named strategies (e.g. `"balanced"`,
  `"gentle"`, `"intense"`) describe how aggressively WorldObserver should work
  to keep Facts fresh for that type. A **strategy** is a high‑level intent
  (for example “cheap but fresh near players” vs. “very gentle background
  scans”), not a list of handlers.
- Internally, each `(type, strategy)` pair is resolved into a concrete
  **plan**: the specific combination of Event Listeners and Active Probes,
  plus their intervals and budgets, that the scheduler will run for that
  type. Plans are derived from strategies; mods configure strategies, the
  engine chooses and executes the corresponding plan.
- Public config lives under `WorldObserver.config.facts.<type>` and is
  intentionally small; detailed knobs remain internal.
- Strategies may react to usage:
  - scale down probes when there are no subscribers for a type;
  - scale up or alter patterns when certain ObservationStreams are active.

---

## 6. From Facts to ObservationStreams

- Each fact plan feeds one or more **base ObservationStreams** by:
  - tagging records with schemas (`SquareObs`, `RoomObs`, `ZombieObs`, …);
  - emitting observations whenever new facts are produced or re‑confirmed.
- Base streams expose observations as per‑emission tables (what the API calls
  a single `observation`) with fields such as `observation.square`,
  `observation.room`, or `observation.zombie`; derived streams (built via LQR
  queries) layer on top without knowing how facts were gathered.
- The fact layer must preserve “observations over time” semantics:
  - no implicit per‑instance dedup; multiple observations for the same
    instance are expected and may matter for time‑based logic.

---

## 7. Throttling and backpressure (high level)

- All listeners and probes share a **budgeted scheduler** that decides how
  much work to perform per tick / per time slice.
- Patterns from the older WorldScanner project (batched scans on `OnTick`,
  configurable max items per tick, etc.) can be reused and refined here.
- LQR and lua‑reactivex provide shaping operators (`throttle`, `buffer`,
  windows, `distinct`, etc.) but **do not** implement a full backpressure
  protocol where downstream explicitly signals demand. The fact layer must
  therefore treat world events and probes as the primary place to enforce
  budgets and avoid overload.
- The scheduler and strategies operate only on work that WorldObserver owns
  (events listened to, probes run, facts emitted). Subscriber callbacks are
  opaque and are not assumed to be cheap or expensive; mod authors are
  responsible for throttling their own gameplay logic if needed.
- Usage can still inform strategy: subscription counts per type and knowledge
  of which ObservationStreams depend on which fact plans can be used to:
  - scale down or idle plans when there are no subscribers for a type; and
  - avoid aggressive downshifts while several streams depend on the same facts.
- Within the LQR layer, WorldObserver can use shaping operators (e.g.
  `distinct`, sampling helpers) to keep in‑memory state and per‑tick work
  bounded, but **upstream pacing** remains the responsibility of the fact
  scheduler and strategies.
- The fact layer is a natural place to gather lightweight metrics (facts
  generated per type, drops, probe timings) that can feed both human‑facing
  debugging (`describeFacts`) and future automatic tuning of strategies.
- Pipeline‑level instrumentation inside LQR (per‑operator counts, buffer
  sizes) should be owned by LQR itself; WorldObserver can surface that
  information in domain terms via `describeStream` rather than duplicating
  instrumentation logic.
- The goal is to keep fact generation predictable and cheap by default,
  while still allowing “heavier” strategies for debugging or offline analysis,
  and to make any future, more advanced backpressure support in LQR a bonus,
  not a requirement for correctness.

---

## 8. External LuaEvent fact sources (cross‑mod signals)

- In addition to engine events and probes, WorldObserver can treat selected
  Starlit LuaEvents as fact sources. This is useful when other mods already
  emit facts (often higher‑level status signals) that we do not want to
  recompute.
- Example: a `RoomAlarms` mod emits `RoomAlarms.OnRoomStatus`
  whenever it recomputes the status of a room:

  ```lua
  LuaEvent.trigger("RoomAlarms.OnRoomStatus", {
    id       = roomId,
    status   = status,       -- "safe" | "warning" | "breached"
    lastSeen = getGameTime():getWorldAgeHours(),
  })
  ```

- WorldObserver can register this as an external fact source:

  ```lua
  WorldObserver.facts.registerLuaEventSource({
    eventName = "RoomAlarms.OnRoomStatus",
    type      = "roomStatus",  -- becomes observation.roomStatus
    idField   = "id",          -- or an idSelector
  })
  ```

- From that point on, `roomStatus` observations flow into the fact layer
  like any other Facts and can back a base ObservationStream. Other mods can
  subscribe to `WorldObserver.observations.roomStatus()` without knowing
  whether the data came from probes, engine events, or LuaEvents.
- LuaEvent sources are **opt‑in** and registered explicitly; core world types
  (squares, rooms, zombies, vehicles, …) still rely primarily on their own
  fact plans (events + probes). LuaEvents can also carry basic facts, but
  using fact plans for core world types keeps scheduling, throttling, and
  coverage consistent.

---

## 9. Example: squares strategies, plans, and builders

The following sketch shows how the Strategy → Plan idea and the listener/probe
builders can come together for the `squares` type.

### 9.1 Strategies and plans for `squares`

For `squares`, config sets the strategy:

```lua
WorldObserver.config.facts.squares.strategy = "balanced"  -- or "gentle", "intense"
```

Internally, WorldObserver resolves this to a concrete plan:

```lua
WorldObserver.facts.registerType("squares", function(Fact)
  return Fact.type{
    defaultStrategy = "balanced",

    plans = {
      balanced = Fact.plan{
        listeners = {
          Fact.listener{
            name  = "OnLoadGridsquare:squares",
            event = "OnLoadGridsquare",

            handle = function(ctx, isoGridSquare)
              if not isoGridSquare then return end
              local record = ctx.makeSquareRecord(isoGridSquare)
              ctx.emit(record)
            end,
          },
        },

        probes = {
          Fact.probe{
            name     = "nearPlayers_closeRing",
            schedule = {
              intervalTicks = 1,    -- every tick
              budgetPerTick = 200,  -- max squares per tick
            },

            run = function(ctx, budget)
              local processed = 0

              for _, player in ipairs(ctx.players:nearby()) do
                for square in ctx.iterSquaresInRing(player, 1, 8) do
                  if processed >= budget then
                    return
                  end

                  local record = ctx.makeSquareRecord(square)
                  ctx.emit(record)
                  processed = processed + 1
                end
              end
            end,
          },
        },
      },

      gentle = Fact.plan{
        listeners = {
          -- maybe only events, no probes
        },
        probes = {},
      },

      intense = Fact.plan{
        listeners = {
          -- same events as balanced
        },
        probes = {
          -- e.g. closeRing + a wider, less frequent probe, higher budgets
        },
      },
    },
  }
end)
```

- Config chooses the **strategy**; the engine resolves it to a **plan** for
  that type by picking the right listeners and probes and handing them to the
  scheduler.
- The plan is what actually runs and feeds the `squares` fact stream, which in
  turn backs `WorldObserver.observations.squares()`.

### 9.2 Listener builder

`Fact.listener{ ... }` hides engine wiring and provides a consistent context:

```lua
Fact.listener{
  name  = "OnLoadGridsquare:squares",
  event = "OnLoadGridsquare",

  handle = function(ctx, isoGridSquare)
    -- ctx.emit(record) pushes into the squares fact stream
    if not isoGridSquare then return end

    local record = ctx.makeSquareRecord(isoGridSquare)
    ctx.emit(record)
  end,
}
```

The builder is responsible for:

- registering/unregistering handlers against the underlying game event;
- wrapping the handler with a `ctx` table that provides:
  - `emit(record)` into the per‑type fact stream;
  - helpers such as `makeSquareRecord`;
  - access to shared config/metrics if needed.

### 9.3 Probe builder

`Fact.probe{ ... }` describes a scheduled job that “shines a light” on the
world and emits Facts via `ctx.emit`:

```lua
Fact.probe{
  name     = "nearPlayers_closeRing",
  schedule = {
    intervalTicks = 1,
    budgetPerTick = 200,
  },

  run = function(ctx, budget)
    local processed = 0

    for _, player in ipairs(ctx.players:nearby()) do
      for square in ctx.iterSquaresInRing(player, 1, 8) do
        if processed >= budget then
          return
        end

        local record = ctx.makeSquareRecord(square)
        ctx.emit(record)
        processed = processed + 1
      end
    end
  end,
}
```

The builder is responsible for:

- registering the probe with the global budgeted scheduler so that `run(ctx, budget)`
  is called with the per‑tick budget; and
- providing `ctx` with:
  - `emit(record)` into the fact stream;
  - helpers such as `players:nearby()` and `iterSquaresInRing`;
  - a small `ctx.state` table for incremental scanning where needed;
  - `ctx.metrics` for counters/timings that can inform strategy tuning.

---

## 10. Open questions

- Exact structure of a fact plan (data‑driven tables vs. builder API).
- How to expose minimal yet useful strategy introspection (e.g.
  `WorldObserver.debug.describeFacts("squares")`).
- Whether certain probes should be conditional on specific ObservationStreams
  being in use (demand‑driven probing) or purely strategy‑driven.
