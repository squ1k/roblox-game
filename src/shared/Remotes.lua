-- Все RemoteEvent/RemoteFunction. Сервер создает, клиент ждет.

local RunService = game:GetService("RunService")

local EVENTS = {
	"DropPop", -- клиент -> сервер: бросить Кейк-попс
	"UseHotbar", -- клиент -> сервер: (slot) применить расходник
	"ProfileChanged", -- сервер -> клиент: инвентарь изменился, перезапросить снимок
	"Notify", -- сервер -> клиент: (text) всплывающее уведомление
	"DevCommand", -- клиент -> сервер, работает только в Studio
	"ClawInput", -- клиент -> сервер: ("move", u, v) или ("drop") во время игры в автомат
	"FridgeTake", -- клиент -> сервер: (index) взять попс из Холодильника в руки, только на своей базе
	"TradeInvite", -- клиент -> сервер: (targetUserId) пригласить к обмену
	"TradeRespond", -- клиент -> сервер: (accept: boolean, block: boolean?) ответ на приглашение
	"TradeOffer", -- клиент -> сервер: (petUids: {string}) мой оффер, до Trade.MaxItems
	"TradeReady", -- клиент -> сервер: (ready: boolean)
	"TradeCancel", -- клиент -> сервер: закрыть обмен
	"TradeState", -- сервер -> клиент: (state | nil) снимок приглашения или обмена
	"OvenStart", -- клиент -> сервер: (fridgeIndex) попс из Холодильника в свободное место Теплового шкафа
	"OvenCollect", -- клиент -> сервер: (slot) забрать вылупившегося Скебобса
	"OvenCancel", -- клиент -> сервер: (slot) вернуть попс в Холодильник, таймер сбрасывается
	"OvenUpgrade", -- клиент -> сервер: следующий уровень шкафа
	"PedestalEquip", -- клиент -> сервер: (uid, slot?) поставить Скебобса (slot nil = первый свободный)
	"PedestalUnequip", -- клиент -> сервер: (slot) снять Скебобса
	"PedestalUpgrade", -- клиент -> сервер: (slot) следующий уровень пьедестала
	"PedestalBuySlot", -- клиент -> сервер: купить следующий пьедестал
	"FridgeBuySlot", -- клиент -> сервер: купить место в Холодильнике
	"PetLock", -- клиент -> сервер: (uid) заблокировать/разблокировать
	"PetDelete", -- клиент -> сервер: (uid) удалить Скебобса
	"BasketTake", -- клиент -> сервер: (index) Спящий попс из АФК-корзины в Холодильник
	"PatronSummon", -- клиент -> сервер: (familyId) призвать Патрона, если собрано 80% Семейства
	"PatronChoose", -- клиент -> сервер: (familyId) сделать главным (повторно = снять)
	"PatronHide", -- клиент -> сервер: (familyId) скрыть/показать модель, бонус остается
	"PetHatched", -- сервер -> клиент: (petId, mutationId?, patronReadyFamilyId?) экран вылупления
	"AchievementClaim", -- клиент -> сервер: (id) забрать награду за выполненное достижение
	"SettingsSet", -- клиент -> сервер: (key, value) сохранить настройку из Balance.DefaultSettings
}

local FUNCTIONS = {
	"GetProfile", -- клиент -> сервер: снимок данных для меню
	"ShopBuy", -- клиент -> сервер: (packIndex) -> (ok, message) купить бананы у Антона
	"ShopSell", -- клиент -> сервер: ("pop", fridgeIndex) или ("pet", uid) -> (ok, coins) продать Антону
	"MergeRun", -- клиент -> сервер: ("risk", {fridgeIndex x3}) или ("guaranteed", skebobId) -> (ok, message)
	"BlackMarketExchange", -- клиент -> сервер: ("buy" | "sell", amount) -> (ok, message) Кристаллы за Монеты и обратно
}

local folder
if RunService:IsServer() then
	folder = script.Parent:FindFirstChild("RemoteObjects") or Instance.new("Folder")
	folder.Name = "RemoteObjects"
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = script.Parent
else
	folder = script.Parent:WaitForChild("RemoteObjects")
end

local Remotes = {}
for _, name in EVENTS do
	Remotes[name] = folder:WaitForChild(name)
end
for _, name in FUNCTIONS do
	Remotes[name] = folder:WaitForChild(name)
end

return Remotes
