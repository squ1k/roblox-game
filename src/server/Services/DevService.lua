-- Тестовые команды. Работают ТОЛЬКО в Studio, на живых серверах игнорируются.
-- Клавиши в Studio: K = +монеты, F = попс в руки/бросить, G = попс на землю рядом, P = тестовые Скебобсы,
-- T = оглушить себя, Y = "чужой" попс рядом (проверка кражи в поле), U/O = быстрые корзина/шкаф,
-- N = почти полное первое Семейство (проверка Патрона), J = погодный ивент вкл/выкл.

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Families = require(Shared:WaitForChild("Config"):WaitForChild("Families"))
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local CakePopService = require(script.Parent:WaitForChild("CakePopService"))
local TrapService = require(script.Parent:WaitForChild("TrapService"))
local TradeService = require(script.Parent:WaitForChild("TradeService"))
local WeatherService = require(script.Parent:WaitForChild("WeatherService"))

local DevService = {}

local function seedPets(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local samples = { "pet_2_1", "pet_8_1", "pet_4_1", "pet_1_3", "pet_3_1" }
	local mutations = { false, "Shiny", false, "Astral", false }
	for i, skebobId in samples do
		if Families.SkebobById[skebobId] then
			local uid = HttpService:GenerateGUID(false)
			data.Pets[uid] = { Id = skebobId, Mutation = mutations[i] or nil, Locked = false }
			local pedestal = data.Pedestals[i]
			if pedestal and not pedestal.Pet then
				pedestal.Pet = uid
			end
		end
	end
	table.insert(data.Fridge, { Id = "pet_2_2", Mutation = nil })
	table.insert(data.Fridge, { Id = "pet_6_4", Mutation = "Prismatic" })
	data.Items.BananaTrap = 3
	EconomyService.Refresh(player)
	Remotes.ProfileChanged:FireClient(player)
end

function DevService.Start()
	if not RunService:IsStudio() then
		return
	end
	Remotes.DevCommand.OnServerEvent:Connect(function(player, command, arg)
		if command == "weather" then
			WeatherService.DevToggle(if type(arg) == "string" and Balance.Weather.Events[arg] then arg else nil)
		elseif command == "coins" then
			local data = DataService.Get(player)
			if data then
				EconomyService.AddCoins(player, math.max(1000, data.Coins))
			end
		elseif command == "carry" then
			if CakePopService.IsCarrying(player) then
				CakePopService.Drop(player, true)
			else
				CakePopService.GiveToHands(player, { Id = "pet_1_1" })
			end
		elseif command == "pop" then
			-- arg = id мутации для проверки эффектов (Toxic, Neon, Frozen...), без него Shiny
			local mutation = if type(arg) == "string" and Balance.MutationById[arg] then arg else "Shiny"
			CakePopService.SpawnNear(player, { Id = "pet_3_3", Mutation = mutation })
		elseif command == "foreignpop" then
			CakePopService.SpawnNear(player, { Id = "pet_5_2" }, -1)
		elseif command == "stun" then
			TrapService.Stun(player)
		elseif command == "tradeban0" then
			TradeService.ClearBan(player)
		elseif command == "afkfast" then
			player:SetAttribute("DevAfkFast", not player:GetAttribute("DevAfkFast"))
		elseif command == "ovenfast" then
			player:SetAttribute("DevOvenFast", not player:GetAttribute("DevOvenFast"))
		elseif command == "family" then
			-- 8 из 9 Скебобсов первого Семейства, чтобы проверить призыв Патрона
			local data = DataService.Get(player)
			if data then
				for index = 1, 8 do
					data.Pets[HttpService:GenerateGUID(false)] =
						{ Id = Families.List[1].Members[index].Id, Locked = false }
				end
				Remotes.ProfileChanged:FireClient(player)
			end
		elseif command == "seed" then
			seedPets(player)
		end
	end)
	DataService.ProfileLoaded:Connect(function(player, data)
		if next(data.Pets) == nil then
			seedPets(player)
		end
	end)
end

return DevService
