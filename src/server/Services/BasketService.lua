-- АФК-корзина: каждые SleepingPopSeconds (VIP: SleepingPopSecondsVip) непрерывного лежания на своем
-- лежаке в data.Basket падает Спящий попс (Обычный, случайное Семейство). После ухода с лежака
-- корзина пустеет через BasketClearSeconds. Попсы из корзины переносятся в Холодильник.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local Afk = Balance.Afk
local DEV_FAST_SECONDS = 10 -- DevCommand "afkfast" в Studio

local BasketService = {}

local random = Random.new()
local session = {} -- [player] = { Given = число попсов за текущее лежание }

local function now()
	return workspace:GetServerTimeNow()
end

function BasketService.Period(player: Player): number
	if RunService:IsStudio() and player:GetAttribute("DevAfkFast") then
		return DEV_FAST_SECONDS
	end
	return if player:GetAttribute("VIP") then Afk.SleepingPopSecondsVip else Afk.SleepingPopSeconds
end

local function sleepingPop()
	local family = Families.List[random:NextInteger(1, #Families.List)]
	return { Id = family.Members[1].Id, Mutation = nil, Sleeping = true }
end

local function update(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local afk = player:GetAttribute("AFK") == true
	local state = session[player]
	if afk then
		if not state then
			state = { Given = 0 }
			session[player] = state
			if data.BasketClearAt ~= 0 then
				data.BasketClearAt = 0
				Remotes.ProfileChanged:FireClient(player)
			end
		end
		local since = player:GetAttribute("AfkSince") or now()
		local due = math.floor((now() - since) / BasketService.Period(player))
		while state.Given < due do
			state.Given += 1
			table.insert(data.Basket, sleepingPop())
			Remotes.Notify:FireClient(player, Strings.SleepingArrived)
			Remotes.ProfileChanged:FireClient(player)
		end
	elseif state then
		session[player] = nil
		if #data.Basket > 0 then
			data.BasketClearAt = now() + Afk.BasketClearSeconds
			Remotes.Notify:FireClient(player, string.format(Strings.AfkSummary, #data.Basket))
			Remotes.ProfileChanged:FireClient(player)
		end
	elseif data.BasketClearAt ~= 0 and now() >= data.BasketClearAt then
		table.clear(data.Basket)
		data.BasketClearAt = 0
		Remotes.ProfileChanged:FireClient(player)
	end
end

function BasketService.Take(player: Player, index)
	local data = DataService.Get(player)
	if not data or type(index) ~= "number" or not data.Basket[index] then
		return
	end
	if #data.Fridge >= data.FridgeSlots then
		Remotes.Notify:FireClient(player, Strings.FridgeFull)
		return
	end
	table.insert(data.Fridge, table.remove(data.Basket, index))
	Remotes.ProfileChanged:FireClient(player)
end

function BasketService.Start()
	Remotes.BasketTake.OnServerEvent:Connect(BasketService.Take)
	Players.PlayerRemoving:Connect(function(player)
		session[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				update(player)
			end
		end
	end)
end

return BasketService
