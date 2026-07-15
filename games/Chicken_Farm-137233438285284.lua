-- AutoPlay.client.lua
-- Drop this into StarterPlayerScripts or a similar client-side container.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Settings = {
	AutoCollectEggs = false,
	AutoCollectMoney = false,
	AutoSellEggs = false,
	SellMultiplierMin = 0,
	SellMultiplierMax = 0,
	SellOnlyDuringEggFrenzy = false,
	AutoBuyChicken = false,
	ChickenCashReserve = 1000,
	AutoMerge = false,
	AutoUpgradeTier = false,
}

local UIState = {
	Visible = true,
}

local PaperShared = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Shared")
local GlobalEvents = require(PaperShared:WaitForChild("GlobalEvents"))

local ActionCooldowns = {}

local function parseCurrency(text)
	local digits = tostring(text or ""):gsub("[^%d]", "")
	if digits == "" then
		return 0
	end
	return tonumber(digits) or 0
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
	return plots:FindFirstChild(LocalPlayer.Name)
end

local function getPlayerGuiMain()
	return PlayerGui:FindFirstChild("Main")
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

local function getButtonLabel(pathParts, labelName)
	local plot = getPlot()
	if not plot then
		return ""
	end

	local node = plot
	for _, segment in ipairs(pathParts) do
		node = node:FindFirstChild(segment)
		if not node then
			return ""
		end
	end

	local buttonPart = node:FindFirstChild("Button", true) or node:FindFirstChild("Hitbox", true)
	if not buttonPart then
		buttonPart = node
	end

	local ui = buttonPart:FindFirstChild("UI", true)
	if not ui then
		return ""
	end

	local label = ui:FindFirstChild(labelName, true)
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		return label.Text
	end

	return ""
end

local function getButtonCost(pathParts)
	return parseCurrency(getButtonLabel(pathParts, "Cost"))
end

local function getEggCount()
	return parseCurrency(getValueText({ "Eggs", "Amount", "Amt" }))
end

local function getCashAmount()
	return parseCurrency(getValueText({ "Currencies", "Cash", "List", "Amount" }))
end

local function isEggFrenzyActive()
	-- Prüfe ob das Egg Frenzy (x271) aktiv ist - das ist der UI Indicator
	local main = getPlayerGuiMain()
	if main then
		local events = main:FindFirstChild("Events")
		if events then
			local eggFrenzy = events:FindFirstChild("EggFrenzy")
			if eggFrenzy and eggFrenzy.Visible then
				return true
			end
		end
	end
	return false
end

-- Der echte Egg Multiplier (0,5x - 3,0x) wird alle ~30 Sekunden über eine
-- Notification bekannt gegeben ("Egg Multiplier rose/dropped to X.XXx!").
-- Wir hören auf diese Notifications und cachen den letzten bekannten Wert,
-- da die Notification selbst nur kurz sichtbar ist.
local CachedEggMultiplier = 1

local function parseEggMultiplierText(text)
	-- Erwartet Text wie "Egg Multiplier rose to 1.09x!" oder "dropped to 0.83x!"
	local value = text:match("to%s+([%d%.]+)x")
	if value then
		return tonumber(value)
	end
	return nil
end

