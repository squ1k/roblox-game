-- Верхний левый угол: Монеты и Кристаллы с кнопкой "+" (донат-магазин).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))
local Strings = require(Shared:WaitForChild("Config"):WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local create = Widgets.Create

local player = Players.LocalPlayer

local function makeRow(parent, order: number, icon: string, color: Color3, onPlus)
	local row = create("Frame", {
		Name = "Row" .. order,
		LayoutOrder = order,
		Size = UDim2.fromOffset(250, 54),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.15,
		Parent = parent,
	}, { Widgets.Corner(UDim.new(1, 0)), Widgets.Stroke() })

	Widgets.Label({
		Name = "Icon",
		Text = icon,
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.fromOffset(4, 4),
		Outline = false,
		Parent = row,
	})
	local value = Widgets.Label({
		Name = "Value",
		Text = "0",
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -112, 0, 32),
		Position = UDim2.fromOffset(54, 4),
		Parent = row,
	})
	local sub = Widgets.Label({
		Name = "PerSecond",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -112, 0, 16),
		Position = UDim2.fromOffset(56, 34),
		MaxTextSize = 16,
		Parent = row,
	})
	Widgets.Button({
		Name = "Plus",
		Text = "+",
		BackgroundColor3 = Theme.Colors.Plus,
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(1, -49, 0, 5),
		CornerRadius = UDim.new(1, 0),
		Parent = row,
	}, onPlus)
	return value, sub
end

-- Плавно докручивает число до нового значения
local function animatedCounter(label: TextLabel)
	local shown = create("NumberValue", { Value = 0 })
	shown.Changed:Connect(function(v)
		label.Text = NumberFormat.Short(math.floor(v))
	end)
	local tween
	return function(target: number, instant: boolean?)
		if tween then
			tween:Cancel()
		end
		if instant then
			shown.Value = target
			label.Text = NumberFormat.Short(math.floor(target))
			return
		end
		tween = TweenService:Create(shown, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Value = target })
		tween:Play()
	end
end

return function(parent: Instance, notify, onShop)
	local panel = create("Frame", {
		Name = "Currency",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(250, 118),
		Parent = parent,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local openShop = onShop or function()
		notify(Strings.ShopSoon)
	end
	local coinsLabel, incomeLabel = makeRow(panel, 1, "💰", Theme.Colors.Coin, openShop)
	local crystalsLabel = makeRow(panel, 2, "💎", Theme.Colors.Crystal, openShop)

	local setCoins = animatedCounter(coinsLabel)
	local setCrystals = animatedCounter(crystalsLabel)
	local lastCoins = 0

	local function onCoins(instant)
		local coins = player:GetAttribute("Coins") or 0
		local income = player:GetAttribute("Income") or 0
		-- Заметный скачок (покупка, награда) - подпрыгнуть
		if not instant and math.abs(coins - lastCoins) > math.max(income * 1.5, 1) then
			Widgets.Pop(coinsLabel.Parent)
		end
		lastCoins = coins
		setCoins(coins, instant)
	end
	local function onIncome()
		local income = player:GetAttribute("Income") or 0
		incomeLabel.Text = if income > 0 then "+" .. NumberFormat.Short(income) .. Strings.PerSecond else ""
	end
	local function onCrystals(instant)
		setCrystals(player:GetAttribute("Crystals") or 0, instant)
	end

	player:GetAttributeChangedSignal("Coins"):Connect(onCoins)
	player:GetAttributeChangedSignal("Income"):Connect(onIncome)
	player:GetAttributeChangedSignal("Crystals"):Connect(onCrystals)
	onCoins(true)
	onIncome()
	onCrystals(true)

	return panel
end
