-- Лавка Антона: покупка бананов по динамической цене (Prices.BananaPack) и продажа попсов
-- из Холодильника и Скебобсов, которые не стоят на пьедесталах, плюс терминал Черного рынка.
-- Все проверки на сервере.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Prices = require(Shared:WaitForChild("Prices"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local TradeService = require(script.Parent:WaitForChild("TradeService"))

local ShopService = {}

local function nearShop(player: Player, parts: { BasePart? }?): boolean
	local shop = MapService.Shop()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not shop or not root then
		return false
	end
	for _, part in parts or { shop.Anton, shop.Counter } do
		if part and (part.Position - root.Position).Magnitude <= Balance.Shop.PromptDistance + 4 then
			return true
		end
	end
	return false
end

local function onPedestal(data, uid: string): boolean
	for _, pedestal in data.Pedestals do
		if pedestal.Pet == uid then
			return true
		end
	end
	return false
end

local function buy(player: Player, packIndex)
	if type(packIndex) ~= "number" or packIndex ~= packIndex or packIndex % 1 ~= 0 then
		return false
	end
	if not nearShop(player) then
		return false, Strings.ShopTooFar
	end
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local price, amount = Prices.BananaPack(data, player:GetAttribute("VIP") == true, packIndex)
	if not price then
		return false
	end
	local have = data.Items.BananaTrap or 0
	if have + amount > Balance.BananaTrap.MaxCarry then
		return false, Strings.LimitReached
	end
	if not EconomyService.TrySpendCoins(player, price) then
		return false, Strings.NoCoins
	end
	data.Items.BananaTrap = have + amount
	Remotes.ProfileChanged:FireClient(player)
	Remotes.Notify:FireClient(player, string.format(Strings.Bought, string.format(Strings.BananasPack, amount)))
	return true
end

local function sell(player: Player, kind, key)
	if not nearShop(player) then
		return false, Strings.ShopTooFar
	end
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local coins
	if kind == "pop" then
		if type(key) ~= "number" or key ~= key or key % 1 ~= 0 then
			return false
		end
		local pop = data.Fridge[key]
		if not pop then
			return false
		end
		coins = Prices.SellPop(pop)
		if not coins then
			return false
		end
		table.remove(data.Fridge, key)
	elseif kind == "pet" then
		if type(key) ~= "string" then
			return false
		end
		local pet = data.Pets[key]
		if not pet or pet.Locked then
			return false
		end
		if onPedestal(data, key) then
			return false, Strings.ShopOnPedestal
		end
		if TradeService.IsOffered(player, key) then
			return false
		end
		coins = Prices.SellPet(pet)
		if not coins then
			return false
		end
		data.Pets[key] = nil
	else
		return false
	end
	data.Stats.Sold += 1
	EconomyService.AddCoins(player, coins)
	EconomyService.Refresh(player)
	Remotes.ProfileChanged:FireClient(player)
	Remotes.Notify:FireClient(player, string.format(Strings.Sold, NumberFormat.Short(coins)))
	return true, coins
end

-- Черный рынок: "buy" = Монеты -> Кристаллы, "sell" = Кристаллы -> Монеты, курс Balance.BlackMarket
local function blackMarket(player: Player, direction, amount)
	local market = Balance.BlackMarket
	if type(amount) ~= "number" or amount ~= amount or amount % 1 ~= 0 or amount < 1 or amount > market.MaxAmount then
		return false
	end
	local shop = MapService.Shop()
	if not nearShop(player, { shop and shop.BlackMarket }) then
		return false, Strings.ShopTooFar
	end
	if direction == "buy" then
		if not EconomyService.TrySpendCoins(player, market.CoinsPerCrystal * amount) then
			return false, Strings.NoCoins
		end
		EconomyService.AddCrystals(player, amount)
	elseif direction == "sell" then
		if not EconomyService.TrySpendCrystals(player, amount) then
			return false, Strings.NoCrystals
		end
		EconomyService.AddCoins(player, market.CoinsForCrystal * amount)
	else
		return false
	end
	Remotes.Notify:FireClient(player, Strings.BlackMarketDone)
	return true
end

function ShopService.Start()
	local shop = MapService.Shop()
	if shop and shop.Anton then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = Strings.ShopOpen
		prompt.ObjectText = Strings.ShopTitle
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Balance.Shop.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = shop.Anton
	end
	Remotes.ShopBuy.OnServerInvoke = buy
	Remotes.ShopSell.OnServerInvoke = sell
	Remotes.BlackMarketExchange.OnServerInvoke = blackMarket
	if shop and shop.BlackMarket then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BlackMarketPrompt"
		prompt.ActionText = Strings.BlackMarketOpen
		prompt.ObjectText = Strings.BlackMarketTitle
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Balance.Shop.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = shop.BlackMarket
	end
end

return ShopService
