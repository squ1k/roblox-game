-- Smoke test: build the HUD with real Roblox instances (Lune validates class/property names)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local Instance = roblox.Instance

-- simple signals
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
				c.fn(...)
			end
		end
	end
	function s:Wait()
		return
	end
	return s
end
local signals = {}
local function sig(inst, name)
	signals[inst] = signals[inst] or {}
	signals[inst][name] = signals[inst][name] or Signal()
	return signals[inst][name]
end
for _, ev in
	{ "Activated", "MouseButton1Down", "MouseButton1Up", "MouseLeave", "Changed", "OnClientEvent", "InputBegan" }
do
	roblox.implementProperty("Instance", ev, function(self)
		return sig(self, ev)
	end)
end
roblox.implementProperty("BindableEvent", "Event", function(self)
	return sig(self, "Event")
end)
roblox.implementMethod("BindableEvent", "Fire", function(self, ...)
	sig(self, "Event"):Fire(...)
end)
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local c = self:FindFirstChild(name)
	assert(c, "WaitForChild would hang: " .. self:GetFullName() .. "." .. name)
	return c
end)
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, p)
	return sig(self, "prop:" .. p)
end)
local fired = {}
roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
	table.insert(fired, { self.Name, ... })
end)
local profile = {
	Coins = 0,
	Crystals = 0,
	FridgeSlots = 5,
	Pets = { a = { Id = "pet_2_1" }, b = { Id = "pet_1_3", Mutation = "Astral" }, c = { Id = "pet_4_1" } },
	Pedestals = { { Level = 0, Pet = "a" }, { Level = 3, Pet = "b" }, { Level = 0, Pet = false } },
	Fridge = { { Id = "pet_2_2" }, { Id = "pet_6_4", Mutation = "Prismatic" } },
	Patrons = { Summoned = { family_4 = true } },
	FlexDecor = {},
	Items = { BananaTrap = 3 },
	OvenLevel = 1,
	Ovens = {},
	Achievements = {},
	Settings = {},
	Stats = { Grabs = 0 },
}
roblox.implementMethod("RemoteFunction", "InvokeServer", function()
	return profile
end)

local place = roblox.deserializePlace(fs.readFile(process.args[1]))
local RS = place:GetService("ReplicatedStorage")
local remotes = Instance.new("Folder")
remotes.Name = "RemoteObjects"
remotes.Parent = RS.Shared
for _, n in
	{
		"DropPop",
		"UseHotbar",
		"ProfileChanged",
		"Notify",
		"DevCommand",
		"ClawInput",
		"FridgeTake",
		"TradeInvite",
		"TradeRespond",
		"TradeOffer",
		"TradeReady",
		"TradeCancel",
		"TradeState",
		"OvenStart",
		"OvenCollect",
		"OvenCancel",
		"OvenUpgrade",
		"PedestalEquip",
		"PedestalUnequip",
		"PedestalUpgrade",
		"PedestalBuySlot",
		"FridgeBuySlot",
		"PetLock",
		"PetDelete",
		"BasketTake",
		"PatronSummon",
		"PatronChoose",
		"PatronHide",
		"PetHatched",
		"AchievementClaim",
		"SettingsSet",
	}
do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
end
local gp = Instance.new("RemoteFunction")
gp.Name = "GetProfile"
gp.Parent = remotes
for _, n in { "ShopBuy", "ShopSell", "MergeRun", "BlackMarketExchange" } do
	local r = Instance.new("RemoteFunction")
	r.Name = n
	r.Parent = remotes
end

-- player mock
local attrs =
	{ DataLoaded = true, Coins = 1234, Crystals = 5, Income = 12, Carrying = false, AFK = false, PvpEnabled = true }
