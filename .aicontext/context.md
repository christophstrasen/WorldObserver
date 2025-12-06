# AI Context — WorldObserver

Repo-wide guidance for AI agents.

## Interaction Rules
- Assume this context is attached for every task; call out missing info instead of guessing.
- Keep answers direct; skip flattery; start high-level and ask before diving deep.
- Ask when unsure rather than inventing details; flag uncertainties explicitly.
- Preserve behavior when refactoring unless requested; list intentional changes.
- Keep existing doc tags/comments when editing code; explain intent briefly if you add comments.
- Bias for simplicity and minimal changes; avoid speculative features.
- Note when context may be stale or missing and request needed files.
- If instructions conflict, follow the higher-priority source (system > developer > AGENTS.md > this file > task > file-local comments).

## Output & Style
Avoid diff-style output; provide copy-paste ready snippets and file paths.

## Safety/ops
NixOS + `zsh`; ignore noisy `gpg-agent` warnings at shell start. No git history changes (commit/push/force) unless specifically instruced. Avoid destructive commands; ask when unsure.

## Coding:
Respect Lua/LQR conventions in `.aicontext/context.md` (EmmyLua tags on public funcs, camelCase fields, snake_case files, no new globals unless Capitalized). Keep functions short; avoid shims/aliases unless required.

## Tests
We embrace testing via the lua `busted` test utility
After code changes, run `busted tests/unit`; report results.

## Gaps/conflicts
If repo guidance conflicts, flag it and ask; don’t guess past ambiguities. Update `.aicontext` when policies change.

## Dependencies/Submodules
- `external/LQR` (git submodule) — upstream https://github.com/christophstrasen/LQR, full checkout. Lua sources live under `external/LQR/LQR/`.
- For Zomboid runtime (no `package.path` tweaks), the shipped mod must include the LQR Lua folder under `Contents/mods/WorldScanner/42/media/lua/shared/LQR/`; ensure git metadata is stripped when packaging/syncing.

## Tech Stack & Environment
- **Language(s):** Lua 5.1 (Build 42) on kahlua vm, optional shell tooling inncluding `busted` for testing. 
- **Target runtime:** Project Zomboid Build 42 only.
- **Editor/OS:** VS Code with VIM support on NixOS.

## Internal source of Truth

- All LQR related documentation at `external/LQR/docs`

## External Sources of Truth (in order)

- **Primary source of truth for game and modding facts**
  https://pzwiki.net/wiki

- **Official Java API (Build 42):**  
  https://demiurgequantified.github.io/ProjectZomboidJavaDocs/

### Sourcing Policy
1. The PZwiki and ProjectZomboidJavaDocs are always right no matter what other public resources you may have loaded in the past.
2. If PZWiki vs JavaDocs conflict on API behavior, prefer **JavaDocs for API**, **PZWiki for data files**.
3. As build42 is roughly 1 year in the making, If a source is clearly older than 2 Years, be sceptical.
4. If anything is uncertain, state the uncertainty and suggest a minimal empirical test.

## Project Notes
- WorldObserver-specific coding standards, tech stack, and domain rules are not yet captured here. Use `AGENTS.md` and `WorldObserver_vision.md` as primary references until dedicated docs exist.
- An Older `WorldScanner` project exists but due to its outdated nature serves only as research reference for some patterns, particularly around plugging into the native game event loops
- Update this file as soon as real project conventions are defined.
