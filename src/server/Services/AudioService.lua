-- Звуки с сервера: игра решает, когда звучать, клиенты играют звук из Config/Sounds (SoundController.client.lua).
-- Play = 2D одному игроку, PlayAt = 3D в точке или на объекте для всех, SetLoop = луп на объекте
-- (атрибут SfxLoop + тег SfxLoop), пока атрибут не снят.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local AudioService = {}

function AudioService.Play(player: Player, key: string)
	if player.Parent then
		Remotes.PlaySound:FireClient(player, key)
	end
end

-- where: Vector3 или BasePart / Attachment
function AudioService.PlayAt(key: string, where)
	if where == nil then
		return
	end
	for _, player in Players:GetPlayers() do
		Remotes.PlaySound:FireClient(player, key, where)
	end
end

function AudioService.SetLoop(part: Instance?, key: string?)
	if not part or part:GetAttribute("SfxLoop") == key then
		return
	end
	part:SetAttribute("SfxLoop", key)
	pcall(function()
		if not CollectionService:HasTag(part, "SfxLoop") then
			CollectionService:AddTag(part, "SfxLoop")
		end
	end)
end

-- Тег для клиентов (например, Sound бумбокса уходит в группу "Музыка")
function AudioService.Tag(instance: Instance, tag: string)
	pcall(function()
		CollectionService:AddTag(instance, tag)
	end)
end

function AudioService.Start() end

return AudioService