local function setupEggMultiplierListener()
	local notifications = PlayerGui:FindFirstChild("Notifications")
	if not notifications then
		notifications = PlayerGui:WaitForChild("Notifications", 10)
	end
	if not notifications then return end

	local holder = notifications:FindFirstChild("Holder")
	if not holder then return end

	-- Beim Start: prüfe ob gerade eine Notification sichtbar ist
	for _, child in ipairs(holder:GetChildren()) do
		if child.Name == "Notification" then
			for _, d in ipairs(child:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text ~= "" then
					local val = parseEggMultiplierText(d.Text)
					if val then
						CachedEggMultiplier = val
					end
				end
			end
		end
	end

	holder.ChildAdded:Connect(function(child)
		if child.Name ~= "Notification" then return end
		task.spawn(function()
			task.wait(0.15) -- warte bis Label befüllt ist
			for _, d in ipairs(child:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text ~= "" then
					local val = parseEggMultiplierText(d.Text)
					if val then
						CachedEggMultiplier = val
					end
				end
			end
		end)
	end)
end

local function getEggMultiplier()
	return CachedEggMultiplier
end

local function getCharacterRoot()
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if not root then
		return nil
	end
	return character, root
end

local function tapPart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	if typeof(firetouchinterest) == "function" then
		pcall(function()
			firetouchinterest(root, part, 0)
			firetouchinterest(root, part, 1)
		end)
		return true
	end

	pcall(function()
		character:PivotTo(part.CFrame * CFrame.new(0, 3, 0))
	end)
	task.wait(0.12)
	return true
end

local function touchByPath(pathParts, preferredParts)
	local plot = getPlot()
	if not plot then
		return false
	end

	local node = plot
	for _, segment in ipairs(pathParts) do
		node = node:FindFirstChild(segment)
		if not node then
			return false
		end
	end

	for _, partName in ipairs(preferredParts or { "Button", "Hitbox" }) do
		local part = node:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			return tapPart(part)
		end
	end

	for _, descendant in ipairs(node:GetDescendants()) do
		if descendant:IsA("BasePart") and tapPart(descendant) then
			return true
		end
	end

	if node:IsA("BasePart") then
		return tapPart(node)
	end

	return false
end

local function touchAllPartsInNode(node)
	if not node then
		return false
	end

	local touched = false
	for _, descendant in ipairs(node:GetDescendants()) do
		if descendant:IsA("BasePart") and tapPart(descendant) then
			touched = true
		end
	end

	return touched
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

local function touchBestBuyChickenButton()
	local cash = getCashAmount()
	if cash <= Settings.ChickenCashReserve then
		return false
	end

	local plot = getPlot()
	if not plot then
		return false
	end

	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	-- Verwende immer Buy1 - kostengünstiger und zuverlässiger
	local buy1 = plot:FindFirstChild("Buttons")
	if not buy1 then return false end
	
	buy1 = buy1:FindFirstChild("BuyChickens")
	if not buy1 then return false end
	
	buy1 = buy1:FindFirstChild("Buy1")
	if not buy1 then return false end

	local buttonPart = buy1:FindFirstChild("Button")
	if not buttonPart then return false end

	local ok = pcall(function()
		-- Teleportiere zum Button
		root.CFrame = buttonPart.CFrame * CFrame.new(0, 3, 0)
		task.wait(0.05)

		-- Triggere firetouchinterest
		if typeof(firetouchinterest) == "function" then
			firetouchinterest(root, buttonPart, 0)
			task.wait(0.05)
			firetouchinterest(root, buttonPart, 1)
		end

		task.wait(0.05)
	end)

	return ok
end

local function collectEggs()
	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	local collected = false
	local eggsFolder = workspace:FindFirstChild("Eggs")

	if not eggsFolder then
		return false
	end

	-- Nur die Part.Touched Event Eier sammeln
	for _, egg in ipairs(eggsFolder:GetChildren()) do
		local eggPart = egg:FindFirstChild("Part", true)
		
		if eggPart and eggPart:IsA("BasePart") then
			local ok = pcall(function()
				if typeof(firetouchinterest) == "function" then
					firetouchinterest(root, eggPart, 0)
					task.wait(0.02)
					firetouchinterest(root, eggPart, 1)
				end
			end)
			if ok then
				collected = true
				task.wait(0.05)
			end
		end
	end

	return collected
end

local function collectMoney()
	local plot = getPlot()
	if not plot then
		return false
	end

	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	local collectMoney = plot:FindFirstChild("Buttons")
	if not collectMoney then return false end
	
	collectMoney = collectMoney:FindFirstChild("CollectMoney")
	if not collectMoney then return false end

	local buttonPart = collectMoney:FindFirstChild("Button")
	if not buttonPart then 
		buttonPart = collectMoney:FindFirstChild("Hitbox")
	end
	if not buttonPart then 
		buttonPart = collectMoney:FindFirstChild("Part")
	end
	if not buttonPart then
		for _, child in ipairs(collectMoney:GetDescendants()) do
			if child:IsA("BasePart") then
				buttonPart = child
				break
			end
		end
	end
	if not buttonPart then return false end

	local ok = pcall(function()
		if typeof(firetouchinterest) == "function" then
			firetouchinterest(root, buttonPart, 0)
			task.wait(0.05)
			firetouchinterest(root, buttonPart, 1)
		end
	end)

	return ok
end

local function shouldSellEggs()
	-- "Nur während Egg Multiplier verkaufen" = nur wenn Egg Frenzy (x271) aktiv ist
	if Settings.SellOnlyDuringEggFrenzy then
		if not isEggFrenzyActive() then
			return false
		end
	end

	-- Prüfe den Egg Multiplier (0,5-3,0) gegen Min/Max Settings
	local multiplier = getEggMultiplier()
	
	-- Wenn SellMultiplierMin > 0, prüfe Minimum
	if Settings.SellMultiplierMin > 0 and multiplier < Settings.SellMultiplierMin then
		return false
	end
	
	-- Wenn SellMultiplierMax > 0, prüfe Maximum
	if Settings.SellMultiplierMax > 0 and multiplier > Settings.SellMultiplierMax then
		return false
	end

	return true
end

local function mergeChickens()
	local plot = getPlot()
	if not plot then
		return false
	end

	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	local mergeChickens = plot:FindFirstChild("Buttons")
	if not mergeChickens then return false end
	
	mergeChickens = mergeChickens:FindFirstChild("MergeChickens")
	if not mergeChickens then return false end

	local buttonPart = mergeChickens:FindFirstChild("Button")
	if not buttonPart then 
		buttonPart = mergeChickens:FindFirstChild("Hitbox")
	end
	if not buttonPart then 
		buttonPart = mergeChickens:FindFirstChild("Part")
	end
	if not buttonPart then
		for _, child in ipairs(mergeChickens:GetDescendants()) do
			if child:IsA("BasePart") then
				buttonPart = child
				break
			end
		end
	end
	if not buttonPart then return false end

	local ok = pcall(function()
		if typeof(firetouchinterest) == "function" then
			firetouchinterest(root, buttonPart, 0)
			task.wait(0.05)
			firetouchinterest(root, buttonPart, 1)
		end
	end)

	return ok
end

local function upgradeTier()
	local plot = getPlot()
	if not plot then
		return false
	end

	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	local upgradeTier = plot:FindFirstChild("Buttons")
	if not upgradeTier then return false end
	
	upgradeTier = upgradeTier:FindFirstChild("UpgradeBuyTier")
	if not upgradeTier then return false end

	local buttonPart = upgradeTier:FindFirstChild("Button")
	if not buttonPart then 
		buttonPart = upgradeTier:FindFirstChild("Hitbox")
	end
	if not buttonPart then 
		buttonPart = upgradeTier:FindFirstChild("Part")
	end
	if not buttonPart then
		for _, child in ipairs(upgradeTier:GetDescendants()) do
			if child:IsA("BasePart") then
				buttonPart = child
				break
			end
		end
	end
	if not buttonPart then return false end

	local ok = pcall(function()
		if typeof(firetouchinterest) == "function" then
			firetouchinterest(root, buttonPart, 0)
			task.wait(0.05)
			firetouchinterest(root, buttonPart, 1)
		end
	end)

	return ok
end

local function sellEggs()
	local plot = getPlot()
	if not plot then
		return false
	end

	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	-- Finde DepositEggs Button
	local depositEggs = plot:FindFirstChild("Buttons")
	if not depositEggs then return false end
	
	depositEggs = depositEggs:FindFirstChild("DepositEggs")
	if not depositEggs then return false end

	-- Versuche verschiedene Part Namen
	local buttonPart = depositEggs:FindFirstChild("Button")
	if not buttonPart then 
		buttonPart = depositEggs:FindFirstChild("Hitbox")
	end
	if not buttonPart then 
		buttonPart = depositEggs:FindFirstChild("Part")
	end
	if not buttonPart then
		-- Versuche Descendants
		for _, child in ipairs(depositEggs:GetDescendants()) do
			if child:IsA("BasePart") then
				buttonPart = child
				break
			end
		end
	end
	
	if not buttonPart then return false end

	local ok = pcall(function()
		if typeof(firetouchinterest) == "function" then
			firetouchinterest(root, buttonPart, 0)
			task.wait(0.05)
			firetouchinterest(root, buttonPart, 1)
		end
	end)

	return ok
end

local function buyChicken()
	return touchBestBuyChickenButton()
end

local function mergeChickens()
	local plot = getPlot()
	if not plot then
		return false
	end

	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	local mergeChickens = plot:FindFirstChild("Buttons")
	if not mergeChickens then return false end
	
	mergeChickens = mergeChickens:FindFirstChild("MergeChickens")
	if not mergeChickens then return false end

	local buttonPart = mergeChickens:FindFirstChild("Button")
	if not buttonPart then 
		buttonPart = mergeChickens:FindFirstChild("Hitbox")
	end
	if not buttonPart then return false end

	local ok = pcall(function()
		if typeof(firetouchinterest) == "function" then
			firetouchinterest(root, buttonPart, 0)
			task.wait(0.05)
			firetouchinterest(root, buttonPart, 1)
		end
	end)

	return ok
end

local function upgradeTier()
	local plot = getPlot()
	if not plot then
		return false
	end

	local character, root = getCharacterRoot()
	if not character or not root then
		return false
	end

	local upgradeTier = plot:FindFirstChild("Buttons")
	if not upgradeTier then return false end
	
	upgradeTier = upgradeTier:FindFirstChild("UpgradeBuyTier")
	if not upgradeTier then return false end

	local buttonPart = upgradeTier:FindFirstChild("Button")
	if not buttonPart then 
		buttonPart = upgradeTier:FindFirstChild("Hitbox")
	end
	if not buttonPart then return false end

	local ok = pcall(function()
		if typeof(firetouchinterest) == "function" then
			firetouchinterest(root, buttonPart, 0)
			task.wait(0.05)
			firetouchinterest(root, buttonPart, 1)
		end
	end)

	return ok
end

local function setSetting(name, value)
	Settings[name] = value
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoPlayUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(500, 520)
Main.Position = UDim2.new(0, 24, 0.5, -260)
Main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
Main.BorderSizePixel = 0
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 14)
MainCorner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(65, 85, 120)
Stroke.Thickness = 1
Stroke.Transparency = 0.2
Stroke.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 54)
Header.BackgroundColor3 = Color3.fromRGB(25, 25, 34)
Header.BorderSizePixel = 0
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 14)
HeaderCorner.Parent = Header

