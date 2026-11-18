-- Каталог звуков и музыки (ТЗ по звуку: sound_design/Skebobs_ТЗ_звук_таблица.xlsx в файлах проекта).
-- Ids = список Roblox Audio ID (вариации, играется случайная, без повтора подряд). Пустой список = тишина,
-- поэтому звук можно заменить или выключить, не трогая код. Сейчас стоят временные звуки из
-- Creator Store (Pro Sound Effects, APM Music и DistroKid по лицензии Roblox, Daily Sounds и
-- бесплатные загрузки сообщества), финальные сдаст саунд-дизайнер (ТЗ, колонка Asset ID).
-- Group = подгруппа в SoundService (громкость задает ползунок "Звуки" или "Музыка").
-- Spatial = { min, max } студов: звук 3D в точке мира, иначе 2D (слышит только этот игрок).
-- Pitch = случайный разброс скорости ±доля. Max = сколько копий звука может играть одновременно.

local Sounds = {}

-- Подгруппы. Parent = группа, чью громкость (ползунок настроек) они наследуют.
Sounds.Groups = {
	Music = { Volume = 1 },
	Sounds = { Volume = 1 },
	UI = { Parent = "Sounds", Volume = 0.6 },
	Gacha = { Parent = "Sounds", Volume = 1 },
	PvP = { Parent = "Sounds", Volume = 1 },
	Base = { Parent = "Sounds", Volume = 0.8 },
	Ambient = { Parent = "Sounds", Volume = 0.35 },
	Voice = { Parent = "Sounds", Volume = 0.8 },
}

local function ui(ids, volume, extra)
	local def = { Ids = ids, Group = "UI", Volume = volume or 0.5, Pitch = 0.04 }
	for k, v in extra or {} do
		def[k] = v
	end
	return def
end

local function at(group, ids, volume, min, max, extra)
	local def = { Ids = ids, Group = group, Volume = volume or 0.6, Spatial = { min, max }, Pitch = 0.05 }
	for k, v in extra or {} do
		def[k] = v
	end
	return def
end

local function flat(group, ids, volume, extra)
	local def = { Ids = ids, Group = group, Volume = volume or 0.6, Pitch = 0.03 }
	for k, v in extra or {} do
		def[k] = v
	end
	return def
end

