-- Погодные ивенты: каждые EveryRestocks обновлений автомата начинается случайный ивент (не тот же,
-- что прошлый) на DurationRestocks обновлений. Пока он идет, MutatedPopShare капсул в автомате
-- получают мутацию ивента. Клиент рисует визуал и баннер по workspace.WeatherEvent / WeatherEndsAt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local GachaService = require(script.Parent:WaitForChild("GachaService"))

local Weather = Balance.Weather

local WeatherService = {}

local random = Random.new()
local restocks = 0
local active = nil -- id текущего ивента
local coveredLeft = 0 -- сколько еще обновлений автомата он захватывает после текущего
local lastEvent = nil

local function eventIds()
	local ids = {}
	for _, mutation in Balance.WeatherMutations do
		table.insert(ids, mutation.Event)
	end
	return ids
end

local function notifyAll(text: string)
	for _, player in Players:GetPlayers() do
		Remotes.Notify:FireClient(player, text)
	end
end

local function setEndsAt()
	if active then
		workspace:SetAttribute(
			"WeatherEndsAt",
			workspace:GetServerTimeNow() + Balance.Gacha.RestockSeconds * (coveredLeft + 1)
		)
	else
		workspace:SetAttribute("WeatherEndsAt", nil)
	end
end

function WeatherService.StartEvent(eventId: string?, covered: number)
	if not eventId then
		local ids = eventIds()
		repeat
			eventId = ids[random:NextInteger(1, #ids)]
		until eventId ~= lastEvent or #ids == 1
	end
	active = eventId
	lastEvent = eventId
	coveredLeft = covered
	workspace:SetAttribute("WeatherEvent", eventId)
	setEndsAt()
	notifyAll(string.format(Strings.WeatherStarted, Strings.WeatherNames[eventId] or eventId))
end

function WeatherService.StopEvent()
	if not active then
		return
	end
	active = nil
	workspace:SetAttribute("WeatherEvent", nil)
	setEndsAt()
	notifyAll(Strings.WeatherEnded)
end

function WeatherService.Current(): string?
	return active
end

-- Перед каждым обновлением автомата: закончить ивент или начать новый
local function beforeRestock()
	restocks += 1
	if active then
		coveredLeft -= 1
		if coveredLeft < 0 then
			WeatherService.StopEvent()
		else
			setEndsAt()
		end
	end
	if not active and restocks % Weather.EveryRestocks == 0 then
		WeatherService.StartEvent(nil, Weather.DurationRestocks - 1)
	end
end

-- Dev: J в Studio. Включает случайный ивент и сразу обновляет автомат; повторно выключает
function WeatherService.DevToggle(eventId: string?)
	if active then
		WeatherService.StopEvent()
		GachaService.Restock()
	else
		WeatherService.StartEvent(eventId, Weather.DurationRestocks)
		GachaService.Restock()
	end
end

function WeatherService.Start()
	GachaService.BeforeRestock:Connect(beforeRestock)
end

return WeatherService
