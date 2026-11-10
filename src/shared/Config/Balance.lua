-- Все числа баланса в одном месте. Источник: диздок + решения от 25.10.2026.
-- Значения с пометкой TODO в диздоке не заданы, стоят заглушки.

local Balance = {}

-- Редкости по порядку. Chance в процентах, Income в монетах/сек,
-- Pity = число попсов до гарантии (nil = без гарантии), HatchSeconds = базовая разморозка.
-- Glaze = цвет глазури попса. 9-й цвет (фиолетовый) добавлен, т.к. редкостей 9.
Balance.Rarities = {
	{
		Id = "Common",
		Name = "Обычный",
		Chance = 48.81,
		Income = 2,
		Pity = nil,
		HatchSeconds = 30,
		Glaze = Color3.fromRGB(245, 245, 245),
	},
	{
		Id = "Uncommon",
		Name = "Необычный",
		Chance = 27.87,
		Income = 10,
		Pity = nil,
		HatchSeconds = 90,
		Glaze = Color3.fromRGB(230, 60, 60),
	},
	{
		Id = "Rare",
		Name = "Редкий",
		Chance = 14.40,
		Income = 35,
		Pity = 20,
		HatchSeconds = 240,
		Glaze = Color3.fromRGB(70, 200, 90),
	},
	{
		Id = "Epic",
		Name = "Эпический",
		Chance = 6.07,
		Income = 100,
		Pity = 50,
		HatchSeconds = 720,
		Glaze = Color3.fromRGB(40, 170, 255),
	},
	{
		Id = "Legendary",
		Name = "Легендарный",
		Chance = 1.88,
		Income = 250,
		Pity = 100,
		HatchSeconds = 1800,
		Glaze = Color3.fromRGB(255, 200, 40),
	},
	{
		Id = "Mythic",
		Name = "Мифический",
		Chance = 0.55,
		Income = 500,
		Pity = 300,
		HatchSeconds = 3600,
		Glaze = Color3.fromRGB(170, 80, 255),
	},
	{
		Id = "Secret",
		Name = "Секретный",
		Chance = 0.24,
		Income = 800,
		Pity = 500,
		HatchSeconds = 7200,
		Glaze = Color3.fromRGB(200, 240, 255),
	},
	{
		Id = "Cosmic",
		Name = "Космический",
		Chance = 0.12,
		Income = 1300,
		Pity = 700,
		HatchSeconds = 10800,
		Glaze = Color3.fromRGB(40, 20, 90),
	},
	{
		Id = "Divine",
		Name = "Божественный",
		Chance = 0.07,
		Income = 2000,
		Pity = 1000,
		HatchSeconds = 14400,
		Glaze = Color3.fromRGB(0, 255, 170),
	},
}

Balance.RarityById = {}
for index, rarity in Balance.Rarities do
	rarity.Order = index
	Balance.RarityById[rarity.Id] = rarity
end

-- Мутации. У пета максимум одна: либо от погоды, либо случайная при вылуплении.
-- IncomeMult множит доход пета. Цена продажи у Антона: см. Balance.Sell (+25% за мутацию).
Balance.HatchMutations = {
	{ Id = "Shiny", Name = "Блестящий", Chance = 9.0, IncomeMult = 1.25 },
	{ Id = "Prismatic", Name = "Призматический", Chance = 2.5, IncomeMult = 1.75 },
	{ Id = "Astral", Name = "Астральный", Chance = 0.5, IncomeMult = 2.5 },
}

-- Особые эффекты погодных мутаций (скорость, кристаллы, соседи и т.д.) делаются в Epic 8,
-- здесь только множитель дохода самого пета.
Balance.WeatherMutations = {
	{ Id = "Melted", Name = "Расплавленный", Event = "Eruption", IncomeMult = 3.0 },
	{ Id = "Frozen", Name = "Ледяной", Event = "CryoStorm", IncomeMult = 1.5 },
	{ Id = "Toxic", Name = "Токсичный", Event = "ToxicFog", IncomeMult = 1.0 },
	{ Id = "Neon", Name = "Неоновый", Event = "NeonSmog", IncomeMult = 1.0 },
	{ Id = "Mirage", Name = "Миражный", Event = "SandMirage", IncomeMult = 1.75 },
	{ Id = "Starlight", Name = "Звездный", Event = "Starfall", IncomeMult = 2.0 },
	{ Id = "Stormy", Name = "Штормовой", Event = "TropicalRain", IncomeMult = 1.8 },
	{ Id = "Bubble", Name = "Пузырьковый", Event = "Tide", IncomeMult = 2.0 },
}

