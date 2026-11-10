-- Состояния игрока (Carrying, Stunned, AFK) как атрибуты, которые читает HUD,
-- и проверки запросов от клиента.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Config"):WaitForChild("Strings"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local AFK_ZONE_TAG = "AfkZone" -- тег на Part лежака (CollectionService)
local HOTBAR_SLOTS = { "BananaTrap", false, false }

local PlayerStateService = {}

-- Обработчики расходников по Id: [itemId] = function(player, data). Регистрируют другие сервисы.
PlayerStateService.ItemHandlers = {}

function PlayerStateService.SetCarrying(player: Player, carrying: boolean)
	player:SetAttribute("Carrying", carrying)
end

function PlayerStateService.IsBusy(player: Player): boolean
	return player:GetAttribute("Carrying") == true or player:GetAttribute("Stunned") == true
end

local function isInsidePart(position: Vector3, part: BasePart): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y + 4 and math.abs(localPos.Z) <= half.Z
end

local function updateAfk(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local inside = false
	if root then
		for _, zone in CollectionService:GetTagged(AFK_ZONE_TAG) do
			local owner = zone:GetAttribute("BaseIndex")
			local ownBed = owner == nil or owner == player:GetAttribute("BaseIndex")
			if ownBed and zone:IsA("BasePart") and isInsidePart(root.Position, zone) then
				inside = true
				break
			end
		end
	end
	if inside and not player:GetAttribute("AFK") then
		player:SetAttribute("AFK", true)
		player:SetAttribute("AfkSince", workspace:GetServerTimeNow())
	elseif not inside and player:GetAttribute("AFK") then
		player:SetAttribute("AFK", false)
		player:SetAttribute("AfkSince", nil)
	end
end

function PlayerStateService.Start()
	local function initPlayer(player: Player)
		player:SetAttribute("Carrying", false)
		player:SetAttribute("Stunned", false)
		player:SetAttribute("AFK", false)
	end
	Players.PlayerAdded:Connect(initPlayer)
	for _, player in Players:GetPlayers() do
		initPlayer(player)
	end

	-- DropPop обрабатывает CakePopService

	Remotes.UseHotbar.OnServerEvent:Connect(function(player, slot)
		if type(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > #HOTBAR_SLOTS then
			return
		end
		if PlayerStateService.IsBusy(player) then
			return
		end
		if player:GetAttribute("PvpEnabled") ~= true then
			Remotes.Notify:FireClient(player, Strings.OnlyInField)
			return
		end
		local itemId = HOTBAR_SLOTS[slot]
		local data = DataService.Get(player)
		if not itemId or not data then
			return
		end
		if (data.Items[itemId] or 0) <= 0 then
			Remotes.Notify:FireClient(player, Strings.NoTraps)
			return
		end
		local handler = PlayerStateService.ItemHandlers[itemId]
		if handler then
			handler(player, data)
		end
	end)

	Remotes.GetProfile.OnServerInvoke = function(player)
		return DataService.WaitFor(player, 10)
	end

	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				updateAfk(player)
			end
		end
	end)
end

return PlayerStateService
