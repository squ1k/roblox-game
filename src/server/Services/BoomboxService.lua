-- Бумбокс (геймпасс Boombox): владелец вводит Roblox Audio ID в настройках, музыка играет на его базе
-- для всех, кто рядом (затухает к Monetization.BoomboxRange). ID хранится в data.Boombox, 0 = выключен.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local AudioService = require(script.Parent:WaitForChild("AudioService"))

local MAX_AUDIO_ID = 1e15

local BoomboxService = {}

local sounds = {} -- [player] = Sound

local function stop(player: Player)
	if sounds[player] then
		sounds[player]:Destroy()
		sounds[player] = nil
	end
end

local function apply(player: Player)
	stop(player)
	local data = DataService.Get(player)
	local base = MapService.GetBase(player:GetAttribute("BaseIndex") or 0)
	local anchor = base and base.Folder:FindFirstChild("Spawn")
	if not data or not anchor or data.Boombox <= 0 or player:GetAttribute("Pass_Boombox") ~= true then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Boombox"
	sound.SoundId = "rbxassetid://" .. string.format("%d", data.Boombox)
	sound.Looped = true
	sound.Volume = Balance.Monetization.BoomboxVolume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = Balance.Monetization.BoomboxRange
	sound.Parent = anchor
	AudioService.Tag(sound, "Boombox") -- клиенты пускают его через группу "Музыка"
	sound:Play()
	sounds[player] = sound
end

-- audioId: целое число > 0 (включить) или 0 (выключить)
function BoomboxService.Set(player: Player, audioId)
	local data = DataService.Get(player)
	if not data or player:GetAttribute("Pass_Boombox") ~= true then
		return
	end
	if type(audioId) ~= "number" or audioId ~= audioId or audioId % 1 ~= 0 or audioId < 0 or audioId > MAX_AUDIO_ID then
		Remotes.Notify:FireClient(player, Strings.BoomboxBadId)
		return
	end
	data.Boombox = audioId
	apply(player)
	Remotes.Notify:FireClient(player, if audioId > 0 then Strings.BoomboxOn else Strings.BoomboxOff)
	Remotes.ProfileChanged:FireClient(player)
end

function BoomboxService.Start()
	Remotes.BoomboxSet.OnServerEvent:Connect(BoomboxService.Set)
	DataService.ProfileLoaded:Connect(function(player)
		-- геймпасс проверяется асинхронно, музыка включится, когда появится атрибут
		player:GetAttributeChangedSignal("Pass_Boombox"):Connect(function()
			apply(player)
		end)
		apply(player)
	end)
	Players.PlayerRemoving:Connect(stop)
end

return BoomboxService
