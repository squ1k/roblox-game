-- Сохранение прогресса с блокировкой сессии: пока игрок на одном сервере,
-- другой сервер не может загрузить и перезаписать его данные (защита от дюпа и потерь).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Balance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Balance"))

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_SECONDS = 60
local LOCK_STALE_SECONDS = 300 -- замок без обновления дольше этого считается брошенным
local LOAD_RETRIES = 6
local LOAD_RETRY_WAIT = 5

local DataService = {}

local profiles = {} -- [player] = { Data = table, Key = string, Persist = bool }
local loadedEvent = Instance.new("BindableEvent")
DataService.ProfileLoaded = loadedEvent.Event -- (player, data)

local store
local storeOk = pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)
local jobId = if game.JobId ~= "" then game.JobId else "studio"

local function makeTemplate()
	local pedestals = {}
	for i = 1, Balance.Pedestals.StartSlots do
		pedestals[i] = { Level = 0, Pet = false }
	end
	return {
		Version = 1,
		Coins = Balance.Player.StartCoins,
		Crystals = Balance.Player.StartCrystals,
		Pets = {}, -- [uid] = { Id, Mutation, Locked }
		Pedestals = pedestals, -- { Level, Pet = uid | false }
		FridgeSlots = Balance.Fridge.StartSlots,
		Fridge = {}, -- { { Id, Mutation, Event } }
		OvenLevel = 1,
		Ovens = {}, -- { { Pop, StartedAt, Duration } }
		Pity = {}, -- [rarityId] = попсов без выпадения
		Patrons = { Summoned = {}, Chosen = false, Hidden = {} },
		FlexDecor = {},
		Items = { BananaTrap = 0 },
		Stats = {
			Grabs = 0,
			Steals = 0,
			PlaySeconds = 0,
			TugWins = 0,
			Hatched = 0,
			Sold = 0,
			TrapsPlaced = 0,
			TrapHits = 0,
			Trades = 0,
			Merges = 0,
			TotalCoins = 0,
		},
		Achievements = {}, -- [id] = "claimed"
		Settings = table.clone(Balance.DefaultSettings),
		TradeBanUntil = 0,
		TradeBlocked = {}, -- [tostring(userId)] = true, приглашения к обмену от них не приходят
		Basket = {}, -- { { Id, Mutation, Sleeping = true } } Спящие попсы с АФК-лежака
		BasketClearAt = 0, -- серверное время, когда корзина опустеет (0 = не идет)
	}
end

-- Добавляет в сохраненные данные ключи, которых не было в старой версии
local function reconcile(data, template)
	for key, value in template do
		if data[key] == nil then
			data[key] = if type(value) == "table" then table.clone(value) else value
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil and #value == 0 then
			reconcile(data[key], value)
		end
	end
end

local function tryLoad(key)
	local loadedData
	local locked = false
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(record)
			record = record or {}
			local lock = record.Lock
			if lock and lock.JobId ~= jobId and os.time() - lock.Time < LOCK_STALE_SECONDS then
				locked = true
				return nil -- отмена записи
			end
			record.Lock = { JobId = jobId, Time = os.time() }
			loadedData = record.Data
			return record
		end)
	end)
	if not ok then
		warn("[DataService] load error", key, err)
		return "error", nil
	end
	if locked then
		return "locked", nil
	end
	return "ok", loadedData
end

local function save(player, release: boolean)
	local profile = profiles[player]
	if not profile or not profile.Persist or not store then
		return -- профиль без сохранения (Studio без доступа к API)
	end
	local ok, err = pcall(function()
		store:UpdateAsync(profile.Key, function(record)
			record = record or {}
			local lock = record.Lock
			if lock and lock.JobId ~= jobId then
				-- Замок перехватил другой сервер: наши данные устарели, не перезаписываем
				warn("[DataService] lock lost, skip save", profile.Key)
				return nil
			end
			record.Data = profile.Data
			record.Lock = if release then nil else { JobId = jobId, Time = os.time() }
			return record
		end)
	end)
	if not ok then
		warn("[DataService] save error", profile.Key, err)
	end
end

local function onPlayerAdded(player: Player)
	local key = "u_" .. player.UserId
	local data
	local loaded = false

	if storeOk and store then
		for _ = 1, LOAD_RETRIES do
			local status, result = tryLoad(key)
			if status == "ok" then
				data = result
				loaded = true
				break
			end
			if status == "error" and RunService:IsStudio() then
				break -- в Studio без доступа к API не ждем 30 секунд
			end
			if not player.Parent then
				return
			end
			task.wait(LOAD_RETRY_WAIT)
		end
		if not loaded then
			if RunService:IsStudio() then
				warn("[DataService] DataStore недоступен, играем без сохранения")
			else
				player:Kick(
					"Данные еще сохраняются на другом сервере. Зайди через минуту."
				)
				return
			end
		end
	else
		warn(
			"[DataService] DataStore недоступен (Studio: включи Game Settings > Security > API Services)"
		)
	end

	if not player.Parent then
		-- игрок вышел во время загрузки: возвращаем данные как были и отпускаем замок
		if loaded then
			profiles[player] = { Data = data or makeTemplate(), Key = key, Persist = true }
			save(player, true)
			profiles[player] = nil
		end
		return
	end

	data = data or makeTemplate()
	reconcile(data, makeTemplate())
	profiles[player] = { Data = data, Key = key, Persist = loaded }
	player:SetAttribute("DataLoaded", true)
	loadedEvent:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	if profiles[player] then
		save(player, true)
		profiles[player] = nil
	end
end

function DataService.Get(player: Player)
	local profile = profiles[player]
	return profile and profile.Data
end

-- Ждет загрузки (для RemoteFunction, которые могут прийти раньше)
function DataService.WaitFor(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.2)
	end
	return DataService.Get(player)
end

function DataService.All()
	local result = {}
	for player, profile in profiles do
		result[player] = profile.Data
	end
	return result
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