local HeaderMask = Instance.new("Frame")
HeaderMask.Size = UDim2.new(1, 0, 0, 14)
HeaderMask.Position = UDim2.new(0, 0, 1, -14)
HeaderMask.BackgroundColor3 = Header.BackgroundColor3
HeaderMask.BorderSizePixel = 0
HeaderMask.Parent = Header

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(16, 0)
Title.Size = UDim2.new(1, -120, 1, 0)
Title.Font = Enum.Font.GothamBold
Title.Text = "AutoPlay Controller"
Title.TextColor3 = Color3.fromRGB(245, 245, 250)
Title.TextSize = 18
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local ToggleGuiButton = Instance.new("TextButton")
ToggleGuiButton.Size = UDim2.fromOffset(86, 30)
ToggleGuiButton.Position = UDim2.new(1, -102, 0, 12)
ToggleGuiButton.BackgroundColor3 = Color3.fromRGB(56, 74, 122)
ToggleGuiButton.BorderSizePixel = 0
ToggleGuiButton.Font = Enum.Font.GothamSemibold
ToggleGuiButton.Text = "Hide"
ToggleGuiButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleGuiButton.TextSize = 14
ToggleGuiButton.Parent = Header

local ToggleButtonCorner = Instance.new("UICorner")
ToggleButtonCorner.CornerRadius = UDim.new(0, 10)
ToggleButtonCorner.Parent = ToggleGuiButton

