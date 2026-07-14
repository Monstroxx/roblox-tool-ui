# Ember

A clean, single-file UI library for Roblox tools. Dark "obsidian + glowing orange" look,
leak-free architecture, config save/load, keybinds, and a runtime theme system with
JSON import/export.

Built as a from-scratch rewrite inspired by the *Speed Hub X* template — same visual
class, but with a proper connection-cleanup (Maid) model, per-notification objects,
theme registry, and a config/flag system.

---

## Loading

**Executor**

```lua
local Ember = loadstring(game:HttpGet("https://raw.githubusercontent.com/USER/REPO/main/src/Ember.lua"))()
```

**Roblox Studio**

Put [`src/Ember.lua`](src/Ember.lua) into a `ModuleScript` named `Ember`, then:

```lua
local Ember = require(path.to.Ember)
```

See [`example.lua`](example.lua) for a full demo that exercises every element.

---

## Quick start

```lua
local Window = Ember:CreateWindow({
    Name      = "Ember",
    Subtitle  = "v1.0",
    Size      = UDim2.fromOffset(560, 340),
    ToggleKey = Enum.KeyCode.RightShift,   -- show/hide the whole UI
    AntiAFK   = true,
})

local Tab = Window:CreateTab({ Name = "Main", Icon = "rbxassetid://7734053426" })
local Sec = Tab:AddSection({ Title = "Movement", Open = true })

Sec:AddToggle({ Title = "Fly", Default = false, Flag = "fly", Callback = function(on)
    print("fly:", on)
end })
```

---

## API

### `Ember:CreateWindow(config) -> Window`

| Field | Type | Default | Notes |
|---|---|---|---|
| `Name` | string | `"Ember"` | Title shown in the top bar |
| `Subtitle` | string | version | Accent-colored subtitle |
| `Size` | UDim2 | `560×340` | Window size |
| `LogoId` | string | `""` | Optional `rbxassetid://` logo |
| `ToggleKey` | KeyCode | `RightShift` | Global show/hide key |
| `AntiAFK` | bool | `true` | Prevents the 20-minute idle kick |

**Window methods:** `:CreateTab(cfg)`, `:CreateConfigTab(name?)`, `:Notify(cfg)`,
`:Dialog(cfg)`, `:SetTheme(nameOrTable)`, `:Toggle()`, `:Destroy()`.

Closing via the top-bar **×** first shows a confirm dialog before unloading.

### `Window:CreateTab({ Name, Icon }) -> Tab`
### `Tab:AddSection({ Title, Open }) -> Section` — collapsible

### Elements (on `Section`)

Every interactive element accepts an optional `Flag` (string) used by the config system,
and a `Callback`. Elements return an object with `:Set(value)` and a `.Value` field.

| Method | Key config | Returns |
|---|---|---|
| `AddButton` | `Title, Content, Callback` | `{ Instance }` |
| `AddToggle` | `Title, Content, Default, Flag, Callback` | `:Set(bool)`, `.Value` |
| `AddSlider` | `Title, Content, Min, Max, Increment, Default, Flag, Callback` | `:Set(n)`, `.Value` |
| `AddSlider` (range) | `Range = true`, `Default = {min,max}` | `:Set({min,max})`, `.Value = {min,max}` |
| `AddInput` | `Title, Content, Default, Placeholder, Flag, Callback` | `:Set(str)`, `.Value` |
| `AddInput` (numeric) | `Numeric = true`, optional `Min, Max` | `:Set(n)`, `.Value` is a `number` |
| `AddDropdown` | `Title, Content, Multi, Options, Default, Flag, Callback` | see below |
| `AddKeybind` | `Title, Content, Default(KeyCode), Flag, Callback` | `:Set(key)`, `.Value` |
| `AddParagraph` | `Title, Content` | `:Set({Title,Content})` |
| `AddSeparator` | `Title` | `:Set({Title})` |
| `AddLine` | – | – |

**Dropdown** extra methods: `:Set(value)`, `:AddOption(name)`, `:Clear()`,
`:Refresh(list, keep)`. `.Value` is a `string` when `Multi = false`, or a `{string}`
array when `Multi = true`. Includes a live search box.

**Range slider** — set `Range = true` and pass `Default = {min, max}`; both handles are
draggable and `min ≤ max` is enforced (Streamlit-style).

**Slider readout is editable** — click the number box and type a value (single mode),
or two values like `20-80` (range mode).

### `Window:Dialog({ Title, Content, Confirm, Cancel, OnConfirm, OnCancel })`

Modal confirm dialog inside the window. Clicking the dimmed overlay cancels.
Returns `{ Close }`.

### `Window:Notify({ Title, Description, Content, Type, Delay })`

`Type` ∈ `"Info" | "Success" | "Warning" | "Error"`. Notifications stack bottom-right and
each has its own `:Close()`. Returns `{ Close }`.

---

## Config / save system

Elements with a `Flag` are tracked in `Ember.Flags`. `Ember.SaveManager` persists them.

```lua
Ember.SaveManager:Save("pvp")        -- write current values
Ember.SaveManager:Load("pvp")        -- restore values (calls each element :Set)
Ember.SaveManager:Delete("pvp")
Ember.SaveManager:List()             -- -> { "pvp", ... }
Ember.SaveManager:SetAutoload("pvp") -- load "pvp" automatically next launch
Ember.SaveManager:LoadAutoload()     -- call once after building your UI
```

On an executor this writes JSON to `workspace/Ember/configs/<name>.json`. In Studio (no
file API) it falls back to in-memory storage so you can still test the flow.

`Window:CreateConfigTab()` builds a ready-made **Settings** tab with Save / Load / Delete /
Autoload buttons and a theme switcher — no extra code needed.

---

## Themes

Three themes ship built in: **Ember** (default), **Molten**, **Solstice**.

```lua
Ember:SetTheme("Molten")             -- switch at runtime (recolors live)

local json = Ember.SaveManager:ExportTheme()   -- also copies to clipboard if available
Ember.SaveManager:ImportTheme(json)            -- apply a theme from JSON
```

Colors live in a single `Theme` table (`Ember.Theme`). Every colored instance is
registered, so `SetTheme` recolors the whole UI without a reload.

**Ember palette**

| Key | Hex |
|---|---|
| Accent | `#FF6A1A` |
| AccentHover | `#FF8A3D` |
| Background | `#0B0B0D` |
| Surface | `#141418` |
| Elevated | `#1C1C22` |
| Stroke | `#2A2A31` |
| Text | `#F4F4F6` |
| Muted | `#8B8B95` |

To brand it as your own: change `Name`, `LogoId`, and the color keys in the `Themes.Ember`
table at the top of [`src/Ember.lua`](src/Ember.lua), or ship your own theme JSON.

---

## Files

- [`src/Ember.lua`](src/Ember.lua) — the library (single file).
- [`example.lua`](example.lua) — demo / verification script.
- `template/` — original reference template (not used at runtime).

## Notes

- Requires an executor for file-based config persistence and `gethui()`/`cloneref` GUI
  parenting; in Studio it parents to `PlayerGui` and uses in-memory config.
- All global input connections are tracked by a Maid and disconnected on
  `Window:Destroy()` — no lingering listeners after unload.
