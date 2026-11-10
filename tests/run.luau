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

print(if failures == 0 then "ALL PASSED" else failures .. " FAILED")