local dragging = false
local dragStart = nil
local startPosition = nil

Header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPosition = Main.Position
	end
end)

Header.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging or not dragStart or not startPosition then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local delta = input.Position - dragStart
	Main.Position = UDim2.new(
		startPosition.X.Scale,
		startPosition.X.Offset + delta.X,
		startPosition.Y.Scale,
		startPosition.Y.Offset + delta.Y
	)
end)

local Body = Instance.new("ScrollingFrame")
Body.BackgroundTransparency = 1
Body.BorderSizePixel = 0
Body.Position = UDim2.fromOffset(0, 62)
Body.Size = UDim2.new(1, 0, 1, -72)
Body.ScrollBarThickness = 4
Body.ScrollBarImageColor3 = Color3.fromRGB(100, 120, 170)
Body.CanvasSize = UDim2.fromOffset(0, 0)
Body.AutomaticCanvasSize = Enum.AutomaticSize.Y
Body.Parent = Main

local BodyPadding = Instance.new("UIPadding")
BodyPadding.PaddingLeft = UDim.new(0, 14)
BodyPadding.PaddingRight = UDim.new(0, 14)
BodyPadding.PaddingTop = UDim.new(0, 4)
BodyPadding.PaddingBottom = UDim.new(0, 10)
BodyPadding.Parent = Body

local List = Instance.new("UIListLayout")
List.Padding = UDim.new(0, 10)
List.SortOrder = Enum.SortOrder.LayoutOrder
List.Parent = Body

local StatusLabel = Instance.new("TextLabel")
StatusLabel.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
StatusLabel.BorderSizePixel = 0
StatusLabel.Size = UDim2.new(1, 0, 0, 42)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.Text = "Status: idle"
StatusLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
StatusLabel.TextSize = 14
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = Body

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 10)
StatusCorner.Parent = StatusLabel

