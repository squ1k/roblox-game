-- Server smoke test: run Main with in-memory DataStore and mocked players
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local task = require("@lune/task")
local Instance = roblox.Instance

local function Signal()
	local s = { conns = {} }
	function s:Connect(fn)
		local c = { fn = fn, Connected = true }
		function c:Disconnect()
			self.Connected = false
		end
		table.insert(s.conns, c)
		return c
	end
	function s:Fire(...)
		for _, c in s.conns do
			if c.Connected then
				task.spawn(c.fn, ...)
			end
		end
	end
	return s
end
local signals = {}
local function sig(inst, name)
	signals[inst] = signals[inst] or {}
	signals[inst][name] = signals[inst][name] or Signal()
	return signals[inst][name]
end
roblox.implementProperty("BindableEvent", "Event", function(self)
	return sig(self, "Event")
end)
roblox.implementMethod("BindableEvent", "Fire", function(self, ...)
	sig(self, "Event"):Fire(...)
end)
roblox.implementProperty("RemoteEvent", "OnServerEvent", function(self)
	return sig(self, "OnServerEvent")
end)
local invokeHandlers = {}
roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(self)
	return invokeHandlers[self]
end, function(self, fn)
	invokeHandlers[self] = fn
end)
local clientEvents = {}
roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
	table.insert(clientEvents, { self.Name, ... })
end)
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return assert(self:FindFirstChild(name), "missing " .. name)
end)

local place = roblox.deserializePlace(fs.readFile(process.args[1]))
local RS = place:GetService("ReplicatedStorage")

-- in-memory datastore
local storeData = {}
local store = {
	UpdateAsync = function(_, key, fn)
		task.wait(0.05)
		local current = storeData[key] and fs and roblox and storeData[key]
		local copy = current and table.clone(current)
		local result = fn(copy)
		if result ~= nil then
			storeData[key] = result
		end
		return result
	end,
}

local playerAdded, playerRemoving = Signal(), Signal()
local playersList = {}
local function makePlayer(userId)
	local attrs = {}
	return {
		Name = "P" .. userId,
		UserId = userId,
		Parent = true,
		Character = nil,
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end,
		IsFriendsWith = function()
			return false
		end,
		Kick = function(self, msg)
			print("KICK", msg)
			self.Parent = nil
		end,
		attrs = attrs,
	}
end
local studio = true
local services = {
	ReplicatedStorage = RS,
	Players = {
		PlayerAdded = playerAdded,
		PlayerRemoving = playerRemoving,
		GetPlayers = function()
			return playersList
		end,
	},
	DataStoreService = {
		GetDataStore = function()
			return store
		end,
	},
	RunService = {
		IsStudio = function()
			return studio
		end,
		IsServer = function()
			return true
		end,
	},
	MarketplaceService = {},
	CollectionService = {
		GetTagged = function()
			return {}
		end,
	},
	HttpService = {
		GenerateGUID = function()
			return tostring(math.random(1, 1e9))
		end,
	},
}
local closeFns = {}
local gameMock = {
	JobId = "server-A",
	GetService = function(_, n)
		return assert(services[n], n)
	end,
	BindToClose = function(_, fn)
		table.insert(closeFns, fn)
	end,
}

local cache = {}
local env
local function run(scriptInst)
	local scope = { script = scriptInst }
	for k, v in env do
		scope[k] = v
	end
	return luau.load(scriptInst.Source, { debugName = scriptInst:GetFullName(), environment = scope })()
end
env = {
	math = math,
	string = string,
	table = table,
	task = task,
	os = os,
	print = print,
	type = type,
	warn = function(...)
		print("WARN", ...)
	end,
	tostring = tostring,
	pairs = pairs,
	next = next,
	pcall = pcall,
	error = error,
	assert = assert,
	setmetatable = setmetatable,
	game = gameMock,
	workspace = {
		GetServerTimeNow = function()
			return os.time()
		end,
	},
	Instance = Instance,
	Color3 = roblox.Color3,
	Vector3 = roblox.Vector3,
	require = function(m)
		if cache[m] == nil then
			cache[m] = run(m)
		end
		return cache[m]
	end,
}

