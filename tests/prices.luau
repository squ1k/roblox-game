-- Проверка цен без Roblox: подменяем script/WaitForChild простыми таблицами
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local modules = {}
local function node(path)
	return setmetatable({ __path = path }, {
		__index = function(self, key)
			if key == "Parent" then
				return node(string.match(self.__path, "^(.*)/[^/]+$"))
			elseif key == "WaitForChild" then
				return function(_, name)
					return node(self.__path .. "/" .. name)
				end
			end
		end,
	})
end
local function load(path)
	if modules[path] then
		return modules[path]
	end
	local env = setmetatable({
		script = node(path),
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		require = function(n)
			return load(n.__path)
		end,
	}, { __index = _G })
	local fn = luau.load(fs.readFile(path .. ".lua"), { environment = env, chunkName = path })
	modules[path] = fn()
	return modules[path]
end
local Prices = load("src/shared/Prices")
local out = {}
for s = 6, 20 do
	table.insert(out, s .. ":" .. Prices.FridgeSlot(s))
end
print("fridge", table.concat(out, " "))
out = {}
for s = 4, 10 do
	table.insert(out, s .. ":" .. Prices.PedestalSlot(s))
end
print("pedestal", table.concat(out, " "))
print("sell common pet/pop", Prices.SellPet({ Id = "pet_1_1" }), Prices.SellPop({ Id = "pet_1_1" }))