local StatusPadding = Instance.new("UIPadding")
StatusPadding.PaddingLeft = UDim.new(0, 12)
StatusPadding.Parent = StatusLabel

local function makeRow(height, titleText)
	local Row = Instance.new("Frame")
	Row.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
	Row.BorderSizePixel = 0
	Row.Size = UDim2.new(1, 0, 0, height)

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 10)
	Corner.Parent = Row

	local Label = Instance.new("TextLabel")
	Label.BackgroundTransparency = 1
	Label.Position = UDim2.fromOffset(12, 6)
	Label.Size = UDim2.new(1, -24, 0, 20)
	Label.Font = Enum.Font.GothamSemibold
	Label.Text = titleText
	Label.TextColor3 = Color3.fromRGB(245, 245, 250)
	Label.TextSize = 14
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Row

	return Row
end

local function makeToggleRow(titleText, settingKey)
	local Row = makeRow(58, titleText)
	Row.Parent = Body

	local Button = Instance.new("TextButton")
	Button.Size = UDim2.fromOffset(84, 28)
	Button.Position = UDim2.new(1, -96, 0, 15)
	Button.BorderSizePixel = 0
	Button.Font = Enum.Font.GothamSemibold
	Button.TextSize = 13
	Button.Parent = Row

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 9)
	Corner.Parent = Button

	local function refresh()
		local enabled = Settings[settingKey]
		Button.Text = enabled and "An" or "Aus"
		Button.BackgroundColor3 = enabled and Color3.fromRGB(68, 130, 90) or Color3.fromRGB(80, 82, 94)
		Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	Button.Activated:Connect(function()
		setSetting(settingKey, not Settings[settingKey])
		refresh()
	end)

	refresh()
	return Row
end

local function makeNumberRow(titleText, settingKey, minValue, maxValue)
	local Row = makeRow(70, titleText)
	Row.Parent = Body

	local Box = Instance.new("TextBox")
	Box.Size = UDim2.new(0, 124, 0, 28)
	Box.Position = UDim2.new(1, -136, 0, 14)
	Box.BorderSizePixel = 0
	Box.BackgroundColor3 = Color3.fromRGB(40, 40, 54)
	Box.Font = Enum.Font.GothamSemibold
	Box.TextColor3 = Color3.fromRGB(255, 255, 255)
	Box.TextSize = 13
	Box.ClearTextOnFocus = false
	Box.Text = tostring(Settings[settingKey])
	Box.Parent = Row

	local BoxCorner = Instance.new("UICorner")
	BoxCorner.CornerRadius = UDim.new(0, 9)
	BoxCorner.Parent = Box

	local Hint = Instance.new("TextLabel")
	Hint.BackgroundTransparency = 1
	Hint.Position = UDim2.fromOffset(12, 30)
	Hint.Size = UDim2.new(1, -156, 0, 24)
	Hint.Font = Enum.Font.Gotham
	Hint.Text = string.format("Bereich: %s - %s", tostring(minValue), tostring(maxValue))
	Hint.TextColor3 = Color3.fromRGB(160, 165, 180)
	Hint.TextSize = 12
	Hint.TextXAlignment = Enum.TextXAlignment.Left
	Hint.Parent = Row

	Box.FocusLost:Connect(function()
		local number = tonumber(Box.Text)
		if not number then
			Box.Text = tostring(Settings[settingKey])
			return
		end

		number = math.clamp(math.floor(number + 0.5), minValue, maxValue)
		Settings[settingKey] = number
		Box.Text = tostring(number)
	end)

	return Row
end

