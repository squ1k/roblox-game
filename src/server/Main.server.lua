-- Точка входа сервера: запускает сервисы по порядку.
-- DataService последним, чтобы остальные успели подписаться на ProfileLoaded.

local Services = script.Parent:WaitForChild("Services")

local order = {
	"MapService",
	"EconomyService",
	"PlayerStateService",
	"BaseService",
	"ZoneService",
	"PetDisplayService",
	"CakePopService",
	"WeatherService",
	"GachaService",
	"ClawService",
	"TrapService",
	"TradeService",
	"ShopService",
	"PedestalService",
	"OvenService",
	"MergeService",
	"BasketService",
	"PatronService",
	"MonetizationService",
	"AchievementService",
	"SettingsService",
	"DevService",
	"DataService",
}

for _, name in order do
	local service = require(Services:WaitForChild(name))
	service.Start()
end
