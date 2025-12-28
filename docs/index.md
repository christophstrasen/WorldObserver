# WorldObserver documentation

WorldObserver helps Lua mods observe the World of Project Zomboid safely and conveniently.

You are reading the documentation index. For a high level overview, see [readme.md](../readme.md).

Recommended reading order:
1. [Quickstart](quickstart.md)
2. [Glossary](glossary.md)
3. [Guide: declaring interest](guides/interest.md)
4. [Observations overview](observations/index.md)
5. [Lifecycle: subscriptions and interest leases](guides/lifecycle.md)
6. [Stream basics](guides/stream_basics.md)
7. [Situation factories (named situations)](guides/situation_factories.md)
8. [Troubleshooting](troubleshooting.md)

## Pages

### Getting started
- [Quickstart](quickstart.md)
- [Glossary](glossary.md)
- [Troubleshooting](troubleshooting.md)

### Guides (workflows + concepts)
- [Declaring interest](guides/interest.md)
- [Architecture rationale (why WO is built this way)](architecture_rationale.md)
- [Lifecycle (unsubscribe + stop/renew leases)](guides/lifecycle.md)
- [Stream basics](guides/stream_basics.md)
- [Situation factories (named situations)](guides/situation_factories.md)
- [Helpers (built-in and extending)](guides/helpers.md)
- [Debugging and performance](guides/debugging_and_performance.md)
- [Derived streams (multi-family observations)](guides/derived_streams.md)
- [Extending record fields](guides/extending_records.md)

### Observations (what you can subscribe to)
- [Observations overview](observations/index.md)

Base observation streams:
- [Squares](observations/squares.md)
- [Rooms](observations/rooms.md)
- [Sprites](observations/sprites.md)
- [Zombies](observations/zombies.md)
- [Vehicles](observations/vehicles.md)
- [Items](observations/items.md)
- [Dead bodies](observations/dead_bodies.md)

Supporting reading:
- [ReactiveX primer](observations/reactivex_primer.md)

### Diagrams
- [Architecture (simple)](diagrams/architecture_simple.drawio)
- [Architecture (full)](diagrams/architecture_full.drawio)
