# WorldObserver — Development (internal notes)

For the canonical local dev commands (tests, sync, watch), see `../development.md`.

Notes:

- This repo may include nested submodules when cloned standalone. Within DREAM-Workspace, those duplicates are usually left uninitialized to avoid confusion.
- If you initialize `external/LQR`, do not initialize or work in `external/LQR/reactivex`. The suite treats `external/lua-reactivex` (or the `pz-reactivex` wrapper repo) as the canonical reactive dependency.
