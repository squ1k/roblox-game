-- Звуки и музыка на клиенте (ТЗ по звуку). Каталог в Config/Sounds, движок в Audio.lua (модуль).
-- Здесь: звуки от сервера (PlaySound), лупы на объектах (тег SfxLoop), вылупление, автомат и Tug-of-War,
-- шкаф, погода, оглушение, АФК, обмен, полноэкранные окна, шаги по материалам и музыка по зонам.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Sounds = require(Config:WaitForChild("Sounds"))
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))

local Audio = require(script.Parent:WaitForChild("Audio"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer

if not Audio.Enabled() then
	return
end

-- Группы громкости по настройкам (ползунки "Музыка" и "Звуки")
local musicGroup = Audio.Group("Music") :: SoundGroup
local soundsGroup = Audio.Group("Sounds") :: SoundGroup
for name in Sounds.Groups do
	Audio.Group(name)
end
local function applyVolume()
	local settings = ClientState.Profile and ClientState.Profile.Settings
	musicGroup.Volume = settings and settings.Music or Balance.DefaultSettings.Music
	soundsGroup.Volume = settings and settings.Sounds or Balance.DefaultSettings.Sounds
end
ClientState.ProfileChanged:Connect(applyVolume)
applyVolume()

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(target: Player): BasePart?
	local character = target.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Звуки от сервера: (key) = 2D, (key, Vector3 | Instance) = 3D
Remotes.PlaySound.OnClientEvent:Connect(function(key, where, opts)
	if type(key) ~= "string" then
		return
	end
	if key == "PatronSummon" or key == "OvenDing" then
		Audio.Duck()
	end
	if where ~= nil then
		Audio.PlayAt(key, where, opts)
	else
		Audio.Play(key, opts)
	end
end)

-- Лупы на объектах: сервер ставит атрибут SfxLoop = ключ и тег SfxLoop (моторы клешней)
local loops = {} -- [Instance] = { Key, Sound }
local function syncLoop(part: Instance)
	local key = part:GetAttribute("SfxLoop")
	local current = loops[part]
	if current and current.Key == key then
		return
	end
	if current then
		current.Sound:Destroy()
		loops[part] = nil
	end
	if type(key) == "string" and part.Parent then
		local sound = Audio.Loop(key, part)
		if sound then
			loops[part] = { Key = key, Sound = sound, Base = sound.Volume }
		end
	end
end
local function watchLoop(part: Instance)
	syncLoop(part)
	part:GetAttributeChangedSignal("SfxLoop"):Connect(function()
		syncLoop(part)
	end)
end
for _, part in CollectionService:GetTagged("SfxLoop") do
	watchLoop(part)
end
CollectionService:GetInstanceAddedSignal("SfxLoop"):Connect(watchLoop)
CollectionService:GetInstanceRemovedSignal("SfxLoop"):Connect(function(part)
	if loops[part] then
		loops[part].Sound:Destroy()
		loops[part] = nil
	end
end)

-- Бумбокс игрока идет через группу "Музыка", рядом с ним музыка игры молчит
local boomboxes = {}
local function addBoombox(sound: Instance)
	if sound:IsA("Sound") then
		sound.SoundGroup = musicGroup
		boomboxes[sound] = true
		sound.Destroying:Connect(function()
			boomboxes[sound] = nil
		end)
	end
end
for _, sound in CollectionService:GetTagged("Boombox") do
	addBoombox(sound)
end
CollectionService:GetInstanceAddedSignal("Boombox"):Connect(addBoombox)
CollectionService:GetInstanceRemovedSignal("Boombox"):Connect(function(sound)
	boomboxes[sound] = nil
end)

local function boomboxNearby(): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	for sound in boomboxes do
		local parent = sound.Parent
		local position = if parent and parent:IsA("BasePart")
			then parent.Position
			elseif parent and parent:IsA("Attachment") then parent.WorldPosition
			else nil
		if
			sound.IsPlaying
			and position
			and (position - root.Position).Magnitude <= (sound.RollOffMaxDistance or Sounds.Mix.BoomboxRange)
		then
			return true
		end
	end
	return false
end

-- Вылупление: звук по тиру редкости, слой мутации, Патрон
Remotes.PetHatched.OnClientEvent:Connect(function(petId, mutationId, readyFamilyId)
	local skebob = Families.SkebobById[petId]
	local rarity = skebob and Balance.RarityById[skebob.Rarity]
	Audio.Duck()
	Audio.Play("Hatch" .. Sounds.Tier(rarity and rarity.Order))
	if mutationId then
		local layer = if mutationId == "Astral" or mutationId == "Prismatic" then mutationId else "Shiny"
		task.delay(0.4, Audio.Play, "Hatch" .. layer)
	end
	if readyFamilyId then
		task.delay(0.8, Audio.Play, "PatronReady")
	end
end)

-- Выигрыш в автомате: тир по редкости из уведомления (Strings.ClawWin)
local function winTier(text: string)
	for _, rarity in Balance.Rarities do
		if text:find(rarity.Name, 1, true) then
			return Sounds.Tier(rarity.Order)
		end
	end
	return "Low"
end
Remotes.Notify.OnClientEvent:Connect(function(text)
	if type(text) == "string" then
		local _, stringKey = Audio.ToastSound(text)
		if stringKey == "ClawWin" then
			Audio.Duck()
			Audio.Play("Win" .. winTier(text))
		end
	end
end)

-- Автомат: старт игры, кнопка "Хватать", последние 3 секунды, Tug-of-War
local lastPhase = nil
local tickedFor = nil
local tugTick = nil
local function onPhase()
	local phase = player:GetAttribute("ClawPhase")
	if phase == "Aiming" and lastPhase == nil then
		Audio.Play("ClawStart")
	elseif phase == "Lowering" and lastPhase == "Aiming" then
		Audio.Play("ClawGrab")
	end
	if phase == "Tug" and lastPhase ~= "Tug" then
		Audio.Play("TugStart")
		tugTick = Audio.Loop("TugTick")
	elseif phase ~= "Tug" and tugTick then
		tugTick:Destroy()
		tugTick = nil
	end
	lastPhase = phase
end
player:GetAttributeChangedSignal("ClawPhase"):Connect(onPhase)

-- PvP включилось или выключилось (граница Пшеничного поля)
player:GetAttributeChangedSignal("PvpEnabled"):Connect(function()
	Audio.Play(if player:GetAttribute("PvpEnabled") then "PvpOn" else "PvpOff")
end)

-- АФК-лежак: плюх на матрас
player:GetAttributeChangedSignal("AFK"):Connect(function()
	if player:GetAttribute("AFK") then
		Audio.PlayAt("AfkLie", rootOf(player))
	end
end)

-- Оглушение: птички над головой любого игрока, пока он Stunned
local stunLoops = {} -- [Player] = Sound
local function syncStun(target: Player)
	local stunned = target:GetAttribute("Stunned") == true
	if stunned and not stunLoops[target] then
		local character = target.Character
		local head = character and character:FindFirstChild("Head")
		stunLoops[target] = head and Audio.Loop("StunStars", head) or nil
	elseif not stunned and stunLoops[target] then
		stunLoops[target]:Destroy()
		stunLoops[target] = nil
	end
end
local function watchPlayer(target: Player)
	target:GetAttributeChangedSignal("Stunned"):Connect(function()
		syncStun(target)
	end)
end
for _, other in Players:GetPlayers() do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(other)
	if stunLoops[other] then
		stunLoops[other]:Destroy()
		stunLoops[other] = nil
	end
end)

-- Обмен: приглашение, "Готов", сброс готовности, тиканье отсчета
local lastTrade = nil
Remotes.TradeState.OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then
		lastTrade = nil
		return
	end
	if state.Kind == "Invite" then
		Audio.Play("TradeInvite")
	elseif lastTrade and lastTrade.Kind ~= "Invite" then
		if state.TheirReady and not lastTrade.TheirReady then
			Audio.Play("TradeReady")
		end
		local wasReady = lastTrade.MyReady or lastTrade.TheirReady
		if wasReady and not state.MyReady and not state.TheirReady and not lastTrade.ConfirmLeft then
			Audio.Play("TradeReset")
		end
		local left = state.ConfirmLeft and math.ceil(state.ConfirmLeft)
		local before = lastTrade.ConfirmLeft and math.ceil(lastTrade.ConfirmLeft)
		if left and left ~= before then
			Audio.Play("TradeTick")
		end
	end
	lastTrade = state
end)

