# PlayerObservation Checklist

---

## 1) Identity

- Observation goal (1 sentence): observe `IsoPlayer` movement/state changes and emit join-ready snapshot records (event scopes: `OnPlayerMove`, `OnPlayerUpdate`) that enable derived situations (example: “players entering dangerous rooms”, “players near zombies”, “players in vehicles”).
- Interest `type` (plural, stable): `players`
- Payload family key (singular, stable): `player`
- Naming notes (why this name; avoided names): `players` matches engine concept (`IsoPlayer`) and aligns with existing `zombies`, `vehicles`, `deadBodies`, `items`.
- Glossary impact:
  - ☑ No new terms
  - ☐ New term added to `docs/glossary.md` (only if unavoidable)

---

## 2) Implementation Status

- Status: ☑ idea ☐ prototyping ☐ in progress ☐ test-complete ☐ documented ☐ shipped
- Last updated (date): `2025-12-27`
- Open tasks / blockers:
  - Confirm which player identifiers are present and stable in SP vs MP (`getSteamID`, `getOnlineID`, `getID`, `getPlayerNum`).
  - Decide whether we need any probe-driven fallback for missed events (likely “no” for v0).
- Known risks / unknowns (perf/correctness/key-stability/hydration):
  - Event flood: both events are high-frequency; we must gate with `cooldown` + recommend `distinct("player", 0.2s)` to keep streams usable.
  - Key stability differs between SP/MP; treat `steamId` as the preferred long-term id when present, but confirm presence + stability in the Lua runtime (assume it is returned as a string).
  - No re-hydration path for `IsoPlayer` by ID exists in WO today; storing `IsoPlayer` is best-effort/ephemeral only.
 - Known event facts (Build 42):
  - `Events.OnPlayerMove` passes an `IsoPlayer` argument.
  - `Events.OnPlayerUpdate` passes an `IsoPlayer` argument.
  - Both are client-side and appear to be “each local player's update” (so usually one player).

---

## 3) Modder UX (v0 contract)

- What does the modder want to accomplish (not implementation): react to player movement and lightweight state changes (position, room/building context, “is aiming”, etc.) without wiring their own `OnPlayer*` loops and cooldown tables.
- “Smallest useful” copy/paste example (declare interest + subscribe): `[...]` (to be validated once `players` stream exists)

```lua
local WorldObserver = require("WorldObserver")

local MOD_ID = "YourModId"

local lease = WorldObserver.factInterest:declare(MOD_ID, "players.move", {
  type = "players",
  scope = "onPlayerMove",
  cooldown = { desired = 0.2 }, -- seconds; v0 guidance: keep modest due to event volume
  highlight = true,            -- highlight the square the player is on
})

local sub = WorldObserver.observations:players()
  :distinct("player", 0.2) -- seconds; keep modest for join-friendly low-noise streams
  :subscribe(function(observation)
    local p = observation.player
    if not p then return end
    print(("[WO] steamId=%s onlineId=%s playerNum=%s tile=%s source=%s"):format(
      tostring(p.steamId),
      tostring(p.onlineId),
      tostring(p.playerNum),
      tostring(p.tileLocation),
      tostring(p.source)
    ))
  end)

-- later:
-- sub:unsubscribe()
-- lease:stop()
```

- One intended derived stream / “situation” this base stream should enable (name it): “players entering dangerous rooms” (join `player.roomLocation` with `room.roomLocation` + zombie proximity streams later).
- Non-goals / explicitly out of scope for v0:
  - Full “player state” modeling (moodles, traits, inventory, stats) beyond a small set of cheap fields.
  - Any persistence / save/load identity guarantees beyond what the chosen primary key can actually support.
  - Re-hydration of `IsoPlayer` from stored IDs (not currently possible in WO).

---

## 4) Interest Surface (data-driven truth)

Define supported combinations and defaults first. This is the contract surface.

- Supported `scope` list:
  - `onPlayerMove`
  - `onPlayerUpdate`
