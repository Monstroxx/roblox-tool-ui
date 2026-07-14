--[[
	Ember UI Library
	A clean, single-file UI library for Roblox tools.

	Usage:
		local Ember = loadstring(game:HttpGet("<raw-url>/src/Ember.lua"))()
		local Window = Ember:CreateWindow({ Name = "Ember", Subtitle = "v1.0" })
		local Tab = Window:CreateTab({ Name = "Main" })
		local Sec = Tab:AddSection({ Title = "Movement", Open = true })
		Sec:AddButton({ Title = "Click me", Callback = function() print("hi") end })

	Reference/architecture: see /home/kimox/.claude/plans/ich-m-chte-eine-eigene-memoized-quilt.md
]]

--// Services
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local HttpService        = game:GetService("HttpService")
local VirtualUser        = game:GetService("VirtualUser")

local Player = Players.LocalPlayer

--// Library table
local Ember = {}
Ember.Version = "1.0.0"
Ember.Flags   = {}       -- [flagName] = elementObject (must expose .Value and :Set)
Ember.Windows = {}

--============================================================================--
--  THEME
--============================================================================--

local COLOR_KEYS = {
	"Accent", "AccentHover", "Background", "Surface", "Elevated",
	"Stroke", "Text", "Muted", "Success", "Warning", "Error",
}

local Themes = {
	Ember = {
		Name        = "Ember",
		Accent      = Color3.fromRGB(255, 106, 26),
		AccentHover = Color3.fromRGB(255, 138, 61),
		Background  = Color3.fromRGB(11, 11, 13),
		Surface     = Color3.fromRGB(20, 20, 24),
		Elevated    = Color3.fromRGB(28, 28, 34),
		Stroke      = Color3.fromRGB(42, 42, 49),
		Text        = Color3.fromRGB(244, 244, 246),
		Muted       = Color3.fromRGB(139, 139, 149),
		Success     = Color3.fromRGB(61, 214, 140),
		Warning     = Color3.fromRGB(255, 176, 32),
		Error       = Color3.fromRGB(255, 77, 77),
		Font        = Enum.Font.GothamBold,
		LogoId      = "",
	},
	Molten = {
		Name        = "Molten",
		Accent      = Color3.fromRGB(255, 90, 44),
		AccentHover = Color3.fromRGB(255, 45, 111),
		Background  = Color3.fromRGB(10, 10, 12),
		Surface     = Color3.fromRGB(19, 19, 23),
		Elevated    = Color3.fromRGB(27, 27, 33),
		Stroke      = Color3.fromRGB(45, 40, 46),
		Text        = Color3.fromRGB(245, 243, 242),
		Muted       = Color3.fromRGB(138, 134, 144),
		Success     = Color3.fromRGB(61, 214, 140),
		Warning     = Color3.fromRGB(255, 176, 32),
		Error       = Color3.fromRGB(255, 77, 77),
		Font        = Enum.Font.GothamBold,
		LogoId      = "",
	},
	Solstice = {
		Name        = "Solstice",
		Accent      = Color3.fromRGB(255, 163, 26),
		AccentHover = Color3.fromRGB(124, 77, 255),
		Background  = Color3.fromRGB(12, 11, 16),
		Surface     = Color3.fromRGB(22, 20, 28),
		Elevated    = Color3.fromRGB(30, 28, 38),
		Stroke      = Color3.fromRGB(48, 44, 60),
		Text        = Color3.fromRGB(243, 242, 247),
		Muted       = Color3.fromRGB(133, 127, 150),
		Success     = Color3.fromRGB(61, 214, 140),
		Warning     = Color3.fromRGB(255, 176, 32),
		Error       = Color3.fromRGB(255, 77, 77),
		Font        = Enum.Font.GothamBold,
		LogoId      = "",
	},
}

-- Active theme (identity is stable; SetTheme mutates fields in place)
local Theme = {}
for k, v in pairs(Themes.Ember) do Theme[k] = v end

Ember.Theme  = Theme
Ember.Themes = Themes

-- Theme registry: entries {inst, prop, key, transform}
local ThemeRegistry = {}

local function applyThemeEntry(entry)
	local value = Theme[entry.key]
	if value == nil then return end
	if entry.transform then value = entry.transform(value) end
	entry.inst[entry.prop] = value
end

-- Register + immediately apply a themed property
local function Themed(inst, prop, key, transform)
	local entry = { inst = inst, prop = prop, key = key, transform = transform }
	table.insert(ThemeRegistry, entry)
	pcall(applyThemeEntry, entry)
	return inst
end

--============================================================================--
--  ASSETS (swap freely)
--============================================================================--

local ASSETS = {
	Ripple   = "rbxassetid://106471194043211",
	Chevron  = "rbxassetid://125609963478878", -- rotated arrow
	TabIcon  = "rbxassetid://7734053426",
	Close    = "rbxassetid://7743878857",
}

--============================================================================--
--  UTILITIES
--============================================================================--

local function Create(className, props)
	local inst = Instance.new(className)
	local parent
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if parent then inst.Parent = parent end
	return inst
end

local function Corner(radius, parent)
	return Create("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

local function Stroke(parent, colorKey, thickness, transparency)
	local s = Create("UIStroke", {
		Thickness    = thickness or 1,
		Transparency = transparency or 0,
		Parent       = parent,
	})
	Themed(s, "Color", colorKey or "Stroke")
	return s
end

local function Tween(inst, time, goal, style, dir)
	local info = TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

-- Run a user callback safely (never crash the UI)
local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(fn, table.unpack(args, 1, args.n))
		if not ok then
			warn("[Ember] callback error: " .. tostring(err))
		end
	end)
end

-- Where to parent the ScreenGui (executor-safe with Studio fallback)
local function GetGuiParent()
	if RunService:IsStudio() then
		return Player:WaitForChild("PlayerGui")
	end
	local ok, hui = pcall(function() return gethui() end)
	if ok and hui then return hui end
	local ok2, cg = pcall(function() return cloneref(game:GetService("CoreGui")) end)
	if ok2 and cg then return cg end
	return game:GetService("CoreGui")
end

-- Material-style ripple.
-- IMPORTANT: AutomaticSize measures the whole descendant subtree (clipping does NOT
-- exclude it), so a growing ripple inside a card would inflate it. We overlay the ripple
-- on a fixed-size `layer` frame (the window's EffectLayer) and position it RELATIVE to
-- that layer — outside any AutomaticSize subtree, and inset-independent (unlike parenting
-- to the ScreenGui with raw screen coords).
local function Ripple(button, x, y, layer)
	task.spawn(function()
		local parent, origin
		if layer then
			parent = layer
			origin = layer.AbsolutePosition
		else
			parent = button:FindFirstAncestorWhichIsA("ScreenGui")
			if not parent then return end
			origin = Vector2.new(0, 0)
		end
		local absPos, absSize = button.AbsolutePosition, button.AbsoluteSize
		local holder = Create("Frame", {
			Name                 = "RippleHolder",
			BackgroundTransparency = 1,
			ClipsDescendants     = true,
			Position             = UDim2.fromOffset(absPos.X - origin.X, absPos.Y - origin.Y),
			Size                 = UDim2.fromOffset(absSize.X, absSize.Y),
			ZIndex               = 40,
			Parent               = parent,
		})
		Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = holder })
		local circle = Create("ImageLabel", {
			Name                 = "Ripple",
			Image                = ASSETS.Ripple,
			ImageColor3          = Color3.fromRGB(255, 255, 255),
			ImageTransparency    = 0.86,
			BackgroundTransparency = 1,
			ZIndex               = 40,
			Size                 = UDim2.fromOffset(0, 0),
			Position             = UDim2.fromOffset(x - absPos.X, y - absPos.Y),
			Parent               = holder,
		})
		local size = math.max(absSize.X, absSize.Y) * 1.6
		Tween(circle, 0.5, {
			Size              = UDim2.fromOffset(size, size),
			Position          = UDim2.new(0.5, -size / 2, 0.5, -size / 2),
			ImageTransparency = 1,
		})
		task.wait(0.5)
		holder:Destroy()
	end)
end

-- Draggable (connections registered on maid)
local function MakeDraggable(handle, target, maid)
	local dragging, dragStart, startPos = false, nil, nil
	maid:Give(handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging  = true
			dragStart = input.Position
			startPos  = target.Position
			local conn
			conn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					conn:Disconnect()
				end
			end)
		end
	end))
	maid:Give(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end))
end

--============================================================================--
--  MAID (connection / instance cleanup)
--============================================================================--

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give(task_)
	table.insert(self._tasks, task_)
	return task_
end

function Maid:Clean()
	for _, t in ipairs(self._tasks) do
		local ty = typeof(t)
		if ty == "RBXScriptConnection" then
			t:Disconnect()
		elseif ty == "Instance" then
			t:Destroy()
		elseif ty == "function" then
			pcall(t)
		elseif ty == "table" and type(t.Clean) == "function" then
			t:Clean()
		end
	end
	table.clear(self._tasks)
end
Maid.Destroy = Maid.Clean

--============================================================================--
--  CONFIG / SAVE MANAGER
--============================================================================--

-- Grab native executor globals directly (undefined identifiers are nil, not errors).
-- Wrapped in pcall in case any is a protected global.
local NATIVE = {}
pcall(function()
	NATIVE.writefile    = writefile
	NATIVE.readfile     = readfile
	NATIVE.isfile       = isfile
	NATIVE.delfile      = delfile
	NATIVE.isfolder     = isfolder
	NATIVE.makefolder   = makefolder
	NATIVE.listfiles    = listfiles
	NATIVE.setclipboard = setclipboard
end)
-- Also merge from getgenv() if available (some executors expose them only there)
pcall(function()
	if type(getgenv) == "function" then
		local g = getgenv()
		for _, name in ipairs({ "writefile", "readfile", "isfile", "delfile", "isfolder", "makefolder", "listfiles", "setclipboard" }) do
			if type(g[name]) == "function" and NATIVE[name] == nil then NATIVE[name] = g[name] end
		end
	end
end)

