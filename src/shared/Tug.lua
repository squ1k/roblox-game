-- Счет мини-игры Tug-of-War (конфликт двух клешней за одну капсулу). Чистые функции:
-- сервер ведет игру в ClawService, клиент рисует шкалу, тесты проверяют правила.

local Config = script.Parent:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))

local Tug = {}

-- Можно ли засчитать еще один клик: не больше MaxClicksPerSecond за прошедшее время (защита от макросов)
function Tug.CanClick(clicks: number, elapsed: number): boolean
	return clicks < math.ceil(math.max(elapsed, 0) * Balance.Gacha.MaxClicksPerSecond) + 1
end

-- Очки игрока: его клики + призрак Авто-кликера (AutoClickerCps за каждую секунду игры)
function Tug.Score(clicks: number, elapsed: number, autoClicker: boolean): number
	local bonus = if autoClicker
		then Balance.Monetization.AutoClickerCps * math.clamp(elapsed, 0, Balance.Gacha.ConflictSeconds)
		else 0
	return clicks + bonus
end

-- 1 или 2: у кого больше очков; при ничьей решает roll (0..1)
function Tug.Winner(scoreA: number, scoreB: number, roll: number): number
	if scoreA ~= scoreB then
		return if scoreA > scoreB then 1 else 2
	end
	return if roll < 0.5 then 1 else 2
end

return Tug