Balance.MutationById = {}
for _, mutation in Balance.HatchMutations do
	Balance.MutationById[mutation.Id] = mutation
end
for _, mutation in Balance.WeatherMutations do
	Balance.MutationById[mutation.Id] = mutation
end

-- Пьедесталы. Уровень 0 = только что купленный, множитель x1.
-- Множитель = 1.3^уровень (совпадает со всеми вехами диздока).
-- Цена следующего уровня берется из вех диздока с лог-интерполяцией между ними.
Balance.Pedestals = {
	StartSlots = 3,
	MaxFreeSlots = 10,
	MaxSlots = 12, -- 11 и 12 только за Robux
	MaxLevel = 60,
	LevelMultBase = 1.3,
	LevelPriceMilestones = {
		{ 1, 100 },
		{ 5, 443 },
		{ 10, 2834 },
		{ 20, 311539 },
		{ 30, 46382737 },
		{ 40, 9350731370 },
		{ 50, 2.51e12 },
		{ 60, 895.73e12 },
	},
	-- Цена слота ~10 минут ожидаемого дохода игрока на момент покупки (доход растет ~x3.5 за слот).
	SlotPrices = { [4] = 3000, [5] = 12000, [6] = 50000, [7] = 200000, [8] = 800000, [9] = 3e6, [10] = 12e6 },
}

Balance.Fridge = {
	StartSlots = 5,
	MaxSlots = 20,
	-- Цена слота n (6..20): 1000 x 1.6^(n-6), округлено до 2 значащих цифр. Последний слот ~720K.
	SlotPriceBase = 1000,
	SlotPriceGrowth = 1.6,
}

Balance.Oven = {
	MaxSlots = 4,
	-- TODO: в диздоке нет таблицы уровней. Speed делит время разморозки.
	Levels = {
		{ Slots = 1, Speed = 1, Price = 0 },
		{ Slots = 1, Speed = 1.5, Price = 5000 },
		{ Slots = 2, Speed = 1.5, Price = 50000 },
		{ Slots = 2, Speed = 2.5, Price = 500000 },
		{ Slots = 3, Speed = 2.5, Price = 5e6 },
		{ Slots = 4, Speed = 4, Price = 5e7 },
	},
	ForeignFamilyTimeMult = 4, -- разморозка в 4 раза дольше, если Семейство попса не разблокировано
	-- Семейство считается разблокированным, если у игрока есть хотя бы один Скебобс этого Семейства.
	-- TODO: в диздоке "куплено ли Семейство" не описано, это временное правило.
}

Balance.Gacha = {
	Capacity = 30,
	RestockSeconds = 240,
	Terminals = 4,
	AttemptSeconds = 10, -- максимум времени внутри терминала
	AttemptCooldownSeconds = 30, -- после любой игры, выигрыш или проигрыш
	GrabHoldChance = 0.75, -- после физического захвата сервер бросает шанс удержания
	ConflictSeconds = 3, -- мини-игра = только Tug-of-War при конфликте клешней
	-- Попытка = вход в интерфейс терминала. Проигрыш в мини-игре попытку не возвращает.
	MaxClicksPerSecond = 15, -- защита от автокликеров
}

