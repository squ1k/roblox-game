-- Тепловой шкаф: разморозка попсов по слотам (Balance.Oven.Levels). Время = HatchSeconds редкости,
-- x ForeignFamilyTimeMult, если у игрока еще нет Скебобсов этого Семейства, / Speed уровня.
-- Таймер идет по серверному времени, поэтому разморозка продолжается и офлайн.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Income = require(Shared:WaitForChild("Income"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local CakePopService = require(script.Parent:WaitForChild("CakePopService"))

local Oven = Balance.Oven
local Objects = Balance.BaseObjects
local DEV_FAST_MULT = 0.01 -- DevCommand "ovenfast" в Studio

local OvenService = {}

local random = Random.new()
local views = {} -- [baseIndex] = { Part, Main, Upgrade, Label }

local function now()
	return workspace:GetServerTimeNow()
end

local function level(data)
	return Oven.Levels[data.OvenLevel] or Oven.Levels[1]
end

local function describe(petId: string, mutationId: string?): string
	local skebob = Families.SkebobById[petId]
	local rarity = skebob and Balance.RarityById[skebob.Rarity] or Balance.Rarities[1]
	local family = skebob and Families.ById[skebob.Family]
	local mutation = mutationId and Balance.MutationById[mutationId]
	return (if family then family.Name .. " · " else "")
		.. (if mutation then mutation.Name .. " " else "")
		.. rarity.Name
end

function OvenService.Duration(player: Player, data, pop): number
	local skebob = Families.SkebobById[pop.Id]
	local rarity = skebob and Balance.RarityById[skebob.Rarity] or Balance.Rarities[1]
	local seconds = rarity.HatchSeconds / level(data).Speed
	if skebob and Income.FamilyProgress(data, skebob.Family) == 0 then
		seconds *= Oven.ForeignFamilyTimeMult
	end
	-- Ледяной Скебобс на пьедестале ускоряет шкаф. TODO: прочие эффекты мутаций Скебобсов из диздока
	-- (Neon +15% скорости, Mirage кристаллы, Starlight соседям, Stormy расходники, Bubble защита)
	for _, pedestal in data.Pedestals do
		local pet = pedestal.Pet and data.Pets[pedestal.Pet]
		if pet and pet.Mutation == "Frozen" then
			seconds *= Balance.Weather.FrozenOvenMult
			break
		end
	end
	if RunService:IsStudio() and player:GetAttribute("DevOvenFast") then
		seconds *= DEV_FAST_MULT
	end
	return seconds
end

local function changed(player: Player)
	Remotes.ProfileChanged:FireClient(player)
	OvenService.RefreshView(player)
end

local function start(player: Player, data, pop): boolean
	if #data.Ovens >= level(data).Slots then
		Remotes.Notify:FireClient(player, Strings.OvenBusy)
		return false
	end
	table.insert(data.Ovens, {
		Pop = { Id = pop.Id, Mutation = pop.Mutation, Sleeping = pop.Sleeping },
		StartedAt = now(),
		Duration = OvenService.Duration(player, data, pop),
	})
	Remotes.Notify:FireClient(player, string.format(Strings.OvenStarted, describe(pop.Id, pop.Mutation)))
	changed(player)
	return true
end

-- Из Холодильника (кнопка в меню)
function OvenService.StartFromFridge(player: Player, fridgeIndex)
	local data = DataService.Get(player)
	if not data or type(fridgeIndex) ~= "number" then
		return
	end
	local pop = data.Fridge[fridgeIndex]
	if not pop then
		return
	end
	if start(player, data, pop) then
		table.remove(data.Fridge, fridgeIndex)
		Remotes.ProfileChanged:FireClient(player)
	end
end

-- Из рук (подсказка на шкафу)
local function startFromHands(player: Player)
	local data = DataService.Get(player)
	if not data or not CakePopService.IsCarrying(player) then
		return
	end
	if #data.Ovens >= level(data).Slots then
		Remotes.Notify:FireClient(player, Strings.OvenBusy)
		return
	end
	local pop, ownerUserId = CakePopService.ConsumeCarried(player)
	if pop then
		if ownerUserId ~= player.UserId then
			data.Stats.Steals += 1
		end
		start(player, data, pop)
	end
end

local function rollHatchMutation(): string?
	local roll = random:NextNumber(0, 100)
	for _, mutation in Balance.HatchMutations do
		roll -= mutation.Chance
		if roll <= 0 then
			return mutation.Id
		end
	end
	return nil
end

function OvenService.Collect(player: Player, slot)
	local data = DataService.Get(player)
	local entry = data and type(slot) == "number" and data.Ovens[slot]
	if not entry or now() < entry.StartedAt + entry.Duration then
		return
	end
	table.remove(data.Ovens, slot)
	local pop = entry.Pop
	if pop.Sleeping and random:NextNumber() < Balance.Afk.SleepingCrystalChance then
		local crystals = random:NextInteger(Balance.Afk.SleepingCrystalsMin, Balance.Afk.SleepingCrystalsMax)
		EconomyService.AddCrystals(player, crystals)
		Remotes.Notify:FireClient(player, string.format(Strings.HatchedCrystals, crystals))
	else
		local uid = HttpService:GenerateGUID(false)
		local mutation = pop.Mutation or rollHatchMutation()
		local skebob = Families.SkebobById[pop.Id]
		local before = skebob and Income.FamilyProgress(data, skebob.Family) or 0
		data.Pets[uid] = { Id = pop.Id, Mutation = mutation, Locked = false }
		data.Stats.Hatched += 1
		-- Патрон стал доступен именно этим вылуплением
		local readyFamily = nil
		if skebob and not data.Patrons.Summoned[skebob.Family] then
			local count, need = Income.FamilyProgress(data, skebob.Family)
			if count >= need and before < need then
				readyFamily = skebob.Family
			end
		end
		Remotes.Notify:FireClient(player, string.format(Strings.Hatched, describe(pop.Id, mutation)))
		Remotes.PetHatched:FireClient(player, pop.Id, mutation, readyFamily)
	end
	EconomyService.Refresh(player)
	changed(player)
end

local function collectAll(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	for slot = #data.Ovens, 1, -1 do
		local entry = data.Ovens[slot]
		if now() >= entry.StartedAt + entry.Duration then
			OvenService.Collect(player, slot)
		end
	end
end

function OvenService.Cancel(player: Player, slot)
	local data = DataService.Get(player)
	local entry = data and type(slot) == "number" and data.Ovens[slot]
	if not entry then
		return
	end
	if #data.Fridge >= data.FridgeSlots then
		Remotes.Notify:FireClient(player, Strings.FridgeFull)
		return
	end
	table.remove(data.Ovens, slot)
	table.insert(data.Fridge, entry.Pop)
	changed(player)
end

function OvenService.Upgrade(player: Player)
	local data = DataService.Get(player)
	local nextLevel = data and Oven.Levels[data.OvenLevel + 1]
	if not nextLevel then
		Remotes.Notify:FireClient(player, Strings.OvenMax)
		return
	end
	if not EconomyService.TrySpendCoins(player, nextLevel.Price) then
		Remotes.Notify:FireClient(player, Strings.NoCoins)
		return
	end
	data.OvenLevel += 1
	Remotes.Notify:FireClient(player, Strings.Upgraded)
	changed(player)
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Табличка над шкафом и тексты подсказок
function OvenService.RefreshView(player: Player)
	local index = player:GetAttribute("BaseIndex")
	local view = index and views[index]
	local data = DataService.Get(player)
	if not view or not data then
		return
	end
	local lines = { string.format(Strings.OvenTitle, data.OvenLevel) }
	local anyReady = false
	for slot = 1, level(data).Slots do
		local entry = data.Ovens[slot]
		if entry then
			local left = entry.StartedAt + entry.Duration - now()
			if left <= 0 then
				anyReady = true
				table.insert(lines, describe(entry.Pop.Id, entry.Pop.Mutation) .. ": " .. Strings.OvenReady)
			else
				table.insert(lines, describe(entry.Pop.Id, entry.Pop.Mutation) .. ": " .. formatTime(left))
			end
		else
			table.insert(lines, Strings.OvenEmpty)
		end
	end
	view.Label.Text = table.concat(lines, "\n")
	view.Label.Parent.Size = UDim2.fromOffset(260, 26 * #lines)
	local canPut = CakePopService.IsCarrying(player) and #data.Ovens < level(data).Slots
	view.Main.Enabled = anyReady or canPut
	view.Main.ActionText = if anyReady then Strings.OvenCollect else Strings.OvenPut
	view.Open.Enabled = true
	local nextLevel = Oven.Levels[data.OvenLevel + 1]
	view.Upgrade.Enabled = nextLevel ~= nil
	if nextLevel then
		view.Upgrade.ActionText = string.format(Strings.OvenUpgrade, NumberFormat.Short(nextLevel.Price))
	end
end

local function buildViews()
	for index = 1, MapService.BaseCount() do
		local base = MapService.GetBase(index)
		local oven = base and base.Folder:FindFirstChild("Oven")
		if oven then
			for _, old in oven:GetChildren() do
				if
					old.Name == "OvenPrompt"
					or old.Name == "OvenUpgradePrompt"
					or old.Name == "OvenOpenPrompt"
					or old.Name == "Timers"
				then
					old:Destroy()
				end
			end
			local function prompt(name: string, key: Enum.KeyCode, gamepad: Enum.KeyCode)
				local p = Instance.new("ProximityPrompt")
				p.Name = name
				p.ObjectText = Strings.OvenLabel
				p.HoldDuration = 0
				p.MaxActivationDistance = Objects.PromptDistance
				p.RequiresLineOfSight = false
				p.KeyboardKeyCode = key
				p.GamepadKeyCode = gamepad
				p.Enabled = false
				p.Parent = oven
				return p
			end
			local main = prompt("OvenPrompt", Enum.KeyCode.E, Enum.KeyCode.ButtonX)
			local upgrade = prompt("OvenUpgradePrompt", Enum.KeyCode.R, Enum.KeyCode.ButtonY)
			-- F: экран шкафа на клиенте (окошки, таймеры, улучшение)
			local open = prompt("OvenOpenPrompt", Enum.KeyCode.F, Enum.KeyCode.ButtonB)
			open.ActionText = Strings.OvenOpen
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "Timers"
			billboard.Size = UDim2.fromOffset(260, 52)
			billboard.StudsOffset = Vector3.new(0, oven.Size.Y / 2 + 3.5, 0)
			billboard.MaxDistance = 60
			billboard.Enabled = false
			billboard.Parent = oven
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0
			label.Parent = billboard
			local function owner(player: Player): boolean
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				return player:GetAttribute("BaseIndex") == index
					and root ~= nil
					and (root.Position - oven.Position).Magnitude <= Objects.PromptDistance + 4
			end
			main.Triggered:Connect(function(player)
				if not owner(player) then
					return
				end
				if CakePopService.IsCarrying(player) then
					startFromHands(player)
				else
					collectAll(player)
				end
			end)
			upgrade.Triggered:Connect(function(player)
				if owner(player) then
					OvenService.Upgrade(player)
				end
			end)
			views[index] = { Part = oven, Main = main, Upgrade = upgrade, Open = open, Label = label }
		end
	end
end

function OvenService.Start()
	buildViews()
	Remotes.OvenStart.OnServerEvent:Connect(OvenService.StartFromFridge)
	Remotes.OvenCollect.OnServerEvent:Connect(OvenService.Collect)
	Remotes.OvenCancel.OnServerEvent:Connect(OvenService.Cancel)
	Remotes.OvenUpgrade.OnServerEvent:Connect(OvenService.Upgrade)
	DataService.ProfileLoaded:Connect(function(player)
		local view = views[player:GetAttribute("BaseIndex")]
		if view then
			view.Label.Parent.Enabled = true
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local view = views[player:GetAttribute("BaseIndex")]
		if view then
			view.Label.Parent.Enabled = false
			view.Main.Enabled = false
			view.Upgrade.Enabled = false
			view.Open.Enabled = false
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Objects.OvenLabelSeconds)
			for _, player in Players:GetPlayers() do
				OvenService.RefreshView(player)
			end
		end
	end)
end

return OvenService