-- Полноэкранные окна HUD: звук открытия/закрытия и приглушение музыки
task.spawn(function()
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("HUD")
	local root = hud:WaitForChild("Root")
	local function watch(child: Instance)
		local openKey = Sounds.Screens[child.Name]
		if not openKey or not child:IsA("GuiObject") then
			return
		end
		local visible = child.Visible
		if visible then
			Audio.ScreenOpened(true)
		end
		child:GetPropertyChangedSignal("Visible"):Connect(function()
			if child.Visible == visible then
				return
			end
			visible = child.Visible
			Audio.ScreenOpened(visible)
			Audio.Play(if visible then openKey else "UiClose")
		end)
	end
	for _, child in root:GetChildren() do
		watch(child)
	end
	root.ChildAdded:Connect(watch)
end)

-- Тепловой шкаф: гудение у своего шкафа, пока идет разморозка, и "дзынь", когда готово
local ovenPart = nil
local function findOven(): BasePart?
	if ovenPart and ovenPart.Parent then
		return ovenPart
	end
	local runtime = workspace:FindFirstChild(Balance.Map.RuntimeFolder)
	local baseIndex = player:GetAttribute("BaseIndex")
	if not runtime or not baseIndex then
		return nil
	end
	for _, part in runtime:GetDescendants() do
		if part.Name == "Oven" and part:IsA("BasePart") and part:GetAttribute("BaseIndex") == baseIndex then
			ovenPart = part
			return part
		end
	end
	return nil
