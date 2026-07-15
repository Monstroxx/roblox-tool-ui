# roblox-tool-ui

Ember — a single-file Roblox UI library for executor scripts, plus a hub template.

- `src/Ember.lua` — the library: UI elements, theme system, SaveManager (configs + auto-save),
  Compat layer (executor capability detection), session extras (Anti-AFK, Auto-Execute, Auto-Rejoin).
- `template.lua` — the universal hub built on Ember. Game cheats (fly, walkspeed, …) live HERE,
  not in the library.

There is no local Lua interpreter on this machine and executor APIs can't run outside Roblox —
verify changes by careful reading, and test in-game via the Diagnostics section of the Settings tab.

## RULE: Executor function names — check the standards first

Before adding, renaming, or adding fallbacks for ANY executor function (e.g. `writefile`,
`setclipboard`, `queue_on_teleport`), consult the naming standards. **Never guess names and never
copy from individual executor docs** — most (e.g. synapsexdocs.github.io) are outdated and
describe dead executors.

Check in this order:

1. **sUNC** — https://docs.sunc.su/ (source: https://github.com/sUNC-Utilities/docs.sunc.su) —
   actively maintained, tested canonical names. Only documents functions **actively tested by the
   sUNC script**; it has diverged from the original UNC list (deprecated functions removed, new
   ones added based on executor developer feedback), so treat it as the primary source of truth
   over UNC when the two disagree.
2. **UNC api/ files** — https://github.com/unified-naming-convention/NamingStandard/tree/main/api —
   archived (May 2024) but the authoritative source for **documented aliases**
   (e.g. `setclipboard` → `toclipboard`, `queue_on_teleport` → `queueonteleport`,
   `identifyexecutor` → `getexecutorname`).

Implementation rules:

- All alias handling lives in `COMPAT_ALIASES` in `src/Ember.lua` — one declarative table,
  no scattered ad-hoc fallbacks. Candidate order: canonical name → documented UNC alias →
  legacy executor namespace (dotted, e.g. `syn.queue_on_teleport`) as a last resort, each with
  a comment naming its source.
- All executor calls go through `Ember.Compat:Get(name)` (validated + cached), never through
  raw globals.
- **Quartz** (https://github.com/notpoiu/Quartz) is the sanctioned runtime polyfill for missing
  functions. It stays **opt-in** via `Ember.Compat:UseQuartz(instance)` — never auto-load remote
  code from the library.

## RULE: Icons — never guess asset IDs, verify them by eye

`Ember.Icons` in `src/Ember.lua` is a **curated subset (~38) of the Lucide set — there are 1500+
more available**. Anything taking an icon (`CreateTab{ Icon = ... }`) accepts any
`rbxassetid://`, so the table is a convenience shortlist, not a limit.

Sources:

1. **https://www.icons.rest/** — browse 1500+ Lucide icons mapped to Roblox asset IDs; easiest
   way to find one by eye and copy its rbxassetid.
2. **https://github.com/frappedevs/lucideblox** — `src/modules/util/icons.json`, a flat
   `name → rbxassetid` map of 565 icons as **individual assets**. This is the source `Ember.Icons`
   was built from; use it when adding entries.
3. **https://github.com/latte-soft/lucide-roblox** — the fuller/maintained set, but it ships a
   **spritesheet** (`ImageRectOffset`/`ImageRectSize`). Our `ImageLabel`s only set `Image`, so its
   IDs do **not** work here without adding rect support first. Don't reach for it by default.

Before adding an icon ID:

- **Verify it visually — never trust the name alone and never recall an ID from memory.** Pipeline:
  `https://thumbnails.roblox.com/v1/assets?assetIds=<ids>&size=150x150&format=Png` → download the
  `imageUrl` → composite onto a dark background → look at it. The icons are **white on
  transparent**, so a raw thumbnail renders white-on-white and looks blank. A labeled contact
  sheet (System.Drawing via PowerShell) makes checking a batch quick.
- Keys in `Ember.Icons` are **PascalCase**: Lucide names like `repeat` are Lua keywords and
  `refresh-cw` isn't a valid identifier, so `Repeat` / `Refresh` sidestep both.
