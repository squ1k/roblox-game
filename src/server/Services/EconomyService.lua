-- Кошельки и серверный тик дохода (раз в секунду).
-- Баланс показывается клиенту через атрибуты игрока Coins, Crystals, Income.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Income = require(Shared:WaitForChild("Income"))
local GamePasses = require(Shared:WaitForChild("Config"):WaitForChild("GamePasses"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local EconomyService = {}

local friendCounts = {} -- [player] = друзей на сервере
local vipOwners = {} -- [player] = true

local function publish(player: Player, data, incomePerSecond: number?)
	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("Crystals", data.Crystals)
	if incomePerSecond then
		player:SetAttribute("Income", incomePerSecond)
	end
end

local function contextFor(player: Player)
	return {
		Afk = player:GetAttribute("AFK") == true,
		Vip = vipOwners[player] == true or player:GetAttribute("VIP") == true, -- атрибут ставит MonetizationService
		FriendsOnServer = friendCounts[player] or 0,
	}
end

local function recountFriends()
	local players = Players:GetPlayers()
	for _, player in players do
		local count = 0
		for _, other in players do
			if other ~= player then
				local ok, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
				if ok and isFriend then
					count += 1
				end
			end
		end
		friendCounts[player] = count
	end
end

local function checkVip(player: Player)
	if GamePasses.VIP == 0 then
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, GamePasses.VIP)
	vipOwners[player] = ok and owns or nil
	player:SetAttribute("VIP", vipOwners[player] == true)
end

function EconomyService.AddCoins(player: Player, amount: number)
	local data = DataService.Get(player)
	if not data or amount ~= amount or amount < 0 then
		return false
	end
	data.Coins += amount
	data.Stats.TotalCoins = (data.Stats.TotalCoins or 0) + amount
	publish(player, data)
	return true
end

function EconomyService.TrySpendCoins(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data or amount ~= amount or amount < 0 or data.Coins < amount then
		return false
	end
	data.Coins -= amount
	publish(player, data)
	return true
end

function EconomyService.AddCrystals(player: Player, amount: number)
	local data = DataService.Get(player)
	if not data or amount ~= amount or amount < 0 then
		return false
	end
	data.Crystals += math.floor(amount)
	publish(player, data)
	return true
end

function EconomyService.TrySpendCrystals(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data or amount ~= amount or amount < 0 or data.Crystals < amount then
		return false
	end
	data.Crystals -= amount
	publish(player, data)
	return true
end

-- Контекст баффов игрока для Income.Compute (нужен и PetDisplayService)
function EconomyService.Context(player: Player)
	return contextFor(player)
end

-- Пересчитать "в секунду" сразу (после смены пьедесталов и т.п.)
function EconomyService.Refresh(player: Player)
	local data = DataService.Get(player)
	if data then
		local perSecond = Income.Compute(data, contextFor(player))
		publish(player, data, perSecond)
	end
end

function EconomyService.Start()
	DataService.ProfileLoaded:Connect(function(player)
		checkVip(player)
		EconomyService.Refresh(player)
	end)
	Players.PlayerAdded:Connect(function()
		task.defer(recountFriends)
	end)
	Players.PlayerRemoving:Connect(function(player)
		friendCounts[player] = nil
		vipOwners[player] = nil
		task.defer(recountFriends)
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			for player, data in DataService.All() do
				local perSecond = Income.Compute(data, contextFor(player))
				data.Coins += perSecond
				data.Stats.TotalCoins = (data.Stats.TotalCoins or 0) + perSecond
				data.Stats.PlaySeconds += 1
				publish(player, data, perSecond)
			end
		end
	end)
end

return EconomyService
