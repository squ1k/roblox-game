-- Донат-магазин: геймпассы и товары из Balance.Monetization. Id = 0 = кнопка серая "Скоро".
-- Покупку подтверждает окно Roblox, выдачу делает сервер (MonetizationService).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local create = Widgets.Create

local player = Players.LocalPlayer

return function(parent: Instance)
	local overlay = create("TextButton", {
		Name = "DonateShop",
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
	overlay.Activated:Connect(function()
		overlay.Visible = false
	end)
	Widgets.Label({
		Text = Strings.DonateTitle,
		TextColor3 = Theme.Colors.TextDark,
		Outline = false,
		Size = UDim2.new(1, -100, 0, 50),
		Position = UDim2.fromOffset(16, 14),
		MaxTextSize = 34,
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
	local content = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 80),
		Size = UDim2.new(1, -32, 1, -96),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = window,
	})

	local function card(order: number, item, isPass: boolean)
		local owned = isPass and player:GetAttribute("Pass_" .. item.Key) == true
		local available = item.Id > 0 and not owned
		local frame = create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 23,
			Parent = content,
		}, { Widgets.Corner(), Widgets.Stroke() })
		local function text(value: string, y: number, height: number, size: number, font)
			Widgets.Label({
				Text = value,
				TextColor3 = Theme.Colors.TextDark,
				Outline = false,
				Font = font or Theme.Font,
				TextWrapped = true,
				Size = UDim2.new(1, -16, 0, height),
				Position = UDim2.fromOffset(8, y),
				MaxTextSize = size,
				ZIndex = 24,
				Parent = frame,
			})
		end
		text(Strings.DonateNames[item.Key] or item.Key, 10, 34, 24)
		text(Strings.DonateInfo[item.Key] or "", 48, 52, 16, Theme.FontBody)
		text("R$ " .. item.Robux, 104, 30, 24)
		local button = Widgets.Button(
			{
				Text = if owned then Strings.DonateOwned elseif available then Strings.DonateBuy else Strings.DonateSoon,
				BackgroundColor3 = if available then Theme.Colors.Buy else Theme.Colors.Locked,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10),
				Size = UDim2.new(1, -20, 0, 52),
				ZIndex = 24,
				Parent = frame,
			},
			if available
				then function()
					if isPass then
						MarketplaceService:PromptGamePassPurchase(player, item.Id)
					else
						MarketplaceService:PromptProductPurchase(player, item.Id)
					end
				end
				else nil
		)
		button.Active = available
	end

	local function render()
		for _, child in content:GetChildren() do
			child:Destroy()
		end
		create("UIGridLayout", {
			CellSize = UDim2.fromOffset(220, 210),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})
		local order = 0
		for _, pass in Balance.Monetization.GamePasses do
			order += 1
			card(order, pass, true)
		end
		for _, product in Balance.Monetization.Products do
			order += 1
			card(order, product, false)
		end
	end

	local shop = {}
	function shop.Open()
		overlay.Visible = true
		render()
	end
	return shop
end