- Per-scope acquisition mode:
  - `scope = "onPlayerMove"`: ☑ listener-driven
  - `scope = "onPlayerUpdate"`: ☑ listener-driven
- Targeting (only if applicable): n/a (facts are “all players” per event; no target bucketing in v0)
- Settings and semantics (per scope):
  - `staleness`: n/a (event-driven)
  - `cooldown` (seconds, in-game clock): per-player re-emit gating (dedup key: `playerKey` — a namespaced string derived from the best available identifier)
  - Defaults (v0 proposal):
    - `cooldown.desired = 0.2` (200ms)
  - other settings: none in v0 (keep surface small)
  - `highlight` support: ☑ yes (highlight the floor square under the player when an observation emits)
- Explicitly unsupported in v0 (so callers don’t guess):
  - `radius` (no spatial query surface yet; use derived streams later)
  - `target` (no “near player” targeting in v0; that’s a derived stream concern)

---

## 5) Fact Acquisition Plan (bounded)

Key rule: produce *small records* and call `ctx.ingest(record)` (don’t do downstream work in engine callbacks).

- Listener sources (engine callbacks / LuaEvents):
  - `Events.OnPlayerMove.Add(fn)` (payload shape to confirm)
  - `Events.OnPlayerUpdate.Add(fn)` (payload shape to confirm)
- Probe sources (active scans): none in v0
- Bounding (how work is capped per tick / per sweep):
  - Listener callbacks must stay constant-time and never loop all players.
  - Use per-key `cooldown` gating (by `playerKey`) and recommend stream-side `distinct("player", 0.2)` to reduce downstream churn.
  - Rely on ingest buffering (registry scheduler + per-type buffers) as the backpressure boundary for bursty events.
  - Logging convention (debug only): keep `record.source` coarse (`event`/`probe`/...) and log a fully-qualified label as `sourceQualified = record.source .. "." .. record.scope` when `record.scope` is present (example: `event.onPlayerMove`).
- Failure behavior (missing APIs, nil/stale engine objects):
  - If events are missing/unavailable in Lua: log a single actionable warning (outside headless) and disable the scope.
  - If `IsoPlayer` or `getCurrentSquare()` is nil/stale: emit record without square/room/building linkage (skip highlight).
  - Room location derivation: if computing `roomLocation` is too expensive in high-frequency scopes, allow leaving it unset (and join via `tileLocation` → `rooms` stream), or add a small cache keyed by the `IsoRoom` userdata to avoid recomputing `roomLocation` repeatedly while the player stays in the same room.

---

## 6) Record Schema + Relations

Design constraints:
- Records are snapshots (primitive fields + best-effort hydration handles).
- Avoid relying on live engine userdata.

  - Required fields (must exist on every record):
  - Identity:
    - At least one of:
      - `steamId` (preferred long-term key when present): `player:getSteamID()`
      - `onlineId` (MP session id): `player:getOnlineID()`
      - `playerId` (session id): `player:getID()`
      - `playerNum` (slot index): `player:getPlayerNum()`
    - `playerKey` (string, dedup/cooldown key; namespaced to avoid collisions across id types):
      - examples: `steamId1234`, `onlineId45`, `playerId77`, `playerNum0`
      - record builder rule (best-effort selection, in order): prefer `steamId`, else `onlineId`, else `playerId`, else `playerNum`
  - Spatial anchor:
    - `tileX/tileY/tileZ` from `player:getCurrentSquare():getX()/getY()/getZ()` (or from player coords getX, getY, getZ, if square missing)
    - `x/y/z` set equal to `tileX/tileY/tileZ` for schema consistency and square hydration helpers
    - `tileLocation` via `SquareHelpers.record.tileLocationFromCoords(tileX, tileY, tileZ)` (join-ready square key)
  - Timing: `sourceTime` (ms, in-game clock; auto-stamped at ingest if omitted)
  - Provenance: `source` (string, producer/lane) — example value: `event`
    - Scope disambiguation (recommended if both scopes are active): `scope` (string) — example values: `onPlayerMove`, `onPlayerUpdate`
