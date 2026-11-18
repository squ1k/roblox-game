-- Вместимость Холодильника и Теплового шкафа с учетом геймпассов "Второй Холодильник" и
-- "Второй Тепловой шкаф": второй объект такой же, как первый (те же слоты и уровень),
-- поэтому мест в Monetization.SecondObjectMult раз больше. Общая для сервера и клиента.

local Config = script.Parent:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))

local Capacity = {}

local function mult(player, passKey: string): number
	return if player and player:GetAttribute("Pass_" .. passKey) == true
		then Balance.Monetization.SecondObjectMult
		else 1
end

function Capacity.Fridge(data, player): number
	return data.FridgeSlots * mult(player, "SecondFridge")
end

function Capacity.Oven(data, player): number
	local level = Balance.Oven.Levels[data.OvenLevel] or Balance.Oven.Levels[1]
	return level.Slots * mult(player, "SecondOven")
end

return Capacity
