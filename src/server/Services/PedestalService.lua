-- Пьедесталы базы: поставить/снять Скебобса, улучшить уровень (1..MaxLevel), купить слот,
-- плюс место в Холодильнике и блокировка/удаление Скебобсов. Кнопки-подсказки висят над
-- каждым из 12 слотов базы (видны только хозяину), все действия проверяет сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Income = require(Shared:WaitForChild("Income"))
local Prices = require(Shared:WaitForChild("Prices"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local PetDisplayService = require(script.Parent:WaitForChild("PetDisplayService"))
local TradeService = require(script.Parent:WaitForChild("TradeService"))

local Objects = Balance.BaseObjects
local Pedestals = Balance.Pedestals

local PedestalService = {}

local prompts = {} -- [baseIndex] = { Slots = { [slot] = { Part, Main, Upgrade } }, FridgeExpand }

function PedestalService.SlotOf(data, uid: string): number?
	for slot, pedestal in data.Pedestals do
		if pedestal.Pet == uid then
			return slot
		end
	end
	return nil
end

-- Свободные Скебобсы (не на пьедестале и не в обмене), лучшие по доходу первыми
function PedestalService.FreePets(player: Player, data)
	local list = {}
	for uid, pet in data.Pets do
		if not PedestalService.SlotOf(data, uid) and not TradeService.IsOffered(player, uid) then
			table.insert(list, uid)
		end
	end
	table.sort(list, function(a, b)
		return Income.PetIncome(data.Pets[a], 0) > Income.PetIncome(data.Pets[b], 0)
	end)
	return list
end

local function changed(player: Player)
	EconomyService.Refresh(player)
	PetDisplayService.Refresh(player)
	Remotes.ProfileChanged:FireClient(player)
	PedestalService.RefreshPrompts(player)
end

function PedestalService.Equip(player: Player, uid, slot)
	local data = DataService.Get(player)
	if not data or type(uid) ~= "string" or not data.Pets[uid] then
		return
	end
	if PedestalService.SlotOf(data, uid) or TradeService.IsOffered(player, uid) then
		return
	end
	if slot ~= nil then
		if type(slot) ~= "number" or not data.Pedestals[slot] or data.Pedestals[slot].Pet then
			slot = nil
		end
	end
	if slot == nil then
		for index, pedestal in data.Pedestals do
			if not pedestal.Pet then
				slot = index
				break
			end
		end
	end
	if not slot then
		Remotes.Notify:FireClient(player, Strings.NoFreePedestal)
		return
	end
	data.Pedestals[slot].Pet = uid
	changed(player)
end

function PedestalService.Unequip(player: Player, slot)
	local data = DataService.Get(player)
	local pedestal = data and type(slot) == "number" and data.Pedestals[slot]
	if pedestal and pedestal.Pet then
		pedestal.Pet = false
		changed(player)
	end
end

function PedestalService.Upgrade(player: Player, slot)
	local data = DataService.Get(player)
	local pedestal = data and type(slot) == "number" and data.Pedestals[slot]
	if not pedestal or pedestal.Level >= Pedestals.MaxLevel then
		return
	end
	local price = Income.PedestalLevelPrice(pedestal.Level + 1)
	if not price or not EconomyService.TrySpendCoins(player, price) then
		Remotes.Notify:FireClient(player, Strings.NoCoins)
		return
	end
	pedestal.Level += 1
	changed(player)
end

function PedestalService.BuySlot(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local slot = #data.Pedestals + 1
	local price = Prices.PedestalSlot(slot)
	if slot > Pedestals.MaxFreeSlots or not price then
		Remotes.Notify:FireClient(player, Strings.PedestalRobux)
		return
	end
	if not EconomyService.TrySpendCoins(player, price) then
		Remotes.Notify:FireClient(player, Strings.NoCoins)
		return
	end
	table.insert(data.Pedestals, { Level = 0, Pet = false })
	changed(player)
end

function PedestalService.FridgeBuySlot(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local price = Prices.FridgeSlot(data.FridgeSlots + 1)
	if not price then
		Remotes.Notify:FireClient(player, Strings.FridgeMax)
		return
	end
	if not EconomyService.TrySpendCoins(player, price) then
		Remotes.Notify:FireClient(player, Strings.NoCoins)
		return
	end
	data.FridgeSlots += 1
	changed(player)
end

function PedestalService.Lock(player: Player, uid)
	local data = DataService.Get(player)
	local pet = data and type(uid) == "string" and data.Pets[uid]
	if pet then
		pet.Locked = not pet.Locked
		changed(player)
	end
end

function PedestalService.Delete(player: Player, uid)
	local data = DataService.Get(player)
	local pet = data and type(uid) == "string" and data.Pets[uid]
	if not pet or pet.Locked or TradeService.IsOffered(player, uid) then
		Remotes.Notify:FireClient(player, Strings.PetLocked)
		return
	end
	local slot = PedestalService.SlotOf(data, uid)
	if slot then
		data.Pedestals[slot].Pet = false
	end
	data.Pets[uid] = nil
	Remotes.Notify:FireClient(player, Strings.PetDeleted)
	changed(player)
end

local function makePrompt(parent: Instance, name: string, key: Enum.KeyCode, gamepad: Enum.KeyCode): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Objects.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = gamepad
	prompt.Enabled = false
	prompt.Parent = parent
	return prompt
end

local function ownerCheck(player: Player, baseIndex: number, part: BasePart): boolean
	if player:GetAttribute("BaseIndex") ~= baseIndex then
		return false
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - part.Position).Magnitude <= Objects.PromptDistance + 4
end

local function buildPrompts()
	for index = 1, MapService.BaseCount() do
		local base = MapService.GetBase(index)
		if base then
			local old = base.Folder:FindFirstChild("PedestalPrompts")
			if old then
				old:Destroy()
			end
			local folder = Instance.new("Folder")
			folder.Name = "PedestalPrompts"
			folder.Parent = base.Folder
			local entry = { Slots = {} }
			for slot, anchor in base.Anchors do
				local part = Instance.new("Part")
				part.Name = "Slot" .. slot
				part.Size = Vector3.one
				part.Transparency = 1
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Position = MapService.AnchorTop(anchor) + Vector3.new(0, Objects.PedestalPromptHeight, 0)
				part:SetAttribute("BaseIndex", index)
				part:SetAttribute("Slot", slot)
				part.Parent = folder
				local main = makePrompt(part, "PedestalPrompt", Enum.KeyCode.E, Enum.KeyCode.ButtonX)
				local upgrade = makePrompt(part, "PedestalUpgradePrompt", Enum.KeyCode.R, Enum.KeyCode.ButtonY)
				main.MaxActivationDistance = Objects.PedestalPromptDistance
				upgrade.MaxActivationDistance = Objects.PedestalPromptDistance
				main.Triggered:Connect(function(player)
					if not ownerCheck(player, index, part) then
						return
					end
					local data = DataService.Get(player)
					if not data then
						return
					end
					local pedestal = data.Pedestals[slot]
					if pedestal and pedestal.Pet then
						PedestalService.Unequip(player, slot)
					elseif not pedestal and slot == #data.Pedestals + 1 then
						PedestalService.BuySlot(player)
					end
					-- пустой свой пьедестал: клиент открывает меню выбора Скебобса
				end)
				upgrade.Triggered:Connect(function(player)
					if ownerCheck(player, index, part) then
						PedestalService.Upgrade(player, slot)
					end
				end)
				entry.Slots[slot] = { Part = part, Main = main, Upgrade = upgrade }
			end
			local fridge = base.Folder:FindFirstChild("Fridge")
			if fridge then
				local old = fridge:FindFirstChild("FridgeExpandPrompt")
				if old then
					old:Destroy()
				end
				entry.FridgeExpand = makePrompt(fridge, "FridgeExpandPrompt", Enum.KeyCode.R, Enum.KeyCode.ButtonY)
				entry.FridgeExpand.ObjectText = Strings.FridgeLabel
				entry.FridgeExpand.Triggered:Connect(function(player)
					if ownerCheck(player, index, fridge) then
						PedestalService.FridgeBuySlot(player)
					end
				end)
			end
			prompts[index] = entry
		end
	end
end

local function set(prompt: ProximityPrompt, enabled: boolean, action: string?, object: string?)
	if prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
	if action and prompt.ActionText ~= action then
		prompt.ActionText = action
	end
	if object and prompt.ObjectText ~= object then
		prompt.ObjectText = object
	end
end

-- Тексты и доступность кнопок базы игрока по его данным
function PedestalService.RefreshPrompts(player: Player)
	local index = player:GetAttribute("BaseIndex")
	local entry = index and prompts[index]
	local data = DataService.Get(player)
	if not entry or not data then
		return
	end
	local hasFree = #PedestalService.FreePets(player, data) > 0
	for slot, view in entry.Slots do
		local pedestal = data.Pedestals[slot]
		if pedestal then
			local object = string.format(Strings.PedestalLevel, slot, pedestal.Level)
			if pedestal.Pet then
				view.Part:SetAttribute("State", "Occupied")
				set(view.Main, true, Strings.PedestalTake, object)
			else
				view.Part:SetAttribute("State", "Empty")
				set(view.Main, hasFree, Strings.PedestalPlace, object)
			end
			local price = pedestal.Level < Pedestals.MaxLevel and Income.PedestalLevelPrice(pedestal.Level + 1)
			if price then
				set(view.Upgrade, true, string.format(Strings.PedestalUpgrade, NumberFormat.Short(price)), object)
			else
				set(view.Upgrade, false)
			end
		elseif slot == #data.Pedestals + 1 and Prices.PedestalSlot(slot) and slot <= Pedestals.MaxFreeSlots then
			view.Part:SetAttribute("State", "Buy")
			set(view.Main, true, string.format(Strings.PedestalBuy, NumberFormat.Short(Prices.PedestalSlot(slot))), "")
			set(view.Upgrade, false)
		else
			view.Part:SetAttribute("State", "Locked")
			set(view.Main, false)
			set(view.Upgrade, false)
		end
	end
	if entry.FridgeExpand then
		local price = Prices.FridgeSlot(data.FridgeSlots + 1)
		if price then
			set(entry.FridgeExpand, true, string.format(Strings.FridgeExpand, NumberFormat.Short(price)))
		else
			set(entry.FridgeExpand, false)
		end
	end
end

local function disableBase(index: number?)
	local entry = index and prompts[index]
	if not entry then
		return
	end
	for _, view in entry.Slots do
		set(view.Main, false)
		set(view.Upgrade, false)
	end
	if entry.FridgeExpand then
		set(entry.FridgeExpand, false)
	end
end

function PedestalService.Start()
	buildPrompts()
	Remotes.PedestalEquip.OnServerEvent:Connect(PedestalService.Equip)
	Remotes.PedestalUnequip.OnServerEvent:Connect(PedestalService.Unequip)
	Remotes.PedestalUpgrade.OnServerEvent:Connect(PedestalService.Upgrade)
	Remotes.PedestalBuySlot.OnServerEvent:Connect(PedestalService.BuySlot)
	Remotes.FridgeBuySlot.OnServerEvent:Connect(PedestalService.FridgeBuySlot)
	Remotes.PetLock.OnServerEvent:Connect(PedestalService.Lock)
	Remotes.PetDelete.OnServerEvent:Connect(PedestalService.Delete)
	Players.PlayerRemoving:Connect(function(player)
		disableBase(player:GetAttribute("BaseIndex"))
	end)
	DataService.ProfileLoaded:Connect(function(player)
		PedestalService.RefreshPrompts(player)
	end)
	-- Цены и наличие свободных Скебобсов меняются от многих событий, раз в секунду дешево
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				PedestalService.RefreshPrompts(player)
			end
		end
	end)
end

return PedestalService