-- Четыре физические клешни, по одной на пульт (решение от 01.11.2026: все 4 игрока играют
-- одновременно, каждая клешня ездит по всей куче). Оси автомата повернуты на 45 градусов.
-- Ложе квадратное (решение от 01.11.2026), у каждого пульта своя дыра в углу ложа над своим лотком Delivery_X.
Balance.Claw = {
	MoveSpeed = 7, -- студов/сек по горизонтали
	LowerSpeed = 7,
	RaiseSpeed = 8,
	AimHalf = 7.9, -- ложе квадратное 20x20 (автомат уменьшен 04.11.2026: по горизонтали /1.2, по высоте /1.1): клешня ходит в квадрате +-AimHalf от центра по осям мира
	ClawReach = 4.9, -- от центра ладони до кончиков пальцев
	FingerOpenDeg = 30,
	FingerSpeedDeg = 160, -- скорость раскрытия/закрытия, градусов/сек
	CloseSeconds = 0.45,
	ReleaseSeconds = 0.9,
	GrabRadius = 1.6, -- захват ищет капсулы в этом радиусе от точки между пальцами
	StallDistance = 1.2, -- если ладонь отстает от цели вниз на столько, клешня уперлась
	StallSeconds = 0.25,
	MaxForce = 25000,
	Responsiveness = 25,
	HoleRadius = 11.08, -- от центра ложа к своему лотку Delivery_X: дыра в углу квадратного ложа над шахтой лотка
	ClawSeparation = 3.75, -- при прицеливании клешни не заезжают друг в друга ближе этого
	ArriveTolerance = 0.85, -- клешня ближе этого к центру своей дыры, но дальше не едет...
	ArriveTimeout = 0.6, -- ...столько секунд: все равно разжимается
	HoleInner = 3.67,
	HoleWallHeight = 2.9,
	ContainerRadius = 12.2, -- не используется: невидимые стенки теперь идут по краям квадратного ложа
	ContainerHeight = 9.1, -- ниже клешни в верхней точке, иначе пальцы цепляют стенки в углах
	ContainerSegments = 20,
	SpawnDropHeight = 7.3, -- новые капсулы падают сверху от ложа
	SpawnHoleClearance = 4.2, -- не ближе к центру дыры, чтобы при рестоке капсулы не падали в нее сами
	AwardWindowSeconds = 3, -- после разжатия капсула, упавшая в дыру, засчитывается игроку
	SpawnRadius = 7.5,
	CapsuleDiameter = 2.17,
	InputRate = 15, -- сообщений ClawInput в секунду с клиента
	-- Камера внутри мельницы (стены ярусов ~24 студа от центра), чуть снаружи колбы со стороны игрока.
	-- Проверено лучами со всех 4 пультов: d 16..22 при h 13..20 видно все ложе.
	CameraDistance = 16.7, -- по горизонтали от центра ложа
	CameraHeight = 14.5, -- над верхом ложа
	CameraLookHeight = 4.5, -- точка взгляда над центром ложа (видно и клешню, и капсулы)
}

