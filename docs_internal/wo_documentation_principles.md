# WorldObserver Documentation Principles

This note captures the guiding principles for **WorldObserver (WO)** documentation. It is intended for maintainers and contributors so new docs and examples stay coherent as the project grows.

WorldObserver’s audience is **primarily simple Project Zomboid modders**: people who can write Lua and use `Events.*`, but who may not be familiar with ReactiveX, streaming joins, or performance budgeting patterns.

## 1. Goals and audience

- **Primary audience:** beginner → intermediate Lua modders who want to *use* observations safely without learning LQR first.
- **Secondary audience:** advanced modders who want to publish new observations and tune performance.
- **Goal:** make it possible to adopt WO by copy‑pasting a small example, then gradually learning the model (facts → observations → situations → actions) without reading the whole codebase.

Non-goals:
- Teach ReactiveX in general. Link out to LQR docs when needed.
- Provide a GUI/config UI story. WO is code-first.

## 2. Layered documentation structure

Keep a clear split between user-facing docs and internal design notes:

- **Root `readme.md` (user-facing overview)**
  - Value proposition, what WO is/is-not.
  - A tiny “hello observation” Quickstart that works in-game.
  - Link to `docs/` and “next steps”.

- **`docs/` (user-facing)**
  - Curated, stable, task-oriented.
  - Target structure:
    - `docs/index.md` — landing page; links into quickstart/observations/guides/troubleshooting.
    - `docs/quickstart.md` — subscribe to an observation, print something, stop/unsubscribe.
    - `docs/observations/` — what’s available (“squares”, “zombies”, …) + what each emits.
    - `docs/guides/` — workflows (declare interest, make a derived observation, debug).
      - `docs/guides/interest.md` — how to declare interest, pick interest `type`, and tune `radius`/`staleness`/`cooldown` (incl. trade-offs).
      - `docs/guides/debugging_and_performance.md` — how to confirm WO is running, inspect merged interest, enable diagnostics, and tune for safety/cost.
      - `docs/guides/derived_streams.md` — multi-family derived streams (streams whose observations carry more than one family, e.g. both `observation.square` and `observation.zombie`) and safe consumption patterns.
        - Explain how to read and guard multi-family observations (only use fields you expect; don’t assume every family is present).
        - Show how to filter with family sugar (`:squareFilter(...)`, `:zombieFilter(...)`) when you only care about one family.
        - Show how to handle “both are present” logic (e.g. “zombie has target and is on a bloody square”) without turning it into a big nil-check mess.
        - Include one small, copy/paste example and a clear “stop/unsubscribe + stop lease” cleanup pattern.
    - `docs/troubleshooting.md` — common pitfalls (nil Iso objects, too much scanning, missing interest, headless vs game runtime).
    - `docs/reference/` — stable API reference once the surface is truly stable.

Additional scope for `docs/` pages (to keep code and docs aligned):
- Every `docs/observations/<type>.md` page should include the currently supported interest configuration for that type (supported `type` / `scope` / `target` combinations and meaningful settings), derived from `docs_internal/interest_combinations.md`.

- **`docs_internal/` (internal)**
  - Vision, design briefs, experiments, refactor plans, logbook.
  - Can be exploratory and verbose; not required reading for end-users.

When in doubt:
- If it helps modders *use* WO, it belongs in `docs/`.
- If it records trade-offs, history, or partial designs, it belongs in `docs_internal/`.

## 3. Content principles (WO-specific)

### 3.1 Start from outcomes, then reveal mechanics

WO docs should begin with “what you want to achieve”:

- “Highlight squares near the player”
- “Detect zombies with a target”
- “Track ‘needs cleaning’ squares over time”

Only after the example works do we explain the machinery (interest, buffering, budgets, derived streams).

### 3.2 Keep vocabulary sticky, but don’t over-jargon

Use WO terms consistently (from `docs_internal/vision.md`):

- **Fact** — raw signal produced by listeners/probes (input side).
- **Observation** — a stream of records derived from facts (what mods subscribe to).
- **Situation** — the modder’s interpretation (“this matters now”).
- **Action** — what the mod does.

When LQR terms are unavoidable, introduce them lightly and link:

- record, schema, join/window, `expired()`

Do not assume the reader knows any of these terms upfront.

### 3.3 “Observations, not entities”

Repeat this early and often:

- streams carry *observations about the world*, not the live engine objects; 
- Iso objects may be missing/stale; treat them as best-effort hydration only;
- prefer stable ids/coords over storing userdata references.

### 3.4 One new idea per page

Avoid mixing multiple hard ideas:

- “interest leases” should not be taught in the same doc as “joins and windows”.
- “debug tooling” should not be bundled into “how to write a probe”.

Link forward instead.

### 3.5 Be honest about cost, budgets, and failure modes

WO exists to make observation safe. Docs must reflect that:

- show how to declare interest instead of scanning unboundedly;
- call out trade-offs (freshness vs cost, radius vs workload);
- explain what happens under load (degraded mode, dropping/compaction, staleness changes);
- teach how to debug “why am I not seeing results?” (interest missing, headless mode, no tick hook, etc.).

## 4. Examples and teaching style

- Prefer **Project Zomboid domains only** (squares, zombies, rooms, vehicles).
- Keep examples runnable and “small enough to paste”.
- Show expected output (log lines) when possible.
- Use a consistent mod id + key pattern for interest declarations (so examples feel uniform).
- Include `unsubscribe()`/`stop()` patterns early so modders don’t leak handlers.

## 5. Style and tone

- Write for modders, not library authors.
- Use short sentences, concrete instructions, and minimal abstraction.
- Avoid long theory sections; prefer “do this, then this” with brief “why”.
- Prefer a single canonical way to do a thing; mention alternatives only in “advanced” callouts.

## 6. Keeping docs aligned with code

- Update docs when:
  - the public `WorldObserver` API surface changes (names, payload shapes);
  - observation record schemas change (fields renamed/added/removed);
  - performance behavior changes (budgets, degraded mode, ingest behavior).
- When behavior changes in a non-obvious way:
  - add a short entry to `docs_internal/logbook.md`; and
  - update the affected page in `docs/` (or add a troubleshooting note).

## 7. “Good citizen” checklist for new docs

Before merging a new or heavily edited WO doc:

- Does it clearly target **simple modders** and start with a runnable outcome?
- Does it introduce at most **one major new concept**?
- Does it use WO vocabulary consistently (Fact/Observation/Situation/Action)?
- Does it avoid leaking LQR complexity unless necessary (and link when it does)?
- Does it mention the relevant safety constraints (interest, budgets, unsubscribing)?
- Does it belong in `docs/` (user-facing) vs `docs_internal/` (internal)?