-- Resolve file-system functions (nil in Studio -> in-memory fallback)
local fs = {
	write      = NATIVE.writefile,
	read       = NATIVE.readfile,
	isfile     = NATIVE.isfile,
	delfile    = NATIVE.delfile,
	isfolder   = NATIVE.isfolder,
	makefolder = NATIVE.makefolder,
	listfiles  = NATIVE.listfiles,
}
local hasFS = type(fs.write) == "function" and type(fs.read) == "function" and type(fs.isfile) == "function"
local hasClipboard = type(NATIVE.setclipboard) == "function" and NATIVE.setclipboard or nil

local SaveManager = {}
SaveManager.Folder  = "Ember"
SaveManager._memory = {}   -- name -> json (Studio / no-FS fallback)

local function ensureFolders()
	if not hasFS or not fs.makefolder then return end
	for _, p in ipairs({ SaveManager.Folder, SaveManager.Folder .. "/configs", SaveManager.Folder .. "/themes" }) do
		pcall(function()
			if not (fs.isfolder and fs.isfolder(p)) then fs.makefolder(p) end
		end)
	end
end

-- JSON-safe encoding of element values (handles EnumItem for keybinds)
local function encodeValue(v)
	if typeof(v) == "EnumItem" then
		return { __enum = tostring(v.EnumType), name = v.Name }
	end
	return v
end

local function decodeValue(v)
	if type(v) == "table" and v.__enum then
		local enumName = tostring(v.__enum):gsub("^Enum%.", "")
		local ok, item = pcall(function() return Enum[enumName][v.name] end)
		if ok then return item end
		return nil
	end
	return v
end

function SaveManager:Save(name)
	if not name or name == "" then return false, "invalid name" end
	local data = {}
	for flag, element in pairs(Ember.Flags) do
		data[flag] = encodeValue(element.Value)
	end
	local json = HttpService:JSONEncode(data)
	if hasFS then
		ensureFolders()
		local ok, err = pcall(fs.write, self.Folder .. "/configs/" .. name .. ".json", json)
		if not ok then return false, err end
	else
		self._memory[name] = json
	end
	return true
end

function SaveManager:Load(name)
	if not name or name == "" then return false, "invalid name" end
	local json
	if hasFS then
		local path = self.Folder .. "/configs/" .. name .. ".json"
		if not (fs.isfile and fs.isfile(path)) then return false, "not found" end
		local ok, res = pcall(fs.read, path)
		if not ok then return false, res end
		json = res
	else
		json = self._memory[name]
		if not json then return false, "not found" end
	end
	local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
	if not ok then return false, "decode error" end
	for flag, value in pairs(data) do
		local element = Ember.Flags[flag]
		if element and type(element.Set) == "function" then
			pcall(function() element:Set(decodeValue(value)) end)
		end
	end
	return true
end

function SaveManager:Delete(name)
	if hasFS then
		local path = self.Folder .. "/configs/" .. name .. ".json"
		if fs.isfile and fs.isfile(path) and fs.delfile then
			pcall(fs.delfile, path)
			return true
		end
		return false, "not found"
	else
		if self._memory[name] then self._memory[name] = nil return true end
		return false, "not found"
	end
end

function SaveManager:List()
	local names = {}
	if hasFS and fs.listfiles then
		local ok, files = pcall(fs.listfiles, self.Folder .. "/configs")
		if ok and files then
			for _, f in ipairs(files) do
				local n = tostring(f):match("([^/\\]+)%.json$")
				if n and n ~= "autoload" then table.insert(names, n) end
			end
		end
	else
		for n in pairs(self._memory) do table.insert(names, n) end
	end
	table.sort(names)
	return names
end

function SaveManager:SetAutoload(name)
	if hasFS then
		ensureFolders()
		pcall(fs.write, self.Folder .. "/configs/autoload.txt", tostring(name))
	else
		self._memory.__autoload = name
	end
end

function SaveManager:GetAutoload()
	if hasFS then
		local path = self.Folder .. "/configs/autoload.txt"
		if fs.isfile and fs.isfile(path) then
			local ok, res = pcall(fs.read, path)
			if ok then return res end
		end
		return nil
	else
		return self._memory.__autoload
	end
end

function SaveManager:LoadAutoload()
	local name = self:GetAutoload()
	if name and name ~= "" then return self:Load(name) end
	return false, "no autoload"
end

Ember.SaveManager = SaveManager

--============================================================================--
--  THEME serialization + SetTheme
--============================================================================--

local function serializeTheme(t)
	local out = { Name = t.Name, LogoId = t.LogoId or "" }
	out.Font = (typeof(t.Font) == "EnumItem") and t.Font.Name or "GothamBold"
	for _, k in ipairs(COLOR_KEYS) do
		local c = t[k]
		if typeof(c) == "Color3" then
			out[k] = {
				math.floor(c.R * 255 + 0.5),
				math.floor(c.G * 255 + 0.5),
				math.floor(c.B * 255 + 0.5),
			}
		end
	end
	return out
end

local function deserializeTheme(data)
	local out = { Name = data.Name, LogoId = data.LogoId or "" }
	if data.Font then
		local ok, f = pcall(function() return Enum.Font[data.Font] end)
		if ok then out.Font = f end
	end
	for _, k in ipairs(COLOR_KEYS) do
		local c = data[k]
		if type(c) == "table" and #c >= 3 then
			out[k] = Color3.fromRGB(c[1], c[2], c[3])
		end
	end
	return out
end

function Ember:SetTheme(nameOrTable)
	local newT
	if type(nameOrTable) == "string" then
		newT = Themes[nameOrTable]
	elseif type(nameOrTable) == "table" then
		newT = nameOrTable
	end
	if not newT then return false end

	for k, v in pairs(newT) do
		Theme[k] = v
	end
	-- Re-apply every registered themed property (prune dead entries)
	for i = #ThemeRegistry, 1, -1 do
		local e = ThemeRegistry[i]
		local ok = pcall(applyThemeEntry, e)
		if not ok then table.remove(ThemeRegistry, i) end
	end
	return true
end

function SaveManager:ExportTheme()
	local json = HttpService:JSONEncode(serializeTheme(Theme))
	if hasFS then
		ensureFolders()
		pcall(fs.write, self.Folder .. "/themes/" .. tostring(Theme.Name or "theme") .. ".json", json)
	end
	if hasClipboard then pcall(hasClipboard, json) end
	return json
end

function SaveManager:ImportTheme(json)
	local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
	if not ok then return false, "decode error" end
	Ember:SetTheme(deserializeTheme(data))
	return true
end

--============================================================================--
--  NOTIFICATIONS
--============================================================================--

local NotifyGui, NotifyHolder

local function ensureNotifyGui()
	if NotifyGui and NotifyGui.Parent then return end
	NotifyGui = Create("ScreenGui", {
		Name             = "EmberNotify",
		ZIndexBehavior   = Enum.ZIndexBehavior.Sibling,
		DisplayOrder     = 10000,
		ResetOnSpawn     = false,
		IgnoreGuiInset   = true,
		Parent           = GetGuiParent(),
	})
	NotifyHolder = Create("Frame", {
		Name                = "Holder",
		AnchorPoint         = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Position            = UDim2.new(1, -20, 1, -20),
		Size                = UDim2.new(0, 300, 1, -40),
		Parent              = NotifyGui,
	})
	Create("UIListLayout", {
		Padding             = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment   = Enum.VerticalAlignment.Bottom,
		SortOrder           = Enum.SortOrder.LayoutOrder,
		Parent              = NotifyHolder,
	})
end

local TYPE_COLOR = { Info = "Accent", Success = "Success", Warning = "Warning", Error = "Error" }

