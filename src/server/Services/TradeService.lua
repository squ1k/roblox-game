-- "ООО СкебобсОбмен": обмен Скебобсами между игроками у ящика. Приглашение -> оба кладут до
-- MaxItems Скебобсов -> оба "Готов" -> ConfirmSeconds -> обмен. Любое изменение оффера
-- сбрасывает готовность обоих (анти-гриф). После обмена у обоих трейд-бан BanSeconds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local MapService = require(script.Parent:WaitForChild("MapService"))

local Trade = Balance.Trade
local ALLOWED_ZONES = { Shop = true, Center = true }

local TradeService = {}

local invites = {} -- [target] = { From = Player, ExpiresAt = os.clock() }
local sessions = {} -- [player] = session { A, B, Offers = { [player] = { uid } }, Ready = { [player] = bool }, ConfirmAt }

local function now()
	return workspace:GetServerTimeNow()
end

local function banLeft(player: Player): number
	local data = DataService.Get(player)
	return if data then math.max(0, (data.TradeBanUntil or 0) - now()) else 0
end

local function formatLeft(seconds: number): string
	seconds = math.ceil(seconds)
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

local function onPedestal(data, uid: string): boolean
	for _, pedestal in data.Pedestals do
		if pedestal.Pet == uid then
			return true
		end
	end
	return false
end

local function partnerOf(session, player: Player): Player
	return if session.A == player then session.B else session.A
end

local function push(session)
	for _, player in { session.A, session.B } do
		local partner = partnerOf(session, player)
		local partnerData = DataService.Get(partner)
		local theirs = {}
		for _, uid in session.Offers[partner] do
			local pet = partnerData and partnerData.Pets[uid]
			if pet then
				table.insert(theirs, { Id = pet.Id, Mutation = pet.Mutation })
			end
		end
		Remotes.TradeState:FireClient(player, {
			Kind = "Session",
			PartnerName = partner.DisplayName,
			MyOffer = session.Offers[player],
			TheirOffer = theirs,
			MyReady = session.Ready[player] == true,
			TheirReady = session.Ready[partner] == true,
			ConfirmLeft = if session.ConfirmAt then math.max(0, session.ConfirmAt - os.clock()) else nil,
		})
	end
end

local function close(session, message: string?)
	for _, player in { session.A, session.B } do
		sessions[player] = nil
		if player.Parent then
			Remotes.TradeState:FireClient(player, nil)
			if message then
				Remotes.Notify:FireClient(player, message)
			end
		end
	end
end

function TradeService.IsOffered(player: Player, uid: string): boolean
	local session = sessions[player]
	return session ~= nil and table.find(session.Offers[player], uid) ~= nil
end

