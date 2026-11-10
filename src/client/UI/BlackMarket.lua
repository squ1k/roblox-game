-- Терминал Черного рынка: 1 Кристалл за CoinsPerCrystal Монет и обратно за CoinsForCrystal.
-- Количество выбирается кнопками -/+ (до MaxAmount за раз).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local create = Widgets.Create

local Market = Balance.BlackMarket

return function(parent: Instance, notify)
	local overlay = create("TextButton", {
		Name = "BlackMarket",
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
		Size = UDim2.fromOffset(520, 360),
		BackgroundColor3 = Theme.Colors.PanelDark,
		ZIndex = 21,
		Parent = overlay,
	}, { Widgets.Corner(UDim.new(0, 24)), Widgets.Stroke(4) })
	overlay.Activated:Connect(function()
		overlay.Visible = false
	end)
	Widgets.Label({
		Text = Strings.BlackMarketTitle,
		Size = UDim2.new(1, -90, 0, 50),
		Position = UDim2.fromOffset(16, 12),
		MaxTextSize = 32,
		ZIndex = 22,
		Parent = window,
	})
	Widgets.Button({
		Text = "X",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Theme.Colors.Drop,
		ZIndex = 23,
		Parent = window,
	}, function()
		overlay.Visible = false
	end)

	local amount = 1
	local amountLabel = Widgets.Label({
		Text = "1",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.fromOffset(120, 56),
		MaxTextSize = 40,
		ZIndex = 22,
		Parent = window,
	})
	local buyButton, sellButton
	local function refresh()
		amountLabel.Text = tostring(amount) .. " 💎"
		buyButton.Text = string
			.format(Strings.BlackMarketBuy, NumberFormat.Short(Market.CoinsPerCrystal * amount))
			:gsub("→ 1", "→ " .. amount)
		sellButton.Text = string
			.format(Strings.BlackMarketSell, NumberFormat.Short(Market.CoinsForCrystal * amount))
			:gsub("1 💎", amount .. " 💎")
	end
	for _, spec in { { "-", -1, 0.5, -150 }, { "+", 1, 0.5, 90 } } do
		Widgets.Button({
			Text = spec[1],
			BackgroundColor3 = Theme.Colors.Backpack,
			Position = UDim2.new(spec[3], spec[4], 0, 76),
			Size = UDim2.fromOffset(60, 56),
			ZIndex = 23,
			Parent = window,
		}, function()
			amount = math.clamp(amount + spec[2], 1, Market.MaxAmount)
			refresh()
		end)
	end
	local function exchange(direction: string)
		local ok, message = Remotes.BlackMarketExchange:InvokeServer(direction, amount)
		if not ok and message then
			notify(message)
		end
	end
	buyButton = Widgets.Button({
		BackgroundColor3 = Theme.Colors.Crystal,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 152),
		Size = UDim2.new(1, -40, 0, 70),
		ZIndex = 23,
		Parent = window,
	}, function()
		exchange("buy")
	end)
	sellButton = Widgets.Button({
		BackgroundColor3 = Theme.Colors.Coin,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 240),
		Size = UDim2.new(1, -40, 0, 70),
		ZIndex = 23,
		Parent = window,
	}, function()
		exchange("sell")
	end)
	refresh()

	local market = {}
	function market.Open()
		amount = 1
		refresh()
		overlay.Visible = true
	end
	return market
end