local failures = 0
local function check(cond, label)
	if cond then
		print("ok  ", label)
	else
		failures += 1
		print("FAIL", label)
	end
end

-- existing data for user 2 with an old-format profile (missing new keys)
storeData.u_2 = { Data = { Coins = 500, Crystals = 1, Pets = {}, Pedestals = { { Level = 2, Pet = false } } } }
-- user 3 locked by another live server
storeData.u_3 = { Data = { Coins = 999 }, Lock = { JobId = "server-B", Time = os.time() } }

-- Сервисы, которым нужна настоящая карта, в smoke-тесте подменяем заглушками
local servicesFolder = place:GetService("ServerScriptService").Server.Services
local noop = function() end
cache[servicesFolder.MapService] = {
	Start = noop,
	GetBase = function()
		return nil
	end,
	BaseCount = function()
		return 8
	end,
	IslandPivot = function()
		return roblox.Vector3.zero
	end,
	BaseAt = function()
		return nil
	end,
	AnchorTop = function()
		return roblox.Vector3.zero
	end,
	Shop = function()
		return nil
	end,
}
cache[servicesFolder.BaseService] = {
	Start = noop,
	Teleport = noop,
	GetIndex = function()
		return nil
	end,
	GetOwner = function()
		return nil
	end,
}
cache[servicesFolder.ZoneService] = {
	Start = noop,
	ZoneAt = function()
		return "Neutral"
	end,
}
cache[servicesFolder.PetDisplayService] = { Start = noop, Refresh = noop }
cache[servicesFolder.GachaService] = { Start = noop }
cache[servicesFolder.ClawService] = { Start = noop }
cache[servicesFolder.TrapService] = { Start = noop, Stun = noop, ClearAll = noop }
cache[servicesFolder.TradeService] = {
	Start = noop,
	ClearBan = noop,
	Cancel = noop,
	IsOffered = function()
		return false
	end,
}
cache[servicesFolder.ShopService] = { Start = noop }
for _, n in
	{
		"PedestalService",
		"OvenService",
		"MergeService",
		"BasketService",
		"PatronService",
		"WeatherService",
		"MonetizationService",
	}
do
	cache[servicesFolder[n]] = { Start = noop, Refresh = noop }
end
-- CakePopService нужна карта и физика: заглушка повторяет только состояние "в руках"
local carryStub = {}
cache[servicesFolder.CakePopService] = {
	Start = function()
		sig(RS.Shared.RemoteObjects.DropPop, "OnServerEvent"):Connect(function(player)
			carryStub[player] = nil
			player:SetAttribute("Carrying", false)
		end)
	end,
	IsCarrying = function(player)
		return carryStub[player] == true
	end,
	GiveToHands = function(player)
		carryStub[player] = true
		player:SetAttribute("Carrying", true)
		return true
	end,
	Drop = function(player)
		carryStub[player] = nil
		player:SetAttribute("Carrying", false)
	end,
	SpawnNear = noop,
	SpawnInTray = noop,
}
run(place:GetService("ServerScriptService").Server.Main)
local p1, p2 = makePlayer(1), makePlayer(2)
table.insert(playersList, p1)
table.insert(playersList, p2)
playerAdded:Fire(p1)
playerAdded:Fire(p2)
task.wait(0.5)
check(p1.attrs.DataLoaded == true, "new player loaded")
check(storeData.u_1.Lock and storeData.u_1.Lock.JobId == "server-A", "lock taken")
check(p2.attrs.Coins == 500, "existing coins kept (got " .. tostring(p2.attrs.Coins) .. ")")
task.wait(2.2)
check((p1.attrs.Income or 0) > 0, "studio seed gives income " .. tostring(p1.attrs.Income))
check((p1.attrs.Coins or 0) > 0, "coins accrue " .. tostring(p1.attrs.Coins))
check(p1.attrs.Carrying == false, "state attrs init")

