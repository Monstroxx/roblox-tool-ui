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
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local Player           = Players.LocalPlayer

-- The exact code re-executed after teleports (auto-execute + server-hop loops)
local AUTOEXEC_CODE = ('loadstring(game:HttpGet("%s/template.lua"))()'):format(RAW_URL)

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
--  Server Hop
--============================================================================--
--[[
	Modes: "hop" (single, instant), "loop" (endless), "version" (until PlaceVersion ==
	target), "below"/"above" (until player count < / > X).

	Loop modes survive the teleport via a state file (Ember/hopstate.json) plus
	queue_on_teleport of AUTOEXEC_CODE; ServerHop.resume() picks the loop back up
	after the script re-executes on the new server.
]]
local ServerHop = {}
do
	local STATE_FILE = "Ember/hopstate.json"
	local cancelled  = false -- session-local; cross-server cancel works via clearState

	local MODE_TEXT = {
		hop     = "random server",
		loop    = "endless loop",
		version = "until place version",
		below   = "until players below X",
		above   = "until players above X",
	}

	local function saveState(state)
		local write = Ember.Compat:Get("writefile")
		if not write then return false end
		return pcall(write, STATE_FILE, HttpService:JSONEncode(state))
	end

	local function loadState()
		local isfile, read = Ember.Compat:Get("isfile"), Ember.Compat:Get("readfile")
		if not (isfile and read) then return nil end
		local ok, json = pcall(function()
			return isfile(STATE_FILE) and read(STATE_FILE) or nil
		end)
		if not ok or type(json) ~= "string" then return nil end
		local ok2, data = pcall(function() return HttpService:JSONDecode(json) end)
		if ok2 and type(data) == "table" then return data end
		return nil
	end

	local function clearState()
		local isfile, del = Ember.Compat:Get("isfile"), Ember.Compat:Get("delfile")
		if isfile and del then
			pcall(function() if isfile(STATE_FILE) then del(STATE_FILE) end end)
		end
	end

	-- One page (100) of public servers from the games API.
	local function fetchServers(sortOrder)
		local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&excludeFullGames=true&limit=100")
			:format(game.PlaceId, sortOrder)
		local ok, res = pcall(function() return game:HttpGet(url) end)
		if not ok then return nil, "servers request failed: " .. tostring(res) end
		local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
		if not ok2 or type(data) ~= "table" or type(data.data) ~= "table" then
			return nil, "unexpected servers response"
		end
		return data.data
	end

	-- Random joinable server matching the mode ("below"/"above" filter by player count).
	local function pickServer(mode, x)
		-- Asc = emptiest first, so the below-filter sees usable candidates on page 1.
		local servers, err = fetchServers(mode == "below" and "Asc" or "Desc")
		if not servers then return nil, err end
		local candidates = {}
		for _, s in ipairs(servers) do
			if type(s) == "table" and s.id and s.id ~= game.JobId
				and type(s.playing) == "number" and type(s.maxPlayers) == "number"
				and s.playing < s.maxPlayers then
				local matches = true
				if mode == "below" then matches = s.playing < x
				elseif mode == "above" then matches = s.playing > x end
				if matches then table.insert(candidates, s) end
			end
		end
		if #candidates == 0 then return nil, "no matching server found" end
		return candidates[math.random(#candidates)]
	end

	function ServerHop.cancel()
		cancelled = true
		clearState()
		-- Our hop queue and auto-execute share AUTOEXEC_CODE; re-queue in case that
		-- feature is enabled (no-op otherwise).
		Ember.AutoExecute:_queue()
		Window:Notify({ Title = "Server hop", Description = "Cancelled", Type = "Warning" })
	end

	-- Find a server and teleport; retries with cooldown until cancelled.
	local function hopNext(state)
		task.spawn(function()
			while not cancelled do
				local server, err = pickServer(state.mode, state.x)
				if cancelled then return end
				if server then
					if state.mode ~= "hop" then
						saveState(state)
						local queue = Ember.Compat:Get("queue_on_teleport")
						if queue then pcall(queue, AUTOEXEC_CODE) end
					end
					local ok = pcall(function()
						TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, Player)
					end)
					if ok then return end -- teleport is underway
					err = "teleport failed"
				end
				Window:Notify({
					Title = "Server hop", Description = "Retrying",
					Content = ("%s — next try in %ds"):format(tostring(err), state.cooldown),
					Type = "Warning", Delay = state.cooldown,
					Buttons = { { Text = "Cancel", Callback = ServerHop.cancel } },
				})
				task.wait(state.cooldown)
			end
		end)
	end

	-- state = { mode, x?, target?, cooldown }
	function ServerHop.start(state)
		if state.mode ~= "hop" then
			if not Ember.Compat:FSOk() then
				Window:Notify({ Title = "Server hop", Description = "Unavailable",
					Content = "Loop modes need a working filesystem API.", Type = "Warning" })
				return
			end
			if not Ember.Compat:Get("queue_on_teleport") then
				Window:Notify({ Title = "Server hop", Description = "Unavailable",
					Content = "Loop modes need queue_on_teleport.", Type = "Warning" })
				return
			end
		end
		cancelled = false
		Window:Notify({
			Title = "Server hop", Description = "Starting",
			Content = "Mode: " .. (MODE_TEXT[state.mode] or state.mode),
			Type = "Info", Delay = 8,
			Buttons = { { Text = "Cancel", Callback = ServerHop.cancel } },
		})
		hopNext(state)
	end

	-- Called once on startup (after flags are restored): continue or finish a loop.
	function ServerHop.resume()
		local state = loadState()
		if not state or not MODE_TEXT[tostring(state.mode)] then return end
		state.cooldown = tonumber(state.cooldown) or 5
		state.x        = tonumber(state.x) or 0

		task.spawn(function()
			local done, doneText = false, ""
			if state.mode == "version" then
				done = (game.PlaceVersion == tonumber(state.target))
				doneText = "Landed on place version " .. tostring(game.PlaceVersion)
			elseif state.mode == "below" or state.mode == "above" then
				task.wait(3) -- let players stream in before counting
				-- Exclude ourselves: the API's `playing` count (used to pick the server)
				-- was taken before we joined, so verify against the same measure.
				local count = #Players:GetPlayers() - 1
				done = (state.mode == "below" and count < state.x)
					or (state.mode == "above" and count > state.x)
				doneText = ("Server has %d other players"):format(count)
			end
			-- mode "loop" is never done; it hops until cancelled

			if done then
				clearState()
				Ember.AutoExecute:_queue()
				Window:Notify({
					Title = "Server hop", Description = "Finished",
					Content = doneText, Type = "Success", Delay = 10,
				})
				return
			end

			Window:Notify({
				Title = "Server hop", Description = "Continuing",
				Content = ("Mode: %s — next hop in %ds"):format(MODE_TEXT[state.mode], state.cooldown),
				Type = "Info", Delay = state.cooldown,
				Buttons = { { Text = "Cancel", Callback = ServerHop.cancel } },
			})
			task.wait(state.cooldown)
			if not cancelled then hopNext(state) end
		end)
	end
end

local Server  = Window:CreateTab({ Name = "Server" })
local HopSec  = Server:AddSection({ Title = "Server Hop", Open = true })

HopSec:AddParagraph({
	Title   = "This server",
	Content = ("Place version %d — %d players"):format(game.PlaceVersion, #Players:GetPlayers()),
})

local hopCooldown = HopSec:AddSlider({
	Title = "Cooldown", Content = "Seconds between hops (loop modes)",
	Min = 3, Max = 60, Increment = 1, Default = 5, Flag = "hop_cooldown",
})

HopSec:AddButton({
	Title = "Hop server", Content = "Teleport to a random other server",
	Callback = function()
		ServerHop.start({ mode = "hop", cooldown = hopCooldown.Value })
	end,
})

HopSec:AddButton({
	Title = "Hop loop (endless)", Content = "Keep hopping after every join until cancelled",
	Callback = function()
		ServerHop.start({ mode = "loop", cooldown = hopCooldown.Value })
	end,
})

local hopVersion = HopSec:AddInput({
	Title = "Target version", Content = "Place version to hunt for",
	Placeholder = tostring(game.PlaceVersion), Default = "", Flag = "hop_version",
})

HopSec:AddButton({
	Title = "Hop until version", Content = "Hop until the server runs the target version",
	Callback = function()
		local target = tonumber(hopVersion.Value)
		if not target then
			Window:Notify({ Title = "Server hop", Description = "Invalid version",
				Content = "Enter a numeric place version first.", Type = "Warning" })
			return
		end
		if target == game.PlaceVersion then
			Window:Notify({ Title = "Server hop", Description = "Already there",
				Content = "This server already runs version " .. tostring(target), Type = "Success" })
			return
		end
		ServerHop.start({ mode = "version", target = target, cooldown = hopCooldown.Value })
	end,
})

local hopPlayers = HopSec:AddSlider({
	Title = "Player threshold X", Content = "For the player-count modes below",
	Min = 1, Max = 100, Increment = 1, Default = 5, Flag = "hop_players",
})

HopSec:AddButton({
	Title = "Hop until players < X", Content = "Find a server with fewer than X players",
	Callback = function()
		ServerHop.start({ mode = "below", x = hopPlayers.Value, cooldown = hopCooldown.Value })
	end,
})

HopSec:AddButton({
	Title = "Hop until players > X", Content = "Find a server with more than X players",
	Callback = function()
		ServerHop.start({ mode = "above", x = hopPlayers.Value, cooldown = hopCooldown.Value })
	end,
})

HopSec:AddButton({
	Title = "Stop hopping", Content = "Cancel any running hop loop",
	Callback = ServerHop.cancel,
})

local NavSec = Server:AddSection({ Title = "Teleport", Open = true })

NavSec:AddButton({
	Title = "Rejoin server", Content = "Reconnect to this exact server",
	Callback = function()
		Window:Notify({
			Title = "Teleport", Description = "Rejoining",
			Content = "Reconnecting...", Type = "Info",
		})
		local ok, err = pcall(function()
			-- JobId is empty in solo/reserved servers; plain Teleport still rejoins the place.
			if game.JobId == "" then
				TeleportService:Teleport(game.PlaceId, Player)
			else
				TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Player)
			end
		end)
		if not ok then
			Window:Notify({ Title = "Teleport", Description = "Error", Content = tostring(err), Type = "Error" })
		end
	end,
})

local joinPlaceInput = NavSec:AddInput({
	Title = "Place ID", Content = "Target place to join",
	Placeholder = tostring(game.PlaceId), Default = "", Flag = "join_placeid",
})

NavSec:AddButton({
	Title = "Join place", Content = "Teleport to the entered place ID",
	Callback = function()
		local id = tonumber(joinPlaceInput.Value)
		if not id then
			Window:Notify({
				Title = "Teleport", Description = "Invalid place ID",
				Content = "Enter a numeric place ID first.", Type = "Warning",
			})
			return
		end
		Window:Notify({
			Title = "Teleport", Description = "Joining",
			Content = "Place " .. tostring(id), Type = "Info",
		})
		local ok, err = pcall(function()
			TeleportService:Teleport(id, Player)
		end)
		if not ok then
			Window:Notify({ Title = "Teleport", Description = "Error", Content = tostring(err), Type = "Error" })
		end
	end,
})

--============================================================================--
--  Settings (config + theme + session extras + diagnostics)
--============================================================================--
Ember.AutoExecute:Configure({ Code = AUTOEXEC_CODE })

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

--// Continue (or finish) a server-hop loop that carried over from the previous server.
ServerHop.resume()
