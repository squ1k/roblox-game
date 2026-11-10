-- Алтарь Слияния: слева "алтарь" (кристалл и 3 круглых слота вокруг, шанс крупно), справа выбор.
-- "Риск": 3 попса одного тира и Семейства из Холодильника, шанс RiskChance (+бонус Токсичного
-- Скебобса на пьедестале). "Гарант": 10 одинаковых свободных Скебобсов, шанс 100%.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local Screen = require(script.Parent:WaitForChild("Screen"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local create = Widgets.Create

local Merge = Balance.Merge
local RUN_LOCK_SECONDS = 2 -- кнопка "Слияние" блокируется на время анимации
local SLOT_RADIUS = 105 -- слоты по кругу вокруг кристалла

local function rarityOf(petId: string)
	local skebob = Families.SkebobById[petId]
	return skebob and Balance.RarityById[skebob.Rarity] or Balance.Rarities[1], skebob
end

return function(parent: Instance, notify)
	local overlay, window = Screen(parent, "Merge", Strings.MergeTitle)

	-- Переключатель режима сверху
	local header = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -80, 0, 14),
		Size = UDim2.new(0.6, 0, 0, 52),
		ZIndex = 22,
		Parent = window,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 10),
		}),
	})

	-- Алтарь
	local altar = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(60, 40, 80),
		Position = UDim2.fromOffset(20, 80),
		Size = UDim2.new(0.42, -20, 1, -100),
		ZIndex = 22,
		Parent = window,
	}, { Widgets.Corner(UDim.new(0, 20)), Widgets.Stroke(4) })
	local crystal = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(80, 80),
		BackgroundColor3 = Color3.fromRGB(200, 140, 255),
		Rotation = 45,
		ZIndex = 23,
		Parent = altar,
	}, { Widgets.Corner(UDim.new(0, 12)), Widgets.Stroke(3) })
	local slots = {}
	for index = 1, 3 do
		local angle = math.rad(-90 + (index - 1) * 120)
		slots[index] = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * SLOT_RADIUS, 0.42, math.sin(angle) * SLOT_RADIUS),
			Size = UDim2.fromOffset(74, 74),
			BackgroundColor3 = Color3.fromRGB(110, 90, 130),
			ZIndex = 23,
			Parent = altar,
		}, { Widgets.Corner(UDim.new(1, 0)), Widgets.Stroke(3) })
	end
	local chanceLabel = Widgets.Label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.new(1, -20, 0, 56),
		MaxTextSize = 46,
		TextColor3 = Theme.Colors.Coin,
		ZIndex = 23,
		Parent = altar,
	})
	local runButton = Widgets.Button({
		Text = Strings.MergeRun,
		BackgroundColor3 = Theme.Colors.Buy,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(1, -40, 0, 70),
		ZIndex = 24,
		Parent = altar,
	})

	-- Выбор
	local hint = Widgets.Label({
		TextColor3 = Theme.Colors.TextDark,
		Outline = false,
		Font = Theme.FontBody,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0.42, 12, 0, 80),
		Size = UDim2.new(0.58, -32, 0, 24),
		MaxTextSize = 18,
		ZIndex = 22,
		Parent = window,
	})
	local content = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.42, 12, 0, 110),
		Size = UDim2.new(0.58, -32, 1, -130),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = window,
	})

	local mode = "Risk"
	local selected = {} -- режим Риск: индексы Холодильника; Гарант: { skebobId }
	local lockedUntil = 0
	local render
	local modeButtons = {}

	for index, spec in
		{ { Id = "Risk", Title = Strings.MergeRisk }, { Id = "Guaranteed", Title = Strings.MergeGuaranteed } }
	do
		modeButtons[spec.Id] = Widgets.Button({
			Text = spec.Title,
			LayoutOrder = index,
			Size = UDim2.new(0.48, 0, 1, 0),
			BackgroundColor3 = Theme.Colors.TabIdle,
			ZIndex = 23,
			Parent = header,
		}, function()
			mode = spec.Id
			selected = {}
			render()
		end)
	end

	local function card(order: number, petId: string, subtitle: string, isSelected: boolean, enabled: boolean, onClick)
		local rarity = rarityOf(petId)
		local button = Widgets.Button({
			LayoutOrder = order,
			BackgroundColor3 = if isSelected
				then Theme.Colors.Buy
				elseif enabled then Color3.new(1, 1, 1)
				else Theme.Colors.Locked,
			ZIndex = 23,
			Parent = content,
		}, if enabled then onClick else nil)
		button.Active = enabled
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(52, 52),
			BackgroundColor3 = rarity.Glaze,
			ZIndex = 24,
			Parent = button,
		}, { Widgets.Corner(UDim.new(1, 0)) })
		Widgets.Label({
			Text = subtitle,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			Font = Theme.FontBody,
			Size = UDim2.new(1, -8, 0, 44),
			Position = UDim2.fromOffset(4, 62),
			MaxTextSize = 14,
			TextWrapped = true,
			ZIndex = 24,
			Parent = button,
		})
	end

	local function toxicBonus(profile): number
		for _, pedestal in profile.Pedestals do
			local pet = pedestal.Pet and profile.Pets[pedestal.Pet]
			if pet and pet.Mutation == "Toxic" then
				return Balance.Weather.ToxicMergeBonus
			end
		end
		return 0
	end

	local function paintSlots(colors)
		for index, slot in slots do
			slot.BackgroundColor3 = colors[index] or Color3.fromRGB(110, 90, 130)
		end
	end

	local function renderRisk(profile)
		hint.Text = Strings.MergePickRisk
		local first = selected[1] and profile.Fridge[selected[1]]
		local _, firstSkebob = if first then rarityOf(first.Id) else nil
		local colors = {}
		for at, index in selected do
			local pop = profile.Fridge[index]
			colors[at] = pop and rarityOf(pop.Id).Glaze
		end
		paintSlots(colors)
		for index, pop in profile.Fridge do
			local rarity, skebob = rarityOf(pop.Id)
			local isSelected = table.find(selected, index) ~= nil
			local fits = skebob ~= nil and Balance.Rarities[rarity.Order + 1] ~= nil
			if fits and firstSkebob then
				fits = skebob.Rarity == firstSkebob.Rarity and skebob.Family == firstSkebob.Family
			end
			local family = skebob and Families.ById[skebob.Family]
			card(
				index,
				pop.Id,
				(if family then family.Name .. " · " else "") .. rarity.Name,
				isSelected,
				fits or isSelected,
				function()
					local at = table.find(selected, index)
					if at then
						table.remove(selected, at)
					elseif #selected < Merge.RiskAmount then
						table.insert(selected, index)
					end
					render()
				end
			)
		end
		chanceLabel.Text =
			string.format(Strings.MergeChance, math.floor((Merge.RiskChance + toxicBonus(profile)) * 100 + 0.5))
		return #selected == Merge.RiskAmount
	end

	local function renderGuaranteed(profile)
		hint.Text = Strings.MergePickGuaranteed
		local onPedestal = {}
		for _, pedestal in profile.Pedestals do
			if pedestal.Pet then
				onPedestal[pedestal.Pet] = true
			end
		end
		local counts = {}
		for uid, pet in profile.Pets do
			if not onPedestal[uid] and not pet.Locked then
				counts[pet.Id] = (counts[pet.Id] or 0) + 1
			end
		end
		local order = 0
		for petId, count in counts do
			order += 1
			local rarity = rarityOf(petId)
			local enough = count >= Merge.GuaranteedAmount and Balance.Rarities[rarity.Order + 1] ~= nil
			card(
				order,
				petId,
				petId .. "\n" .. count .. "/" .. Merge.GuaranteedAmount,
				selected[1] == petId,
				enough,
				function()
					selected = { petId }
					render()
				end
			)
		end
		local color = selected[1] and rarityOf(selected[1]).Glaze
		paintSlots({ color, color, color })
		chanceLabel.Text = string.format(Strings.MergeChance, 100)
		return selected[1] ~= nil
	end

	function render()
		for id, button in modeButtons do
			button.BackgroundColor3 = if id == mode then Theme.Colors.TabActive else Theme.Colors.TabIdle
		end
		for _, child in content:GetChildren() do
			child:Destroy()
		end
		create("UIGridLayout", {
			CellSize = UDim2.fromOffset(120, 112),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})
		local profile = ClientState.Profile
		if not profile then
			return
		end
		local ready = if mode == "Risk" then renderRisk(profile) else renderGuaranteed(profile)
		local unlocked = os.clock() >= lockedUntil
		runButton.BackgroundColor3 = if ready and unlocked then Theme.Colors.Buy else Theme.Colors.Locked
		runButton.Active = ready and unlocked
	end

	runButton.Activated:Connect(function()
		if not runButton.Active or os.clock() < lockedUntil then
			return
		end
		lockedUntil = os.clock() + RUN_LOCK_SECONDS
		local ok, message
		if mode == "Risk" then
			ok, message = Remotes.MergeRun:InvokeServer("risk", selected)
		else
			ok, message = Remotes.MergeRun:InvokeServer("guaranteed", selected[1])
		end
		if not ok and message then
			notify(message)
		end
		Widgets.Pop(crystal)
		selected = {}
		render()
		task.delay(RUN_LOCK_SECONDS, function()
			if overlay.Visible then
				render()
			end
		end)
	end)

	ClientState.ProfileChanged:Connect(function()
		if overlay.Visible then
			selected = {}
			render()
		end
	end)

	local merge = {}
	function merge.Open()
		mode = "Risk"
		selected = {}
		overlay.Visible = true
		render()
		ClientState.Refresh()
	end
	return merge
end