- Optional fields (cheap, high leverage; keep short):
  - `username` via `player:getUsername()` 
  - `displayName` via `player:getDisplayName()`
  - `accessLevel` via `player:getAccessLevel()` (useful for admin/mod tooling)
  - `hoursSurvived` via `player:getHoursSurvived()`
  - `isLocalPlayer` via `player:isLocalPlayer()`
  - `isAiming` via `player:isAiming()`
- Best-effort hydration fields (may be missing/stale; do not rely on rehydration):
  - `IsoPlayer` (the live engine object; stored directly but not rehydratable today)
  - `IsoGridSquare` (from `player:getCurrentSquare()`)
  - `IsoRoom` (from `player:getCurrentSquare():getRoom()`)
  - `IsoBuilding` (from `player:getBuilding()`)
- Relations captured (join-ready keys + engine objects):
  - Current square (`player:getCurrentSquare()`):
    - keys: `tileX/tileY/tileZ`, `x/y/z`, `tileLocation`
    - engine: `IsoGridSquare`
  - Current room (`player:getCurrentSquare():getRoom()`):
    - keys: `roomLocation` + optional `roomName`
    - engine: `IsoRoom`
  - Current building (`player:getBuilding()`):
    - keys: `buildingId` (from `player:getBuilding():getID()`)
    - engine: `IsoBuilding`
- Hydration helpers used (reference existing helpers; don’t re-spec contracts here):
  - `WorldObserver.helpers.square.record.getIsoGridSquare(squareLikeRecord, opts)` (requires `x/y/z`)
  - `WorldObserver.helpers.square.record.squareHasIsoGridSquare(squareLikeRecord, opts)`
  - Room/building hydration: none yet (store best-effort `IsoRoom`/`IsoBuilding` only if we choose to)
  - New helper(s) introduced (only if needed; contract in 3–6 bullets):
  - Proposed DRY refactor (investigate local code architecture across fact builders):
    - `WorldObserver.helpers.room.record.roomLocationFromIsoRoom(room)` (extract from `facts/rooms/record.lua:deriveRoomIdFromFirstSquare`)
    - `WorldObserver.helpers.room.record.buildingIdFromIsoBuilding(building)` (extract from `facts/rooms/record.lua:deriveBuildingId`)
  - Goal: avoid more “hidden internal” reuse via `Record._internal.*` across families.
- Record extenders (if any): `players.playerRecord` extender hook (pattern: `registerPlayerRecordExtender(id, fn)`), only if we need per-mod augmentation later.

---

## 7) Key / ID and Stability Contract

- Primary key field(s): `playerKey` (string; namespaced best-effort id, derived from the best available identifier)
- Stability:
  - Stable within session? ☑ yes (at least one of the ids should be stable; verify per field)
  - Stable across save/load? ☑ yes ☐ no (notes: `steamId` expected yes when present; confirm in Lua runtime)
  - Stable in MP? ☑ yes ☐ no (notes: `steamId` expected yes when present; `onlineId` expected stable within connection/session only)
- Dedup/cooldown key:
  - Which field defines “same underlying fact” for cooldown? `playerKey`
  - Any alternate stable anchor to prefer: none in v0; revisit if `steamId` is missing or not exposed in Lua.

---

## 8) Stream Behavior (subscriber summary)

- Sources → emissions (per scope):
  - `scope="onPlayerMove"`: event-driven bursts; gated by `cooldown` and subscriber `distinct("player", 0.2)`
  - `scope="onPlayerUpdate"`: very frequent events; *must* be gated by `cooldown` and `distinct("player", 0.2)`
