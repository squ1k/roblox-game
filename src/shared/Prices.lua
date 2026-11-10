-- Цены Лавки Антона. Общие для сервера (списание/начисление) и клиента (показ в UI).
-- Бонусы Flex-декора, VIP и погоды на цены продажи не влияют.

local Config = script.Parent:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Income = require(script.Parent:WaitForChild("Income"))

local MAX_OTHER_PLAYERS = 7 -- 8 игроков на сервере

local Prices = {}

local function petBaseValue(skebobId: string, mutationId): number?
	local skebob = Families.SkebobById[skebobId]
	if not skebob then
		return nil
	end
	local value = Balance.RarityById[skebob.Rarity].Income * Balance.Sell.PetIncomeSeconds
	if mutationId then
		value *= Balance.Sell.MutationMult
	end
	return value
end

-- pet: { Id, Mutation }
function Prices.SellPet(pet): number?
	local value = petBaseValue(pet.Id, pet.Mutation)
	return value and math.floor(value)
end

-- pop: { Id, Mutation }
function Prices.SellPop(pop): number?
	local value = petBaseValue(pop.Id, pop.Mutation)
	return value and math.floor(value * Balance.Sell.PopShare)
end

-- Максимально возможный доход игрока сейчас: текущие пьедесталы + все временные баффы
function Prices.MaxIncomePerSecond(data, isVip: boolean): number
	return (Income.Compute(data, { Afk = true, Vip = isVip, FriendsOnServer = MAX_OTHER_PLAYERS }))
end

-- packIndex: индекс в Balance.BananaTrap.Packs. Возвращает цену и количество.
function Prices.BananaPack(data, isVip: boolean, packIndex: number): (number?, number?)
	local trap = Balance.BananaTrap
	local pack = trap.Packs[packIndex]
	if not pack then
		return nil, nil
	end
	local unit = math.max(trap.MinPrice, Prices.MaxIncomePerSecond(data, isVip) * trap.PriceIncomeSeconds)
	return math.floor(unit * pack.PriceMult), pack.Amount
end

-- Округление до 2 значащих цифр: 1638 -> 1600
local function roundPrice(value: number): number
	local magnitude = 10 ^ math.max(0, math.floor(math.log10(value)) - 1)
	return math.floor(value / magnitude + 0.5) * magnitude
end

-- Цена покупки слота Холодильника номер `slot` (StartSlots+1..MaxSlots)
function Prices.FridgeSlot(slot: number): number?
	local fridge = Balance.Fridge
	if slot <= fridge.StartSlots or slot > fridge.MaxSlots then
		return nil
	end
	return roundPrice(fridge.SlotPriceBase * fridge.SlotPriceGrowth ^ (slot - fridge.StartSlots - 1))
end

-- Цена покупки пьедестала номер `slot` за Монеты (11 и 12 только за Robux)
function Prices.PedestalSlot(slot: number): number?
	return Balance.Pedestals.SlotPrices[slot]
end

return Prices