-- Погода (решение от 28.10.2026): ивент начинается на каждом 4-м обновлении автомата,
-- тип случайный, длится ровно один цикл автомата. Ровно половина попсов в автомате с мутацией ивента.
Balance.Weather = {
	EveryRestocks = 4,
	DurationRestocks = 1,
	MutatedPopShare = 0.5,
	-- Визуал заглушками через Lighting на клиенте (WeatherEffects). Color = цвет баннера и подсветки капсул.
	Events = {
		Eruption = {
			Color = Color3.fromRGB(255, 90, 40),
			Ambient = Color3.fromRGB(150, 60, 40),
			FogColor = Color3.fromRGB(120, 50, 30),
			FogEnd = 400,
			Haze = 3,
		},
		CryoStorm = {
			Color = Color3.fromRGB(150, 220, 255),
			Ambient = Color3.fromRGB(120, 160, 200),
			FogColor = Color3.fromRGB(200, 230, 255),
			FogEnd = 250,
		},
		ToxicFog = {
			Color = Color3.fromRGB(110, 230, 80),
			Ambient = Color3.fromRGB(80, 140, 60),
			FogColor = Color3.fromRGB(90, 160, 60),
			FogEnd = 150,
		},
		NeonSmog = {
			Color = Color3.fromRGB(255, 60, 220),
			ClockTime = 0,
			Ambient = Color3.fromRGB(80, 40, 120),
			MillGlow = true,
		},
		SandMirage = {
			Color = Color3.fromRGB(240, 200, 100),
			Ambient = Color3.fromRGB(180, 150, 90),
			FogColor = Color3.fromRGB(230, 200, 130),
			FogEnd = 180,
			Haze = 2,
		},
		Starfall = {
			Color = Color3.fromRGB(255, 240, 150),
			ClockTime = 0,
			Ambient = Color3.fromRGB(70, 70, 120),
			Sparkles = true,
		},
		TropicalRain = {
			Color = Color3.fromRGB(120, 160, 190),
			Ambient = Color3.fromRGB(110, 120, 130),
			FogColor = Color3.fromRGB(140, 150, 160),
			FogEnd = 300,
			Rain = true,
		},
		Tide = { Color = Color3.fromRGB(60, 160, 255), Ambient = Color3.fromRGB(70, 130, 190) },
	},
	-- Эффекты мутаций (простые из диздока, остальное TODO в сервисах)
	FrozenPopFriction = 0.05, -- ледяной попс скользит дальше при сбросе
	ToxicStickSeconds = 1.5, -- брошенный токсичный попс нельзя поднять сразу
	NeonPopScale = 0.6, -- неоновый попс маленький и без замедления в поле
	FrozenOvenMult = 0.75, -- Ледяной Скебобс на пьедестале: шкаф на 25% быстрее
	ToxicMergeBonus = 0.1, -- Токсичный Скебобс на пьедестале: +10% к шансу "Риска" на Алтаре
}

-- Донат (Epic 8). Id = 0: товар виден, кнопка серая "Скоро". Цены в Robux из диздока.
Balance.Monetization = {
	GamePasses = {
		{ Key = "XRay", Id = 0, Robux = 379 },
		{ Key = "Vip", Id = 0, Robux = 1000 },
		{ Key = "SecondOven", Id = 0, Robux = 789 },
		{ Key = "SecondFridge", Id = 0, Robux = 779 },
		{ Key = "AutoClicker", Id = 0, Robux = 489 },
		{ Key = "SpeedPotion", Id = 0, Robux = 979 },
	},
	Products = {
		{ Key = "LuckPotion", Id = 0, Robux = 99 },
		{ Key = "Coins1", Id = 0, Robux = 50, IncomeSeconds = 1800 }, -- TODO: сколько монет, в диздоке нет
		{ Key = "Coins2", Id = 0, Robux = 400, IncomeSeconds = 18000 },
		{ Key = "Coins3", Id = 0, Robux = 2500, IncomeSeconds = 150000 },
		{ Key = "Crystals1", Id = 0, Robux = 500, Crystals = 500 }, -- 1 Кристалл = 1 R$
		{ Key = "Crystals2", Id = 0, Robux = 4000, Crystals = 4000 },
		{ Key = "Crystals3", Id = 0, Robux = 25000, Crystals = 25000 },
	},
	MinCoinsPack = 1000, -- если доход еще маленький
}

-- Терминал Черного рынка у Лавки Антона: обмен Монет на Кристаллы и обратно (курс из диздока)
Balance.BlackMarket = {
	CoinsPerCrystal = 1e12, -- купить 1 Кристалл
	CoinsForCrystal = 1e5, -- продать 1 Кристалл
	MaxAmount = 100, -- за одну операцию
}

