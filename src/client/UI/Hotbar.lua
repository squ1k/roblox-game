-- Нижний центр: 3 слота расходников. Клавиши 1-3 на ПК, тап на мобилках.
-- Пока игрок несет Кейк-попс, слоты серые с замком.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local Strings = require(Shared:WaitForChild("Config"):WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local create = Widgets.Create

local player = Players.LocalPlayer

local SLOTS = {
	{ Item = "BananaTrap", Icon = "🍌", Max = Balance.BananaTrap.MaxCarry },
	{ Item = false, Icon = "" },
	{ Item = false, Icon = "" },
}
local SLOT_SIZE = 84
local GAP = 12
local KEYS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 }

return function(parent: Instance)
	local width = SLOT_SIZE * #SLOTS + GAP * (#SLOTS - 1)
	local bar = create("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(width, SLOT_SIZE + 22),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local lockedHint = Widgets.Label({
		Name = "LockedHint",
		Text = Strings.HotbarLocked,
		Size = UDim2.new(1, 0, 0, 20),
		MaxTextSize = 18,
		Visible = false,
		Parent = bar,
	})

	local slotViews = {}
	for index, slot in SLOTS do
		local button = Widgets.Button({
			Name = "Slot" .. index,
			BackgroundColor3 = Theme.Colors.Slot,
			Position = UDim2.fromOffset((index - 1) * (SLOT_SIZE + GAP), 22),
			Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
			Parent = bar,
		}, function()
			Remotes.UseHotbar:FireServer(index)
		end)
		Widgets.Label({
			Name = "Icon",
			Text = if slot.Item then slot.Icon else Strings.SlotSoon,
			TextColor3 = if slot.Item then Theme.Colors.Text else Theme.Colors.Locked,
			Outline = slot.Item ~= false,
			Size = UDim2.fromScale(if slot.Item then 0.7 else 0.8, 0.7),
			Position = UDim2.fromScale(if slot.Item then 0.15 else 0.1, 0.12),
			MaxTextSize = if slot.Item then 56 else 18,
			Parent = button,
		})
		local count = Widgets.Label({
			Name = "Count",
			Text = "",
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(1, -8, 0, 20),
			Position = UDim2.new(0, 0, 1, -22),
			MaxTextSize = 18,
			Parent = button,
		})
		local key = Widgets.Label({
			Name = "Key",
			Text = tostring(index),
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(20, 18),
			Position = UDim2.fromOffset(6, 4),
			MaxTextSize = 16,
			Parent = button,
		})
		local lock = create("Frame", {
			Name = "Lock",
			BackgroundColor3 = Theme.Colors.Locked,
			BackgroundTransparency = 0.25,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 5,
			Parent = button,
		}, { Widgets.Corner() })
		Widgets.Label({
			Text = "🔒",
			Size = UDim2.fromScale(0.6, 0.6),
			Position = UDim2.fromScale(0.2, 0.2),
			Outline = false,
			ZIndex = 6,
			Parent = lock,
		})
		slotViews[index] = { Button = button, Count = count, Key = key, Lock = lock }
	end

	local function refreshCounts(profile)
		for index, slot in SLOTS do
			local view = slotViews[index]
			if slot.Item and profile then
				local have = profile.Items and profile.Items[slot.Item] or 0
				view.Count.Text = have .. "/" .. slot.Max
			else
				view.Count.Text = ""
			end
		end
	end

	local function refreshLock()
		local busy = player:GetAttribute("Carrying") == true or player:GetAttribute("Stunned") == true
		local outsideField = player:GetAttribute("PvpEnabled") ~= true
		local locked = busy or outsideField
		lockedHint.Text = if busy then Strings.HotbarLocked else Strings.OnlyInField
		lockedHint.Visible = locked
		for _, view in slotViews do
			view.Lock.Visible = locked
			view.Button.Active = not locked
		end
	end

	local function refreshKeyHints()
		local keyboard = UserInputService.KeyboardEnabled
		for _, view in slotViews do
			view.Key.Visible = keyboard
		end
	end

	ClientState.ProfileChanged:Connect(refreshCounts)
	player:GetAttributeChangedSignal("Carrying"):Connect(refreshLock)
	player:GetAttributeChangedSignal("Stunned"):Connect(refreshLock)
	player:GetAttributeChangedSignal("PvpEnabled"):Connect(refreshLock)
	UserInputService.LastInputTypeChanged:Connect(refreshKeyHints)
	refreshCounts(ClientState.Profile)
	refreshLock()
	refreshKeyHints()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local index = KEYS[input.KeyCode]
		if index and not slotViews[index].Lock.Visible then
			Widgets.Pop(slotViews[index].Button)
			Remotes.UseHotbar:FireServer(index)
		end
	end)

	return bar
end
