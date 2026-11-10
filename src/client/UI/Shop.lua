-- Лавка Антона: вкладка "Купить" (зеленая, бананы по динамической цене) и "Продать"
-- (оранжевая, попсы из Холодильника и Скебобсы не на пьедесталах). Только крупные тапы.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Prices = require(Shared:WaitForChild("Prices"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local create = Widgets.Create

local player = Players.LocalPlayer

return function(parent: Instance, notify)
	local overlay = create("TextButton", {
		Name = "Shop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	local window = create("Frame", {
		Active = true, -- клики по окну не закрывают его
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.88),
		BackgroundColor3 = Theme.Colors.Panel,
		ZIndex = 21,
		Parent = overlay,
	}, {
		Widgets.Corner(UDim.new(0, 24)),
		Widgets.Stroke(4),
		create("UISizeConstraint", { MaxSize = Vector2.new(1100, 700) }),
	})
	-- Тап вне окна закрывает
	overlay.Activated:Connect(function()
		overlay.Visible = false
	end)
	local header = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 64),
		Position = UDim2.fromOffset(12, 12),
		ZIndex = 22,
		Parent = window,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local content = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 88),
		Size = UDim2.new(1, -32, 1, -104),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = window,
	})

	local currentTab = "Buy"
	local confirmKey = nil -- первая нажатая карточка в "Продать" ждет подтверждения
	local render

	local tabs = {}
	for index, tab in
		{
			{ Id = "Buy", Title = Strings.ShopBuyTab, Color = Theme.Colors.Buy },
			{ Id = "Sell", Title = Strings.ShopSellTab, Color = Theme.Colors.Sell },
		}
	do
		tabs[tab.Id] = {
			Color = tab.Color,
			Button = Widgets.Button({
				Text = tab.Title,
				LayoutOrder = index,
				Size = UDim2.new(0.3, 0, 1, 0),
				BackgroundColor3 = Theme.Colors.TabIdle,
				ZIndex = 23,
				Parent = header,
			}, function()
				currentTab = tab.Id
				confirmKey = nil
				render()
			end),
		}
	end
	Widgets.Label({
		Text = Strings.ShopTitle,
		TextColor3 = Theme.Colors.TextDark,
		Outline = false,
		LayoutOrder = 50,
		Size = UDim2.new(0.25, 0, 1, 0),
		MaxTextSize = 30,
		ZIndex = 23,
		Parent = header,
	})
	Widgets.Button({
		Text = "X",
		LayoutOrder = 99,
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = Theme.Colors.Drop,
		ZIndex = 23,
		Parent = header,
	}, function()
		overlay.Visible = false
	end)

	local function clear()
		for _, child in content:GetChildren() do
			child:Destroy()
		end
	end

	local function emptyText(text: string)
		Widgets.Label({
			Text = text,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			Size = UDim2.new(1, 0, 0, 60),
			MaxTextSize = 26,
			ZIndex = 23,
			Parent = content,
		})
	end

	local function textOn(button, text, props)
		local defaults = {
			Text = text,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			ZIndex = 25,
			Parent = button,
		}
		for key, value in props do
			defaults[key] = value
		end
		return Widgets.Label(defaults)
	end

	local function renderBuy(profile)
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 18),
			Parent = content,
		})
		local trap = Balance.BananaTrap
		local have = profile.Items and profile.Items.BananaTrap or 0
		local isVip = player:GetAttribute("VIP") == true
		for index, pack in trap.Packs do
			local price = Prices.BananaPack(profile, isVip, index)
			local blocked = have + pack.Amount > trap.MaxCarry
			local card = create("Frame", {
				LayoutOrder = index,
				Size = UDim2.fromOffset(210, 280),
				BackgroundColor3 = Color3.new(1, 1, 1),
				ZIndex = 23,
				Parent = content,
			}, { Widgets.Corner(), Widgets.Stroke() })
			textOn(
				card,
				"🍌",
				{ Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 10), MaxTextSize = 70 }
			)
			textOn(
				card,
				"x" .. pack.Amount,
				{ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 92), MaxTextSize = 32 }
			)
			textOn(
				card,
				"💰 " .. NumberFormat.Short(price),
				{ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 130), MaxTextSize = 28 }
			)
			textOn(card, have .. "/" .. trap.MaxCarry, {
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromOffset(0, 164),
				MaxTextSize = 20,
				Font = Theme.FontBody,
			})
			local buy = Widgets.Button(
				{
					Text = if blocked then Strings.LimitReached else Strings.ShopBuyTab,
					BackgroundColor3 = if blocked then Theme.Colors.Locked else Theme.Colors.Buy,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -12),
					Size = UDim2.new(1, -24, 0, 64),
					ZIndex = 25,
					Parent = card,
				},
				if blocked
					then nil
					else function()
						local ok, message = Remotes.ShopBuy:InvokeServer(index)
						if not ok and message then
							notify(message)
						end
					end
			)
			buy.Active = not blocked
		end
	end

	local function onPedestal(profile, uid: string): boolean
		for _, pedestal in profile.Pedestals do
			if pedestal.Pet == uid then
				return true
			end
		end
		return false
	end

	local function sellCard(
		order: number,
		key: string,
		petId: string,
		mutationId: string?,
		price: number?,
		note: string?,
		onSell
	)
		local skebob = Families.SkebobById[petId]
		local rarity = skebob and Balance.RarityById[skebob.Rarity] or Balance.Rarities[1]
		local mutation = mutationId and Balance.MutationById[mutationId]
		local confirming = confirmKey == key
		local card = Widgets.Button(
			{
				LayoutOrder = order,
				BackgroundColor3 = if confirming then Theme.Colors.Sell else Color3.new(1, 1, 1),
				ZIndex = 23,
				Parent = content,
			},
			if note
				then nil
				else function()
					if confirmKey == key then
						confirmKey = nil
						onSell()
					else
						confirmKey = key
						render()
					end
				end
		)
		create("Frame", {
			BackgroundColor3 = rarity.Glaze,
			Size = UDim2.new(1, -12, 0, 60),
			Position = UDim2.fromOffset(6, 6),
			ZIndex = 24,
			Parent = card,
		}, { Widgets.Corner() })
		textOn(card, petId, { Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 72), MaxTextSize = 20 })
		textOn(card, (if mutation then mutation.Name .. " · " else "") .. rarity.Name, {
			Size = UDim2.new(1, -12, 0, 20),
			Position = UDim2.fromOffset(6, 100),
			MaxTextSize = 15,
			Font = Theme.FontBody,
		})
		local bottom = if confirming
			then Strings.ConfirmSell
			elseif note then note
			else "💰 " .. NumberFormat.Short(price or 0)
		textOn(card, bottom, {
			Size = UDim2.new(1, -12, 0, 44),
			Position = UDim2.fromOffset(6, 126),
			MaxTextSize = 20,
			TextWrapped = true,
		})
	end

	local function renderSell(profile)
		create("UIGridLayout", {
			CellSize = UDim2.fromOffset(150, 180),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})
		local order = 0
		for index, pop in profile.Fridge do
			order += 1
			sellCard(order, "pop" .. index, pop.Id, pop.Mutation, Prices.SellPop(pop), nil, function()
				local ok, message = Remotes.ShopSell:InvokeServer("pop", index)
				if not ok and message then
					notify(message)
				end
			end)
		end
		for uid, pet in profile.Pets do
			order += 1
			local note = if onPedestal(profile, uid) then Strings.ShopOnPedestal else nil
			sellCard(order, uid, pet.Id, pet.Mutation, Prices.SellPet(pet), note, function()
				local ok, message = Remotes.ShopSell:InvokeServer("pet", uid)
				if not ok and message then
					notify(message)
				end
			end)
		end
		if order == 0 then
			content:FindFirstChildWhichIsA("UIGridLayout"):Destroy()
			emptyText(Strings.ShopNothingToSell)
		end
	end

	function render()
		for id, tab in tabs do
			tab.Button.BackgroundColor3 = if id == currentTab then tab.Color else Theme.Colors.TabIdle
		end
		clear()
		local profile = ClientState.Profile
		if not profile then
			emptyText("...")
			return
		end
		if currentTab == "Buy" then
			renderBuy(profile)
		else
			renderSell(profile)
		end
	end

	ClientState.ProfileChanged:Connect(function()
		if overlay.Visible then
			render()
		end
	end)

	local shop = {}
	function shop.Open()
		currentTab = "Buy"
		confirmKey = nil
		overlay.Visible = true
		render()
		ClientState.Refresh()
	end
	function shop.Close()
		overlay.Visible = false
	end
	return shop
end