Balance.CakePop = {
	CarrySpeedMult = 0.8, -- только в Пшеничном поле
	MeltInHandsSeconds = 600,
	MeltOnGroundSeconds = 300,
	-- Физический попс (Epic 3): шар цвета глазури на палочке. Пока поднять может только владелец
	-- (OwnerUserId), кража чужих попсов будет в Epic 4.
	Diameter = 2.2,
	StickLength = 2.4,
	BackOffset = Vector3.new(0, 0.6, 1.6), -- устарело: раньше попс висел на спине
	HoldArmAngle = 45, -- правая рука согнута вперед на столько градусов (поза CarryPose на клиенте)
	CarrySwayDeg = 5, -- покачивание руки при ходьбе
	CarrySwaySpeed = 8,
	CarryBlendSeconds = 0.2, -- плавный подъем и опускание руки
	CarryAnimationId = 0, -- TODO: можно заменить позу на загруженную анимацию переноса
	GripInset = 0.4, -- насколько палочка входит в кисть
	ThrowSpeed = 15, -- толчок вперед при сбросе, студов/сек
	TrayLift = 1.5, -- над точкой CapsuleExit в лотке
	TrayAnchorSeconds = 0.5, -- попс в лотке сначала без физики
	PromptDistance = 8, -- ProximityPrompt и серверная проверка расстояния
	OwnerOfflineSeconds = 60, -- попс вышедшего игрока удаляется через столько секунд
}

Balance.BananaTrap = {
	MaxCarry = 10, -- в инвентаре
	MaxActivePerPlayer = 3, -- одновременно стоящих на карте
	MaxActivePerServer = 24, -- 3 x 8 игроков
	LifetimeSeconds = 120, -- исчезает раньше, если автомат обновил ассортимент
	TriggerRadius = 2.5,
	StunSeconds = 1.5,
	FieldOpacity = 0.2, -- в пшенице чужой капкан виден на 20%
	OwnOpacity = 0.7, -- свои капканы владелец видит лучше (только у себя на клиенте)
	MinSpacing = 4, -- не ближе к своему другому капкану
	PlaceDistance = 3, -- ставится перед игроком
	VictimHeight = 4, -- по вертикали от корня персонажа до капкана, чтобы сработал
	CheckSeconds = 0.1, -- как часто сервер проверяет наступивших
	SlipImpulse = 30, -- толчок жертве назад при падении
	-- Цена динамическая: столько секунд максимально возможного дохода игрока
	-- (все пьедесталы с текущими петами + все временные баффы: АФК, друзья по максимуму).
	PriceIncomeSeconds = 60, -- TODO: подобрать на плейтестах
	MinPrice = 50, -- для новичка без петов
	Packs = {
		{ Amount = 1, PriceMult = 1 },
		{ Amount = 5, PriceMult = 4.5 }, -- -10%
		{ Amount = 10, PriceMult = 8 }, -- -20%
	},
}

-- Лавка Антона и "ООО СкебобсОбмен" (Epic 4). Пещеры под мельницей на карте нет,
-- обе заглушки стоят в Skebobs_Runtime.Shop у мельницы, в безопасной зоне.
Balance.Shop = {
	PromptDistance = 8, -- ProximityPrompt и серверная проверка расстояния до прилавка
	SafeRadius = 12, -- вокруг прилавка и ящика PvP выключено
}

Balance.Trade = {
	MaxItems = 3, -- до 3 Скебобсов с каждой стороны
	ConfirmSeconds = 3, -- таймер после "Готов" у обоих (на случай миссклика)
	BanSeconds = 3600, -- трейд-бан после успешного обмена
	PromptDistance = 8, -- ProximityPrompt у ящика
	InviteSeconds = 20, -- сколько живет приглашение
}

-- Продажа Антону. Решение от 28.10.2026: цена Скебобса = 4 минуты его дохода
-- (базовый доход редкости, без уровня пьедестала и глобальных баффов),
-- попс стоит треть цены Скебобса той же редкости, мутация (максимум одна) +25%.
Balance.Sell = {
	PetIncomeSeconds = 240,
	PopShare = 1 / 3,
	MutationMult = 1.25,
}

-- Оффлайн-доход: доля обычного дохода, начисляется не дольше MaxHours отсутствия
Balance.Offline = {
	IncomeShare = 0.5,
	MaxHours = 24,
}

Balance.Afk = {
	SleepingPopSeconds = 3600,
	SleepingPopSecondsVip = 2700,
	BasketClearSeconds = 1800,
	SleepingCrystalChance = 0.05, -- Спящий попс при разморозке вместо Скебобса дает Кристаллы
	SleepingCrystalsMin = 10,
	SleepingCrystalsMax = 50,
}

