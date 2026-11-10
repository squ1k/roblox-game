-- "ООО СкебобсОбмен" на клиенте: выбор партнера у ящика, окно приглашения (Принять / Отклонить /
-- Заблокировать) и окно обмена: слева мои свободные Скебобсы (тап = добавить/убрать, до MaxItems),
-- справа оффер партнера, кнопка "Готов" (желтая -> зеленая). Все решает сервер (TradeService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local create = Widgets.Create

local player = Players.LocalPlayer
local ALLOWED_ZONES = { Shop = true, Center = true }

local function formatLeft(seconds: number): string
	seconds = math.ceil(seconds)
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

return function(parent: Instance, notify)
	local state = nil -- последний снимок сессии с сервера

	local function overlayFrame(name: string)
		local overlay = create("TextButton", {
			Name = name,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 30,
			Parent = parent,
		})
		local window = create("Frame", {
			Active = true, -- клики по окну не закрывают его
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.92, 0.88),
			BackgroundColor3 = Theme.Colors.Panel,
			ZIndex = 31,
			Parent = overlay,
		}, {
			Widgets.Corner(UDim.new(0, 24)),
			Widgets.Stroke(4),
			create("UISizeConstraint", { MaxSize = Vector2.new(1100, 700) }),
		})
		return overlay, window
	end

	local function title(window, text: string)
		return Widgets.Label({
			Text = text,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			Size = UDim2.new(1, -100, 0, 50),
			Position = UDim2.fromOffset(16, 14),
			MaxTextSize = 32,
			ZIndex = 32,
			Parent = window,
		})
	end

	-- Выбор партнера
	local pickerOverlay, pickerWindow = overlayFrame("TradePicker")
	title(pickerWindow, Strings.TradePick)
	pickerOverlay.Activated:Connect(function()
		pickerOverlay.Visible = false
	end)
	Widgets.Button({
		Text = "X",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Theme.Colors.Drop,
		ZIndex = 33,
		Parent = pickerWindow,
	}, function()
		pickerOverlay.Visible = false
	end)
	local pickerList = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 80),
		Size = UDim2.new(1, -32, 1, -96),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ZIndex = 32,
		Parent = pickerWindow,
	}, { create("UIListLayout", { Padding = UDim.new(0, 10) }) })

	-- Приглашение
	local invite = create("Frame", {
		Name = "TradeInvite",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(520, 150),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Visible = false,
		ZIndex = 40,
		Parent = parent,
	}, { Widgets.Corner(), Widgets.Stroke() })
	local inviteText = Widgets.Label({
		Size = UDim2.new(1, -20, 0, 50),
		Position = UDim2.fromOffset(10, 8),
		MaxTextSize = 26,
		ZIndex = 41,
		Parent = invite,
	})
	local buttons = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 70),
		Position = UDim2.fromOffset(10, 68),
		ZIndex = 41,
		Parent = invite,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	})
	for _, entry in
		{
			{ Strings.TradeAccept, Theme.Colors.Buy, true, false },
			{ Strings.TradeDecline, Theme.Colors.Drop, false, false },
			{ Strings.TradeBlock, Theme.Colors.Locked, false, true },
		}
	do
		Widgets.Button({
			Text = entry[1],
			BackgroundColor3 = entry[2],
			Size = UDim2.fromOffset(160, 64),
			ZIndex = 42,
			Parent = buttons,
		}, function()
			invite.Visible = false
			Remotes.TradeRespond:FireServer(entry[3], entry[4])
		end)
	end

	-- Окно обмена
	local sessionOverlay, sessionWindow = overlayFrame("TradeSession")
	local sessionTitle = title(sessionWindow, Strings.ExchangeTitle)
	Widgets.Label({
		Text = Strings.TradeHint,
		TextColor3 = Theme.Colors.TextDark,
		Outline = false,
		Font = Theme.FontBody,
		Size = UDim2.new(0.5, -24, 0, 22),
		Position = UDim2.fromOffset(16, 64),
		MaxTextSize = 16,
		ZIndex = 32,
		Parent = sessionWindow,
	})
	local function column(xScale: number)
		return create("ScrollingFrame", {
			BackgroundColor3 = Color3.fromRGB(240, 232, 220),
			BorderSizePixel = 0,
			Position = UDim2.new(xScale, 16, 0, 92),
			Size = UDim2.new(0.5, -24, 1, -190),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 8,
			ZIndex = 32,
			Parent = sessionWindow,
		}, {
			Widgets.Corner(),
			create("UIGridLayout", { CellSize = UDim2.fromOffset(120, 120), CellPadding = UDim2.fromOffset(8, 8) }),
			create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8) }),
		})
	end
	local mine = column(0)
	local theirs = column(0.5)
	local status = Widgets.Label({
		TextColor3 = Theme.Colors.TextDark,
		Outline = false,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.new(0.4, 0, 0, 64),
		MaxTextSize = 26,
		ZIndex = 32,
		Parent = sessionWindow,
	})
	local readyButton = Widgets.Button({
		Text = Strings.TradeReady,
		BackgroundColor3 = Theme.Colors.Coin,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -196, 1, -16),
		Size = UDim2.fromOffset(200, 64),
		ZIndex = 33,
		Parent = sessionWindow,
	}, function()
		if state then
			Remotes.TradeReady:FireServer(not state.MyReady)
		end
	end)
	Widgets.Button({
		Text = Strings.TradeCancelButton,
		BackgroundColor3 = Theme.Colors.Drop,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(170, 64),
		ZIndex = 33,
		Parent = sessionWindow,
	}, function()
		Remotes.TradeCancel:FireServer()
		sessionOverlay.Visible = false
	end)

	local function petCard(container, petId: string, mutationId: string?, selected: boolean, onClick)
		local skebob = Families.SkebobById[petId]
		local rarity = skebob and Balance.RarityById[skebob.Rarity] or Balance.Rarities[1]
		local mutation = mutationId and Balance.MutationById[mutationId]
		local card = Widgets.Button({
			BackgroundColor3 = if selected then Theme.Colors.Buy else Color3.new(1, 1, 1),
			ZIndex = 33,
			Parent = container,
		}, onClick)
		create("Frame", {
			BackgroundColor3 = rarity.Glaze,
			Size = UDim2.new(1, -12, 0, 48),
			Position = UDim2.fromOffset(6, 6),
			ZIndex = 34,
			Parent = card,
		}, { Widgets.Corner() })
		Widgets.Label({
			Text = petId,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			Size = UDim2.new(1, -8, 0, 24),
			Position = UDim2.fromOffset(4, 58),
			MaxTextSize = 18,
			ZIndex = 34,
			Parent = card,
		})
		Widgets.Label({
			Text = (if mutation then mutation.Name .. " · " else "") .. rarity.Name,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			Font = Theme.FontBody,
			Size = UDim2.new(1, -8, 0, 30),
			Position = UDim2.fromOffset(4, 84),
			MaxTextSize = 13,
			TextWrapped = true,
			ZIndex = 34,
			Parent = card,
		})
	end

	local function clearGrid(frame)
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function renderSession()
		if not state then
			return
		end
		sessionTitle.Text = Strings.ExchangeTitle .. ": " .. Strings.TradeYou .. " ⇄ " .. state.PartnerName
		clearGrid(mine)
		clearGrid(theirs)
		local profile = ClientState.Profile
		if profile then
			local onPedestal = {}
			for _, pedestal in profile.Pedestals do
				if pedestal.Pet then
					onPedestal[pedestal.Pet] = true
				end
			end
			for uid, pet in profile.Pets do
				if not onPedestal[uid] and not pet.Locked then
					local selected = table.find(state.MyOffer, uid) ~= nil
					petCard(mine, pet.Id, pet.Mutation, selected, function()
						local offer = table.clone(state.MyOffer)
						local index = table.find(offer, uid)
						if index then
							table.remove(offer, index)
						elseif #offer < Balance.Trade.MaxItems then
							table.insert(offer, uid)
						else
							return
						end
						Remotes.TradeOffer:FireServer(offer)
					end)
				end
			end
		end
		for _, pet in state.TheirOffer do
			petCard(theirs, pet.Id, pet.Mutation, false, nil)
		end
		readyButton.BackgroundColor3 = if state.MyReady then Theme.Colors.Buy else Theme.Colors.Coin
		if state.ConfirmLeft then
			status.Text = string.format(Strings.TradeCountdown, math.ceil(state.ConfirmLeft))
		elseif state.TheirReady then
			status.Text = state.PartnerName .. ": " .. Strings.TradeReady
		else
			status.Text = ""
		end
	end

	Remotes.TradeState.OnClientEvent:Connect(function(newState)
		if not newState then
			state = nil
			invite.Visible = false
			sessionOverlay.Visible = false
			return
		end
		if newState.Kind == "Invite" then
			inviteText.Text = string.format(Strings.TradeInviteFrom, newState.FromName)
			invite.Visible = true
			Widgets.Pop(invite)
		elseif newState.Kind == "Session" then
			state = newState
			invite.Visible = false
			pickerOverlay.Visible = false
			if not sessionOverlay.Visible then
				sessionOverlay.Visible = true
				ClientState.Refresh()
			end
			renderSession()
		end
	end)
	ClientState.ProfileChanged:Connect(function()
		if sessionOverlay.Visible then
			renderSession()
		end
	end)

	local trade = {}
	function trade.OpenPicker()
		local profile = ClientState.Profile
		local left = profile and (profile.TradeBanUntil or 0) - workspace:GetServerTimeNow() or 0
		if left > 0 then
			notify(string.format(Strings.TradeBanLeft, formatLeft(left)))
			return
		end
		clearGrid(pickerList)
		local count = 0
		for _, other in Players:GetPlayers() do
			if other ~= player and ALLOWED_ZONES[other:GetAttribute("Zone")] then
				count += 1
				Widgets.Button({
					Text = other.DisplayName,
					BackgroundColor3 = Theme.Colors.Backpack,
					Size = UDim2.new(1, -16, 0, 64),
					ZIndex = 33,
					Parent = pickerList,
				}, function()
					pickerOverlay.Visible = false
					Remotes.TradeInvite:FireServer(other.UserId)
				end)
			end
		end
		if count == 0 then
			notify(Strings.TradeNobody)
			return
		end
		pickerOverlay.Visible = true
	end
	return trade
end
