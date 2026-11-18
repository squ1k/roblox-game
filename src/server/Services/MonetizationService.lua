-- Донат: геймпассы и товары из Balance.Monetization (ID в Config/GamePasses.lua, 0 = кнопка "Скоро").
-- Владение геймпассом = атрибут игрока "Pass_<Key>", его читают системы с эффектами:
--   VIP / XRay (+ старые атрибуты VIP и XRay), SecondOven / SecondFridge (Capacity), AutoClicker (ClawService),
--   SpeedPotion (скорость в CakePopService + трейл здесь), Boombox (BoomboxService).
-- Товары выдаются через журнал покупок data.Receipts: один чек = одна выдача, даже если Roblox
-- пришлет его повторно. PurchaseGranted отвечаем только после записи в DataStore.
-- Все вызовы MarketplaceService в pcall.

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
local PedestalService = require(script.Parent:WaitForChild("PedestalService"))

local Monetization = Balance.Monetization
local RECEIPT_WAIT_SECONDS = 10

local MonetizationService = {}

-- Атрибуты, которые читают старые системы, по ключу геймпасса
local PASS_ATTRIBUTES = {
	Vip = "VIP",
	XRay = "XRay",
}

local function addSpeedTrail(character: Model?)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or root:FindFirstChild("SpeedTrail") then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "SpeedTrailTop"
	top.Position = Vector3.new(0, 0.8, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "SpeedTrailBottom"
	bottom.Position = Vector3.new(0, -0.8, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "SpeedTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = root
end

function MonetizationService.GrantPass(player: Player, key: string)
	player:SetAttribute("Pass_" .. key, true)
	local attribute = PASS_ATTRIBUTES[key]
	if attribute then
		player:SetAttribute(attribute, true)
	end
	if key == "SpeedPotion" then
		addSpeedTrail(player.Character)
	end
	EconomyService.Refresh(player)
	Remotes.ProfileChanged:FireClient(player)
end

function MonetizationService.HasPass(player: Player, key: string): boolean
	return player:GetAttribute("Pass_" .. key) == true
end

local function checkPasses(player: Player)
	for _, pass in Monetization.GamePasses do
		if pass.Id > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and owns then
				MonetizationService.GrantPass(player, pass.Key)
			end
		end
	end
end

-- Обработчики товаров по Key: function(player, data, product) -> true, если выдали
local productHandlers = {}

local function coins(player: Player, data, product)
	local income = player:GetAttribute("Income") or 0
	return EconomyService.AddCoins(
		player,
		math.max(Monetization.MinCoinsPack, math.floor(income * product.IncomeSeconds))
	)
end
productHandlers.Coins1 = coins
productHandlers.Coins2 = coins
productHandlers.Coins3 = coins

local function crystals(player: Player, data, product)
	return EconomyService.AddCrystals(player, product.Crystals)
end
productHandlers.Crystals1 = crystals
productHandlers.Crystals2 = crystals
productHandlers.Crystals3 = crystals

-- Зелье Удачи: до следующего обновления автомата (один пул попсов) без повторных Скебобсов (GachaService)
productHandlers.LuckPotion = function(player: Player)
	local restockAt = workspace:GetAttribute("GachaRestockAt")
	local now = workspace:GetServerTimeNow()
	player:SetAttribute(
		"LuckUntil",
		math.max(player:GetAttribute("LuckUntil") or 0, restockAt or now + Balance.Gacha.RestockSeconds)
	)
	return true
end

-- Премиум-пьедестал: 11-й, потом 12-й. Если оба уже куплены (купили дважды в разных окнах),
-- возвращаем стоимость Кристаллами (1 Кристалл = 1 R$), чтобы покупка не пропала.
productHandlers.PremiumPedestal = function(player: Player, data, product)
	if PedestalService.AddPremiumSlot(player) then
		return true
	end
	EconomyService.AddCrystals(player, product.Robux)
	Remotes.Notify:FireClient(player, string.format(Strings.PremiumPedestalRefund, product.Robux))
	return true
end

function MonetizationService.ProductByKey(key: string)
	for _, entry in Monetization.Products do
		if entry.Key == key then
			return entry
		end
	end
	return nil
end

-- Окно покупки товара по Key (кнопки в мире). false, если товар еще не создан (Id = 0).
function MonetizationService.PromptProduct(player: Player, key: string): boolean
	local product = MonetizationService.ProductByKey(key)
	if not product or product.Id <= 0 then
		Remotes.Notify:FireClient(player, Strings.DonateSoon)
		return false
	end
	pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, product.Id)
	return true
end

local function pruneReceipts(data, nowTime: number)
	local keep = Monetization.ReceiptKeepDays * 86400
	for purchaseId, grantedAt in data.Receipts do
		if type(grantedAt) ~= "number" or nowTime - grantedAt > keep then
			data.Receipts[purchaseId] = nil
		end
	end
end

function MonetizationService.ProcessReceipt(receipt)
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
	local purchaseId = tostring(receipt.PurchaseId)
	if not data.Receipts[purchaseId] then
		local ok, granted = pcall(handler, player, data, product)
		if not ok or not granted then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		data.Receipts[purchaseId] = os.time()
		pruneReceipts(data, os.time())
		Remotes.Notify:FireClient(player, Strings.DonatePurchased)
		Remotes.ProfileChanged:FireClient(player)
	end
	-- Чек уже в журнале: подтверждаем, только когда журнал записан. Иначе Roblox пришлет чек еще раз,
	-- а журнал (в этой сессии он в памяти) не даст выдать товар второй раз.
	if not DataService.Save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = MonetizationService.ProcessReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, pass in Monetization.GamePasses do
			if pass.Id > 0 and pass.Id == passId then
				MonetizationService.GrantPass(player, pass.Key)
				Remotes.Notify:FireClient(player, Strings.DonatePurchased)
			end
		end
	end)
	DataService.ProfileLoaded:Connect(function(player)
		task.spawn(checkPasses, player)
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			if MonetizationService.HasPass(player, "SpeedPotion") then
				addSpeedTrail(character)
			end
		end)
	end)
end

return MonetizationService