Sounds.Sfx = {
	-- UI
	UiTap = ui({ 106984966606682 }, 0.45, { Max = 6 }),
	UiOpen = ui({ 106984966606682 }, 0.4),
	UiClose = ui({ 106984966606682 }, 0.35),
	Toast = ui({ 106984966606682 }, 0.35),
	Error = ui({ 9120222115 }, 0.5),
	Buy = ui({ 130378474223829 }, 0.55),
	Sell = ui({ 130378474223829, 138309872562566 }, 0.55),
	PetDelete = ui({ 106984966606682 }, 0.45),
	Lock = ui({ 9118941667 }, 0.45),
	Purchase = ui({ 9067124098 }, 0.6),
	BlackMarket = ui({ 4612374393 }, 0.5),
	Achievement = ui({ 9067124098 }, 0.6),
	OfflineIncome = ui({ 130378474223829 }, 0.55),
	PvpOn = ui({}, 0.35),
	PvpOff = ui({}, 0.35),
	ShopOpen = ui({ 106984966606682 }, 0.5),
	TradeInvite = ui({ 4612374495 }, 0.55),
	TradeReady = ui({ 106984966606682 }, 0.45),
	TradeReset = ui({ 80890994815283 }, 0.5),
	TradeTick = ui({}, 0.6, { Pitch = 0 }),
	TradeDone = ui({ 9067124098 }, 0.6),
	TradeFail = ui({ 96795857757261 }, 0.45),

	-- Гача-автомат
	ClawStart = flat("Gacha", { 138309872562566 }, 0.6),
	ClawMotor = at("Gacha", { 9120214801 }, 0.35, 8, 45, { Looped = true, Pitch = 0, ByVelocity = 7 }),
	ClawTimeTick = flat("Gacha", { 136924498052589 }, 0.5, { Pitch = 0 }),
	ClawGrab = flat("Gacha", { 133564751966469 }, 0.6),
	ClawBump = at("Gacha", { 9116541944 }, 0.5, 6, 35),
	ClawClose = at("Gacha", { 9118941667 }, 0.6, 6, 35),
	ClawOpen = at("Gacha", { 9118941971 }, 0.5, 6, 35),
	CapsuleSlip = at("Gacha", { 9119197913 }, 0.7, 6, 40),
	CapsuleChute = at("Gacha", {}, 0.7, 8, 45),
	IceCrack = at("Gacha", { 1571353871 }, 0.6, 6, 35),
	WinLow = flat("Gacha", { 130378474223829 }, 0.7),
	WinMid = flat("Gacha", { 138309872562566, 130378474223829 }, 0.75),
	WinHigh = flat("Gacha", { 9067124098 }, 0.8),
	ClawMiss = flat("Gacha", { 96795857757261 }, 0.55),
	Restock = at("Gacha", { 9116541944 }, 0.7, 15, 120),
	TugStart = flat("Gacha", { 80890994815283 }, 0.7),
	TugTick = flat("Gacha", {}, 0.4, { Looped = true, Pitch = 0 }),
	TugClick = flat("Gacha", { 106984966606682 }, 0.35, { Max = 8, Pitch = 0.08 }),
	TugWin = flat("Gacha", { 9067124098 }, 0.8),
	TugLose = flat("Gacha", { 96795857757261 }, 0.6),

	-- Перенос и PvP
	PopPickup = at("PvP", { 106984966606682 }, 0.6, 6, 40),
	PopDrop = at("PvP", { 127599335301017 }, 0.6, 6, 40),
	PopLost = at("PvP", { 138309872562566 }, 0.7, 10, 60),
	PopMelt = at("PvP", { 96795857757261 }, 0.6, 6, 40),
	PopSticky = flat("PvP", {}, 0.5),
	TrapPlace = at("PvP", { 127599335301017 }, 0.65, 10, 70),
	TrapSlip = at("PvP", { 9119197913, 9119198140 }, 0.8, 10, 80),
	TrapTriggered = flat("PvP", { 133564751966469 }, 0.5),
	StunStars = at("PvP", {}, 0.4, 4, 25, { Looped = true, Pitch = 0 }),
	FellOff = flat("PvP", { 9119198140 }, 0.6),

	-- База и Скебобсы
	FridgeStore = at("Base", { 1571353871 }, 0.6, 5, 30),
	FridgeOpen = ui({}, 0.5),
	OvenPut = at("Base", {}, 0.55, 4, 25),
	OvenHum = at("Base", {}, 0.25, 3, 20, { Looped = true, Pitch = 0 }),
	OvenDing = at("Base", { 106123953900389 }, 0.7, 6, 60),
	OvenCancel = ui({ 96795857757261 }, 0.45),
	TimeSkip = ui({ 94077390731779 }, 0.55),
	Upgrade = ui({ 4612374495 }, 0.6),
	HatchLow = flat("Base", { 130378474223829 }, 0.7),
	HatchMid = flat("Base", { 138309872562566 }, 0.75),
	HatchHigh = flat("Base", { 9067124098 }, 0.8),
	HatchShiny = flat("Base", { 4612374393 }, 0.5),
	HatchPrismatic = flat("Base", { 4612374495 }, 0.55),
	HatchAstral = flat("Base", { 4612374393, 4612374495 }, 0.6),
	HatchCrystals = flat("Base", { 4612374495 }, 0.6),
	PatronReady = flat("Base", { 9067124098 }, 0.9),
	PatronSummon = at("Base", { 94077390731779 }, 0.9, 30, 250),
	PedestalEquip = flat("Base", { 106984966606682 }, 0.55),
	PedestalUnequip = flat("Base", { 106984966606682 }, 0.45),
	IncomeTick = at("Base", { 130378474223829 }, 0.15, 3, 15, { Max = 3 }),
	AfkLie = at("Base", {}, 0.5, 4, 20),
	SleepingPop = flat("Base", { 4612374393 }, 0.55),
	AfkSummary = flat("Base", { 4612374495 }, 0.5),
	MergeRun = flat("Base", { 94077390731779 }, 0.6),
	MergeSuccess = flat("Base", { 9067124098 }, 0.75),
	MergeFail = flat("Base", { 96795857757261 }, 0.55),
	MergeAppear = at("Base", { 4612374495 }, 0.6, 4, 30),

	-- Погода (стингер старта и конца общий, у каждого ивента свой старт и фоновый луп)
	WeatherStart = flat("Ambient", { 80890994815283 }, 1.6),
	WeatherEnd = flat("Ambient", { 96795857757261 }, 1.2),
}