-- Объекты базы (Epic 5): кнопки на пьедесталах, Холодильнике, Тепловом шкафу, Алтаре и лежаке
Balance.BaseObjects = {
	PromptDistance = 8,
	PedestalPromptHeight = 2.5, -- над верхом пьедестала
	PedestalPromptDistance = 5, -- меньше, чтобы E у пьедестала не перехватывал Холодильник/шкаф рядом
	OvenLabelSeconds = 1, -- как часто обновлять таймеры над шкафом
}

Balance.Merge = {
	-- Режим "риск": 3 попса одного тира и Семейства, шанс 33% на следующий тир
	RiskAmount = 3,
	RiskChance = 0.33,
	-- Режим "гарант": 10 одинаковых Скебобсов одного тира, гарантированный попс следующего тира
	GuaranteedAmount = 10,
	PopLifetimeSeconds = 600,
}

-- Патроны (Epic 6). Призыв бесплатный, когда собрано PatronUnlockShare уникальных Скебобсов Семейства.
-- Главный (Chosen) Патрон один, повторный выбор снимает. Модели пока заглушки над базой.
Balance.Patrons = {
	SizeMult = 2, -- модель Патрона в 2 раза больше Скебобса на пьедестале
	ChosenSizeMult = 10, -- главный в 10 раз больше...
	ChosenMaxSize = 12, -- ...но не больше этого, чтобы не вылезать за базу
	HoverHeight = 12, -- над полом базы
	ChosenHeight = 20,
	RingRadius = 8, -- несколько Патронов висят кольцом над центром базы
	RefreshSeconds = 2,
	ChosenPrice = 0, -- TODO: в диздоке "за Софт/Хард валюту" без числа, пока бесплатно
}

-- Достижения (раздел "Достижения" диздока). Stat = счетчик data.Stats или вычисляемое значение
-- (UniquePets, Patrons, FullFamilies). Награда забирается кнопкой в рюкзаке.
Balance.Achievements = {
	{ Id = "FirstWin", Icon = "🕹️", Stat = "Grabs", Goal = 1, Coins = 500 },
	{ Id = "Wins10", Icon = "🎯", Stat = "Grabs", Goal = 10, Coins = 5000 },
	{ Id = "Wins100", Icon = "🏆", Stat = "Grabs", Goal = 100, Crystals = 25 },
	{ Id = "TugWin", Icon = "💪", Stat = "TugWins", Goal = 1, Coins = 2000 },
	{ Id = "Hatch10", Icon = "🐣", Stat = "Hatched", Goal = 10, Coins = 3000 },
	{ Id = "Collector20", Icon = "📖", Stat = "UniquePets", Goal = 20, Crystals = 10 },
	{ Id = "FullFamily", Icon = "👪", Stat = "FullFamilies", Goal = 1, Crystals = 20 },
	{ Id = "FirstPatron", Icon = "👑", Stat = "Patrons", Goal = 1, Crystals = 15 },
	{ Id = "Patrons3", Icon = "🌟", Stat = "Patrons", Goal = 3, Crystals = 50 },
	{ Id = "Seller10", Icon = "🦝", Stat = "Sold", Goal = 10, Coins = 5000 },
	{ Id = "Thief", Icon = "🥷", Stat = "Steals", Goal = 1, Coins = 3000 },
	{ Id = "Trapper20", Icon = "🍌", Stat = "TrapsPlaced", Goal = 20, Coins = 4000 },
	{ Id = "Trader", Icon = "🤝", Stat = "Trades", Goal = 1, Coins = 2000 },
	{ Id = "Alchemist", Icon = "🔮", Stat = "Merges", Goal = 5, Crystals = 10 },
	{ Id = "Millionaire", Icon = "💰", Stat = "TotalCoins", Goal = 1e6, Crystals = 30 },
}

-- Настройки игрока по умолчанию (data.Settings). Тип каждого ключа проверяет сервер.
Balance.DefaultSettings = {
	Music = 0.5,
	Sounds = 0.8,
	ShowOtherPrompts = false, -- подсказки на чужих базах
	IncomePopups = true,
	ScreenShake = true,
	TradeBlockAll = false,
	Language = "RU",
}

