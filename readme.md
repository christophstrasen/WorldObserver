# WorldObserver

[![CI](https://github.com/christophstrasen/WorldObserver/actions/workflows/ci.yml/badge.svg)](https://github.com/christophstrasen/WorldObserver/actions/workflows/ci.yml)


**WorldObserver** is a shared observation layer for **Project Zomboid (Build 42)** mods.

It helps mods **observe what is happening in the world — safely, fairly, and over time** —
without every mod re-implementing fragile scan loops, throttling logic, or ad-hoc state tracking.

WorldObserver is deliberately focused on **facts and observations**.

> It answers **“what do we know about the world?”**  
> You decide **“what does this mean?”** and **“what should happen?”**

---

## Status

- Approaching **Alpha**
- API surface is stabilizing, naming may still change
- Focus: correctness, performance safety, and expressive observation

---

## Before: how mods observe the world today

Most Zomboid mods that observe the world end up hand-rolling variations of the same patterns:

- periodic scans of nearby squares or chunks
- multiple `OnTick` counters and cooldowns
- partial event subscriptions
- manual deduplication and state tables
- defensive throttling to avoid frame drops
- bespoke logic to remember “what we already saw”

This works — but it scales poorly.

Problems appear when:
- observation logic becomes complex or stateful
- multiple mods observe the same areas
- bursts of world activity happen (chunk loads)
- you want to reason *over time*, not just per event

Even worse:  
**each mod solves these problems in isolation**, often rediscovering the same pitfalls.

---

## What WorldObserver changes

WorldObserver tackles two things at once:

1. **It centralizes observation work**  
   so that probing, buffering, and throttling are shared and fair.

2. **It raises the level of expression**  
   so mods can reason about *patterns*, not just raw events.

This is where LQR becomes important.

---

## Why LQR underneath matters

WorldObserver builds on **LQR (Lua Query over Reactive streams)** as its observation backbone.

This unlocks capabilities that are difficult to hand-roll correctly:

### Joining observations
Observe *relationships* instead of isolated facts:
- zombies near certain squares
- entities overlapping in space and time
- correlated signals across streams

### Grouping & aggregation
Reason about *sets*, not just individuals:
- “how many”
- “how often”
- “over what window of time”

### Stateful observation
Maintain rolling or derived state safely:
- A picture that gets progressively clearer over time
- temporal conditions (“still true”, “no longer true”)
- transitions instead of snapshots

### Declarative intent
Describe *what you want to observe*, not *how to poll it*:
- the runtime decides when and how work happens
- observation stays readable even as complexity grows

Before WorldObserver, these patterns were:
- rare,
- fragile,
- expensive,
- or simply not attempted.

WorldObserver makes them **normal, safe, and composable**.

---

## What WorldObserver is (and is not)

### It *is*
- A **facts & observations** system
- A way to observe the world **over time**
- A shared runtime with **budgets and fairness**
- A foundation for higher-level mod logic

### It is *not*
- A gameplay framework
- A decision engine
- A story system
- A replacement for your mod’s logic

WorldObserver intentionally **stops at observation**.

---

## The core mental model

WorldObserver is built around a clear pipeline:

1. **Facts**  
   Raw fact signals from the world (events, scanning probes).

2. **Observations**  
   Time-aware streams of higher level observations you can subscribe to.

3. **Situations**  
   *Your* interpretation of observations.  
   This is the responsibility boundary.

4. **Actions**  
   What your mod does when a situation matters.

WorldObserver owns **facts and observations**.  
You own **situations and actions**.

---

## How observation works (two equal pillars)

WorldObserver is supported by **two equally important systems**.

### 1. Runtime controller  
**Safety**

- Buffers incoming facts
- Regulates ingest vs drain
- Throttles probes
- Enforces per-tick budgets
- Drops work deterministically under pressure
- Ensures fairness across mods

No matter how expensive observation becomes,  
**it never bypasses runtime safety**.

### 2. Observation streams & queries  
**Expressiveness**

- Facts become typed **ObservationStreams**
- Streams can be refined using **helpers**
- More complex relationships are expressed using **queries**
- Query results are exposed as *new streams*

Everything remains subscribable, composable, and time-aware.


---

## Interest declarations: collaborative probing

Before any mod can successfuly subscribe to obervsations, it needs to **declare interest** in observations via specifying:
- rough area
- freshness expectations
- cadence bands ??

This enables something new:

> **Collaborative probing**

Instead of each mod probing independently:
- needs are merged
- probes are shared
- fairness is enforced
- degradation is coordinated

This is not an optimization trick —  
it is a governance mechanism for a shared runtime.

---

## When should I use WorldObserver?

WorldObserver shines when your mod:
- observes continuously
- reasons over time
- correlates multiple signals
- must stay performant alongside other mods

If you only need a single event hook —
WorldObserver is likely unnecessary.

---

## How this relates to LQR

You do **not** need to know LQR to use WorldObserver.

If you do:
- you can drop down when needed
- but LQR remains a *means*, to an end
- @TODO mention reactivex

WorldObserver is **not “LQR with probes”**.  
It is an observation system that **uses LQR to make complex observation safe and expressive**.

---

## What to read next

- `docs/quickstart.md`
- `docs/observations/index.md`
- `docs/guides/lifecycle.md`

---

## License

MIT
