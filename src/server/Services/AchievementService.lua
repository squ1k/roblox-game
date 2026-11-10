-- Достижения: сервер сообщает о выполненных и выдает награду по кнопке "Забрать"
-- (data.Achievements[id] = "claimed"). Прогресс считает общий модуль Shared.Achievements.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Achievements = require(Shared:WaitForChild("Achievements"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local CHECK_SECONDS = 3

local AchievementService = {}

local announced = {} -- [player] = { [id] = true } уже показали "Достижение выполнено"

local function claim(player: Player, id)
	local data = DataService.Get(player)
	local achievement = type(id) == "string" and Achievements.ById(id)
	if
		not data
		or not achievement
		or data.Achievements[id] == "claimed"
		or not Achievements.IsDone(data, achievement)
	then
		return
	end
	data.Achievements[id] = "claimed"
	if achievement.Coins then
		EconomyService.AddCoins(player, achievement.Coins)
	end
	if achievement.Crystals then
		EconomyService.AddCrystals(player, achievement.Crystals)
	end
	Remotes.ProfileChanged:FireClient(player)
end

local function check(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local seen = announced[player]
	if not seen then
		-- при входе не спамим уже выполненными
		seen = {}
		for _, achievement in Balance.Achievements do
			seen[achievement.Id] = Achievements.IsDone(data, achievement)
		end
		announced[player] = seen
		return
	end
	for _, achievement in Balance.Achievements do
		if not seen[achievement.Id] and Achievements.IsDone(data, achievement) then
			seen[achievement.Id] = true
			Remotes.Notify:FireClient(
				player,
				string.format(Strings.AchievementDone, Strings.AchievementNames[achievement.Id] or achievement.Id)
			)
			Remotes.ProfileChanged:FireClient(player)
		end
	end
end

function AchievementService.Start()
	Remotes.AchievementClaim.OnServerEvent:Connect(claim)
	Players.PlayerRemoving:Connect(function(player)
		announced[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				check(player)
			end
		end
	end)
end

return AchievementService