-- Погода: ключи из Sounds.Sfx. Loop играет 2D-фоном (тише на базах), Muffle = приглушить звуки мира.
Sounds.Weather = {
	Eruption = { Start = "EruptionStart", Loop = "EruptionLoop" },
	CryoStorm = { Start = "CryoStormStart", Loop = "CryoStormLoop" },
	ToxicFog = { Start = "ToxicFogStart", Loop = "ToxicFogLoop", Muffle = true },
	NeonSmog = { Start = "NeonSmogStart", Loop = "NeonSmogLoop", Night = true },
	SandMirage = { Start = "SandMirageStart", Loop = "SandMirageLoop" },
	Starfall = { Start = "StarfallStart", Loop = "StarfallLoop", Night = true },
	TropicalRain = { Start = "TropicalRainStart", Loop = "TropicalRainLoop" },
	Tide = { Start = "TideStart", Loop = "TideLoop" },
}
for _, weather in Sounds.Weather do
	Sounds.Sfx[weather.Start] = Sounds.Sfx[weather.Start] or flat("Ambient", {}, 1.6)
	Sounds.Sfx[weather.Loop] = Sounds.Sfx[weather.Loop] or flat("Ambient", {}, 1, { Looped = true, Pitch = 0 })
end

-- Шаги: звук бега персонажа (Running из стандартных звуков Roblox) по материалу под ногами.
-- Пустой список = стандартный звук Roblox.
Sounds.Footsteps = {
	Volume = 0.6,
	Spatial = { 8, 60 },
	Materials = {
		Grass = { "Grass", "LeafyGrass", "Ground", "Mud" },
		Wood = { "Wood", "WoodPlanks" },
		Stone = { "Concrete", "Slate", "Rock", "Cobblestone", "Brick", "Granite", "Basalt", "Pavement", "Marble" },
		Sand = { "Sand", "Sandstone" },
		Snow = { "Snow" },
		Ice = { "Ice", "Glacier" },
		Water = { "Water" },
	},
	Ids = {
		Grass = {},
		Wood = {},
		Stone = {},
		Sand = {},
		Snow = {},
		Ice = {},
		Water = {},
	},
}

-- Музыка. Fade = секунды перехода к этому треку. Night = версия трека на ночные ивенты (если есть Ids).
Sounds.Music = {
	Base = { Ids = { 140722099430139 }, Volume = 0.5, Fade = 2 },
	Field = { Ids = { 9044702250, 113603259167759 }, Volume = 0.4, Fade = 1.5 },
	Center = { Ids = { 140486290054589 }, Volume = 0.45, Fade = 1.5 },
	Shop = { Ids = { 9046863253 }, Volume = 0.45, Fade = 2 },
	Afk = { Ids = { 96240272516811 }, Volume = 0.5, Fade = 3 },
	Tug = { Ids = { 98334096366477 }, Volume = 0.6, Fade = 0.1 },
	Neutral = { Ids = {}, Volume = 0.35, Fade = 2 },
	FieldNight = { Ids = {}, Volume = 0.4, Fade = 3 },
}

-- Зона игрока (атрибут Zone от ZoneService) -> трек
Sounds.MusicByZone = {
	Base = "Base",
	OtherBase = "Base",
	Field = "Field",
	Center = "Center",
	Shop = "Shop",
	Neutral = "Base", -- мосты и окраины: музыка базы (свой трек Neutral можно задать в Music)
}

