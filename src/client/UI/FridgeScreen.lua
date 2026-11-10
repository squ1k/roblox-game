-- Экран Холодильника: слева большая карточка выбранного попса и действия, справа сетка попсов,
-- сверху счетчик мест и "Расширить". Продать можно только у Антона (зона Shop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Prices = require(Shared:WaitForChild("Prices"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local Screen = require(script.Parent:WaitForChild("Screen"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local create = Widgets.Create

local player = Players.LocalPlayer

local function describe(pop)
	local skebob = Families.SkebobById[pop.Id]
	local rarity = skebob and Balance.RarityById[skebob.Rarity] or Balance.Rarities[1]
	local family = skebob and Families.ById[skebob.Family]
	local mutation = pop.Mutation and Balance.MutationById[pop.Mutation]
	return rarity, family, mutation
end

return function(parent: Instance, notify)
	local overlay, window, setTitle = Screen(parent, "FridgeScreen", Strings.TabFridge)
	local selected = 1

	local expand = Widgets.Button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -80, 0, 16),
		Size = UDim2.fromOffset(260, 50),
		BackgroundColor3 = Theme.Colors.Buy,
		ZIndex = 23,
		Parent = window,
	}, function()
		Remotes.FridgeBuySlot:FireServer()
	end)

	-- Левая карточка
	local cardFrame = create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(20, 80),
		Size = UDim2.new(0.36, -20, 1, -100),
		ZIndex = 22,
		Parent = window,
	}, { Widgets.Corner(), Widgets.Stroke() })
	local ball = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(120, 120),
		ZIndex = 23,
		Parent = cardFrame,
	}, { Widgets.Corner(UDim.new(1, 0)), Widgets.Stroke(4) })
	local function cardText(y: number, height: number, size: number)
		return Widgets.Label({
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			TextWrapped = true,
			Size = UDim2.new(1, -20, 0, height),
			Position = UDim2.fromOffset(10, y),
			MaxTextSize = size,
			ZIndex = 23,
			Parent = cardFrame,
		})
	end
	local familyLabel = cardText(146, 34, 28)
	local rarityLabel = cardText(182, 28, 22)
	local priceLabel = cardText(212, 26, 20)
	local actions = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(1, -20, 0, 190),
		ZIndex = 23,
		Parent = cardFrame,
	}, { create("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom }) })

	local grid = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.36, 12, 0, 80),
		Size = UDim2.new(0.64, -32, 1, -100),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = window,
	})

	local render
	local function actionButton(text: string, color: Color3, run)
		local button = Widgets.Button({
			Text = text,
			BackgroundColor3 = if run then color else Theme.Colors.Locked,
			Size = UDim2.new(1, 0, 0, 56),
			ZIndex = 24,
			Parent = actions,
		}, run)
		button.Active = run ~= nil
	end

	function render()
		local profile = ClientState.Profile
		if not profile then
			return
		end
		setTitle(Strings.TabFridge .. " " .. #profile.Fridge .. "/" .. profile.FridgeSlots)
		local price = Prices.FridgeSlot(profile.FridgeSlots + 1)
		expand.Text = if price
			then string.format(Strings.FridgeExpand, NumberFormat.Short(price))
			else Strings.FridgeMax
		expand.Active = price ~= nil
		expand.BackgroundColor3 = if price then Theme.Colors.Buy else Theme.Colors.Locked

		for _, child in grid:GetChildren() do
			child:Destroy()
		end
		create("UIGridLayout", {
			CellSize = UDim2.fromOffset(110, 120),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		selected = math.clamp(selected, 1, math.max(1, #profile.Fridge))
		for index, pop in profile.Fridge do
			local rarity, family, mutation = describe(pop)
			local tile = Widgets.Button({
				LayoutOrder = index,
				BackgroundColor3 = if index == selected then Theme.Colors.TabActive else Color3.new(1, 1, 1),
				ZIndex = 23,
				Parent = grid,
			}, function()
				selected = index
				render()
			end)
			create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 8),
				Size = UDim2.fromOffset(60, 60),
				BackgroundColor3 = rarity.Glaze,
				ZIndex = 24,
				Parent = tile,
			}, { Widgets.Corner(UDim.new(1, 0)), Widgets.Stroke(2) })
			Widgets.Label({
				Text = (if mutation then "★ " else "") .. (if family then family.Name else pop.Id),
				TextColor3 = Theme.Colors.TextDark,
				Outline = false,
				Font = Theme.FontBody,
				Size = UDim2.new(1, -8, 0, 40),
				Position = UDim2.fromOffset(4, 72),
				MaxTextSize = 14,
				TextWrapped = true,
				ZIndex = 24,
				Parent = tile,
			})
		end

		for _, child in actions:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local pop = profile.Fridge[selected]
		cardFrame.Visible = true
		if not pop then
			ball.BackgroundColor3 = Theme.Colors.Locked
			familyLabel.Text = Strings.EmptyFridge
			rarityLabel.Text = ""
			priceLabel.Text = ""
			return
		end
		local rarity, family, mutation = describe(pop)
		ball.BackgroundColor3 = rarity.Glaze
		familyLabel.Text = if family then family.Name else pop.Id
		rarityLabel.Text = (if mutation then mutation.Name .. " · " else "") .. rarity.Name
		rarityLabel.TextColor3 = rarity.Glaze
		local sellPrice = Prices.SellPop(pop) or 0
		priceLabel.Text = "💰 " .. NumberFormat.Short(sellPrice)
		local index = selected
		actionButton(Strings.TakeToHands, Theme.Colors.Backpack, function()
			Remotes.FridgeTake:FireServer(index)
			overlay.Visible = false
		end)
		actionButton(Strings.SendToOven, Theme.Colors.Buy, function()
			Remotes.OvenStart:FireServer(index)
		end)
		local atShop = player:GetAttribute("Zone") == "Shop"
		actionButton(
			if atShop then Strings.ShopSellTab else Strings.SellAtShop,
			Theme.Colors.Sell,
			if atShop
				then function()
					local ok, message = Remotes.ShopSell:InvokeServer("pop", index)
					if not ok and message then
						notify(message)
					end
				end
				else nil
		)
	end

	ClientState.ProfileChanged:Connect(function()
		if overlay.Visible then
			render()
		end
	end)

	local screen = {}
	function screen.Open()
		overlay.Visible = true
		render()
		ClientState.Refresh()
	end
	return screen
end
