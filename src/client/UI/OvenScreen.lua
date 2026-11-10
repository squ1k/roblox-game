-- Экран Теплового шкафа: "микроволновка" с окошками по уровню (закрытые до MaxSlots серые),
-- в каждом попс, прогресс и таймер, "Забрать"/"Отменить". Внизу что дает следующий уровень и
-- "Улучшить", плюс выбор попса из Холодильника для свободного окошка.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local Screen = require(script.Parent:WaitForChild("Screen"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local create = Widgets.Create

local Oven = Balance.Oven

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function describe(pop)
	local skebob = Families.SkebobById[pop.Id]
	local rarity = skebob and Balance.RarityById[skebob.Rarity] or Balance.Rarities[1]
	local family = skebob and Families.ById[skebob.Family]
	return rarity, (if family then family.Name .. " · " else "") .. rarity.Name
end

return function(parent: Instance, notify)
	local picking = false
	local overlay, window, setTitle = Screen(parent, "OvenScreen", "", function()
		picking = false
	end)

	-- Корпус микроволновки
	local body = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(70, 75, 90),
		Position = UDim2.fromOffset(20, 80),
		Size = UDim2.new(1, -40, 1, -220),
		ZIndex = 22,
		Parent = window,
	}, {
		Widgets.Corner(UDim.new(0, 20)),
		Widgets.Stroke(4),
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 14),
		}),
	})
	local footer = Widgets.Label({
		TextColor3 = Theme.Colors.TextDark,
		Outline = false,
		Font = Theme.FontBody,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -20),
		Size = UDim2.new(0.5, 0, 0, 100),
		MaxTextSize = 20,
		TextWrapped = true,
		ZIndex = 22,
		Parent = window,
	})
	local upgradeButton = Widgets.Button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(280, 64),
		BackgroundColor3 = Theme.Colors.Buy,
		ZIndex = 23,
		Parent = window,
	}, function()
		Remotes.OvenUpgrade:FireServer()
	end)
	local fromFridge = Widgets.Button({
		Text = Strings.OvenFromFridge,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -94),
		Size = UDim2.fromOffset(280, 52),
		BackgroundColor3 = Theme.Colors.Backpack,
		ZIndex = 23,
		Parent = window,
	})

	local timers = {} -- { Label, Bar, Entry }
	local render

	local function windowSlot(slot: number, entry, unlocked: boolean)
		local glass = create("Frame", {
			LayoutOrder = slot,
			BackgroundColor3 = if unlocked then Color3.fromRGB(30, 35, 45) else Color3.fromRGB(110, 110, 120),
			Size = UDim2.new(0.22, 0, 0.86, 0),
			ZIndex = 23,
			Parent = body,
		}, { Widgets.Corner(), Widgets.Stroke(3) })
		if not unlocked then
			Widgets.Label({
				Text = "🔒",
				Size = UDim2.fromScale(1, 0.5),
				Position = UDim2.fromScale(0, 0.25),
				Outline = false,
				ZIndex = 24,
				Parent = glass,
			})
			return
		end
		if not entry then
			Widgets.Label({
				Text = Strings.OvenEmpty,
				Size = UDim2.new(1, -10, 0, 30),
				Position = UDim2.new(0, 5, 0.45, 0),
				MaxTextSize = 20,
				ZIndex = 24,
				Parent = glass,
			})
			return
		end
		local rarity, text = describe(entry.Pop)
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 14),
			Size = UDim2.fromOffset(70, 70),
			BackgroundColor3 = rarity.Glaze,
			ZIndex = 24,
			Parent = glass,
		}, { Widgets.Corner(UDim.new(1, 0)) })
		Widgets.Label({
			Text = text,
			Size = UDim2.new(1, -10, 0, 40),
			Position = UDim2.fromOffset(5, 90),
			MaxTextSize = 16,
			TextWrapped = true,
			ZIndex = 24,
			Parent = glass,
		})
		local track = create("Frame", {
			BackgroundColor3 = Color3.fromRGB(60, 60, 70),
			Position = UDim2.new(0, 8, 0, 136),
			Size = UDim2.new(1, -16, 0, 16),
			ZIndex = 24,
			Parent = glass,
		}, { Widgets.Corner(UDim.new(1, 0)) })
		local bar = create(
			"Frame",
			{ BackgroundColor3 = Theme.Colors.Coin, Size = UDim2.fromScale(0, 1), ZIndex = 25, Parent = track },
			{ Widgets.Corner(UDim.new(1, 0)) }
		)
		local timeLabel = Widgets.Label({
			Size = UDim2.new(1, -10, 0, 28),
			Position = UDim2.fromOffset(5, 156),
			MaxTextSize = 22,
			ZIndex = 24,
			Parent = glass,
		})
		local ready = workspace:GetServerTimeNow() >= entry.StartedAt + entry.Duration
		Widgets.Button({
			Text = if ready then Strings.OvenCollect else Strings.OvenCancel,
			BackgroundColor3 = if ready then Theme.Colors.Buy else Theme.Colors.Drop,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -16, 0, 48),
			ZIndex = 25,
			Parent = glass,
		}, function()
			if ready then
				Remotes.OvenCollect:FireServer(slot)
			else
				Remotes.OvenCancel:FireServer(slot)
			end
		end)
		table.insert(timers, { Label = timeLabel, Bar = bar, Entry = entry, Ready = ready })
	end

	local function renderPicker(profile)
		for index, pop in profile.Fridge do
			local rarity, text = describe(pop)
			Widgets.Button({
				LayoutOrder = index,
				Text = text,
				BackgroundColor3 = rarity.Glaze,
				Size = UDim2.new(0.22, 0, 0.4, 0),
				ZIndex = 24,
				Parent = body,
			}, function()
				picking = false
				Remotes.OvenStart:FireServer(index)
			end)
		end
		if #profile.Fridge == 0 then
			Widgets.Label({ Text = Strings.EmptyFridge, Size = UDim2.new(1, 0, 0, 40), ZIndex = 24, Parent = body })
		end
	end

	function render()
		local profile = ClientState.Profile
		if not profile then
			return
		end
		table.clear(timers)
		for _, child in body:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local level = Oven.Levels[profile.OvenLevel] or Oven.Levels[1]
		local nextLevel = Oven.Levels[profile.OvenLevel + 1]
		setTitle(string.format(Strings.OvenTitle, profile.OvenLevel))
		if picking then
			setTitle(Strings.OvenPick)
			renderPicker(profile)
		else
			for slot = 1, Oven.MaxSlots do
				windowSlot(slot, profile.Ovens[slot], slot <= level.Slots)
			end
		end
		footer.Text = string.format(Strings.OvenNow, level.Slots, tostring(level.Speed))
			.. (
				if nextLevel
					then "\n" .. string.format(Strings.OvenNext, nextLevel.Slots, tostring(nextLevel.Speed))
					else ""
			)
		upgradeButton.Text = if nextLevel
			then string.format(Strings.OvenUpgrade, NumberFormat.Short(nextLevel.Price))
			else Strings.OvenMax
		upgradeButton.Active = nextLevel ~= nil
		upgradeButton.BackgroundColor3 = if nextLevel then Theme.Colors.Buy else Theme.Colors.Locked
		local free = #profile.Ovens < level.Slots
		fromFridge.Active = free
		fromFridge.BackgroundColor3 = if free then Theme.Colors.Backpack else Theme.Colors.Locked
	end

	fromFridge.Activated:Connect(function()
		if fromFridge.Active then
			picking = not picking
			render()
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not overlay.Visible then
			return
		end
		local now = workspace:GetServerTimeNow()
		for _, timer in timers do
			local entry = timer.Entry
			local left = entry.StartedAt + entry.Duration - now
			timer.Bar.Size = UDim2.fromScale(math.clamp(1 - left / entry.Duration, 0, 1), 1)
			timer.Label.Text = if left <= 0 then Strings.OvenReady else formatTime(left)
			if left <= 0 and not timer.Ready then
				timer.Ready = true
				task.defer(render) -- кнопка "Отменить" сменится на "Забрать"
			end
		end
	end)

	ClientState.ProfileChanged:Connect(function()
		if overlay.Visible then
			render()
		end
	end)

	local screen = {}
	function screen.Open()
		picking = false
		overlay.Visible = true
		render()
		ClientState.Refresh()
	end
	return screen
end
