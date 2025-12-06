# WorldObserver Logbook

## day1 – Setup & dependencies

### Highlights
- Added `AGENTS.md` with repo-wide agent priorities, safety rules, and testing expectations.
- Rebuilt `.aicontext/context.md` to generic guidance and documented the `external/LQR` submodule (full checkout) plus Zomboid packaging needs.
- Integrated `external/LQR` (upstream https://github.com/christophstrasen/LQR); decided to ship its `LQR/` Lua folder inside `Contents/mods/WorldScanner/42/media/lua/shared/LQR/` since `package.path` cannot be tweaked at runtime.
- Updated `watch-workshop-sync.sh` to exclude `external/` from the main rsync and add a second rsync that mirrors only `*.lua` from `external/LQR/LQR/` into the shipped mod path.

### Next steps
- Script a sync/copy step that mirrors `external/LQR/LQR` into the mod tree while stripping git metadata.
- Capture WorldObserver-specific coding standards and runtime notes in `.aicontext/` and docs as they emerge.
