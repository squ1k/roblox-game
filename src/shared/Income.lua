-- Формулы дохода. Общие для сервера (начисление) и клиента (показ "в секунду").

local Config = script.Parent:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))

local Income = {}

function Income.PedestalLevelMult(level: number): number
	return Balance.Pedestals.LevelMultBase ^ level
end

-- Цена покупки уровня `level` (1..MaxLevel) по вехам диздока
function Income.PedestalLevelPrice(level: number): number?
	local milestones = Balance.Pedestals.LevelPriceMilestones
	if level < 1 or level > Balance.Pedestals.MaxLevel then
		return nil
	end
	for i = 1, #milestones - 1 do
		local fromLevel, fromPrice = milestones[i][1], milestones[i][2]
		local toLevel, toPrice = milestones[i + 1][1], milestones[i + 1][2]
		if level >= fromLevel and level <= toLevel then
			local t = (level - fromLevel) / (toLevel - fromLevel)
			local logPrice = math.log(fromPrice) + (math.log(toPrice) - math.log(fromPrice)) * t
			return math.floor(math.exp(logPrice) + 0.5)
		end
	end
	return nil
end

-- Доход одного пета на пьедестале без глобальных баффов
function Income.PetIncome(pet, pedestalLevel: number, summonedPatrons): number
	local skebob = Families.SkebobById[pet.Id]
	if not skebob then
		return 0
	end
	local rarity = Balance.RarityById[skebob.Rarity]
	local value = rarity.Income * Income.PedestalLevelMult(pedestalLevel)
	local mutation = pet.Mutation and Balance.MutationById[pet.Mutation]
	if mutation then
		value *= mutation.IncomeMult
	end
	if summonedPatrons and summonedPatrons[skebob.Family] then
		value *= Balance.Buffs.PatronFamilyMult
	end
	return value
end

-- ctx: { Afk: boolean, Vip: boolean, FriendsOnServer: number }
function Income.GlobalMult(data, ctx): number
	local buffs = Balance.Buffs
	local mult = 1
	if ctx.Vip then
		mult *= buffs.VipMult
	end
	if ctx.Afk then
		mult *= buffs.AfkMult
	end
	if (ctx.FriendsOnServer or 0) > 0 then
		mult *= buffs.FriendMult
	end
	local flexCount = data.FlexDecor and #data.FlexDecor or 0
	mult *= buffs.FlexDecorMult ^ flexCount
	return mult
end

-- Возвращает доход в секунду и доход по каждому пьедесталу (для всплывающих цифр)
function Income.Compute(data, ctx)
	local perPedestal = {}
	local sum = 0
	local summoned = data.Patrons and data.Patrons.Summoned
	for slot, pedestal in data.Pedestals do
		local pet = pedestal.Pet and data.Pets[pedestal.Pet]
		if pet then
			local value = Income.PetIncome(pet, pedestal.Level, summoned)
			perPedestal[slot] = value
			sum += value
		end
	end
	local mult = Income.GlobalMult(data, ctx)
	for slot, value in perPedestal do
		perPedestal[slot] = value * mult
	end
	return sum * mult, perPedestal
end

-- Прогресс Семейства для Патрона: сколько уникальных Скебобсов есть и сколько нужно
function Income.FamilyProgress(data, familyId: string)
	local family = Families.ById[familyId]
	local owned = {}
	for _, pet in data.Pets do
		local skebob = Families.SkebobById[pet.Id]
		if skebob and skebob.Family == familyId then
			owned[pet.Id] = true
		end
	end
	local count = 0
	for _ in owned do
		count += 1
	end
	local total = #family.Members
	local need = math.ceil(total * Balance.Buffs.PatronUnlockShare)
	return count, need, total
end

return Income