local function makeDecimalRow(titleText, settingKey, minValue, maxValue)
	local Row = makeRow(70, titleText)
	Row.Parent = Body

	local Box = Instance.new("TextBox")
	Box.Size = UDim2.new(0, 124, 0, 28)
	Box.Position = UDim2.new(1, -136, 0, 14)
	Box.BorderSizePixel = 0
	Box.BackgroundColor3 = Color3.fromRGB(40, 40, 54)
	Box.Font = Enum.Font.GothamSemibold
	Box.TextColor3 = Color3.fromRGB(255, 255, 255)
	Box.TextSize = 13
	Box.ClearTextOnFocus = false
	Box.Text = tostring(Settings[settingKey])
	Box.Parent = Row

	local BoxCorner = Instance.new("UICorner")
	BoxCorner.CornerRadius = UDim.new(0, 9)
	BoxCorner.Parent = Box

	local Hint = Instance.new("TextLabel")
	Hint.BackgroundTransparency = 1
	Hint.Position = UDim2.fromOffset(12, 30)
	Hint.Size = UDim2.new(1, -156, 0, 24)
	Hint.Font = Enum.Font.Gotham
	Hint.Text = string.format("Bereich: %s - %s", tostring(minValue), tostring(maxValue))
	Hint.TextColor3 = Color3.fromRGB(160, 165, 180)
	Hint.TextSize = 12
	Hint.TextXAlignment = Enum.TextXAlignment.Left
	Hint.Parent = Row

	Box.FocusLost:Connect(function()
		local number = tonumber(Box.Text)
		if not number then
			Box.Text = tostring(Settings[settingKey])
			return
		end

		number = math.clamp(number, minValue, maxValue)
		Settings[settingKey] = number
		Box.Text = tostring(number)
	end)

	return Row
end

makeToggleRow("Auto-Collect Eggs", "AutoCollectEggs")
makeToggleRow("Auto-Collect Money", "AutoCollectMoney")
makeToggleRow("Auto-Sell Eggs", "AutoSellEggs")
makeDecimalRow("Min-Egg-Multiplier", "SellMultiplierMin", 0.5, 999999)
makeDecimalRow("Max-Egg-Multiplier", "SellMultiplierMax", 0.5, 999999)
makeToggleRow("Nur während Egg Multiplier verkaufen", "SellOnlyDuringEggFrenzy")
makeToggleRow("Auto-Buy Chicken", "AutoBuyChicken")
makeNumberRow("Mindest-Cash-Reserve", "ChickenCashReserve", 0, 999999999)
makeToggleRow("Auto-Merge", "AutoMerge")
makeToggleRow("Auto-Upgrade Tier", "AutoUpgradeTier")

local Footer = Instance.new("TextLabel")
Footer.BackgroundTransparency = 1
Footer.Size = UDim2.new(1, 0, 0, 34)
Footer.Font = Enum.Font.Gotham
Footer.Text = "Auto-wires to the live plot buttons and HUD in Chicken Farm."
Footer.TextColor3 = Color3.fromRGB(150, 155, 170)
Footer.TextSize = 12
Footer.TextWrapped = true
Footer.Parent = Body

local function updateStatus(message)
	StatusLabel.Text = message
end

local function setVisible(visible)
	UIState.Visible = visible
	Body.Visible = visible
	Main.Size = visible and UDim2.fromOffset(500, 520) or UDim2.fromOffset(500, 54)
	ToggleGuiButton.Text = visible and "Hide" or "Show"
end

ToggleGuiButton.Activated:Connect(function()
	setVisible(not UIState.Visible)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.RightShift then
		setVisible(not UIState.Visible)
	end
end)

task.spawn(function()
	while task.wait(0.35) do
		if Settings.AutoCollectEggs then
			runWithCooldown("AutoCollectEggs", 1.5, collectEggs)
		end

		if Settings.AutoCollectMoney then
			runWithCooldown("AutoCollectMoney", 1.5, collectMoney)
		end

		if Settings.AutoSellEggs then
			if shouldSellEggs() then
				runWithCooldown("AutoSellEggs", 1.0, sellEggs)
			end
		end

		if Settings.AutoBuyChicken then
			runWithCooldown("AutoBuyChicken", 0.8, buyChicken)
		end

		if Settings.AutoMerge then
			runWithCooldown("AutoMerge", 1.0, mergeChickens)
		end

		if Settings.AutoUpgradeTier then
			runWithCooldown("AutoUpgradeTier", 2.0, upgradeTier)
		end

		local activeCount = 0
		for _, key in ipairs({
			"AutoCollectEggs",
			"AutoCollectMoney",
			"AutoSellEggs",
			"AutoBuyChicken",
			"AutoMerge",
			"AutoUpgradeTier",
		}) do
			if Settings[key] then
				activeCount += 1
			end
		end

		updateStatus(string.format(
			"Status: %d aktiv | Cash: %s | Eggs: %s | Multiplier: x%s",
			activeCount,
			formatCurrency(getCashAmount()),
			formatCurrency(getEggCount()),
			tostring(getEggMultiplier())
		))
	end
end)

task.spawn(function()
	while task.wait(5) do
		TweenService:Create(Stroke, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Transparency = 0.15 + math.random() * 0.2,
		}):Play()
	end
end)

setVisible(true)
setupEggMultiplierListener()