local function invite(player: Player, targetUserId)
	if type(targetUserId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return
	end
	if not ALLOWED_ZONES[player:GetAttribute("Zone")] or not ALLOWED_ZONES[target:GetAttribute("Zone")] then
		return
	end
	local left = math.max(banLeft(player), banLeft(target))
	if left > 0 then
		Remotes.Notify:FireClient(player, string.format(Strings.TradeBanLeft, formatLeft(left)))
		return
	end
	local targetData = DataService.Get(target)
	if sessions[player] or sessions[target] or invites[target] or not targetData then
		Remotes.Notify:FireClient(player, Strings.TradeBusy)
		return
	end
	if
		targetData.TradeBlocked[tostring(player.UserId)] or (targetData.Settings and targetData.Settings.TradeBlockAll)
	then
		Remotes.Notify:FireClient(player, Strings.TradeBusy)
		return
	end
	invites[target] = { From = player, ExpiresAt = os.clock() + Trade.InviteSeconds }
	Remotes.TradeState:FireClient(
		target,
		{ Kind = "Invite", FromName = player.DisplayName, FromUserId = player.UserId }
	)
	Remotes.Notify:FireClient(player, Strings.TradeSent)
end

local function respond(player: Player, accept, block)
	local entry = invites[player]
	if not entry then
		return
	end
	invites[player] = nil
	local from = entry.From
	if block == true then
		local data = DataService.Get(player)
		if data then
			data.TradeBlocked[tostring(from.UserId)] = true
		end
	end
	Remotes.TradeState:FireClient(player, nil)
	if accept ~= true or not from.Parent or sessions[from] or sessions[player] then
		if from.Parent then
			Remotes.Notify:FireClient(from, Strings.TradeDeclined)
		end
		return
	end
	local session = { A = from, B = player, Offers = { [from] = {}, [player] = {} }, Ready = {}, ConfirmAt = nil }
	sessions[from] = session
	sessions[player] = session
	push(session)
end

local function resetReady(session)
	session.Ready = {}
	session.ConfirmAt = nil
end

local function offer(player: Player, uids)
	local session = sessions[player]
	local data = DataService.Get(player)
	if not session or not data or type(uids) ~= "table" or #uids > Trade.MaxItems then
		return
	end
	local clean = {}
	for _, uid in uids do
		if type(uid) ~= "string" or table.find(clean, uid) then
			return
		end
		local pet = data.Pets[uid]
		if not pet or pet.Locked or onPedestal(data, uid) then
			return
		end
		table.insert(clean, uid)
	end
	session.Offers[player] = clean
	resetReady(session)
	push(session)
end

local function ready(player: Player, value)
	local session = sessions[player]
	if not session then
		return
	end
	session.Ready[player] = value == true
	if session.Ready[session.A] and session.Ready[session.B] then
		session.ConfirmAt = os.clock() + Trade.ConfirmSeconds
	else
		session.ConfirmAt = nil
	end
	push(session)
end

-- Обмен в данных: еще раз проверяем, что все Скебобсы на месте и свободны
local function execute(session)
	local dataA, dataB = DataService.Get(session.A), DataService.Get(session.B)
	if not dataA or not dataB then
		close(session, Strings.TradeCancelled)
		return
	end
	for _, pair in { { session.A, dataA }, { session.B, dataB } } do
		for _, uid in session.Offers[pair[1]] do
			local pet = pair[2].Pets[uid]
			if not pet or pet.Locked or onPedestal(pair[2], uid) then
				close(session, Strings.TradeNoRoom)
				return
			end
		end
	end
	local function move(fromData, toData, uids)
		for _, uid in uids do
			toData.Pets[uid] = fromData.Pets[uid]
			fromData.Pets[uid] = nil
		end
	end
	move(dataA, dataB, session.Offers[session.A])
	move(dataB, dataA, session.Offers[session.B])
	local banUntil = now() + Trade.BanSeconds
	dataA.TradeBanUntil = banUntil
	dataB.TradeBanUntil = banUntil
	dataA.Stats.Trades += 1
	dataB.Stats.Trades += 1
	for _, player in { session.A, session.B } do
		EconomyService.Refresh(player)
		Remotes.ProfileChanged:FireClient(player)
	end
	close(session, Strings.TradeDone)
end

function TradeService.Cancel(player: Player)
	local session = sessions[player]
	if session then
		close(session, Strings.TradeCancelled)
	end
end

function TradeService.ClearBan(player: Player)
	local data = DataService.Get(player)
	if data then
		data.TradeBanUntil = 0
		Remotes.ProfileChanged:FireClient(player)
	end
end

function TradeService.Start()
	local shop = MapService.Shop()
	if shop and shop.Exchange then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TradePrompt"
		prompt.ActionText = Strings.ExchangeOpen
		prompt.ObjectText = Strings.ExchangeTitle
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Trade.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = shop.Exchange
	end
	Remotes.TradeInvite.OnServerEvent:Connect(invite)
	Remotes.TradeRespond.OnServerEvent:Connect(respond)
	Remotes.TradeOffer.OnServerEvent:Connect(offer)
	Remotes.TradeReady.OnServerEvent:Connect(ready)
	Remotes.TradeCancel.OnServerEvent:Connect(TradeService.Cancel)

	Players.PlayerRemoving:Connect(function(player)
		invites[player] = nil
		for target, entry in invites do
			if entry.From == player then
				invites[target] = nil
				if target.Parent then
					Remotes.TradeState:FireClient(target, nil)
				end
			end
		end
		TradeService.Cancel(player)
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			for target, entry in invites do
				if os.clock() > entry.ExpiresAt then
					invites[target] = nil
					Remotes.TradeState:FireClient(target, nil)
				end
			end
			local seen = {}
			for player, session in sessions do
				if not seen[session] then
					seen[session] = true
					-- Ушел от ящика или из безопасной зоны = обмен сорван
					local away = not ALLOWED_ZONES[session.A:GetAttribute("Zone")]
						or not ALLOWED_ZONES[session.B:GetAttribute("Zone")]
					if away then
						close(session, Strings.TradeCancelled)
					elseif session.ConfirmAt then
						if os.clock() >= session.ConfirmAt then
							execute(session)
						else
							push(session)
						end
					end
				end
			end
		end
	end)
end

return TradeService
