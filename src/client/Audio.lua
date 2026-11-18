-- Звук на клиенте: группы громкости, 2D/3D звуки из Config/Sounds, лупы, приглушение музыки
-- и звуки уведомлений. Если SoundService недоступен (тесты), все функции молча ничего не делают.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Sounds = require(Config:WaitForChild("Sounds"))
local Strings = require(Config:WaitForChild("Strings"))

local okService, SoundService = pcall(function()
	return game:GetService("SoundService")
end)
local enabled = okService and SoundService ~= nil

local Audio = {}

local groups = {} -- [name] = SoundGroup
local lastIndex = {} -- [key] = индекс последней вариации
local active = {} -- [key] = сколько копий играет
local duckUntil = 0
local openScreens = 0

function Audio.Enabled(): boolean
	return enabled
end

-- SoundGroup по имени из Sounds.Groups (создается один раз, вложенные наследуют громкость родителя)
function Audio.Group(name: string): SoundGroup?
	if not enabled then
		return nil
	end
	if groups[name] then
		return groups[name]
	end
	local def = Sounds.Groups[name]
	local parent = if def and def.Parent then Audio.Group(def.Parent) else SoundService
	local group = parent:FindFirstChild(name)
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = def and def.Volume or 1
		group.Parent = parent
	end
	groups[name] = group
	return group
end

local function pickId(key: string, ids): number?
	if not ids or #ids == 0 then
		return nil
	end
	local index = math.random(1, #ids)
	if #ids > 1 and index == lastIndex[key] then
		index = index % #ids + 1
	end
	lastIndex[key] = index
	return ids[index]
end
Audio.PickId = pickId

local function make(key: string, opts): Sound?
	if not enabled then
		return nil
	end
	local def = Sounds.Sfx[key]
	if not def then
		return nil
	end
	local id = pickId(key, def.Ids)
	if not id then
		return nil
	end
	if not def.Looped and (active[key] or 0) >= (def.Max or 4) then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = "rbxassetid://" .. string.format("%d", id)
	sound.Volume = (def.Volume or 0.5) * (opts and opts.Volume or 1)
	local spread = def.Pitch or 0
	sound.PlaybackSpeed = (opts and opts.Pitch or 1) * (1 + (math.random() * 2 - 1) * spread)
	sound.Looped = def.Looped == true
	sound.SoundGroup = Audio.Group(def.Group or "UI")
	if def.Spatial then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = def.Spatial[1]
		sound.RollOffMaxDistance = def.Spatial[2]
	end
	return sound
end

local function oneShot(key: string, sound: Sound, cleanup: Instance?)
	active[key] = (active[key] or 0) + 1
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		active[key] = math.max(0, (active[key] or 1) - 1)
		sound:Destroy()
		if cleanup then
			cleanup:Destroy()
		end
	end
	sound.Ended:Connect(finish)
	task.delay(20, finish) -- страховка: звук не загрузился или очень длинный
	sound:Play()
end

-- 2D: слышит только этот игрок
function Audio.Play(key: string, opts)
	local sound = make(key, opts)
	if not sound then
		return
	end
	sound.Parent = SoundService
	oneShot(key, sound)
end

-- 3D: в точке (Vector3) или на объекте (BasePart / Attachment). Без Spatial играет как 2D.
function Audio.PlayAt(key: string, where, opts)
	local def = Sounds.Sfx[key]
	if not def or not def.Spatial or where == nil then
		Audio.Play(key, opts)
		return
	end
	local sound = make(key, opts)
	if not sound then
		return
	end
	local holder = nil
	if typeof(where) == "Vector3" then
		holder = Instance.new("Attachment")
		holder.Name = "Sfx_" .. key
		holder.WorldPosition = where
		holder.Parent = workspace.Terrain
		sound.Parent = holder
	elseif typeof(where) == "Instance" and where.Parent and (where:IsA("BasePart") or where:IsA("Attachment")) then
		sound.Parent = where
	else
		sound:Destroy()
		Audio.Play(key, opts)
		return
	end
	oneShot(key, sound, holder)
end

-- Луп на объекте (или 2D без parent). Возвращает Sound, остановка = :Destroy()
function Audio.Loop(key: string, parent: Instance?, opts): Sound?
	local sound = make(key, opts)
	if not sound then
		return nil
	end
	sound.Looped = true
	sound.Parent = parent or SoundService
	sound:Play()
	return sound
end

-- Приглушение музыки на seconds (вылупление, выигрыш, Патрон)
function Audio.Duck(seconds: number?)
	duckUntil = math.max(duckUntil, os.clock() + (seconds or Sounds.Mix.EventDuckSeconds))
end

function Audio.ScreenOpened(open: boolean)
	openScreens = math.max(0, openScreens + (if open then 1 else -1))
end

-- Множитель громкости музыки с учетом приглушений
function Audio.MusicDuck(): number
	local factor = 1
	if openScreens > 0 then
		factor = math.min(factor, Sounds.Mix.ScreenDuck)
	end
	if os.clock() < duckUntil then
		factor = math.min(factor, Sounds.Mix.EventDuck)
	end
	return factor
end

-- Уведомления: текст сравнивается с шаблонами Strings (%s и %d), ключ -> звук из Sounds.Toasts
local patterns = nil
local function compile()
	patterns = {}
	for stringKey, sfx in Sounds.Toasts do
		local template = Strings[stringKey]
		if type(template) == "string" then
			local pattern = template:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
			pattern = pattern:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%-?%%d+)")
			table.insert(patterns, { Pattern = "^" .. pattern .. "$", Key = stringKey, Sfx = sfx })
		end
	end
	-- длинные шаблоны первыми, чтобы "%s" не перехватывал более точные
	table.sort(patterns, function(a, b)
		return #a.Pattern > #b.Pattern
	end)
end

-- Какой звук у уведомления: имя из Sounds.Sfx, false (без звука) и захваченный аргумент
function Audio.ToastSound(text: string): (string | boolean, string?)
	if not patterns then
		compile()
	end
	for _, entry in patterns do
		local capture = text:match(entry.Pattern)
		if capture ~= nil then
			return entry.Sfx, entry.Key
		end
	end
	return "Toast", nil
end

function Audio.OnToast(text: string)
	if not enabled or type(text) ~= "string" then
		return
	end
	local sfx = Audio.ToastSound(text)
	if sfx then
		Audio.Play(sfx :: string)
	end
end

return Audio
