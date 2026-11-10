-- Зона игрока (Base / OtherBase / Field / Center / Shop / Neutral) и флаг PvpEnabled как атрибуты,
-- плюс обработка падения с острова.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MapService = require(script.Parent:WaitForChild("MapService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local CakePopService = require(script.Parent:WaitForChild("CakePopService"))

local Zones = Balance.Zones
local MapConfig = Balance.Map
local FALL_DEBOUNCE = 2

local ZoneService = {}

local lastFall = {} -- [player] = os.clock()

function ZoneService.ZoneAt(player: Player, position: Vector3): string
	local pivot = MapService.IslandPivot()
	local radius = Vector3.new(position.X - pivot.X, 0, position.Z - pivot.Z).Magnitude
	if radius < Zones.CenterRadius then
		return "Center"
	end
	-- Безопасный пятачок вокруг Лавки Антона и ящика обмена (стоят у стены мельницы, в пшенице)
	local shop = MapService.Shop()
	if shop then
		for _, part in { shop.Counter, shop.Exchange, shop.BlackMarket } do
			if
				part
				and (Vector3.new(position.X, 0, position.Z) - Vector3.new(part.Position.X, 0, part.Position.Z)).Magnitude
					< Balance.Shop.SafeRadius
			then
				return "Shop"
			end
		end
	end
	if radius < Zones.FieldRadius then
		return "Field"
	end
	local baseIndex = MapService.BaseAt(position)
	if baseIndex then
		return if baseIndex == player:GetAttribute("BaseIndex") then "Base" else "OtherBase"
	end
	return "Neutral"
end

local function onFell(player: Player)
	local now = os.clock()
	if lastFall[player] and now - lastFall[player] < FALL_DEBOUNCE then
		return
	end
	lastFall[player] = now
	-- Попс падает вместе с игроком, CakePopService вернет его в лоток пульта
	CakePopService.Drop(player, false)
	BaseService.Teleport(player)
	Remotes.Notify:FireClient(player, Strings.FellOff)
end

local function update(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local position = root.Position
	local pivot = MapService.IslandPivot()
	local horizontal = Vector3.new(position.X - pivot.X, 0, position.Z - pivot.Z).Magnitude
	if position.Y < MapConfig.FallMinY or horizontal > MapConfig.FallMaxRadius then
		onFell(player)
		return
	end
	local zone = ZoneService.ZoneAt(player, position)
	if player:GetAttribute("Zone") ~= zone then
		player:SetAttribute("Zone", zone)
	end
	local pvp = zone == "Field"
	if player:GetAttribute("PvpEnabled") ~= pvp then
		player:SetAttribute("PvpEnabled", pvp)
	end
end

function ZoneService.Start()
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("Zone", "Neutral")
		player:SetAttribute("PvpEnabled", false)
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Zone", "Neutral")
		player:SetAttribute("PvpEnabled", false)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastFall[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Zones.UpdateSeconds)
			for _, player in Players:GetPlayers() do
				update(player)
			end
		end
	end)
end

return ZoneService