function Ember:Notify(config)
	config = config or {}
	ensureNotifyGui()

	local title   = config.Title       or config[1] or "Notification"
	local desc    = config.Description  or config[2] or ""
	local content = config.Content      or config[3] or ""
	local ntype   = config.Type         or "Info"
	local delay   = tonumber(config.Delay or config.Time) or 5
	local accentKey = TYPE_COLOR[ntype] or "Accent"

	local card = Create("CanvasGroup", {
		Name             = "Notification",
		BackgroundColor3 = Theme.Surface,
		GroupTransparency = 1,
		Size             = UDim2.new(1, 0, 0, 0),
		AutomaticSize    = Enum.AutomaticSize.Y,
		Parent           = NotifyHolder,
	})
	Themed(card, "BackgroundColor3", "Surface")
	Corner(8, card)
	Stroke(card, "Stroke", 1, 0.2)

	local bar = Create("Frame", {
		Name             = "AccentBar",
		BackgroundColor3 = Theme[accentKey],
		BorderSizePixel  = 0,
		Size             = UDim2.new(0, 3, 1, -12),
		Position         = UDim2.new(0, 6, 0, 6),
		Parent           = card,
	})
	Themed(bar, "BackgroundColor3", accentKey)
	Corner(2, bar)

	local col = Create("Frame", {
		BackgroundTransparency = 1,
		Position      = UDim2.fromOffset(16, 0),
		Size          = UDim2.new(1, -46, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent        = card,
	})
	Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = col })
	Create("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = col })

	local titleLbl = Create("TextLabel", {
		BackgroundTransparency = 1,
		Font          = Theme.Font,
		Text          = title,
		TextColor3    = Theme.Text,
		TextSize      = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size          = UDim2.new(1, 0, 0, 16),
		LayoutOrder   = 1,
		Parent        = col,
	})
	Themed(titleLbl, "TextColor3", "Text")

	if desc ~= "" then
		local descLbl = Create("TextLabel", {
			BackgroundTransparency = 1,
			Font          = Theme.Font,
			Text          = desc,
			TextColor3    = Theme[accentKey],
			TextSize      = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size          = UDim2.new(1, 0, 0, 14),
			LayoutOrder   = 2,
			Parent        = col,
		})
		Themed(descLbl, "TextColor3", accentKey)
	end

	if content ~= "" then
		local contentLbl = Create("TextLabel", {
			BackgroundTransparency = 1,
			Font          = Enum.Font.Gotham,
			Text          = content,
			TextColor3    = Theme.Muted,
			TextSize      = 12,
			TextWrapped   = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size          = UDim2.new(1, 0, 0, 0),
			LayoutOrder   = 3,
			Parent        = col,
		})
		Themed(contentLbl, "TextColor3", "Muted")
	end

	local closeBtn = Create("TextButton", {
		BackgroundTransparency = 1,
		Font          = Theme.Font,
		Text          = "×",
		TextColor3    = Theme.Muted,
		TextSize      = 20,
		AnchorPoint   = Vector2.new(1, 0),
		Position      = UDim2.new(1, -6, 0, 4),
		Size          = UDim2.fromOffset(24, 24),
		Parent        = card,
	})
	Themed(closeBtn, "TextColor3", "Muted")

	local closed = false
	local function close()
		if closed then return end
		closed = true
		local t = Tween(card, 0.25, { GroupTransparency = 1 })
		t.Completed:Wait()
		card:Destroy()
	end

	closeBtn.Activated:Connect(close)
	Tween(card, 0.28, { GroupTransparency = 0 })
	task.delay(delay, close)

	return { Close = close }
end

--============================================================================--
--  ELEMENT HELPERS (shared card layout)
--============================================================================--

-- Standard card with a left text column (title + optional content) that drives height.
-- Returns card, and a table with the control-area right pad already reserved.
local function buildCard(parent, order, rightPad)
	local card = Create("Frame", {
		Name             = "Item",
		BackgroundColor3 = Theme.Elevated,
		BorderSizePixel  = 0,
		Size             = UDim2.new(1, 0, 0, 0),
		AutomaticSize    = Enum.AutomaticSize.Y,
		LayoutOrder      = order,
		Parent           = parent,
	})
	Themed(card, "BackgroundColor3", "Elevated")
	Corner(6, card)
	Create("UISizeConstraint", { MinSize = Vector2.new(0, 36), Parent = card })
	return card
end

local function buildTextColumn(card, title, content, rightPad)
	local col = Create("Frame", {
		Name             = "TextCol",
		BackgroundTransparency = 1,
		Position         = UDim2.fromOffset(12, 0),
		Size             = UDim2.new(1, -(rightPad or 24), 0, 0),
		AutomaticSize    = Enum.AutomaticSize.Y,
		Parent           = card,
	})
	Create("UIListLayout", {
		Padding           = UDim.new(0, 2),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder         = Enum.SortOrder.LayoutOrder,
		Parent            = col,
	})
	Create("UIPadding", { PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9), Parent = col })

	local titleLbl = Create("TextLabel", {
		Name           = "Title",
		BackgroundTransparency = 1,
		Font           = Theme.Font,
		Text           = title or "",
		TextColor3     = Theme.Text,
		TextSize       = 13,
		TextWrapped    = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize  = Enum.AutomaticSize.Y,
		Size           = UDim2.new(1, 0, 0, 14),
		LayoutOrder    = 1,
		Parent         = col,
	})
	Themed(titleLbl, "TextColor3", "Text")

	local contentLbl
	if content and content ~= "" then
		contentLbl = Create("TextLabel", {
			Name           = "Content",
			BackgroundTransparency = 1,
			Font           = Enum.Font.Gotham,
			Text           = content,
			TextColor3     = Theme.Muted,
			TextSize       = 12,
			TextWrapped    = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			AutomaticSize  = Enum.AutomaticSize.Y,
			Size           = UDim2.new(1, 0, 0, 12),
			LayoutOrder    = 2,
			Parent         = col,
		})
		Themed(contentLbl, "TextColor3", "Muted")
	end

	return col, titleLbl, contentLbl
end

-- transparent full-cover click layer + ripple
local function clickLayer(card, callback, layer)
	local btn = Create("TextButton", {
		Name             = "Click",
		BackgroundTransparency = 1,
		Text             = "",
		Size             = UDim2.new(1, 0, 1, 0),
		ZIndex           = 5,
		Parent           = card,
	})
	btn.Activated:Connect(function()
		local m = Player:GetMouse()
		Ripple(card, m.X, m.Y, layer)
		if callback then callback() end
	end)
	return btn
end

--============================================================================--
--  WINDOW
--============================================================================--