- Primary stream dimension(s): `distinct("player", seconds)` → dedup key: `playerKey`
- Freshness + buffering: best-effort; may be delayed by ingest buffering; under load the effective cadence may degrade
- Payload guarantees: base stream emits `observation.player`; relation/hydration fields are best-effort and may be `nil`/stale

---

## 9) Helpers (minimum useful)

- Required on every base observation stream:
  - `:playerFilter(fn)` as the generic “custom predicate” escape hatch.
  - `:distinct("player", seconds)` where the internal keyField is `playerKey`.
- Record helpers (predicates/utilities + hydration):
  - (none required for dedup; use `record.playerKey`)
  - `WorldObserver.helpers.square.record.getIsoGridSquare(record)` (square hydration reuse)
- Stream helpers (chainable sugar): none in v0
- Effectful helpers (rare; clearly named): none in v0
- Listed in docs (where): `docs/observations/players.md` (new)

---

## 10) Debug + Verify (quick)

- `highlight` behavior (what gets highlighted): highlight the floor square the player is on when an observation emits.
- “How to verify it works” steps (2–6 bullets):
  - Declare `type="players", scope="onPlayerMove", cooldown={desired=0.2}, highlight=true`
  - Subscribe and print `steamId/onlineId/playerNum` plus `tileLocation` and `source`
  - Walk around: confirm highlighted squares track your movement and that output rate is bounded (~<=10 Hz per player)
- Example / smoke script path (if any): `Contents/mods/WorldObserver/42/media/lua/shared/examples/smoke_players.lua`
- Smoke notes (PZ `require` paths, headless compatibility): event scopes require engine runtime; headless tests should target record helpers and registry/ingest behavior.

---

## 11) Touchpoints (evidence you updated the system)

- Central truth (interest surface):
  - ☐ `WorldObserver/interest/definitions.lua` updated (add `players` + scopes)
  - ☐ `docs_internal/interest_combinations.md` updated
- Tests:
  - ☐ unit tests added/updated: `tests/unit/players_*`
  - ☐ headless command: `busted tests`
  - ☐ engine checks done (event payload shape, nil-safe, bounded per tick): `[...]`
- Documentation:
  - ☐ user-facing docs updated: `docs/observations/players.md`, `docs/observations/index.md`, `docs/guides/interest.md`
  - ☐ internal docs updated (if needed): `docs_internal/fact_layer.md`, `docs_internal/code_architecture.md`
- Examples:
  - ☐ example / smoke script added/updated: `Contents/mods/WorldObserver/42/media/lua/shared/examples/smoke_players.lua`
  - ☐ minimal smoke scenario described (1–3 bullets): `[...]`
- Logbook / lessons:
  - ☐ `docs_internal/logbook.md` entry added/updated (if meaningful): `[...]`

---

## Appendix (optional): Research notes

- PZWiki links consulted:
  - `https://pzwiki.net/wiki/OnPlayerMove`
  - `https://pzwiki.net/wiki/OnPlayerUpdate`
- ProjectZomboidJavaDocs entrypoints and methods used:
  - `https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/characters/IsoPlayer.html`
    - `getSteamID()`, `getOnlineID()`, `getID()`, `getPlayerNum()`
    - `getUsername()`, `getDisplayName()`, `getAccessLevel()`, `getHoursSurvived()`
    - `isLocalPlayer()`, `isAiming()`
- Events/hooks used (and exact payload shape if non-obvious): `[...]` (confirm callback args in-engine)
- Empirical checks run (console snippets / in-game test steps): `[...]`
- Open questions / uncertainties (and proposed minimal tests):
  - Confirm which IDs are available in Lua for SP vs MP and their stability claims (especially `steamId`).
  - Confirm whether `player:getBuilding()` is available in Lua and whether it’s cheaper/more reliable than `square:getRoom():getBuilding()`.
  - Confirm whether deriving `roomLocation` via `room:getSquares()` is safe/perf-acceptable on high-frequency events; if not, keep `roomLocation` nil for v0 and rely on joining via `tileLocation` → `rooms` stream later.