Sounds.Mix = {
	MinSwitchSeconds = 2, -- на границе зон трек не меняется чаще
	ScreenDuck = 0.65, -- открыт полноэкранный UI: музыка x0.65 (около -4 дБ)
	EventDuck = 0.4, -- вылупление, выигрыш, Патрон: музыка x0.4 на время звука
	EventDuckSeconds = 2.5,
	WeatherAmbientOnBase = 0.4, -- фон погоды на базах тише, чем в поле
	BoomboxRange = 90, -- рядом с бумбоксом музыка игры молчит
	AfkMuffle = true,
}

-- Уведомления (ключи Strings) -> звук. false = без звука (звук играет в другом месте).
-- Уведомление без записи играет Toast.
Sounds.Toasts = {
	NoCoins = "Error",
	NoCrystals = "Error",
	FridgeFull = "Error",
	FridgeMax = "Error",
	TradeBusy = "Error",
	TradeBanLeft = "Error",
	TradeNobody = "Error",
	OwnBaseOnly = "Error",
	OvenBusy = "Error",
	OvenMax = "Error",
	HandsBusy = "Error",
	TrapTooClose = "Error",
	TrapLimit = "Error",
	OnlyInField = "Error",
	NoTraps = "Error",
	NoLitterMill = "Error",
	NoFreePedestal = "Error",
	PedestalRobux = "Error",
	ClawCooldown = "Error",
	ClawCarrying = "Error",
	ClawBusy = "Error",
	BoomboxBadId = "Error",
	LimitReached = "Error",
	MergeNotEnough = "Error",
	MergeMaxTier = "Error",
	MergeOwnOnly = "Error",
	ShopTooFar = "Error",
	ShopNothingToSell = "Error",
	ShopOnPedestal = "Error",
	NoFreePets = "Error",
	HotbarLocked = "Error",
	DonateSoon = "Error",
	ComingSoon = "Error",
	ShopSoon = "Error",
	SettingsSoon = "Error",
	Bought = "Buy",
	Sold = "Sell",
	DonatePurchased = "Purchase",
	BlackMarketDone = "BlackMarket",
	PetDeleted = "PetDelete",
	PetLocked = "Lock",
	Upgraded = "Upgrade",
	TimeSkipDone = "TimeSkip",
	OvenStarted = "OvenPut",
	OfflineIncome = "OfflineIncome",
	AchievementDone = "Achievement",
	TugWon = "TugWin",
	TugLost = "TugLose",
	ClawMiss = "ClawMiss",
	ClawWin = false, -- WinLow / WinMid / WinHigh по редкости
	TrapTriggered = "TrapTriggered",
	TrapPlaced = false, -- 3D от сервера
	Stunned = false, -- 3D от сервера
	PopStored = false, -- 3D от сервера
	PopMelted = false,
	PopSticky = "PopSticky",
	FellOff = "FellOff",
	SleepingArrived = "SleepingPop",
	AfkSummary = "AfkSummary",
	MergeSuccess = "MergeSuccess",
	MergeFailed = "MergeFail",
	HatchedCrystals = "HatchCrystals",
	Hatched = false, -- экран вылупления
	PatronReady = false, -- экран вылупления
	PatronSummoned = false, -- 3D от сервера
	TradeDone = "TradeDone",
	TradeCancelled = "TradeFail",
	TradeDeclined = "TradeFail",
	TradeNoRoom = "TradeFail",
	TradeSent = "Toast",
	WeatherStarted = false, -- звук погоды
	WeatherEnded = false,
	BoomboxOn = "Toast",
	BoomboxOff = "Toast",
}

-- Полноэкранные окна (дети HUD.Root): звук открытия (закрытие всегда UiClose), пока открыто, музыка тише
Sounds.Screens = {
	MainMenu = "UiOpen",
	FridgeScreen = "FridgeOpen",
	OvenScreen = "UiOpen",
	Settings = "UiOpen",
	Merge = "UiOpen",
	Shop = "ShopOpen",
	DonateShop = "UiOpen",
	BlackMarket = "UiOpen",
	TradePicker = "UiOpen",
	TradeSession = "UiOpen",
}

-- Тир редкости для звуков выигрыша и вылупления: 1-3 Low, 4-5 Mid, 6-9 High
function Sounds.Tier(order: number?): string
	order = order or 1
	if order >= 6 then
		return "High"
	elseif order >= 4 then
		return "Mid"
	end
	return "Low"
end

return Sounds