end
local dinged = {} -- [ключ слота] = true
local ovenPrimed = false
local ovenHum = nil
local function ovenCheck()
	local profile = ClientState.Profile
	local ovens = profile and profile.Ovens
	if type(ovens) ~= "table" then
		return
	end
	local t = serverNow()
	local running = false
	for _, entry in ovens do
		if type(entry) == "table" and entry.StartedAt and entry.Duration then
			local key = tostring(entry.StartedAt) .. ":" .. tostring(entry.Duration)
			if t >= entry.StartedAt + entry.Duration then
				if not dinged[key] then
					dinged[key] = true
					if ovenPrimed then
						Audio.Play("OvenDing")
						Audio.PlayAt("OvenDing", findOven())
					end
				end
			else
				running = true
			end
		end
	end
	ovenPrimed = true -- то, что дозрело до входа в игру, не звенит
	local oven = if running then findOven() else nil
	if oven and not ovenHum then
		ovenHum = Audio.Loop("OvenHum", oven)
	elseif not oven and ovenHum then
		ovenHum:Destroy()
		ovenHum = nil
	end
end
task.spawn(function()
	while true do
		task.wait(0.5)
		ovenCheck()
	end
end)

-- Погода: стингер старта и конца, фоновый луп ивента, приглушение мира в Токсичном Тумане
local weatherLoop = nil
local weatherLevel = 0
local weatherTarget = 1
local muffles = {} -- [SoundGroup] = EqualizerSoundEffect
local function setMuffle(on: boolean)
	for _, name in { "Gacha", "PvP", "Base" } do
		local group = Audio.Group(name)
		if group then
			if on and not muffles[group] then
				local eq = Instance.new("EqualizerSoundEffect")
				eq.Name = "Muffle"
				eq.HighGain = -20
				eq.MidGain = -6
				eq.LowGain = 0
				eq.Parent = group
				muffles[group] = eq
			elseif not on and muffles[group] then
				muffles[group]:Destroy()
				muffles[group] = nil
			end
		end
	end
end
local function onWeather()
	local eventId = workspace:GetAttribute("WeatherEvent")
	local weather = eventId and Sounds.Weather[eventId]
	if weatherLoop then
		local old = weatherLoop
		weatherLoop = nil
		task.spawn(function()
			for _ = 1, 30 do
				old.Volume *= 0.85
				task.wait(0.1)
			end
			old:Destroy()
		end)
	end
	if weather then
		Audio.Duck(3)
		Audio.Play("WeatherStart")
		task.delay(0.8, Audio.Play, weather.Start)
		weatherLoop = Audio.Loop(weather.Loop)
		if weatherLoop then
			weatherLoop:SetAttribute("BaseVolume", weatherLoop.Volume)
			weatherLoop.Volume = 0
		end
		weatherLevel = 0
	elseif eventId == nil then
		Audio.Play("WeatherEnd")
	end
end
workspace:GetAttributeChangedSignal("WeatherEvent"):Connect(onWeather)
if workspace:GetAttribute("WeatherEvent") then
	onWeather()
end

-- Шаги: звук бега (Running от стандартных звуков персонажа) по материалу под ногами
local materialToKind = {}
for kind, names in Sounds.Footsteps.Materials do
	for _, name in names do
		materialToKind[name] = kind
	end
end
local pvpGroup = Audio.Group("PvP")
local function updateFootsteps()
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local running = root and root:FindFirstChild("Running")
		if humanoid and running and running:IsA("Sound") then
			if running:GetAttribute("Default") == nil then
				running:SetAttribute("Default", running.SoundId)
				running.SoundGroup = pvpGroup
				running.RollOffMode = Enum.RollOffMode.InverseTapered
				running.RollOffMinDistance = Sounds.Footsteps.Spatial[1]
				running.RollOffMaxDistance = Sounds.Footsteps.Spatial[2]
			end
			local kind = materialToKind[humanoid.FloorMaterial.Name]
			if kind ~= running:GetAttribute("Kind") then
				running:SetAttribute("Kind", kind)
				local id = kind and Audio.PickId("Steps" .. kind, Sounds.Footsteps.Ids[kind])
				running.SoundId = if id
					then "rbxassetid://" .. string.format("%d", id)
					else running:GetAttribute("Default")
				if id then
					running.Volume = Sounds.Footsteps.Volume
				end
			end
		end
	end
