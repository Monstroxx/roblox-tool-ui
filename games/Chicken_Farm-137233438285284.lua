--[[
	Chicken Farm (137233438285284) — hub built on the Ember UI library.

	Based on template.lua: Home / Movement / Fly / Server hop / Settings come from there,
	the Farm tab below is the game-specific part. Game cheats live HERE, not in the library.

	Executor:  loadstring(game:HttpGet("<RAW_URL>/games/Chicken_Farm-137233438285284.lua"))()
	Studio:    put src/Ember.lua into a ModuleScript named "Ember" next to this LocalScript.
]]

--============================================================================--
--  CONFIG — change these
--============================================================================--
local RAW_URL        = "https://raw.githubusercontent.com/Monstroxx/roblox-tool-ui/main"
local HUB_NAME       = "Chicken Farm"
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

-- The exact code re-executed after teleports (auto-execute + server-hop loops).
-- Points at this script, not template.lua, so a hop lands back in the farm hub.
local AUTOEXEC_CODE = ('loadstring(game:HttpGet("%s/games/Chicken_Farm-137233438285284.lua"))()'):format(RAW_URL)

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
local Home = Window:CreateTab({ Name = "Home", Icon = Ember.Icons.Home })
local Info = Home:AddSection({ Title = "Welcome", Open = true })