local attrSignals = {}
local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"
local player = {
	Name = "Tester",
	GetAttribute = function(_, k)
		return attrs[k]
	end,
	SetAttribute = function(_, k, v)
		attrs[k] = v
		if attrSignals[k] then
			attrSignals[k]:Fire()
		end
	end,
	GetAttributeChangedSignal = function(_, k)
		attrSignals[k] = attrSignals[k] or Signal()
		return attrSignals[k]
	end,
	WaitForChild = function(_, n)
		assert(n == "PlayerGui")
		return playerGui
	end,
}
local tweens = 0
local services = {
	ReplicatedStorage = RS,
	Players = { LocalPlayer = player },
	TweenService = {
		Create = function(_, inst, info, goal)
			for k, v in goal do
				inst[k] = inst[k]
			end -- validates property names
			tweens += 1
			return {
				Play = function()
					for k, v in goal do
						inst[k] = v
					end
				end,
				Cancel = function() end,
			}
		end,
	},
	UserInputService = { KeyboardEnabled = true, InputBegan = Signal(), LastInputTypeChanged = Signal() },
	RunService = {
		IsStudio = function()
			return true
		end,
		IsServer = function()
			return false
		end,
		Heartbeat = Signal(),
	},
	ContextActionService = { BindAction = function() end, UnbindAction = function() end },
	ProximityPromptService = { PromptTriggered = Signal() },
	MarketplaceService = {},
	Lighting = {
		Ambient = roblox.Color3.new(0, 0, 0),
		OutdoorAbient = nil,
		OutdoorAmbient = roblox.Color3.new(0, 0, 0),
		FogColor = roblox.Color3.new(1, 1, 1),
		FogEnd = 100000,
		ClockTime = 14,
		FindFirstChildOfClass = function()
			return nil
		end,
	},
}
local camera = {
	ViewportSize = roblox.Vector2.new(844, 390),
	GetPropertyChangedSignal = function()
		return Signal()
	end,
}
local workspaceMock = {
	CurrentCamera = camera,
	GetPropertyChangedSignal = function()
		return Signal()
	end,
	GetServerTimeNow = function()
		return os.clock()
	end,
}
local gameMock = {
	GetService = function(_, n)
		return assert(services[n], "service " .. n)
	end,
}

local cache = {}
local env
local function run(scriptInst)
	local scope = { script = scriptInst }
	for k, v in env do
		scope[k] = v
	end
	local fn = luau.load(scriptInst.Source, { debugName = scriptInst:GetFullName(), environment = scope })
	return fn()
end
env = {
	math = math,
	string = string,
	table = table,
	task = require("@lune/task"),
	os = os,
	print = print,
	warn = warn,
	type = type,
	tostring = tostring,
	pairs = pairs,
	ipairs = ipairs,
	next = next,
	pcall = pcall,
	error = error,
	assert = assert,
	setmetatable = setmetatable,
	select = select,
	tonumber = tonumber,
	utf8 = utf8,
	game = gameMock,
	workspace = workspaceMock,
	Instance = Instance,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	TweenInfo = {
		new = function(...)
			return { ... }
		end,
	},
	require = function(m)
		if cache[m] == nil then
			cache[m] = run(m)
		end
		return cache[m]
	end,
}

local client = place:GetService("StarterPlayer").StarterPlayerScripts.Client
run(client.HUD)

local hud = playerGui:FindFirstChild("HUD")
local root = hud.Root
local function find(name)
	return root:FindFirstChild(name, true)
end
local failures = 0
local function check(cond, label)
	if cond then
		print("ok  ", label)
	else
		failures += 1
		print("FAIL", label)
	end
end

