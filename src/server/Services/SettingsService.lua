-- Настройки игрока (data.Settings). Ключи и типы берутся из Balance.DefaultSettings,
-- громкость ограничена 0..1. Язык: "Auto" (по языку Roblox) до первого выбора, потом RU или EN.
-- Итоговый язык идет клиенту атрибутом игрока "Language" (его читает Localize.client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local LANGUAGES = { RU = true, EN = true }

local SettingsService = {}

local function resolveLanguage(player: Player, value): string
	if LANGUAGES[value] then
		return value
	end
	local locale = tostring(player.LocaleId or "")
	return if locale:sub(1, 2) == "ru" then "RU" else "EN"
end

local function set(player: Player, key, value)
	local data = DataService.Get(player)
	local default = type(key) == "string" and Balance.DefaultSettings[key]
	if not data or default == nil or type(value) ~= type(default) then
		return
	end
	if type(value) == "number" then
		if value ~= value then
			return
		end
		value = math.clamp(value, 0, 1)
	elseif key == "Language" and not LANGUAGES[value] then
		return
	end
	data.Settings[key] = value
	if key == "Language" then
		player:SetAttribute("Language", value)
	end
	Remotes.ProfileChanged:FireClient(player)
end

function SettingsService.Get(player: Player, key: string)
	local data = DataService.Get(player)
	local value = data and data.Settings and data.Settings[key]
	if value == nil then
		return Balance.DefaultSettings[key]
	end
	return value
end

function SettingsService.Start()
	Remotes.SettingsSet.OnServerEvent:Connect(set)
	DataService.ProfileLoaded:Connect(function(player, data)
		player:SetAttribute("Language", resolveLanguage(player, data.Settings.Language))
	end)
end

return SettingsService