function Ember:CreateWindow(config)
	config = config or {}
	local name     = config.Name      or config[1] or "Ember"
	local subtitle = config.Subtitle  or config[2] or Ember.Version
	local size     = config.Size      or UDim2.fromOffset(560, 340)
	local logoId   = config.LogoId    or Theme.LogoId or ""
	local toggleKey = config.ToggleKey or Enum.KeyCode.RightShift
	local antiAFK  = config.AntiAFK
	if antiAFK == nil then antiAFK = true end

	local wmaid = Maid.new()
	local Window = { _maid = wmaid, _tabs = {}, _flags = {} }

	local gui = Create("ScreenGui", {
		Name           = "Ember_" .. name,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ResetOnSpawn   = false,
		IgnoreGuiInset = true,
		DisplayOrder   = 5000,
		Parent         = GetGuiParent(),
	})
	wmaid:Give(gui)

	--// Main frame
	local main = Create("Frame", {
		Name             = "Main",
		AnchorPoint      = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel  = 0,
		Position         = UDim2.new(0.5, 0, 0.5, 0),
		Size             = size,
		Parent           = gui,
	})
	Themed(main, "BackgroundColor3", "Background")
	Corner(10, main)
	Stroke(main, "Stroke", 1.4, 0)

	-- Fixed-size overlay for click ripples (kept out of any AutomaticSize subtree).
	-- Active=false + transparent so it never blocks input to the controls beneath it.
	local effectLayer = Create("Frame", {
		Name             = "EffectLayer",
		Active           = false,
		BackgroundTransparency = 1,
		Size             = UDim2.new(1, 0, 1, 0),
		ClipsDescendants = true,
		ZIndex           = 30,
		Parent           = main,
	})
	Corner(10, effectLayer)

	--// Topbar
	local top = Create("Frame", {
		Name             = "Top",
		BackgroundTransparency = 1,
		Size             = UDim2.new(1, 0, 0, 40),
		Parent           = main,
	})

	local textX = 14
	if logoId ~= "" then
		Create("ImageLabel", {
			Name             = "Logo",
			BackgroundTransparency = 1,
			Image            = logoId,
			AnchorPoint      = Vector2.new(0, 0.5),
			Position         = UDim2.new(0, 14, 0.5, 0),
			Size             = UDim2.fromOffset(22, 22),
			Parent           = top,
		})
		textX = 44
	end

	local titleLbl = Create("TextLabel", {
		Name             = "Title",
		BackgroundTransparency = 1,
		Font             = Theme.Font,
		Text             = name,
		TextColor3       = Theme.Text,
		TextSize         = 15,
		TextXAlignment   = Enum.TextXAlignment.Left,
		AnchorPoint      = Vector2.new(0, 0.5),
		Position         = UDim2.new(0, textX, 0.5, 0),
		Size             = UDim2.new(0, 200, 1, 0),
		AutomaticSize    = Enum.AutomaticSize.X,
		Parent           = top,
	})
	Themed(titleLbl, "TextColor3", "Text")

	local subLbl = Create("TextLabel", {
		Name             = "Subtitle",
		BackgroundTransparency = 1,
		Font             = Theme.Font,
		Text             = subtitle,
		TextColor3       = Theme.Accent,
		TextSize         = 13,
		TextXAlignment   = Enum.TextXAlignment.Left,
		AnchorPoint      = Vector2.new(0, 0.5),
		Position         = UDim2.new(0, textX + 4, 0.5, 0),
		Size             = UDim2.new(0, 120, 1, 0),
		AutomaticSize    = Enum.AutomaticSize.X,
		Parent           = top,
	})
	Themed(subLbl, "TextColor3", "Accent")
	-- keep subtitle after the title
	titleLbl:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		subLbl.Position = UDim2.new(0, textX + titleLbl.AbsoluteSize.X + 8, 0.5, 0)
	end)
	task.defer(function()
		subLbl.Position = UDim2.new(0, textX + titleLbl.AbsoluteSize.X + 8, 0.5, 0)
	end)

	local function topButton(txt, offset)
		local b = Create("TextButton", {
			BackgroundTransparency = 1,
			Font           = Theme.Font,
			Text           = txt,
			TextColor3     = Theme.Muted,
			TextSize       = 18,
			AnchorPoint    = Vector2.new(1, 0.5),
			Position       = UDim2.new(1, offset, 0.5, 0),
			Size           = UDim2.fromOffset(26, 26),
			Parent         = top,
		})
		Themed(b, "TextColor3", "Muted")
		b.MouseEnter:Connect(function() Tween(b, 0.15, { TextColor3 = Theme.Text }) end)
		b.MouseLeave:Connect(function() Tween(b, 0.15, { TextColor3 = Theme.Muted }) end)
		return b
	end

	local closeBtn = topButton("×", -10)
	local minBtn   = topButton("–", -42)

	-- topbar divider
	local divider = Create("Frame", {
		Name             = "Divider",
		BackgroundColor3 = Theme.Stroke,
		BorderSizePixel  = 0,
		Position         = UDim2.new(0, 0, 0, 40),
		Size             = UDim2.new(1, 0, 0, 1),
		Parent           = main,
	})
	Themed(divider, "BackgroundColor3", "Stroke")

	--// Sidebar (tab list)
	local sidebar = Create("ScrollingFrame", {
		Name             = "Sidebar",
		Active           = true,
		BackgroundTransparency = 1,
		BorderSizePixel  = 0,
		Position         = UDim2.new(0, 10, 0, 50),
		Size             = UDim2.new(0, 150, 1, -60),
		CanvasSize       = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 0,
		Parent           = main,
	})
	Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sidebar })

	--// Content area + page layout
	local content = Create("Frame", {
		Name             = "Content",
		BackgroundTransparency = 1,
		Position         = UDim2.new(0, 170, 0, 50),
		Size             = UDim2.new(1, -180, 1, -60),
		ClipsDescendants = true,
		Parent           = main,
	})

	local pagesFolder = Create("Frame", {
		Name             = "Pages",
		BackgroundTransparency = 1,
		Size             = UDim2.new(1, 0, 1, 0),
		Parent           = content,
	})
	local pageLayout = Create("UIPageLayout", {
		SortOrder        = Enum.SortOrder.LayoutOrder,
		TweenTime        = 0.35,
		EasingStyle      = Enum.EasingStyle.Quad,
		EasingDirection  = Enum.EasingDirection.InOut,
		Circular         = false,
		GamepadInputEnabled = false,
		ScrollWheelInputEnabled = false,
		TouchInputEnabled = false,
		Parent           = pagesFolder,
	})

	MakeDraggable(top, main, wmaid)

	--// Reopen (floating) button for minimize + toggle key
	local reopen = Create("TextButton", {
		Name             = "Reopen",
		BackgroundColor3 = Theme.Accent,
		Font             = Theme.Font,
		Text             = string.sub(name, 1, 1):upper(),
		TextColor3       = Theme.Background,
		TextSize         = 20,
		Position         = UDim2.fromOffset(20, 120),
		Size             = UDim2.fromOffset(44, 44),
		Visible          = false,
		Parent           = gui,
	})
	Themed(reopen, "BackgroundColor3", "Accent")
	Themed(reopen, "TextColor3", "Background")
	Corner(10, reopen)
	Stroke(reopen, "Stroke", 1, 0.3)
	MakeDraggable(reopen, reopen, wmaid)

	local visible = true
	local function setVisible(v)
		visible = v
		main.Visible = v
		reopen.Visible = not v
	end

	minBtn.Activated:Connect(function() setVisible(false) end)
	reopen.Activated:Connect(function() setVisible(true) end)

	--// Modal dialog (confirm/cancel). Overlay click = cancel.
	function Window:Dialog(cfg)
		cfg = cfg or {}
		local dTitle   = cfg.Title   or "Confirm"
		local dContent = cfg.Content or ""
		local dConfirm = cfg.Confirm or "Confirm"
		local dCancel  = cfg.Cancel  or "Cancel"

		local overlay = Create("TextButton", {
			Name             = "DialogOverlay",
			AutoButtonColor  = false,
			Text             = "",
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel  = 0,
			Size             = UDim2.new(1, 0, 1, 0),
			ZIndex           = 50,
			Parent           = main,
		})
		Corner(10, overlay)
		Tween(overlay, 0.15, { BackgroundTransparency = 0.45 })

		local dialog = Create("Frame", {
			Name             = "Dialog",
			Active           = true, -- sink clicks so they don't fall through to the overlay (= cancel)
			AnchorPoint      = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Surface,
			BorderSizePixel  = 0,
			Position         = UDim2.new(0.5, 0, 0.5, 0),
			Size             = UDim2.fromOffset(280, 0),
			AutomaticSize    = Enum.AutomaticSize.Y,
			ZIndex           = 51,
			Parent           = overlay,
		})
		Themed(dialog, "BackgroundColor3", "Surface")
		Corner(8, dialog)
		Stroke(dialog, "Stroke", 1.2, 0)
		Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = dialog })
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = dialog,
		})

		local dTitleLbl = Create("TextLabel", {
			BackgroundTransparency = 1,
			Font           = Theme.Font,
			Text           = dTitle,
			TextColor3     = Theme.Text,
			TextSize       = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size           = UDim2.new(1, 0, 0, 16),
			ZIndex         = 51,
			LayoutOrder    = 0,
			Parent         = dialog,
		})
		Themed(dTitleLbl, "TextColor3", "Text")

		if dContent ~= "" then
			local dContentLbl = Create("TextLabel", {
				BackgroundTransparency = 1,
				Font           = Enum.Font.Gotham,
				Text           = dContent,
				TextColor3     = Theme.Muted,
				TextSize       = 12,
				TextWrapped    = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				AutomaticSize  = Enum.AutomaticSize.Y,
				Size           = UDim2.new(1, 0, 0, 12),
				ZIndex         = 51,
				LayoutOrder    = 1,
				Parent         = dialog,
			})
			Themed(dContentLbl, "TextColor3", "Muted")
		end

		local buttonRow = Create("Frame", {
			BackgroundTransparency = 1,
			Size           = UDim2.new(1, 0, 0, 28),
			ZIndex         = 51,
			LayoutOrder    = 2,
			Parent         = dialog,
		})
		Create("UIListLayout", {
			Padding             = UDim.new(0, 8),
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder           = Enum.SortOrder.LayoutOrder,
			Parent              = buttonRow,
		})

		local closedD = false
		local function closeDialog(confirmed)
			if closedD then return end
			closedD = true
			Tween(overlay, 0.15, { BackgroundTransparency = 1 })
			task.delay(0.15, function() overlay:Destroy() end)
			if confirmed then
				SafeCall(cfg.OnConfirm)
			else
				SafeCall(cfg.OnCancel)
			end
		end

		local cancelBtn = Create("TextButton", {
			BackgroundColor3 = Theme.Elevated,
			Font           = Theme.Font,
			Text           = dCancel,
			TextColor3     = Theme.Text,
			TextSize       = 12,
			Size           = UDim2.fromOffset(74, 28),
			ZIndex         = 51,
			LayoutOrder    = 0,
			Parent         = buttonRow,
		})
		Themed(cancelBtn, "BackgroundColor3", "Elevated")
		Themed(cancelBtn, "TextColor3", "Text")
		Corner(6, cancelBtn)

		local confirmBtn = Create("TextButton", {
			BackgroundColor3 = Theme.Accent,
			Font           = Theme.Font,
			Text           = dConfirm,
			TextColor3     = Theme.Background,
			TextSize       = 12,
			Size           = UDim2.fromOffset(74, 28),
			ZIndex         = 51,
			LayoutOrder    = 1,
			Parent         = buttonRow,
		})
		Themed(confirmBtn, "BackgroundColor3", "Accent")
		Themed(confirmBtn, "TextColor3", "Background")
		Corner(6, confirmBtn)

		cancelBtn.Activated:Connect(function() closeDialog(false) end)
		confirmBtn.Activated:Connect(function() closeDialog(true) end)
		overlay.Activated:Connect(function() closeDialog(false) end)

		return { Close = function() closeDialog(false) end }
	end

	closeBtn.Activated:Connect(function()
		Window:Dialog({
			Title     = "Unload " .. name .. "?",
			Content   = "This will close the UI and disconnect all listeners.",
			Confirm   = "Unload",
			Cancel    = "Cancel",
			OnConfirm = function() Window:Destroy() end,
		})
	end)

	-- global toggle key
	wmaid:Give(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == toggleKey then
			setVisible(not visible)
		end
	end))

	-- anti-AFK
	if antiAFK then
		wmaid:Give(Player.Idled:Connect(function()
			VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
			task.wait(1)
			VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
		end))
	end

	--// Shared slider drag state (ONE listener for all sliders, not one-per-slider)
	local activeSlider = nil   -- { update = function(x) end }
	wmaid:Give(UserInputService.InputChanged:Connect(function(input)
		if activeSlider and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			activeSlider.update(input.Position.X)
		end
	end))
	wmaid:Give(UserInputService.InputEnded:Connect(function(input)
		if activeSlider and (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) then
			local s = activeSlider
			activeSlider = nil
			if s.done then s.done() end
		end
	end))

	--========================================================================--
	--  TAB
	--========================================================================--
	function Window:CreateTab(tabConfig)
		tabConfig = tabConfig or {}
		local tabName = tabConfig.Name or tabConfig[1] or "Tab"
		local tabIcon = tabConfig.Icon or tabConfig[2] or ASSETS.TabIcon
		local index   = #Window._tabs

		-- sidebar button
		local tabBtn = Create("TextButton", {
			Name             = "TabButton",
			AutoButtonColor  = false,
			BackgroundColor3 = Theme.Elevated,
			BackgroundTransparency = index == 0 and 0 or 1,
			Text             = "",
			Size             = UDim2.new(1, 0, 0, 32),
			LayoutOrder      = index,
			Parent           = sidebar,
		})
		Themed(tabBtn, "BackgroundColor3", "Elevated")
		Corner(6, tabBtn)

		local indicator = Create("Frame", {
			Name             = "Indicator",
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel  = 0,
			AnchorPoint      = Vector2.new(0, 0.5),
			Position         = UDim2.new(0, 3, 0.5, 0),
			Size             = index == 0 and UDim2.fromOffset(2, 14) or UDim2.fromOffset(2, 0),
			Parent           = tabBtn,
		})
		Themed(indicator, "BackgroundColor3", "Accent")
		Corner(2, indicator)

		Create("ImageLabel", {
			Name             = "Icon",
			BackgroundTransparency = 1,
			Image            = tabIcon,
			Position         = UDim2.new(0, 12, 0.5, -8),
			Size             = UDim2.fromOffset(16, 16),
			Parent           = tabBtn,
		})

		local tabLbl = Create("TextLabel", {
			Name             = "Label",
			BackgroundTransparency = 1,
			Font             = Theme.Font,
			Text             = tabName,
			TextColor3       = index == 0 and Theme.Text or Theme.Muted,
			TextSize         = 13,
			TextXAlignment   = Enum.TextXAlignment.Left,
			Position         = UDim2.new(0, 36, 0, 0),
			Size             = UDim2.new(1, -40, 1, 0),
			Parent           = tabBtn,
		})
		Themed(tabLbl, "TextColor3", index == 0 and "Text" or "Muted")

		-- content page
		local page = Create("ScrollingFrame", {
			Name             = "Page",
			Active           = true,
			BackgroundTransparency = 1,
			BorderSizePixel  = 0,
			Size             = UDim2.new(1, 0, 1, 0),
			CanvasSize       = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.Accent,
			ScrollBarImageTransparency = 0.4,
			LayoutOrder      = index,
			Parent           = pagesFolder,
		})
		Themed(page, "ScrollBarImageColor3", "Accent")
		Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 8), Parent = page,
		})

		local Tab = { _button = tabBtn, _label = tabLbl, _indicator = indicator, _index = index }
		table.insert(Window._tabs, Tab)

		local function selectTab()
			for _, t in ipairs(Window._tabs) do
				local active = (t == Tab)
				Tween(t._button, 0.2, { BackgroundTransparency = active and 0 or 1 })
				Tween(t._label, 0.2, { TextColor3 = active and Theme.Text or Theme.Muted })
				Tween(t._indicator, 0.2, { Size = active and UDim2.fromOffset(2, 14) or UDim2.fromOffset(2, 0) })
			end
			pcall(function() pageLayout:JumpToIndex(Tab._index) end)
		end

		tabBtn.Activated:Connect(selectTab)
		if index == 0 then task.defer(function() pcall(function() pageLayout:JumpToIndex(0) end) end) end

		--====================================================================--
		--  SECTION
		--====================================================================--
		local sectionCount = 0
		function Tab:AddSection(secConfig)
			secConfig = secConfig or {}
			local secTitle = secConfig.Title or secConfig[1] or "Section"
			local isOpen   = secConfig.Open
			if isOpen == nil then isOpen = secConfig[2] end
			isOpen = isOpen and true or false

			local section = Create("Frame", {
				Name             = "Section",
				BackgroundTransparency = 1,
				Size             = UDim2.new(1, 0, 0, 0),
				AutomaticSize    = Enum.AutomaticSize.Y,
				LayoutOrder      = sectionCount,
				Parent           = page,
			})
			sectionCount += 1
			Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = section })

			local header = Create("TextButton", {
				Name             = "Header",
				AutoButtonColor  = false,
				BackgroundColor3 = Theme.Surface,
				Text             = "",
				Size             = UDim2.new(1, 0, 0, 32),
				LayoutOrder      = 0,
				Parent           = section,
			})
			Themed(header, "BackgroundColor3", "Surface")
			Corner(6, header)

			local hTitle = Create("TextLabel", {
				BackgroundTransparency = 1,
				Font           = Theme.Font,
				Text           = secTitle,
				TextColor3     = Theme.Text,
				TextSize       = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position       = UDim2.new(0, 12, 0, 0),
				Size           = UDim2.new(1, -40, 1, 0),
				Parent         = header,
			})
			Themed(hTitle, "TextColor3", "Text")

			-- chevron asset points DOWN at Rotation 0; closed = right (-90), open = down (0)
			local chevron = Create("ImageLabel", {
				BackgroundTransparency = 1,
				Image          = ASSETS.Chevron,
				ImageColor3    = Theme.Muted,
				AnchorPoint    = Vector2.new(1, 0.5),
				Position       = UDim2.new(1, -12, 0.5, 0),
				Size           = UDim2.fromOffset(14, 14),
				Rotation       = isOpen and 0 or -90,
				Parent         = header,
			})
			Themed(chevron, "ImageColor3", "Muted")

			local body = Create("Frame", {
				Name             = "Body",
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Size             = UDim2.new(1, 0, 0, 0),
				LayoutOrder      = 1,
				Parent           = section,
			})
			local bodyList = Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })

			local function refreshBody(animate)
				if isOpen then
					body.Visible = true
					local target = bodyList.AbsoluteContentSize.Y
					if animate then
						Tween(body, 0.2, { Size = UDim2.new(1, 0, 0, target) })
					else
						body.Size = UDim2.new(1, 0, 0, target)
					end
				else
					if animate then
						Tween(body, 0.2, { Size = UDim2.new(1, 0, 0, 0) })
					else
						body.Size = UDim2.new(1, 0, 0, 0)
					end
				end
			end

			wmaid:Give(bodyList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				if isOpen then
					Tween(body, 0.15, { Size = UDim2.new(1, 0, 0, bodyList.AbsoluteContentSize.Y) })
				end
			end))

			header.Activated:Connect(function()
				isOpen = not isOpen
				Tween(chevron, 0.15, { Rotation = isOpen and 0 or -90 })
				refreshBody(true)
			end)
			task.defer(function() refreshBody(false) end)

			local Section = {}
			local itemCount = 0
			local function nextOrder() local o = itemCount; itemCount += 1; return o end

			-- registers flag if provided (tracked per window for cleanup on Destroy)
			local function registerFlag(flag, obj)
				if flag and flag ~= "" then
					Ember.Flags[flag] = obj
					table.insert(Window._flags, flag)
				end
			end

			------------------------------------------------------------------
			-- BUTTON
			------------------------------------------------------------------
			function Section:AddButton(c)
				c = c or {}
				local title    = c.Title or c[1] or "Button"
				local contentT = c.Content or c[2] or ""
				local callback = type(c.Callback) == "function" and c.Callback
					or (type(c[3]) == "function" and c[3])
					or (type(c[4]) == "function" and c[4])
					or nil

				local card = buildCard(body, nextOrder(), 40)
				buildTextColumn(card, title, contentT, 40)

				local chev = Create("ImageLabel", {
					BackgroundTransparency = 1,
					Image        = ASSETS.Chevron,
					ImageColor3  = Theme.Muted,
					AnchorPoint  = Vector2.new(1, 0.5),
					Position     = UDim2.new(1, -12, 0.5, 0),
					Size         = UDim2.fromOffset(14, 14),
					Rotation     = -90, -- asset points down at 0; -90 = right (>)
					Parent       = card,
				})
				Themed(chev, "ImageColor3", "Muted")

				clickLayer(card, function() SafeCall(callback) end, effectLayer)
				return { Instance = card }
			end

			------------------------------------------------------------------
			-- TOGGLE
			------------------------------------------------------------------
			function Section:AddToggle(c)
				c = c or {}
				local title    = c.Title or c[1] or "Toggle"
				local contentT = c.Content or c[2] or ""
				local default  = c.Default; if default == nil then default = c[3] end; default = default and true or false
				local callback = type(c.Callback) == "function" and c.Callback or nil
				local flag     = c.Flag

				local obj = { Value = default }
				local card = buildCard(body, nextOrder(), 56)
				card.Parent = body
				buildTextColumn(card, title, contentT, 56)

				local track = Create("Frame", {
					Name             = "Track",
					BackgroundColor3 = Theme.Stroke,
					BorderSizePixel  = 0,
					AnchorPoint      = Vector2.new(1, 0.5),
					Position         = UDim2.new(1, -14, 0.5, 0),
					Size             = UDim2.fromOffset(38, 20),
					Parent           = card,
				})
				Corner(10, track)
				local knob = Create("Frame", {
					Name             = "Knob",
					BackgroundColor3 = Theme.Text,
					BorderSizePixel  = 0,
					AnchorPoint      = Vector2.new(0, 0.5),
					Position         = UDim2.new(0, 3, 0.5, 0),
					Size             = UDim2.fromOffset(14, 14),
					Parent           = track,
				})
				Themed(knob, "BackgroundColor3", "Text")
				Corner(8, knob)

				local function visual(v)
					Tween(track, 0.2, { BackgroundColor3 = v and Theme.Accent or Theme.Stroke })
					Tween(knob, 0.2, { Position = v and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
				end

				function obj:Set(v)
					obj.Value = v and true or false
					visual(obj.Value)
					SafeCall(callback, obj.Value)
				end

				clickLayer(card, function() obj:Set(not obj.Value) end, effectLayer)

				visual(default)
				SafeCall(callback, default) -- fire initial value once
				registerFlag(flag, obj)
				return obj
			end

			------------------------------------------------------------------
			-- SLIDER  (single value, or Range = true for {min,max})
			------------------------------------------------------------------
			function Section:AddSlider(c)
				c = c or {}
				local title    = c.Title or c[1] or "Slider"
				local contentT = c.Content or c[2] or ""
				local minV     = tonumber(c.Min) or 0
				local maxV     = tonumber(c.Max) or 100
				local inc      = tonumber(c.Increment) or 1
				local isRange  = c.Range and true or false
				local callback = type(c.Callback) == "function" and c.Callback or nil
				local flag     = c.Flag

				local function round(n)
					local r = math.clamp(math.floor(n / inc + 0.5) * inc, minV, maxV)
					-- kill floating-point noise (e.g. 0.30000000004 -> 0.3) without
					-- distorting legitimate increments like 0.25
					return tonumber(string.format("%.5f", r)) or r
				end

				local card = buildCard(body, nextOrder(), 170)
				card.Parent = body
				buildTextColumn(card, title, contentT, 170)

				-- value readout (editable: type a number, or "20-80" in range mode)
				local readout = Create("TextBox", {
					Name             = "Readout",
					BackgroundColor3 = Theme.Surface,
					Font             = Theme.Font,
					Text             = "",
					TextColor3       = Theme.Text,
					TextSize         = 12,
					ClearTextOnFocus = false,
					AnchorPoint      = Vector2.new(1, 0.5),
					Position         = UDim2.new(1, -14, 0.5, -12),
					Size             = UDim2.fromOffset(64, 20),
					Parent           = card,
				})
				Themed(readout, "BackgroundColor3", "Surface")
				Themed(readout, "TextColor3", "Text")
				Corner(4, readout)

				-- live filter: digits, minus, dot (and separators in range mode)
				readout:GetPropertyChangedSignal("Text"):Connect(function()
					local allowed = isRange and "[^%d%-%.%, ]" or "[^%d%-%.]"
					local filtered = readout.Text:gsub(allowed, "")
					if filtered ~= readout.Text then readout.Text = filtered end
				end)

				-- track
				local trackFrame = Create("Frame", {
					Name             = "Track",
					BackgroundColor3 = Theme.Stroke,
					BorderSizePixel  = 0,
					AnchorPoint      = Vector2.new(1, 0.5),
					Position         = UDim2.new(1, -14, 0.5, 10),
					Size             = UDim2.new(0, 130, 0, 4),
					Parent           = card,
				})
				Themed(trackFrame, "BackgroundColor3", "Stroke")
				Corner(2, trackFrame)

				local fill = Create("Frame", {
					Name             = "Fill",
					BackgroundColor3 = Theme.Accent,
					BorderSizePixel  = 0,
					Position         = UDim2.new(0, 0, 0, 0),
					Size             = UDim2.new(0, 0, 1, 0),
					Parent           = trackFrame,
				})
				Themed(fill, "BackgroundColor3", "Accent")
				Corner(2, fill)

				local function makeHandle()
					local h = Create("Frame", {
						Name             = "Handle",
						BackgroundColor3 = Theme.Accent,
						BorderSizePixel  = 0,
						AnchorPoint      = Vector2.new(0.5, 0.5),
						Position         = UDim2.new(0, 0, 0.5, 0),
						Size             = UDim2.fromOffset(12, 12),
						ZIndex           = 3,
						Parent           = trackFrame,
					})
					Themed(h, "BackgroundColor3", "Accent")
					Corner(6, h)
					Stroke(h, "Text", 1.5, 0.2)
					return h
				end

				local obj
				if isRange then
					----------------------------------------------------------
					-- RANGE MODE
					----------------------------------------------------------
					local def = c.Default or { minV, maxV }
					local lo = round(tonumber(def[1]) or minV)
					local hi = round(tonumber(def[2]) or maxV)
					if lo > hi then lo, hi = hi, lo end
					obj = { Value = { lo, hi } }

					local hLo = makeHandle()
					local hHi = makeHandle()

					local function redraw()
						local a = (obj.Value[1] - minV) / (maxV - minV)
						local b = (obj.Value[2] - minV) / (maxV - minV)
						hLo.Position = UDim2.new(a, 0, 0.5, 0)
						hHi.Position = UDim2.new(b, 0, 0.5, 0)
						fill.Position = UDim2.new(a, 0, 0, 0)
						fill.Size = UDim2.new(b - a, 0, 1, 0)
						readout.Text = tostring(obj.Value[1]) .. "-" .. tostring(obj.Value[2])
					end

					function obj:Set(v)
						v = v or obj.Value
						local a = round(tonumber(v[1]) or obj.Value[1])
						local b = round(tonumber(v[2]) or obj.Value[2])
						if a > b then a, b = b, a end
						obj.Value = { a, b }
						redraw()
						SafeCall(callback, obj.Value)
					end

					local function valueFromX(px)
						local scale = math.clamp((px - trackFrame.AbsolutePosition.X) / trackFrame.AbsoluteSize.X, 0, 1)
						return round(minV + (maxV - minV) * scale)
					end

					local function beginDrag(which)
						activeSlider = {
							update = function(px)
								local val = valueFromX(px)
								if which == "lo" then
									obj:Set({ math.min(val, obj.Value[2]), obj.Value[2] })
								else
									obj:Set({ obj.Value[1], math.max(val, obj.Value[1]) })
								end
							end,
							done = function() SafeCall(callback, obj.Value) end,
						}
					end

					hLo.InputBegan:Connect(function(i)
						if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then beginDrag("lo") end
					end)
					hHi.InputBegan:Connect(function(i)
						if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then beginDrag("hi") end
					end)

					-- Parse two numbers from "20-80", "20, 80" or "20 80".
					-- Comma/space are tried first; a dash BETWEEN two numbers is treated as a
					-- separator (not a minus) so ranges like "20-80" and "-10-50" both work.
					local function parseRange(text)
						local parts = {}
						for p in text:gmatch("[^,%s]+") do table.insert(parts, p) end
						if #parts == 2 then
							local a, b = tonumber(parts[1]), tonumber(parts[2])
							if a and b then return a, b end
						end
						local s1, s2 = text:match("^%s*(%-?%d+%.?%d*)%s*%-%s*(%-?%d+%.?%d*)%s*$")
						if s1 and s2 then
							local a, b = tonumber(s1), tonumber(s2)
							if a and b then return a, b end
						end
						return nil
					end

					readout.FocusLost:Connect(function()
						local a, b = parseRange(readout.Text)
						if a and b then
							obj:Set({ a, b })
						else
							redraw() -- restore valid display
						end
					end)

					redraw()
					SafeCall(callback, obj.Value) -- fire initial value once
				else
					----------------------------------------------------------
					-- SINGLE MODE
					----------------------------------------------------------
					local def = tonumber(c.Default)
					if def == nil then def = tonumber(c[3]) end
					if def == nil then def = minV end
					obj = { Value = round(def) }

					local handle = makeHandle()

					local function redraw()
						local a = (obj.Value - minV) / (maxV - minV)
						handle.Position = UDim2.new(a, 0, 0.5, 0)
						fill.Size = UDim2.new(a, 0, 1, 0)
						readout.Text = tostring(obj.Value)
					end

					function obj:Set(v)
						obj.Value = round(tonumber(v) or obj.Value)
						redraw()
						SafeCall(callback, obj.Value)
					end

					local function valueFromX(px)
						local scale = math.clamp((px - trackFrame.AbsolutePosition.X) / trackFrame.AbsoluteSize.X, 0, 1)
						return round(minV + (maxV - minV) * scale)
					end

					local function beginDrag()
						activeSlider = {
							update = function(px) obj:Set(valueFromX(px)) end,
							done   = function() SafeCall(callback, obj.Value) end,
						}
					end

					trackFrame.InputBegan:Connect(function(i)
						if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
							obj:Set(valueFromX(i.Position.X))
							beginDrag()
						end
					end)
					handle.InputBegan:Connect(function(i)
						if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then beginDrag() end
					end)

					-- typed entry
					readout.FocusLost:Connect(function()
						local n = tonumber(readout.Text)
						if n then
							obj:Set(n)
						else
							redraw() -- restore valid display
						end
					end)

					redraw()
					SafeCall(callback, obj.Value) -- fire initial value once
				end

				registerFlag(flag, obj)
				return obj
			end

			------------------------------------------------------------------
			-- INPUT
			------------------------------------------------------------------
			function Section:AddInput(c)
				c = c or {}
				local title    = c.Title or c[1] or "Input"
				local contentT = c.Content or c[2] or ""
				local default  = c.Default or c[3] or ""
				local placeholder = c.Placeholder or "Type here..."
				local callback = type(c.Callback) == "function" and c.Callback or nil
				local flag     = c.Flag
				local numeric  = c.Numeric and true or false
				local numMin   = tonumber(c.Min)
				local numMax   = tonumber(c.Max)

				if numeric then
					default = tonumber(default) or numMin or 0
					if numMin then default = math.max(default, numMin) end
					if numMax then default = math.min(default, numMax) end
					placeholder = c.Placeholder or "0"
				end

				local obj = { Value = numeric and default or tostring(default) }
				local card = buildCard(body, nextOrder(), 160)
				card.Parent = body
				buildTextColumn(card, title, contentT, 160)

				local box = Create("Frame", {
					Name             = "Box",
					BackgroundColor3 = Theme.Surface,
					BorderSizePixel  = 0,
					AnchorPoint      = Vector2.new(1, 0.5),
					Position         = UDim2.new(1, -14, 0.5, 0),
					Size             = UDim2.new(0, 140, 0, 26),
					Parent           = card,
				})
				Themed(box, "BackgroundColor3", "Surface")
				Corner(4, box)
				Stroke(box, "Stroke", 1, 0.3)

				local tb = Create("TextBox", {
					BackgroundTransparency = 1,
					Font             = Enum.Font.Gotham,
					Text             = tostring(default),
					PlaceholderText  = placeholder,
					PlaceholderColor3 = Theme.Muted,
					TextColor3       = Theme.Text,
					TextSize         = 12,
					TextXAlignment   = Enum.TextXAlignment.Left,
					ClearTextOnFocus = false,
					Position         = UDim2.new(0, 8, 0, 0),
					Size             = UDim2.new(1, -12, 1, 0),
					Parent           = box,
				})
				Themed(tb, "TextColor3", "Text")
				Themed(tb, "PlaceholderColor3", "Muted")

				if numeric then
					-- live filter: digits, minus, dot only
					tb:GetPropertyChangedSignal("Text"):Connect(function()
						local filtered = tb.Text:gsub("[^%d%-%.]", "")
						if filtered ~= tb.Text then tb.Text = filtered end
					end)

					function obj:Set(v)
						local n = tonumber(v)
						if n == nil then n = obj.Value end -- keep last valid
						if numMin then n = math.max(n, numMin) end
						if numMax then n = math.min(n, numMax) end
						obj.Value = n
						tb.Text = tostring(n)
						SafeCall(callback, obj.Value)
					end

					tb.FocusLost:Connect(function()
						obj:Set(tb.Text)
					end)
				else
					function obj:Set(v)
						obj.Value = tostring(v)
						tb.Text = obj.Value
						SafeCall(callback, obj.Value)
					end

					tb.FocusLost:Connect(function()
						obj.Value = tb.Text
						SafeCall(callback, obj.Value)
					end)
				end

				registerFlag(flag, obj)
				return obj
			end

			------------------------------------------------------------------
			-- KEYBIND
			------------------------------------------------------------------
			function Section:AddKeybind(c)
				c = c or {}
				local title    = c.Title or c[1] or "Keybind"
				local contentT = c.Content or c[2] or ""
				local default  = c.Default or c[3] or Enum.KeyCode.Unknown
				local callback = type(c.Callback) == "function" and c.Callback or nil
				local flag     = c.Flag

				local obj = { Value = default }
				local card = buildCard(body, nextOrder(), 100)
				card.Parent = body
				buildTextColumn(card, title, contentT, 100)

				local keyBtn = Create("TextButton", {
					Name             = "Key",
					BackgroundColor3 = Theme.Surface,
					Font             = Theme.Font,
					Text             = default.Name == "Unknown" and "None" or default.Name,
					TextColor3       = Theme.Text,
					TextSize         = 12,
					AnchorPoint      = Vector2.new(1, 0.5),
					Position         = UDim2.new(1, -14, 0.5, 0),
					Size             = UDim2.fromOffset(80, 24),
					Parent           = card,
				})
				Themed(keyBtn, "BackgroundColor3", "Surface")
				Themed(keyBtn, "TextColor3", "Text")
				Corner(4, keyBtn)
				Stroke(keyBtn, "Stroke", 1, 0.3)

				local binding = false

				function obj:Set(key)
					if typeof(key) ~= "EnumItem" then return end
					obj.Value = key
					keyBtn.Text = key.Name == "Unknown" and "None" or key.Name
				end

				keyBtn.Activated:Connect(function()
					binding = true
					keyBtn.Text = "..."
					keyBtn.TextColor3 = Theme.Accent
				end)

				wmaid:Give(UserInputService.InputBegan:Connect(function(input, gameProcessed)
					if binding then
						if input.UserInputType == Enum.UserInputType.Keyboard then
							binding = false
							keyBtn.TextColor3 = Theme.Text
							if input.KeyCode == Enum.KeyCode.Escape then
								-- cancel; keep previous
								keyBtn.Text = obj.Value.Name == "Unknown" and "None" or obj.Value.Name
							else
								obj:Set(input.KeyCode)
							end
						end
						return
					end
					if gameProcessed then return end
					if input.KeyCode == obj.Value and obj.Value ~= Enum.KeyCode.Unknown then
						SafeCall(callback, obj.Value)
					end
				end))

				registerFlag(flag, obj)
				return obj
			end

			------------------------------------------------------------------
			-- DROPDOWN  (single / multi, with search, inline expansion)
			------------------------------------------------------------------
			function Section:AddDropdown(c)
				c = c or {}
				local title    = c.Title or c[1] or "Dropdown"
				local contentT = c.Content or c[2] or ""
				local multi    = c.Multi and true or false
				local options  = c.Options or c[4] or {}
				local callback = type(c.Callback) == "function" and c.Callback or nil
				local flag     = c.Flag

				-- normalize default -> internal table of selected strings
				local function toSet(v)
					if type(v) == "table" then return table.clone(v) end
					if type(v) == "string" and v ~= "" then return { v } end
					return {}
				end
				local selected = toSet(c.Default)

				local obj = { Options = table.clone(options) }

				-- outer card uses a vertical list: header + expandable list
				local card = Create("Frame", {
					Name             = "Dropdown",
					BackgroundColor3 = Theme.Elevated,
					BorderSizePixel  = 0,
					Size             = UDim2.new(1, 0, 0, 0),
					AutomaticSize    = Enum.AutomaticSize.Y,
					LayoutOrder      = nextOrder(),
					ClipsDescendants = true,
					Parent           = body,
				})
				Themed(card, "BackgroundColor3", "Elevated")
				Corner(6, card)
				Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })

				-- header
				local headerF = Create("Frame", {
					Name             = "Header",
					BackgroundTransparency = 1,
					Size             = UDim2.new(1, 0, 0, 0),
					AutomaticSize    = Enum.AutomaticSize.Y,
					LayoutOrder      = 0,
					Parent           = card,
				})
				Create("UISizeConstraint", { MinSize = Vector2.new(0, 40), Parent = headerF })
				buildTextColumn(headerF, title, contentT, 150)

				local selLbl = Create("TextLabel", {
					Name             = "Selected",
					BackgroundColor3 = Theme.Surface,
					Font             = Enum.Font.Gotham,
					Text             = "Select...",
					TextColor3       = Theme.Muted,
					TextSize         = 12,
					TextXAlignment   = Enum.TextXAlignment.Left,
					TextTruncate     = Enum.TextTruncate.AtEnd,
					AnchorPoint      = Vector2.new(1, 0.5),
					Position         = UDim2.new(1, -14, 0.5, 0),
					Size             = UDim2.fromOffset(130, 26),
					Parent           = headerF,
				})
				Themed(selLbl, "BackgroundColor3", "Surface")
				Themed(selLbl, "TextColor3", "Muted")
				Corner(4, selLbl)
				Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 22), Parent = selLbl })
				-- asset points down at 0; closed = right (-90), open = down (0)
				local arrow = Create("ImageLabel", {
					BackgroundTransparency = 1,
					Image        = ASSETS.Chevron,
					ImageColor3  = Theme.Muted,
					AnchorPoint  = Vector2.new(1, 0.5),
					Position     = UDim2.new(1, -4, 0.5, 0),
					Size         = UDim2.fromOffset(12, 12),
					Rotation     = -90,
					Parent       = selLbl,
				})
				Themed(arrow, "ImageColor3", "Muted")

				local headerBtn = Create("TextButton", {
					BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 1, 0), ZIndex = 4, Parent = headerF,
				})

				-- list container (animated open/close)
				local listWrap = Create("Frame", {
					Name             = "List",
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					Size             = UDim2.new(1, 0, 0, 0),
					LayoutOrder      = 1,
					Parent           = card,
				})
				local inner = Create("Frame", {
					BackgroundTransparency = 1,
					Position         = UDim2.new(0, 0, 0, 0),
					Size             = UDim2.new(1, 0, 0, 0),
					AutomaticSize    = Enum.AutomaticSize.Y,
					Parent           = listWrap,
				})
				Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
				Create("UIPadding", {
					PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
					PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8), Parent = inner,
				})

				local searchBox = Create("TextBox", {
					Name             = "Search",
					BackgroundColor3 = Theme.Surface,
					Font             = Enum.Font.Gotham,
					PlaceholderText  = "Search...",
					PlaceholderColor3 = Theme.Muted,
					Text             = "",
					TextColor3       = Theme.Text,
					TextSize         = 12,
					TextXAlignment   = Enum.TextXAlignment.Left,
					ClearTextOnFocus = false,
					Size             = UDim2.new(1, 0, 0, 26),
					LayoutOrder      = 0,
					Parent           = inner,
				})
				Themed(searchBox, "BackgroundColor3", "Surface")
				Themed(searchBox, "TextColor3", "Text")
				Themed(searchBox, "PlaceholderColor3", "Muted")
				Corner(4, searchBox)
				Create("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = searchBox })

				local optHolder = Create("ScrollingFrame", {
					Name             = "Options",
					Active           = true,
					BackgroundTransparency = 1,
					BorderSizePixel  = 0,
					Size             = UDim2.new(1, 0, 0, 0),
					AutomaticSize    = Enum.AutomaticSize.Y,
					CanvasSize       = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollBarThickness = 2,
					ScrollBarImageColor3 = Theme.Accent,
					LayoutOrder      = 1,
					Parent           = inner,
				})
				Themed(optHolder, "ScrollBarImageColor3", "Accent")
				Create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = optHolder })
				Create("UISizeConstraint", { MaxSize = Vector2.new(100000, 120), Parent = optHolder })

				local expanded = false
				local function setExpanded(v)
					expanded = v
					Tween(arrow, 0.15, { Rotation = v and 0 or -90 })
					if v then
						Tween(listWrap, 0.18, { Size = UDim2.new(1, 0, 0, inner.AbsoluteSize.Y) })
					else
						Tween(listWrap, 0.18, { Size = UDim2.new(1, 0, 0, 0) })
					end
				end
				wmaid:Give(inner:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					if expanded then listWrap.Size = UDim2.new(1, 0, 0, inner.AbsoluteSize.Y) end
				end))

				headerBtn.Activated:Connect(function() setExpanded(not expanded) end)

				local function isSelected(name)
					return table.find(selected, name) ~= nil
				end

				local function updateSelectedLabel()
					if #selected == 0 then
						selLbl.Text = "Select..."
						selLbl.TextColor3 = Theme.Muted
					else
						selLbl.Text = table.concat(selected, ", ")
						selLbl.TextColor3 = Theme.Text
					end
				end

				local optButtons = {}

				local function fireCallback()
					if multi then
						SafeCall(callback, table.clone(selected))
					else
						SafeCall(callback, selected[1])
					end
				end

				local function rebuildVisual()
					for name, entry in pairs(optButtons) do
						local on = isSelected(name)
						Tween(entry.frame, 0.15, { BackgroundColor3 = on and Theme.Accent or Theme.Surface })
						entry.label.TextColor3 = on and Theme.Background or Theme.Text
					end
					updateSelectedLabel()
				end

				function obj:Set(v)
					if v ~= nil then selected = toSet(v) end
					rebuildVisual()
					fireCallback()
				end

				local function toggleOption(name)
					if multi then
						local idx = table.find(selected, name)
						if idx then table.remove(selected, idx) else table.insert(selected, name) end
					else
						selected = { name }
						setExpanded(false)
					end
					rebuildVisual()
					fireCallback()
				end

				function obj:AddOption(name)
					if optButtons[name] then return end
					local of = Create("Frame", {
						Name             = "Option",
						BackgroundColor3 = Theme.Surface,
						BorderSizePixel  = 0,
						Size             = UDim2.new(1, 0, 0, 26),
						Parent           = optHolder,
					})
					Corner(4, of)
					local ol = Create("TextLabel", {
						BackgroundTransparency = 1,
						Font           = Enum.Font.Gotham,
						Text           = name,
						TextColor3     = Theme.Text,
						TextSize       = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						Position       = UDim2.new(0, 8, 0, 0),
						Size           = UDim2.new(1, -12, 1, 0),
						Parent         = of,
					})
					Themed(ol, "TextColor3", "Text") -- rebuildVisual re-applies selected state after theme swap
					local ob = Create("TextButton", {
						BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 1, 0), Parent = of,
					})
					ob.Activated:Connect(function() toggleOption(name) end)
					optButtons[name] = { frame = of, label = ol }
				end

				function obj:Clear()
					for _, entry in pairs(optButtons) do entry.frame:Destroy() end
					optButtons = {}
					selected = {}
					obj.Options = {}
					updateSelectedLabel()
				end

				function obj:Refresh(list, keep)
					obj:Clear()
					obj.Options = table.clone(list or {})
					for _, name in ipairs(obj.Options) do obj:AddOption(name) end
					selected = toSet(keep)
					rebuildVisual()
					fireCallback()
				end

				-- search filter
				searchBox:GetPropertyChangedSignal("Text"):Connect(function()
					local q = string.lower(searchBox.Text)
					for name, entry in pairs(optButtons) do
						entry.frame.Visible = (q == "") or (string.find(string.lower(name), q, 1, true) ~= nil)
					end
				end)

				-- build initial
				for _, name in ipairs(obj.Options) do obj:AddOption(name) end
				rebuildVisual()
				fireCallback() -- fire initial selection once

				-- expose Value as getter-friendly field
				setmetatable(obj, {
					__index = function(_, k)
						if k == "Value" then
							if multi then return table.clone(selected) else return selected[1] end
						end
					end,
				})

				registerFlag(flag, obj)
				return obj
			end

			------------------------------------------------------------------
			-- PARAGRAPH
			------------------------------------------------------------------
			function Section:AddParagraph(c)
				c = c or {}
				local title    = c.Title or c[1] or "Paragraph"
				local contentT = c.Content or c[2] or ""
				local card = buildCard(body, nextOrder(), 20)
				card.Parent = body
				local _, titleLbl, contentLbl = buildTextColumn(card, title, contentT, 20)
				local o = {}
				function o:Set(cc)
					cc = cc or {}
					titleLbl.Text = cc.Title or cc[1] or titleLbl.Text
					if contentLbl then contentLbl.Text = cc.Content or cc[2] or contentLbl.Text end
				end
				return o
			end

			------------------------------------------------------------------
			-- SEPARATOR (titled)
			------------------------------------------------------------------
			function Section:AddSeparator(c)
				c = c or {}
				local title = c.Title or c[1] or ""
				local card = Create("Frame", {
					Name             = "Separator",
					BackgroundTransparency = 1,
					Size             = UDim2.new(1, 0, 0, 24),
					LayoutOrder      = nextOrder(),
					Parent           = body,
				})
				local lbl = Create("TextLabel", {
					BackgroundTransparency = 1,
					Font           = Theme.Font,
					Text           = title,
					TextColor3     = Theme.Muted,
					TextSize       = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position       = UDim2.new(0, 6, 0, 0),
					Size           = UDim2.new(1, -12, 1, 0),
					Parent         = card,
				})
				Themed(lbl, "TextColor3", "Muted")
				local o = {}
				function o:Set(cc) lbl.Text = (cc and (cc.Title or cc[1])) or "" end
				return o
			end

			------------------------------------------------------------------
			-- LINE (divider)
			------------------------------------------------------------------
			function Section:AddLine()
				local holder = Create("Frame", {
					Name             = "Line",
					BackgroundTransparency = 1,
					Size             = UDim2.new(1, 0, 0, 8),
					LayoutOrder      = nextOrder(),
					Parent           = body,
				})
				local line = Create("Frame", {
					BackgroundColor3 = Theme.Stroke,
					BorderSizePixel  = 0,
					AnchorPoint      = Vector2.new(0.5, 0.5),
					Position         = UDim2.new(0.5, 0, 0.5, 0),
					Size             = UDim2.new(1, -8, 0, 1),
					Parent           = holder,
				})
				Themed(line, "BackgroundColor3", "Stroke")
				return {}
			end

			return Section
		end

		return Tab
	end

	--========================================================================--
	--  Window-level helpers
	--========================================================================--
	function Window:Notify(cfg) return Ember:Notify(cfg) end
	function Window:SetTheme(t) return Ember:SetTheme(t) end
	function Window:Toggle() setVisible(not visible) end

	function Window:Destroy()
		wmaid:Clean()
		-- remove this window's flagged elements from the global registry
		for _, flag in ipairs(Window._flags) do
			Ember.Flags[flag] = nil
		end
		table.clear(Window._flags)
		for i = #Ember.Windows, 1, -1 do
			if Ember.Windows[i] == Window then table.remove(Ember.Windows, i) end
		end
	end

	-- Built-in Settings tab: config manager + theme switcher
	function Window:CreateConfigTab(tabName)
		local tab = Window:CreateTab({ Name = tabName or "Settings", Icon = ASSETS.TabIcon })

		local cfgSection = tab:AddSection({ Title = "Configuration", Open = true })
		local nameInput = cfgSection:AddInput({ Title = "Config name", Placeholder = "my-config", Default = "" })
		local listDrop = cfgSection:AddDropdown({ Title = "Saved configs", Multi = false, Options = SaveManager:List(), Default = "" })

		local function refreshList()
			listDrop:Refresh(SaveManager:List(), listDrop.Value)
		end

		cfgSection:AddButton({ Title = "Save", Content = "Write current values to a config", Callback = function()
			local n = nameInput.Value
			if n == "" then n = "default" end
			local ok, err = SaveManager:Save(n)
			refreshList()
			Ember:Notify({ Title = "Config", Description = ok and "Saved" or "Error", Content = ok and n or tostring(err), Type = ok and "Success" or "Error" })
		end })

		cfgSection:AddButton({ Title = "Load", Content = "Load the selected config", Callback = function()
			local n = listDrop.Value or nameInput.Value
			if not n or n == "" then return end
			local ok, err = SaveManager:Load(n)
			Ember:Notify({ Title = "Config", Description = ok and "Loaded" or "Error", Content = ok and n or tostring(err), Type = ok and "Success" or "Error" })
		end })

		cfgSection:AddButton({ Title = "Delete", Content = "Delete the selected config", Callback = function()
			local n = listDrop.Value
			if not n or n == "" then return end
			SaveManager:Delete(n)
			refreshList()
			Ember:Notify({ Title = "Config", Description = "Deleted", Content = n, Type = "Warning" })
		end })

		cfgSection:AddButton({ Title = "Set autoload", Content = "Load selected config on next launch", Callback = function()
			local n = listDrop.Value
			if not n or n == "" then return end
			SaveManager:SetAutoload(n)
			Ember:Notify({ Title = "Config", Description = "Autoload set", Content = n, Type = "Success" })
		end })

		local themeSection = tab:AddSection({ Title = "Theme", Open = true })
		local themeNames = {}
		for tn in pairs(Themes) do table.insert(themeNames, tn) end
		table.sort(themeNames)
		themeSection:AddDropdown({
			Title = "Theme", Multi = false, Options = themeNames, Default = Theme.Name,
			Callback = function(v) if v then Ember:SetTheme(v) end end,
		})
		themeSection:AddButton({ Title = "Export theme", Content = "Copy current theme JSON to clipboard", Callback = function()
			SaveManager:ExportTheme()
			Ember:Notify({ Title = "Theme", Description = "Exported", Content = hasClipboard and "Copied to clipboard" or "Saved to file", Type = "Success" })
		end })

		return tab
	end

	Ember.Windows[#Ember.Windows + 1] = Window
	return Window
end

return Ember
