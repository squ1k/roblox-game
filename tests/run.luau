local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local ROOT = "src/shared/"
local cache = {}

local function makeScript(path)
	-- path: "Income" or "Config/Balance"; mimic script.Parent:WaitForChild(...)
	local function node(dir)
		return {
			WaitForChild = function(_, name)
				local sub = if dir == "" then name else dir .. "/" .. name
				if fs.isDir(ROOT .. sub) then
					return node(sub)
				end
				return { __module = sub }
			end,
		}
	end
	local dir = path:match("^(.*)/[^/]+$") or ""
	return { Parent = node(dir) }
end

local function load(path)
	if cache[path] then
		return cache[path]
	end
	local src = fs.readFile(ROOT .. path .. ".lua")
	local env = setmetatable({
		script = makeScript(path),
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		require = function(m)
			return load(m.__module)
		end,
	}, { __index = getfenv() })
	local fn = luau.load(src, { debugName = path, environment = env })
	cache[path] = fn()
	return cache[path]
end

local NumberFormat = load("NumberFormat")
local Income = load("Income")
local Balance = load("Config/Balance")
local Families = load("Config/Families")

local failures = 0
local function eq(actual, expected, label)
	if actual ~= expected then
		failures += 1
		print("FAIL", label, "got", actual, "expected", expected)
	else
		print("ok  ", label, actual)
	end
end

eq(NumberFormat.Short(0), "0", "fmt 0")
eq(NumberFormat.Short(999), "999", "fmt 999")
eq(NumberFormat.Short(12.5), "12.5", "fmt 12.5")
eq(NumberFormat.Short(1000), "1K", "fmt 1000")
eq(NumberFormat.Short(1234), "1.23K", "fmt 1234")
eq(NumberFormat.Short(100000), "100K", "fmt 100000")
eq(NumberFormat.Short(1.2e6), "1.2M", "fmt 1.2M")
eq(NumberFormat.Short(5e15), "5Qa", "fmt 5Qa")
eq(NumberFormat.Short(895.73e12), "895T", "fmt 895T")

-- Rarity chances sum ~100
local sum = 0
for _, r in Balance.Rarities do
	sum += r.Chance
end
eq(math.floor(sum * 100 + 0.5) / 100, 100.01, "rarity chances sum (doc table)")

-- Pedestal milestones from the design doc
eq(string.format("%.2f", Income.PedestalLevelMult(10)), "13.79", "mult L10")
eq(string.format("%.2f", Income.PedestalLevelMult(60) / 1e6), "6.86", "mult L60 (M)")
eq(Income.PedestalLevelPrice(1), 100, "price L1")
eq(Income.PedestalLevelPrice(5), 443, "price L5")
eq(Income.PedestalLevelPrice(20), 311539, "price L20")
eq(Income.PedestalLevelPrice(61), nil, "price L61")
local monotonic = true
for l = 2, 60 do
	if Income.PedestalLevelPrice(l) <= Income.PedestalLevelPrice(l - 1) then
		monotonic = false
	end
end
eq(monotonic, true, "price monotonic")

-- Every family patron is a member, every rarity exists
local valid = true
for _, f in Families.List do
	if not Families.SkebobById[f.Patron] or Families.SkebobById[f.Patron].Family ~= f.Id then
		valid = false
	end
	for _, m in f.Members do
		if not Balance.RarityById[m.Rarity] then
			valid = false
		end
	end
