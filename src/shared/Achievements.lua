-- Прогресс достижений по данным игрока. Общий для сервера (выдача награды) и клиента (полоски).

local Config = script.Parent:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))

local Achievements = {}

local computed = {}

function computed.UniquePets(data): number
	local seen, count = {}, 0
	for _, pet in data.Pets do
		if not seen[pet.Id] then
			seen[pet.Id] = true
			count += 1
		end
	end
	return count
end

function computed.Patrons(data): number
	local count = 0
	for _ in data.Patrons.Summoned do
		count += 1
	end
	return count
end

function computed.FullFamilies(data): number
	local owned = {}
	for _, pet in data.Pets do
		owned[pet.Id] = true
	end
	local count = 0
	for _, family in Families.List do
		local full = true
		for _, member in family.Members do
			if not owned[member.Id] then
				full = false
				break
			end
		end
		if full then
			count += 1
		end
	end
	return count
end

function Achievements.Value(data, achievement): number
	local compute = computed[achievement.Stat]
	if compute then
		return compute(data)
	end
	return data.Stats and data.Stats[achievement.Stat] or 0
end

function Achievements.IsDone(data, achievement): boolean
	return Achievements.Value(data, achievement) >= achievement.Goal
end

function Achievements.ById(id: string)
	for _, achievement in Balance.Achievements do
		if achievement.Id == id then
			return achievement
		end
	end
	return nil
end

return Achievements