end
task.spawn(function()
	while true do
		task.wait(0.25)
		updateFootsteps()
	end
end)

-- Музыка по зонам: кроссфейд, обрыв на Tug-of-War, тишина у бумбокса, приглушение UI
local tracks = {} -- [name] = { Sound, Level }
local current = nil
local lastSwitch = -math.huge
local fadeSeconds = 2

local function wantedTrack(): string?
	if boomboxNearby() then
		return nil
	end
	if player:GetAttribute("ClawPhase") == "Tug" then
		return "Tug"
	end
	if player:GetAttribute("AFK") then
		return "Afk"
	end
	local name = Sounds.MusicByZone[player:GetAttribute("Zone") or "Neutral"]
	local weather = Sounds.Weather[workspace:GetAttribute("WeatherEvent") or ""]
	if name and weather and weather.Night then
		local night = Sounds.Music[name .. "Night"]
		if night and #night.Ids > 0 then
			return name .. "Night"
		end
	end
	return name
end

local function trackSound(name: string)
	local entry = tracks[name]
	if entry then
		return entry
	end
	local def = Sounds.Music[name]
	local id = def and Audio.PickId("Music" .. name, def.Ids)
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. name
	sound.SoundId = "rbxassetid://" .. string.format("%d", id)
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = musicGroup
	sound.Parent = musicGroup.Parent
	entry = { Sound = sound, Level = 0, Volume = def.Volume or 0.5 }
	tracks[name] = entry
	return entry
end

local zoneVolumeOnBase = Sounds.Mix.WeatherAmbientOnBase
RunService.Heartbeat:Connect(function(dt)
	local wanted = wantedTrack()
	if wanted ~= current then
		local urgent = wanted == "Tug" or current == "Tug" or wanted == "Afk" or current == "Afk" or wanted == nil
		if urgent or os.clock() - lastSwitch >= Sounds.Mix.MinSwitchSeconds then
			local def = wanted and Sounds.Music[wanted]
			fadeSeconds = if wanted == "Tug" or current == "Tug" then 0.1 else (def and def.Fade or 2)
			current = wanted
			lastSwitch = os.clock()
		end
	end
	if current then
		trackSound(current)
	end
	local duck = Audio.MusicDuck()
	local fieldQuiet = if player:GetAttribute("Zone") == "Field" then 0.7 else 1
	local step = dt / math.max(fadeSeconds, 0.05)
	for name, entry in tracks do
		local target = if name == current then 1 else 0
		if entry.Level < target then
			entry.Level = math.min(target, entry.Level + step)
		elseif entry.Level > target then
			entry.Level = math.max(target, entry.Level - step)
		end
		local sound = entry.Sound
		sound.Volume = entry.Volume * entry.Level * duck * fieldQuiet
		if entry.Level > 0 and not sound.IsPlaying then
			if name == "Tug" then
				sound.TimePosition = 0
			end
			sound:Resume()
		elseif entry.Level <= 0 and sound.IsPlaying then
			sound:Pause()
		end
	end

	-- мотор клешни: громкость от скорости ладони
	for part, loop in loops do
		local def = Sounds.Sfx[loop.Key]
		if def and def.ByVelocity and part:IsA("BasePart") then
			local speed = part.AssemblyLinearVelocity.Magnitude
			local k = math.clamp(speed / def.ByVelocity, 0, 1)
			loop.Sound.Volume = loop.Base * (0.25 + 0.75 * k)
			loop.Sound.PlaybackSpeed = 0.85 + 0.3 * k
		end
	end

	-- последние 3 секунды прицеливания
	local endsAt = player:GetAttribute("ClawEndsAt")
	if player:GetAttribute("ClawPhase") == "Aiming" and endsAt and endsAt ~= tickedFor then
		if endsAt - serverNow() <= 3 then
			tickedFor = endsAt
			Audio.Play("ClawTimeTick")
		end
	end

	-- фон погоды: плавное появление и исчезновение, на базах тише
	if weatherLoop then
		weatherLevel = math.min(weatherTarget, weatherLevel + dt / 3)
		local zone = player:GetAttribute("Zone")
		local onBase = zone == "Base" or zone == "OtherBase"
		weatherLoop.Volume = (weatherLoop:GetAttribute("BaseVolume") or 0.3)
			* weatherLevel
			* (if onBase then zoneVolumeOnBase else 1)
	end
	local weather = Sounds.Weather[workspace:GetAttribute("WeatherEvent") or ""]
	local afkMuffle = Sounds.Mix.AfkMuffle and player:GetAttribute("AFK") == true
	local fieldMuffle = weather and weather.Muffle and player:GetAttribute("Zone") == "Field"
	setMuffle(afkMuffle or fieldMuffle == true)
end)