end
eq(valid, true, "families valid")
eq(#Families.List, 8, "8 families")

-- Income: pet_2_1 (Common 2/s) L0 + pet_1_3 (Rare 35) Astral x2.5 on L10
local data = {
	Pets = {
		a = { Id = "pet_2_1" },
		b = { Id = "pet_1_3", Mutation = "Astral" },
		c = { Id = "pet_4_1" }, -- not on pedestal
	},
	Pedestals = { { Level = 0, Pet = "a" }, { Level = 10, Pet = "b" }, { Level = 0, Pet = false } },
	Patrons = { Summoned = {} },
	FlexDecor = {},
}
local total = Income.Compute(data, {})
eq(string.format("%.2f", total), string.format("%.2f", 2 + 35 * 2.5 * 1.3 ^ 10), "income basic")
data.Patrons.Summoned.family_2 = true
total = Income.Compute(data, { Vip = true, Afk = true, FriendsOnServer = 9 })
eq(
	string.format("%.2f", total),
	string.format("%.2f", (4 + 35 * 2.5 * 1.3 ^ 10) * 1.2 * 1.1 * 1.1),
	"income buffs + patron + friend"
)
local count, need, all = Income.FamilyProgress(data, "family_4")
eq(count .. "/" .. need .. "/" .. all, "1/8/9", "family progress family_4")

-- Tug-of-War: лимит кликов, призрак Авто-кликера, победитель
local Tug = load("Tug")
eq(Tug.CanClick(0, 0), true, "tug first click")
eq(Tug.CanClick(16, 1), false, "tug >15 cps rejected")
eq(Tug.CanClick(15, 1), true, "tug 15 cps ok")
eq(Tug.Score(10, 3, true), 25, "tug autoclicker +5/s")
eq(Tug.Score(10, 9, true), 25, "tug autoclicker capped by duration")
eq(Tug.Winner(10, 12, 0.1), 2, "tug winner by score")
eq(Tug.Winner(7, 7, 0.9), 2, "tug tie by roll")

-- Вместимость со вторым Холодильником/шкафом и цена тайм-скипа
local Capacity = load("Capacity")
local passPlayer = {
	GetAttribute = function(_, key)
		return key == "Pass_SecondFridge" or key == "Pass_SecondOven"
	end,
}
eq(Capacity.Fridge({ FridgeSlots = 7 }, nil), 7, "fridge no pass")
eq(Capacity.Fridge({ FridgeSlots = 7 }, passPlayer), 14, "fridge second")
eq(Capacity.Oven({ OvenLevel = 3 }, passPlayer), 4, "oven second")
local Prices = load("Prices")
eq(Prices.TimeSkip(24 * 3600), 288, "time skip 24h = 288")
eq(Prices.TimeSkip(10), 1, "time skip min 1")

-- Локализация: у каждого английского ключа есть русский с теми же %d/%s, и переводчик собирает склейки
local Strings = load("Config/Strings")
local StringsRU = load("Config/StringsRU")
local function specs(text)
	local list = {}
	for spec in text:gmatch("%%([ds])") do
		table.insert(list, spec)
	end
	return table.concat(list)
end
local function compareKeys(en, ru, path)
	for key, value in en do
		local other = ru[key]
		if type(value) == "table" then
			if type(other) ~= "table" then
				eq(type(other), "table", "RU table " .. path .. key)
			else
				compareKeys(value, other, path .. key .. ".")
			end
		elseif type(other) ~= "string" then
			eq(type(other), "string", "RU key " .. path .. key)
		elseif specs(value) ~= specs(other) then
			eq(specs(other), specs(value), "RU format " .. path .. key)
		end
	end
end
compareKeys(Strings, StringsRU, "")
local tr = load("Localizer").Build(Strings, StringsRU)
eq(tr(Strings.ClawPlay), StringsRU.ClawPlay, "ru exact")
eq(
	tr(string.format(Strings.ClawWin, "Rare")),
	"Выигрыш: Редкий попс! Отнесите его в Холодильник",
	"ru format + name"
)
eq(
	tr(string.format(Strings.PopStored, string.format(Strings.PopOfRarity, "Epic"))),
	"Эпический попс в Холодильнике",
	"ru nested"
)
eq(
	tr("Family 3 · Shiny · Legendary: 1:05"),
	"Семейство 3 · Блестящий · Легендарный: 1:05",
	"ru oven line"
)
eq(tr("🛒 " .. Strings.DonateButton), "🛒 Магазин", "ru emoji prefix")
eq(tr(string.format(Strings.MergeChance, 33)), "Шанс 33%", "ru percent")
eq(tr(string.format(Strings.IncomePerSecond, "1.5K")), "+1.5K/сек", "ru income")
eq(tr("Bob"), "Bob", "unknown stays")
-- одинаковый английский текст не должен значить разное по-русски
local seen = {}
local function dupes(en, ru)
	for key, value in en do
		if type(value) == "table" then
			dupes(value, ru[key])
		elseif not value:find("%%[ds]") then
			if seen[value] and seen[value] ~= ru[key] then
				eq(ru[key], seen[value], "ambiguous EN '" .. value .. "'")
			end
			seen[value] = seen[value] or ru[key]
		end
	end
end
dupes(Strings, StringsRU)

print(if failures == 0 then "ALL PASSED" else failures .. " FAILED")
