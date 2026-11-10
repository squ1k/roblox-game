-- Алтарь Слияния. "Риск": 3 попса из Холодильника одного тира и Семейства, шанс RiskChance на
-- попс следующего тира того же Семейства. "Гарант": GuaranteedAmount одинаковых свободных
-- Скебобсов -> попс следующего тира. Результат появляется у Алтаря и живет PopLifetimeSeconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local CakePopService = require(script.Parent:WaitForChild("CakePopService"))
local PedestalService = require(script.Parent:WaitForChild("PedestalService"))
local TradeService = require(script.Parent:WaitForChild("TradeService"))

local Merge = Balance.Merge
local Objects = Balance.BaseObjects

local MergeService = {}

local random = Random.new()

local function altarOf(player: Player): BasePart?
	local base = MapService.GetBase(player:GetAttribute("BaseIndex") or 0)
	return base and base.Folder:FindFirstChild("Altar")
end

local function nearAltar(player: Player): BasePart?
	local altar = altarOf(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if altar and root and (root.Position - altar.Position).Magnitude <= Objects.PromptDistance + 6 then
		return altar
	end
	return nil
end

-- Следующий тир того же Семейства
local function upgraded(petId: string)
	local skebob = Families.SkebobById[petId]
	if not skebob then
		return nil
	end
	local rarity = Balance.RarityById[skebob.Rarity]
	local family = Families.ById[skebob.Family]
	local nextRarity = Balance.Rarities[rarity.Order + 1]
	if not nextRarity then
		return nil
	end
	for _, member in family.Members do
		if member.Rarity == nextRarity.Id then
			return member, nextRarity
		end
	end
	return nil
end

local function spawnResult(player: Player, altar: BasePart, member, rarity)
	local data = DataService.Get(player)
	if data then
		data.Stats.Merges += 1
	end
	CakePopService.SpawnAt(
		player,
		{ Id = member.Id },
		altar.Position + Vector3.new(0, altar.Size.Y / 2 + 2, 0),
		Merge.PopLifetimeSeconds
	)
	Remotes.Notify:FireClient(player, string.format(Strings.MergeSuccess, rarity.Name))
end

local function risk(player: Player, data, altar: BasePart, indices)
	if type(indices) ~= "table" or #indices ~= Merge.RiskAmount then
		return false, Strings.MergeNotEnough
	end
	local pops = {}
	for _, index in indices do
		if type(index) ~= "number" or table.find(pops, data.Fridge[index]) or not data.Fridge[index] then
			return false, Strings.MergeNotEnough
		end
		table.insert(pops, data.Fridge[index])
	end
	local first = Families.SkebobById[pops[1].Id]
	for _, pop in pops do
		local skebob = Families.SkebobById[pop.Id]
		if not skebob or not first or skebob.Rarity ~= first.Rarity or skebob.Family ~= first.Family then
			return false, Strings.MergePickRisk
		end
	end
	local member, rarity = upgraded(pops[1].Id)
	if not member then
		return false, Strings.MergeMaxTier
	end
	table.sort(indices, function(a, b)
		return a > b
	end)
	for _, index in indices do
		table.remove(data.Fridge, index)
	end
	Remotes.ProfileChanged:FireClient(player)
	-- Токсичный Скебобс на пьедестале: +ToxicMergeBonus к шансу
	local chance = Merge.RiskChance
	for _, pedestal in data.Pedestals do
		local pet = pedestal.Pet and data.Pets[pedestal.Pet]
		if pet and pet.Mutation == "Toxic" then
			chance += Balance.Weather.ToxicMergeBonus
			break
		end
	end
	if random:NextNumber() < chance then
		spawnResult(player, altar, member, rarity)
		return true
	end
	Remotes.Notify:FireClient(player, Strings.MergeFailed)
	return true, Strings.MergeFailed
end

local function guaranteed(player: Player, data, altar: BasePart, petId)
	if type(petId) ~= "string" then
		return false
	end
	local member, rarity = upgraded(petId)
	if not member then
		return false, Strings.MergeMaxTier
	end
	local uids = {}
	for uid, pet in data.Pets do
		if
			pet.Id == petId
			and not pet.Locked
			and not PedestalService.SlotOf(data, uid)
			and not TradeService.IsOffered(player, uid)
		then
			table.insert(uids, uid)
			if #uids >= Merge.GuaranteedAmount then
				break
			end
		end
	end
	if #uids < Merge.GuaranteedAmount then
		return false, Strings.MergeNotEnough
	end
	for _, uid in uids do
		data.Pets[uid] = nil
	end
	Remotes.ProfileChanged:FireClient(player)
	spawnResult(player, altar, member, rarity)
	return true
end

local function run(player: Player, mode, keys)
	local data = DataService.Get(player)
	local altar = nearAltar(player)
	if not data or not altar then
		return false, Strings.MergeOwnOnly
	end
	if mode == "risk" then
		return risk(player, data, altar, keys)
	elseif mode == "guaranteed" then
		return guaranteed(player, data, altar, keys)
	end
	return false
end

function MergeService.Start()
	for index = 1, MapService.BaseCount() do
		local base = MapService.GetBase(index)
		local altar = base and base.Folder:FindFirstChild("Altar")
		if altar then
			local old = altar:FindFirstChild("AltarPrompt")
			if old then
				old:Destroy()
			end
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "AltarPrompt"
			prompt.ActionText = Strings.MergeOpen
			prompt.ObjectText = Strings.AltarLabel
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = Objects.PromptDistance
			prompt.RequiresLineOfSight = false
			prompt.Parent = altar
		end
	end
	Remotes.MergeRun.OnServerInvoke = run
end

return MergeService