Info:AddParagraph({
	Title   = HUB_NAME,
	Content = "Automation for Chicken Farm. Press RightShift to show/hide the UI. Executor: "
		.. tostring(Ember.Compat.Executor),
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
local Move   = Window:CreateTab({ Name = "Movement", Icon = Ember.Icons.Move })
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
--  Farm — game logic for Chicken Farm
--============================================================================--
--[[
	Everything below drives the live plot buttons and the HUD.

	The UI callbacks only WRITE to `Farm`; they never start threads. Ember fires a
	toggle's callback once at construction and again for every flag the SaveManager
	restores, so spawning work from a callback would duplicate it on every config load.
	A single driver loop at the bottom reads `Farm` instead.
]]
local Farm = {
	CollectEggs   = false,
	CollectMoney  = false,
	SellEggs      = false,
	SellMultMin   = 0.5,
	SellMultMax   = 3.0,
	BuyChicken    = false,
	CashReserve   = 1000,
	Merge         = false,
	UpgradeTier   = false,
}

-- sUNC: firetouchinterest(part1, part2, toggle) — 0 begins the touch, 1 ends it.
-- Resolved once; nil on executors without it, and the tapPart fallback takes over.
local fireTouch = Ember.Compat:Get("firetouchinterest")

local ActionCooldowns = {}

-- The HUD mixes two formats, both verified in-game: suffixed ("$102.83M", "4.3B") for
-- large values and plain grouped digits ("$77,231", "31,885") for small ones. Stripping
-- non-digits would read "$102.83M" as 10283, so the suffix has to be applied.
local SUFFIX = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, Q = 1e15 }

local function parseCurrency(text)
	text = tostring(text or ""):gsub(",", ""):gsub("%s", "")
	local num, suffix = text:match("([%d%.]+)%s*([KMBTQkmbtq]?)")
	local n = tonumber(num or "")
	if not n then
		return 0
	end
	if suffix ~= "" then
		n = n * (SUFFIX[suffix:upper()] or 1)
	end
	return math.floor(n)
end

local function formatCurrency(amount)
	amount = tonumber(amount) or 0
	if amount >= 1000000000 then
		return string.format("%.1fB", amount / 1000000000)
	elseif amount >= 1000000 then
		return string.format("%.1fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("%.1fK", amount / 1000)
	else
		return tostring(amount)
	end
end

local function getPlot()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	return plots:FindFirstChild(Player.Name)
end

local function getPlayerGuiMain()
	return Player:FindFirstChild("PlayerGui") and Player.PlayerGui:FindFirstChild("Main")
end

local function getValueText(path)
	local node = getPlayerGuiMain()
	if not node then
		return ""
	end

	for _, segment in ipairs(path) do
		node = node:FindFirstChild(segment)
		if not node then
			return ""
		end
	end

	if node:IsA("TextLabel") or node:IsA("TextButton") then
		return node.Text
	end

	return ""
end

local function getEggCount()
	return parseCurrency(getValueText({ "Eggs", "Amount", "Amt" }))
end

local function getCashAmount()
	return parseCurrency(getValueText({ "Currencies", "Cash", "List", "Amount" }))
end

-- Egg Frenzy (x271) exposes itself as a HUD indicator.
local function isEggFrenzyActive()
	local main = getPlayerGuiMain()
	if not main then return false end
	local events = main:FindFirstChild("Events")
	if not events then return false end
	local eggFrenzy = events:FindFirstChild("EggFrenzy")
	return (eggFrenzy and eggFrenzy.Visible) and true or false
end

-- The egg multiplier (0.5x - 3.0x) has no HUD label anywhere; it is only announced every
-- ~30s via a short-lived notification. Verified in-game — the exact wording is
-- "Egg Multiplier rose to 1.5x!" / "Egg Multiplier dropped to 1.45x!" in a Holder child
-- named "Notification". So cache the last announced value.
--
-- nil = not announced yet. Deliberately not defaulted to 1: a made-up value sits inside
-- the default range and would sell at an unknown real multiplier for the first ~30s.
local CachedEggMultiplier = nil

local function parseEggMultiplierText(text)
	local value = text:match("to%s+([%d%.]+)x")
	if value then
		return tonumber(value)
	end
	return nil
end

local function readMultiplierFrom(notification)
	for _, d in ipairs(notification:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text ~= "" then
			local val = parseEggMultiplierText(d.Text)
			if val then
				CachedEggMultiplier = val
			end
		end
	end
end

local function setupEggMultiplierListener()
	local playerGui = Player:FindFirstChild("PlayerGui")
	if not playerGui then return end

	local notifications = playerGui:FindFirstChild("Notifications")
		or playerGui:WaitForChild("Notifications", 10)
	if not notifications then return end

	local holder = notifications:FindFirstChild("Holder") or notifications:WaitForChild("Holder", 5)
	if not holder then return end

	-- A notification may already be on screen when we load.
	for _, child in ipairs(holder:GetChildren()) do
		if child.Name == "Notification" then
			readMultiplierFrom(child)
		end
	end

	holder.ChildAdded:Connect(function(child)
		if child.Name ~= "Notification" then return end
		task.spawn(function()
			task.wait(0.15) -- wait for the label to be filled in
			readMultiplierFrom(child)
		end)
	end)
end

local function getEggMultiplier()
	return CachedEggMultiplier
end

local function getCharacterRoot()
	local character = getChar()
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil, nil
	end
	return character, root
end

-- Physically move onto a part, dwell, then return. Needed wherever the game only reacts
-- to a real body, and as the fallback when firetouchinterest is unavailable.
local function standOnPart(part, dwell)
	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	local restore = root.CFrame
	local ok = pcall(function()
		character:PivotTo(part.CFrame * CFrame.new(0, 3, 0))
	end)
	if not ok then
		return false
	end

	task.wait(dwell or 0.3)

	pcall(function()
		local _, back = getCharacterRoot() -- may be a new character after a respawn
		if back then back.CFrame = restore end
	end)
	return true
end

-- Fire a touch on a part that carries a TouchInterest. Verified in-game: eggs and the
-- four plot buttons all trigger from ~30 studs away, with no need to move.
-- The gap between begin and end matters — both in one frame is not registered.
local function tapPart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	local _, root = getCharacterRoot()
	if not root then
		return false
	end

	if fireTouch then
		local ok = pcall(function()
			fireTouch(root, part, 0)
			task.wait(0.02)
			fireTouch(root, part, 1)
		end)
		return ok
	end

	return standOnPart(part, 0.12)
end

-- Plot buttons wrap their touch part inconsistently; try the known names, then any part.
local function findButtonPart(node)
	for _, name in ipairs({ "Button", "Hitbox", "Part" }) do
		local part = node:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	for _, child in ipairs(node:GetDescendants()) do
		if child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

-- Press plot.Buttons.<name> — for the buttons that carry a TouchInterest.
-- The buy pads do not; see buyChicken.
local function pressPlotButton(name)
	local plot = getPlot()
	if not plot then
		return false
	end

	local node = plot:FindFirstChild("Buttons")
	node = node and node:FindFirstChild(name)
	if not node then
		return false
	end

	local part = findButtonPart(node)
	if not part then
		return false
	end

	return tapPart(part)
end

local function collectEggs()
	local eggsFolder = workspace:FindFirstChild("Eggs")
	if not eggsFolder then
		return false
	end

	local collected = false
	for _, egg in ipairs(eggsFolder:GetChildren()) do
		local eggPart = egg:FindFirstChild("Part", true)
		if eggPart and eggPart:IsA("BasePart") and tapPart(eggPart) then
			collected = true
		end
	end

	return collected
end

local function collectMoney()  return pressPlotButton("CollectMoney") end
local function sellEggs()      return pressPlotButton("DepositEggs") end
local function mergeChickens() return pressPlotButton("MergeChickens") end
local function upgradeTier()   return pressPlotButton("UpgradeBuyTier") end

-- Buy1 is the cheapest of the buy buttons. Unlike every other button it carries NO
-- TouchInterest (verified in-game), so firetouchinterest does nothing here — the pad only
-- reacts to a real body standing on it, which is why this one teleports. Standing there
-- buys repeatedly, so dwell briefly and let the next cycle re-check the reserve.
local function buyChicken()
	if getCashAmount() <= Farm.CashReserve then
		return false
	end

	local plot = getPlot()
	local node = plot and plot:FindFirstChild("Buttons")
	node = node and node:FindFirstChild("BuyChickens")
	node = node and node:FindFirstChild("Buy1")
	local part = node and node:FindFirstChild("Button")
	if not part or not part:IsA("BasePart") then
		return false
	end

	return standOnPart(part, 0.3)
end

-- Sell only when the multiplier is known AND inside the range. Until the first
-- announcement arrives the multiplier is nil, and we hold rather than guess.
local function shouldSellEggs()
	local multiplier = getEggMultiplier()
	if not multiplier then
		return false
	end
	return multiplier >= Farm.SellMultMin and multiplier <= Farm.SellMultMax
end

local function runWithCooldown(key, cooldownSeconds, handler)
	local now = os.clock()
	local last = ActionCooldowns[key]
	if last and now - last < cooldownSeconds then
		return false
	end

	local ok, result = pcall(handler)
	if ok and result then
		ActionCooldowns[key] = now
		return true
	end

	return false
end

--// Farm tab
local FarmTab = Window:CreateTab({ Name = "Farm", Icon = Ember.Icons.Package })

local Collect = FarmTab:AddSection({ Title = "Collect", Open = true })

Collect:AddToggle({
	Title = "Auto-collect eggs", Content = "Touch every egg in the workspace",
	Default = false, Flag = "cf_eggs",
	Callback = function(v) Farm.CollectEggs = v end,
})

Collect:AddToggle({
	Title = "Auto-collect money", Content = "Press the CollectMoney button",
	Default = false, Flag = "cf_money",
	Callback = function(v) Farm.CollectMoney = v end,
})

local Sell = FarmTab:AddSection({ Title = "Sell", Open = true })

Sell:AddToggle({
	Title = "Auto-sell eggs", Content = "Deposit eggs when the multiplier fits",
	Default = false, Flag = "cf_sell",
	Callback = function(v) Farm.SellEggs = v end,
})

Sell:AddSlider({
	Title = "Multiplier range", Content = "Holds until the multiplier is announced and in range",
	Range = true, Min = 0.5, Max = 3, Increment = 0.05, Default = { 0.5, 3 }, Flag = "cf_mult",
	Callback = function(v)
		Farm.SellMultMin, Farm.SellMultMax = v[1], v[2]
	end,
})

local Chickens = FarmTab:AddSection({ Title = "Chickens", Open = true })

Chickens:AddToggle({
	Title = "Auto-buy chicken", Content = "Buy while cash stays above the reserve",
	Default = false, Flag = "cf_buy",
	Callback = function(v) Farm.BuyChicken = v end,
})

Chickens:AddInput({
	Title = "Cash reserve", Content = "Never spend below this amount",
	Numeric = true, Min = 0, Default = 1000, Placeholder = "1000", Flag = "cf_reserve",
	Callback = function(v) Farm.CashReserve = v end,
})

Chickens:AddToggle({
	Title = "Auto-merge", Content = "Press the MergeChickens button",
	Default = false, Flag = "cf_merge",
	Callback = function(v) Farm.Merge = v end,
})

Chickens:AddToggle({
	Title = "Auto-upgrade tier", Content = "Press the UpgradeBuyTier button",
	Default = false, Flag = "cf_tier",
	Callback = function(v) Farm.UpgradeTier = v end,
})

local StatusSec = FarmTab:AddSection({ Title = "Status", Open = true })
local StatusText = StatusSec:AddParagraph({
	Title   = "Idle",
	Content = "Enable an automation above to get started.",
})

--// Driver loop — the single owner of all automation.
task.spawn(function()
	local ACTIONS = {
		{ key = "CollectEggs",  cooldown = 1.5, run = collectEggs },
		{ key = "CollectMoney", cooldown = 1.5, run = collectMoney },
		{ key = "SellEggs",     cooldown = 1.0, run = sellEggs, guard = shouldSellEggs },
		{ key = "BuyChicken",   cooldown = 0.8, run = buyChicken },
		{ key = "Merge",        cooldown = 1.0, run = mergeChickens },
		{ key = "UpgradeTier",  cooldown = 2.0, run = upgradeTier },
	}

	local lastStatus = 0

	while task.wait(0.35) do
		local active = 0
		for _, action in ipairs(ACTIONS) do
			if Farm[action.key] then
				active += 1
				if not action.guard or action.guard() then
					runWithCooldown(action.key, action.cooldown, action.run)
				end
			end
		end

		-- The readout only needs to be human-readable, not per-frame.
		if os.clock() - lastStatus >= 1 then
			lastStatus = os.clock()
			local mult = getEggMultiplier()
			StatusText:Set({
				Title = active > 0 and ("%d automation(s) running"):format(active) or "Idle",
				Content = ("Cash: %s  |  Eggs: %s  |  Multiplier: %s%s"):format(
					formatCurrency(getCashAmount()),
					formatCurrency(getEggCount()),
					mult and ("x" .. tostring(mult)) or "waiting for announcement",
					isEggFrenzyActive() and "  |  Egg Frenzy!" or ""
				),
			})
		end
	end
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

local Server  = Window:CreateTab({ Name = "Server", Icon = Ember.Icons.Server })
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

--// Listen for the multiplier notifications. Spawned: it waits on the game's GUI and
--   must not delay the config restore below.
task.spawn(setupEggMultiplierListener)

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