check(find("Currency") ~= nil, "currency panel built")
check(find("Row1").Value.Text == "1.23K", "coins shown as 1.23K (got " .. find("Row1").Value.Text .. ")")
check(find("Row1").PerSecond.Text == "+12/сек", "income shown")
check(find("Hotbar").Slot1.Count.Text == "3/10", "banana count 3/10")
check(find("Drop").Visible == false, "drop hidden when not carrying")
player:SetAttribute("Carrying", true)
check(find("Drop").Visible == true, "drop visible when carrying")
check(find("Hotbar").Slot1.Lock.Visible == true, "hotbar locked when carrying")
sig(find("Drop"), "Activated"):Fire()
check(fired[#fired][1] == "DropPop", "drop fires DropPop")
player:SetAttribute("Carrying", false)
check(find("Drop").Visible == false and find("Hotbar").Slot1.Lock.Visible == false, "unlock after drop")
sig(find("Hotbar").Slot1, "Activated"):Fire()
check(fired[#fired][1] == "UseHotbar" and fired[#fired][2] == 1, "slot 1 fires UseHotbar(1)")
player:SetAttribute("AfkSince", 0)
player:SetAttribute("AFK", true)
services.RunService.Heartbeat:Fire()
check(find("AfkBar").Visible == true, "afk bar visible on bed")

sig(find("Backpack"), "Activated"):Fire()
local menu = find("MainMenu")
check(menu.Visible, "menu opens")
local content = menu.Window.Content
local cards = 0
for _, c in content:GetChildren() do
	if c:IsA("TextButton") then
		cards += 1
	end
end
check(cards == 3, "3 skebob cards (got " .. cards .. ")")
sig(menu.Window:FindFirstChild("Fridge", true), "Activated"):Fire()
cards = 0
for _, c in content:GetChildren() do
	if c:IsA("TextButton") then
		cards += 1
	end
end
check(cards == 2, "2 fridge cards (got " .. cards .. ")")
check(menu.Window:FindFirstChild("Fridge", true).Text == "Холодильник 2/5", "fridge tab shows 2/5")
sig(menu.Window:FindFirstChild("Patrons", true), "Activated"):Fire()
local rows = 0
for _, c in content:GetChildren() do
	if c:IsA("TextButton") then
		rows += 1
	end
end
check(rows == 8, "8 patron rows (got " .. rows .. ")")
sig(menu.Window:FindFirstChild("Achievements", true), "Activated"):Fire()
rows = 0
for _, c in content:GetChildren() do
	if c:IsA("Frame") then
		rows += 1
	end
end
check(rows == 15, "15 achievement rows (got " .. rows .. ")")
check(find("SettingsButton") ~= nil, "settings button in HUD")
sig(find("SettingsButton"), "Activated"):Fire()
check(find("Settings").Visible, "settings screen opens")
sig(find("Settings").Window:FindFirstChild("Close", true), "Activated"):Fire()
check(not find("Settings").Visible, "settings screen closes")
services.ProximityPromptService.PromptTriggered:Fire({ Name = "FridgeOpenPrompt", Parent = nil }, player)
check(find("FridgeScreen").Visible, "fridge screen opens on prompt")
sig(find("FridgeScreen").Window:FindFirstChild("Close", true), "Activated"):Fire()
services.ProximityPromptService.PromptTriggered:Fire({ Name = "OvenOpenPrompt", Parent = nil }, player)
check(find("OvenScreen").Visible, "oven screen opens on prompt")
sig(find("OvenScreen").Window:FindFirstChild("Close", true), "Activated"):Fire()
-- tap a skebob card shows actions
sig(menu.Window:FindFirstChild("Skebobs", true), "Activated"):Fire()
local firstCard
for _, c in content:GetChildren() do
	if c:IsA("TextButton") then
		firstCard = c
		break
	end
end
sig(firstCard, "Activated"):Fire()
check(firstCard:FindFirstChild("Actions") ~= nil, "card action popup")
-- notify toast
sig(remotes.Notify, "OnClientEvent"):Fire("Привет")
check(find("Toasts"):FindFirstChildOfClass("Frame") ~= nil, "toast shown")
sig(menu.Window:FindFirstChild("Close", true), "Activated"):Fire()
check(not menu.Visible, "menu closes")
print("ui scale", hud.UIScale.Scale)
print(if failures == 0 then "ALL PASSED" else failures .. " FAILED")
process.exit(failures)