-- remotes
local remotes = RS.Shared.RemoteObjects
sig(remotes.DevCommand, "OnServerEvent"):Fire(p1, "carry")
task.wait(0.05)
check(p1.attrs.Carrying == true, "dev carry on")
sig(remotes.UseHotbar, "OnServerEvent"):Fire(p1, 1)
sig(remotes.UseHotbar, "OnServerEvent"):Fire(p1, "x")
sig(remotes.UseHotbar, "OnServerEvent"):Fire(p1, 1.5)
sig(remotes.DropPop, "OnServerEvent"):Fire(p1)
task.wait(0.05)
check(p1.attrs.Carrying == false, "drop clears carrying")
local before = p1.attrs.Coins
sig(remotes.DevCommand, "OnServerEvent"):Fire(p1, "coins")
task.wait(0.05)
check(p1.attrs.Coins >= before + 1000, "dev coins")

local snapshot = invokeHandlers[remotes.GetProfile](p1)
check(type(snapshot) == "table" and next(snapshot.Pets) ~= nil, "GetProfile returns pets")

-- settings: valid values saved, wrong types rejected
sig(remotes.SettingsSet, "OnServerEvent"):Fire(p1, "Music", 0.2)
sig(remotes.SettingsSet, "OnServerEvent"):Fire(p1, "Music", "loud")
sig(remotes.SettingsSet, "OnServerEvent"):Fire(p1, "Nope", true)
sig(remotes.SettingsSet, "OnServerEvent"):Fire(p1, "ScreenShake", false)
snapshot = invokeHandlers[remotes.GetProfile](p1)
check(snapshot.Settings.Music == 0.2 and snapshot.Settings.ScreenShake == false, "settings saved")
check(snapshot.Settings.Nope == nil, "unknown setting ignored")

-- achievements: claim only once, only when done
local coinsBefore = p1.attrs.Coins
sig(remotes.AchievementClaim, "OnServerEvent"):Fire(p1, "FirstWin")
task.wait(0.05)
check(p1.attrs.Coins < coinsBefore + 500, "unfinished achievement not claimable")
snapshot.Stats.Grabs = 1
sig(remotes.AchievementClaim, "OnServerEvent"):Fire(p1, "FirstWin")
task.wait(0.05)
check(p1.attrs.Coins >= coinsBefore + 500 and p1.attrs.Coins < coinsBefore + 600, "achievement claimed (+500)")
local afterClaim = p1.attrs.Coins
sig(remotes.AchievementClaim, "OnServerEvent"):Fire(p1, "FirstWin")
task.wait(0.05)
check(p1.attrs.Coins < afterClaim + 500, "achievement claimed once")
check(snapshot.Achievements.FirstWin == "claimed", "achievement marked claimed")

-- leaving releases lock and saves
local coinsAtLeave = p2.attrs.Coins
table.remove(playersList, 2)
p2.Parent = nil
playerRemoving:Fire(p2)
task.wait(0.3)
check(storeData.u_2.Lock == nil, "lock released on leave")
check(storeData.u_2.Data.Coins >= coinsAtLeave and storeData.u_2.Data.FridgeSlots == 5, "saved with reconciled keys")
check(storeData.u_2.Data.Pedestals[1].Level == 2, "old pedestal level kept")

-- locked user on a live server gets kicked after retries (shortened by not waiting: just check no overwrite)
studio = false
local p3 = makePlayer(3)
table.insert(playersList, p3)
playerAdded:Fire(p3)
task.wait(0.5)
check(p3.attrs.DataLoaded == nil, "locked profile not loaded")
check(storeData.u_3.Data.Coins == 999 and storeData.u_3.Lock.JobId == "server-B", "locked profile untouched")

print(if failures == 0 then "ALL PASSED" else failures .. " FAILED")
process.exit(failures)
