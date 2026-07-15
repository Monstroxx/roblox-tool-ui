--[[
	Ember UI Library — demo / verification script

	How to run:
	  • Executor:  loadstring(game:HttpGet("<RAW_URL>/example.lua"))()
	               (set RAW_URL below to your repo's raw path)
	  • Studio:    put src/Ember.lua into a ModuleScript named "Ember" as a sibling
	               of this LocalScript, then Play.

	This script exercises every element so you can visually confirm the library works.
]]

local RAW_URL = "https://raw.githubusercontent.com/Monstroxx/roblox-tool-ui/main" -- <- change me for executor use

--// Obtain the library (executor via HttpGet, else require sibling ModuleScript)
local Ember
do
	local ok, lib = pcall(function()
		return loadstring(game:HttpGet(RAW_URL .. "/src/Ember.lua"))()
	end)
	if ok and type(lib) == "table" then
		Ember = lib
	else
		Ember = require(script.Parent:WaitForChild("Ember"))
	end
end

--============================================================================--
--  Window
--============================================================================--
local Window = Ember:CreateWindow({
	Name      = "Ember",
	Subtitle  = "v" .. Ember.Version,
	-- LogoId = "rbxassetid://<your-logo>",   -- optional
	Size      = UDim2.fromOffset(560, 340),
	ToggleKey = Enum.KeyCode.RightShift,       -- show/hide the whole UI
	AntiAFK   = true,
})

--============================================================================--
--  Tab 1 — Main (core elements)
--============================================================================--
local Main = Window:CreateTab({ Name = "Main" })

local Combat = Main:AddSection({ Title = "Combat", Open = true })

Combat:AddButton({
	Title = "Kill all", Content = "Runs a one-shot action",
	Callback = function()
		Window:Notify({ Title = "Ember", Description = "Button", Content = "Kill all pressed", Type = "Success" })
	end,
})

Combat:AddToggle({
	Title = "Aimbot", Content = "Toggle aim assist",
	Default = false, Flag = "aimbot",
	Callback = function(v) print("[demo] aimbot =", v) end,
})

Combat:AddSlider({
	Title = "FOV", Content = "Aimbot field of view",
	Min = 10, Max = 500, Increment = 5, Default = 120, Flag = "aimbot_fov",
	Callback = function(v) print("[demo] fov =", v) end,
})

Combat:AddSlider({
	Title = "Damage range", Content = "Streamlit-style min/max slider",
	Range = true, Min = 0, Max = 100, Increment = 1, Default = { 20, 80 }, Flag = "dmg_range",
	Callback = function(v) print("[demo] range =", v[1], v[2]) end,
})

Combat:AddKeybind({
	Title = "Trigger key", Content = "Hold to activate",
	Default = Enum.KeyCode.E, Flag = "trigger_key",
	Callback = function(key) print("[demo] trigger pressed:", key.Name) end,
})

local Targets = Main:AddSection({ Title = "Targets", Open = true })

Targets:AddDropdown({
	Title = "Priority", Content = "Single select",
	Multi = false, Options = { "Closest", "Lowest HP", "Random" }, Default = "Closest", Flag = "priority",
	Callback = function(v) print("[demo] priority =", v) end,
})

Targets:AddDropdown({
	Title = "Body parts", Content = "Multi select + search",
	Multi = true, Options = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" },
	Default = { "Head" }, Flag = "hitparts",
	Callback = function(v) print("[demo] parts =", table.concat(v, ", ")) end,
})

Targets:AddInput({
	Title = "Whitelist", Content = "Comma-separated usernames",
	Placeholder = "friend1, friend2", Default = "", Flag = "whitelist",
	Callback = function(v) print("[demo] whitelist =", v) end,
})

Targets:AddInput({
	Title = "Walkspeed", Content = "Numbers only, clamped 16-500",
	Numeric = true, Min = 16, Max = 500, Default = 16, Flag = "walkspeed",
	Callback = function(v) print("[demo] walkspeed =", v, type(v)) end,
})

--============================================================================--
--  Tab 2 — Visuals (decorative elements)
--============================================================================--
local Visuals = Window:CreateTab({ Name = "Visuals" })

local ESP = Visuals:AddSection({ Title = "ESP", Open = true })

ESP:AddParagraph({
	Title = "About ESP",
	Content = "This paragraph wraps long text automatically across multiple lines so you can describe features in detail without breaking the layout.",
})
ESP:AddSeparator({ Title = "Boxes" })
ESP:AddToggle({ Title = "Box ESP", Default = true, Flag = "esp_box" })
ESP:AddToggle({ Title = "Name ESP", Default = true, Flag = "esp_name" })
ESP:AddLine()
ESP:AddSeparator({ Title = "Tracers" })
ESP:AddToggle({ Title = "Tracers", Default = false, Flag = "esp_tracer" })

--============================================================================--
--  Tab 3 — Settings (config + theme, built in)
--============================================================================--
Window:CreateConfigTab("Settings")

--// Autoload the last-used config on launch
Ember.SaveManager:LoadAutoload()

Window:Notify({
	Title = "Ember", Description = "Loaded", Content = "Press RightShift to toggle the UI.", Type = "Info", Delay = 6,
})