-- Клиентские эффекты мира (Epic 7)
Balance.WorldEffects = {
	IncomePopupSeconds = 3, -- раз в столько секунд над своими Скебобсами всплывает их доход "+N"
	FloatSeconds = 1.6,
	FloatRise = 4,
	ZzzSeconds = 1.4,
	PatronBobHeight = 1.2,
	PatronBobSpeed = 1.5,
	PatronSpinSpeed = 0.6, -- радиан/сек
}

-- Глобальные множители дохода
Balance.Buffs = {
	PatronFamilyMult = 2, -- x2 к доходу своего Семейства
	PatronUnlockShare = 0.8,
	FlexDecorMult = 1.5, -- за каждую полную коллекцию. TODO: стакаются ли - сейчас перемножаются
	VipMult = 1.2,
	AfkMult = 1.1, -- +10% на АФК-лежаке
	FriendMult = 1.1, -- +10%, если на сервере есть хотя бы один друг из Roblox
}

-- Задания. Награды в Монетах по сложности, бонус за все 5 (по разделу "Ежедневные задания").
-- Кристаллы за дейлики (из раздела монетизации) не выдаются.
Balance.Quests = {
	DailyCount = 5,
	-- Сброс в 00:00 по местному времени игрока (часовой пояс запоминается при первом входе)
	ResetLocalHour = 0,
	WeeklyCount = 5,
	WeeklyResetWeekday = 6, -- суббота (1 = понедельник, 7 = воскресенье)
	-- TODO: суммы наград в диздоке не заданы. Предложение: награда = N секунд дохода игрока,
	-- чтобы задания не обесценивались на поздних стадиях.
	RewardIncomeSeconds = { Easy = 120, Medium = 300, Hard = 600 },
	DailyBonusIncomeSeconds = 900,
	WeeklyBonusIncomeSeconds = 3600, -- + один случайный расходник
}

-- Карта (решение от 28.10.2026: базы стоят прямо в биомах, а не у края острова).
-- Имена моделей в Workspace.RoundField_Big. Порядок задает BaseIndex 1..8.
Balance.Map = {
	FieldModel = "RoundField_Big",
	IslandPivot = "IslandPivot",
	RuntimeFolder = "Skebobs_Runtime", -- заглушки и служебные объекты, модели художника не трогаем
	BaseOrder = {
		"BaseTownHall",
		"BaseBeachBar",
		"BasePyramid",
		"BaseIce",
		"BaseCave",
		"BaseSwamp",
		"BaseJungle",
		"BaseHell",
	},
	SpawnHeight = 3,
	PedestalSpacing = 4.5, -- минимум между пьедесталами при генерации недостающих
	PlaceholderPedestalSize = Vector3.new(2.5, 1, 2.5),
	FacilitySize = Vector3.new(4, 4, 4), -- Холодильник, Тепловой шкаф, Алтарь (заглушки)
	AfkBedSize = Vector3.new(10, 1, 10),
	AfkBedColor = Color3.fromRGB(153, 120, 255),
	FallMinY = 2, -- земля острова ~10.4, верх Baseplate 0
	FallMaxRadius = 320, -- по горизонтали от IslandPivot
}

-- Зоны: концентрические круги вокруг IslandPivot + коробки баз
Balance.Zones = {
	CenterRadius = 32, -- автомат вместе с местами операторов у пультов, без PvP
	FieldRadius = 68, -- Пшеничное поле, PvP и расходники разрешены только здесь
	BaseMargin = 6, -- насколько расширить габариты модели базы
	UpdateSeconds = 0.25,
}

-- Скебобсы на пьедесталах (пока цветные кубы)
Balance.PetDisplay = {
	CubeSize = 3,
	RefreshSeconds = 2,
	LabelMaxDistance = 60,
}

Balance.Player = {
	BaseSpeed = 16,
	StartCoins = 0,
	StartCrystals = 0,
}

return Balance
