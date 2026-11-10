-- Временная сквозная нумерация (решение от 28.10.2026): 8 Семейств по 9 Скебобсов,
-- по одному на каждую редкость. pet_3_4 = четвертый Скебобс третьего Семейства (Epic).
-- Patron = Божественный Скебобс Семейства. Когда появятся имена, меняется только Name.

local Balance = require(script.Parent:WaitForChild("Balance"))

local FAMILY_COUNT = 8

local Families = {}
for f = 1, FAMILY_COUNT do
	local members = {}
	for index, rarity in Balance.Rarities do
		members[index] = { Id = "pet_" .. f .. "_" .. index, Name = "pet_" .. f .. "_" .. index, Rarity = rarity.Id }
	end
	Families[f] = {
		Id = "family_" .. f,
		Name = "Семейство " .. f,
		Color = Color3.fromHSV((f - 1) / FAMILY_COUNT, 0.55, 1), -- цвет Патрона-заглушки и бестиария
		Patron = members[#members].Id,
		Members = members,
	}
end

local byId = {}
local skebobById = {}
for _, family in Families do
	byId[family.Id] = family
	for _, member in family.Members do
		member.Family = family.Id
		skebobById[member.Id] = member
	end
end

return {
	List = Families,
	ById = byId,
	SkebobById = skebobById,
}
