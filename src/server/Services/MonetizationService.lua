-- Донат-каркас: геймпассы и товары из Balance.Monetization. Пока Id = 0, товар виден в магазине,
-- но купить его нельзя ("Скоро"). Владение геймпассом = атрибут игрока "Pass_<Key>"
-- (+ VIP / XRay для систем, которые их читают). Все вызовы MarketplaceService в pcall.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local Monetization = Balance.Monetization
local RECEIPT_WAIT_SECONDS = 10

local MonetizationService = {}

-- Атрибуты, которые читают другие системы, по ключу геймпасса
local PASS_ATTRIBUTES = {
	Vip = "VIP",
	XRay = "XRay",
}

local function grantPass(player: Player, pass)
	player:SetAttribute("Pass_" .. pass.Key, true)
	local attribute = PASS_ATTRIBUTES[pass.Key]
	if attribute then
		player:SetAttribute(attribute, true)
	end
	-- TODO: SecondOven/SecondFridge/AutoClicker/SpeedPotion - эффекты появятся вместе с механиками
end

local function checkPasses(player: Player)
	for _, pass in Monetization.GamePasses do
		if pass.Id > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and owns then
				grantPass(player, pass)
			end
		end
	end
	EconomyService.Refresh(player)
end

-- Обработчики товаров по Key: function(player, data, product) -> true, если выдали
local productHandlers = {}

local function coins(player: Player, data, product)
	local income = player:GetAttribute("Income") or 0
	EconomyService.AddCoins(player, math.max(Monetization.MinCoinsPack, math.floor(income * product.IncomeSeconds)))
	return true
end
productHandlers.Coins1 = coins
productHandlers.Coins2 = coins
productHandlers.Coins3 = coins

local function crystals(player: Player, data, product)
	EconomyService.AddCrystals(player, product.Crystals)
	return true
end
productHandlers.Crystals1 = crystals
productHandlers.Crystals2 = crystals
productHandlers.Crystals3 = crystals

productHandlers.LuckPotion = function(player: Player, data, product)
	-- TODO Epic 8: Зелье Удачи (без повторных Скебобсов один цикл автомата), пока только отметка
	player:SetAttribute("LuckUntil", workspace:GetServerTimeNow() + Balance.Gacha.RestockSeconds)
	return true
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product
	for _, entry in Monetization.Products do
		if entry.Id > 0 and entry.Id == receipt.ProductId then
			product = entry
			break
		end
	end
	local handler = product and productHandlers[product.Key]
	local data = DataService.WaitFor(player, RECEIPT_WAIT_SECONDS)
	if not handler or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handler, player, data, product)
	if not ok or not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- TODO: журнал покупок в DataStore, чтобы повтор чека не выдал товар дважды
	Remotes.Notify:FireClient(player, Strings.DonatePurchased)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, pass in Monetization.GamePasses do
			if pass.Id > 0 and pass.Id == passId then
				grantPass(player, pass)
				EconomyService.Refresh(player)
				Remotes.Notify:FireClient(player, Strings.DonatePurchased)
			end
		end
	end)
	DataService.ProfileLoaded:Connect(function(player)
		task.spawn(checkPasses, player)
	end)
end

return MonetizationService
