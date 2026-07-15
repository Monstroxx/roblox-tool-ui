--[[
	Universal hub template built on the Ember UI library.

	Copy this file, change the constants below, and add your own game-specific tabs.
	The cheats here (walkspeed / inf jump / gravity / fly) live in the TEMPLATE, not in
	the library — Ember stays a UI library.

	Executor:  loadstring(game:HttpGet("<RAW_URL>/template.lua"))()
	Studio:    put src/Ember.lua into a ModuleScript named "Ember" next to this LocalScript.
]]

--============================================================================--
--  CONFIG — change these
--============================================================================--
local RAW_URL        = "https://raw.githubusercontent.com/Monstroxx/roblox-tool-ui/main"
local HUB_NAME       = "Ember"
local DISCORD_INVITE = "https://discord.gg/your-invite"

--============================================================================--
--  Load the library
--============================================================================--
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

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Player           = Players.LocalPlayer

--============================================================================--
--  Character helpers (everything must survive respawns)
--============================================================================--
local function getChar()      return Player.Character end
local function getHumanoid()  local c = getChar() return c and c:FindFirstChildOfClass("Humanoid") end
local function getRoot()      local c = getChar() return c and c:FindFirstChild("HumanoidRootPart") end

-- state that must be re-applied on respawn
local state = { walkspeed = 16, infJump = false, flying = false, flySpeed = 60 }

local function applyWalkspeed()
	local h = getHumanoid()
	if h then h.WalkSpeed = state.walkspeed end
end

--============================================================================--
--  Window
--============================================================================--
local Window = Ember:CreateWindow({
	Name      = HUB_NAME,
	Subtitle  = "v" .. Ember.Version,
	Size      = UDim2.fromOffset(560, 340),
	ToggleKey = Enum.KeyCode.RightShift,
	AntiAFK   = true,
})

--============================================================================--
--  Home
--============================================================================--
local Home = Window:CreateTab({ Name = "Home" })
local Info = Home:AddSection({ Title = "Welcome", Open = true })

Info:AddParagraph({
	Title   = HUB_NAME,
	Content = "Press RightShift to show/hide the UI. Executor: " .. tostring(Ember.Compat.Executor),
})

Info:AddButton({
	Title = "Copy Discord invite", Content = DISCORD_INVITE,
	Callback = function()
		-- Roblox can't open URLs, so copying to the clipboard is the standard route.
		local setclipboard = Ember.Compat:Get("setclipboard")
		if setclipboard then
			setclipboard(DISCORD_INVITE)
			Window:Notify({ Title = "Discord", Description = "Copied", Content = DISCORD_INVITE, Type = "Success" })
		else
			Window:Notify({
				Title = "Discord", Description = "Clipboard unavailable",
				Content = DISCORD_INVITE, Type = "Warning", Delay = 12,
			})
		end
	end,
})

--============================================================================--
--  Movement
--============================================================================--
local Move   = Window:CreateTab({ Name = "Movement" })
local Speed  = Move:AddSection({ Title = "Speed & Jump", Open = true })

Speed:AddSlider({
	Title = "Walkspeed", Content = "Default is 16",
	Min = 16, Max = 500, Increment = 1, Default = 16, Flag = "walkspeed",
	Callback = function(v) state.walkspeed = v applyWalkspeed() end,
})

Speed:AddToggle({
	Title = "Infinite jump", Content = "Jump again while airborne",
	Default = false, Flag = "infjump",
	Callback = function(v) state.infJump = v end,
})

UserInputService.JumpRequest:Connect(function()
	if not state.infJump then return end
	local h = getHumanoid()
	if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

local World = Move:AddSection({ Title = "World", Open = true })

World:AddSlider({
	Title = "Gravity", Content = "Default is 196.2",
	Min = 0, Max = 400, Increment = 1, Default = 196, Flag = "gravity",
	Callback = function(v) workspace.Gravity = v end,
})

--============================================================================--
--  Fly
--============================================================================--
local FlySec = Move:AddSection({ Title = "Fly", Open = true })

local flyVelocity, flyGyro, flyConn

local function stopFly()
	if flyConn then flyConn:Disconnect() flyConn = nil end
	if flyVelocity then flyVelocity:Destroy() flyVelocity = nil end
	if flyGyro then flyGyro:Destroy() flyGyro = nil end
	local h = getHumanoid()
	if h then h.PlatformStand = false end
end

local function startFly()
	local root, hum = getRoot(), getHumanoid()
	if not root or not hum then return end
	stopFly()

	hum.PlatformStand = true

	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.MaxForce = Vector3.new(1, 1, 1) * 9e9
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = root

	flyGyro = Instance.new("BodyGyro")
	flyGyro.MaxTorque = Vector3.new(1, 1, 1) * 9e9
	flyGyro.P = 9e4
	flyGyro.CFrame = root.CFrame
	flyGyro.Parent = root

	flyConn = RunService.RenderStepped:Connect(function()
		local r = getRoot()
		if not r or not flyVelocity or not flyGyro then return end
		local cam = workspace.CurrentCamera
		local dir = Vector3.zero

		if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end

		flyVelocity.Velocity = (dir.Magnitude > 0 and dir.Unit or Vector3.zero) * state.flySpeed
		flyGyro.CFrame = cam.CFrame
	end)
end

FlySec:AddToggle({
	Title = "Fly", Content = "WASD + Space / LeftShift",
	Default = false, Flag = "fly",
	Callback = function(v)
		state.flying = v
		if v then startFly() else stopFly() end
	end,
})

FlySec:AddSlider({
	Title = "Fly speed", Content = "Studs per second",
	Min = 10, Max = 300, Increment = 5, Default = 60, Flag = "flyspeed",
	Callback = function(v) state.flySpeed = v end,
})

--// Re-apply everything after a respawn
Player.CharacterAdded:Connect(function(char)
	char:WaitForChild("Humanoid")
	task.wait(0.25)
	applyWalkspeed()
	if state.flying then startFly() end
end)

--============================================================================--
--  Settings (config + theme + session extras + diagnostics)
--============================================================================--
Ember.AutoExecute:Configure({
	Code = ('loadstring(game:HttpGet("%s/template.lua"))()'):format(RAW_URL),
})

Window:CreateConfigTab({
	Name        = "Settings",
	AntiAFK     = true,
	AutoExecute = true,
	AutoRejoin  = true,
	Diagnostics = true,
})

--// Restore the last session and start tracking changes.
--   Must run AFTER every tab/element exists, otherwise later flags miss the restore.
if Ember.SaveManager:StartAutoSave() then
	Window:NotifyConfigLoaded("Your last settings")
else
	Window:Notify({
		Title = HUB_NAME, Description = "Loaded",
		Content = "Press RightShift to toggle the UI.", Type = "Info", Delay = 6,
	})
end
