-- Раздает базы игрокам (BaseIndex 1..8) и ставит персонажа на точку спавна своей базы.
-- Стандартный SpawnLocation остается запасным вариантом.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MapService = require(script.Parent:WaitForChild("MapService"))

local BaseService = {}

local owners = {} -- [baseIndex] = player

local function assign(player: Player)
	for index = 1, MapService.BaseCount() do
		if not owners[index] and MapService.GetBase(index) then
			owners[index] = player
			player:SetAttribute("BaseIndex", index)
			return index
		end
	end
	warn("[BaseService] нет свободной базы для", player.Name)
	return nil
end

function BaseService.GetIndex(player: Player): number?
	return player:GetAttribute("BaseIndex")
end

function BaseService.GetOwner(index: number): Player?
	return owners[index]
end

-- Телепорт персонажа на спавн своей базы
function BaseService.Teleport(player: Player)
	local index = player:GetAttribute("BaseIndex")
	local base = index and MapService.GetBase(index)
	local character = player.Character
	if not base or not character then
		return
	end
	-- StreamingEnabled: сначала подгружаем окрестности точки, потом переносим
	pcall(player.RequestStreamAroundAsync, player, base.SpawnCFrame.Position, 5)
	if character.Parent then
		character:PivotTo(base.SpawnCFrame)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	RunService.Heartbeat:Wait()
	BaseService.Teleport(player)
end

local function onPlayerAdded(player: Player)
	assign(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function BaseService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		local index = player:GetAttribute("BaseIndex")
		if index and owners[index] == player then
			owners[index] = nil
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return BaseService
