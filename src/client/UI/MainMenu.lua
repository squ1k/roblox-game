-- Главное меню (Рюкзак): вкладки Скебобсы / Холодильник / База / Индекс (бестиарий и Патроны) /
-- Достижения.
-- Только крупные тапы, без drag & drop. Действия в карточках пока заглушки.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Income = require(Shared:WaitForChild("Income"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Prices = require(Shared:WaitForChild("Prices"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local renderAchievements = require(script.Parent:WaitForChild("Achievements"))
local create = Widgets.Create

local TABS = {
	{ Id = "Skebobs", Title = Strings.TabSkebobs },
	{ Id = "Fridge", Title = Strings.TabFridge },
	{ Id = "Base", Title = Strings.TabBase },
	{ Id = "Patrons", Title = Strings.TabIndex },
	{ Id = "Achievements", Title = Strings.TabAchievements },
}

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function describePop(pop): string
	local skebob = Families.SkebobById[pop.Id]
	local rarity = skebob and Balance.RarityById[skebob.Rarity] or Balance.Rarities[1]
	local family = skebob and Families.ById[skebob.Family]
	return (if pop.Sleeping then Strings.SleepingPop .. " · " else "")
		.. (if family then family.Name .. " · " else "")
		.. rarity.Name
end

local function rarityOf(skebobId: string)
	local skebob = Families.SkebobById[skebobId]
	return skebob and Balance.RarityById[skebob.Rarity], skebob
end

-- screens: { OpenOven = function } отдельные экраны, которые можно открыть из вкладок
return function(parent: Instance, notify, screens)
	local overlay = create("TextButton", {
		Name = "MainMenu",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	local window = create("Frame", {
		Name = "Window",
		Active = true, -- клики по окну не закрывают меню
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.88),
		BackgroundColor3 = Theme.Colors.Panel,
		ZIndex = 21,
		Parent = overlay,
	}, {
		Widgets.Corner(UDim.new(0, 24)),
		Widgets.Stroke(4),
		create("UISizeConstraint", { MaxSize = Vector2.new(1100, 700) }),
		create("UIScale"),
	})

	-- Тап вне окна закрывает меню
	overlay.Activated:Connect(function()
		overlay.Visible = false
	end)

	-- Шапка: вкладки + крестик
	local header = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 0, 64),
		Position = UDim2.fromOffset(12, 12),
		ZIndex = 22,
		Parent = window,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local content = create("ScrollingFrame", {
		Name = "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 88),
		Size = UDim2.new(1, -32, 1, -104),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 22,
		Parent = window,
	})

	local currentTab = "Skebobs"
	local tabButtons = {}
	local render
	local pendingSlot = nil -- пьедестал, на который ставим Скебобса из меню (подсказка на пустом пьедестале)
	local expandedFamily = nil -- раскрытое Семейство в бестиарии (вкладка Патроны)

	for index, tab in TABS do
		tabButtons[tab.Id] = Widgets.Button({
			Name = tab.Id,
			Text = tab.Title,
			LayoutOrder = index,
			Size = UDim2.new(0.165, 0, 1, 0),
			BackgroundColor3 = Theme.Colors.TabIdle,
			ZIndex = 23,
			Parent = header,
		}, function()
			currentTab = tab.Id
			render()
		end)
	end
	Widgets.Button({
		Name = "Close",
		Text = "X",
		LayoutOrder = 99,
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = Theme.Colors.Drop,
		ZIndex = 23,
		Parent = header,
	}, function()
		overlay.Visible = false
	end)

	local function clear()
		for _, child in content:GetChildren() do
			child:Destroy()
		end
	end

	local function emptyText(text: string)
		Widgets.Label({
			Text = text,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			Size = UDim2.new(1, 0, 0, 60),
			MaxTextSize = 28,
			ZIndex = 23,
			Parent = content,
		})
	end

	local function grid()
		create("UIGridLayout", {
			CellSize = UDim2.fromOffset(150, 180),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})
	end

	-- Всплывающие действия над карточкой
	local function showActions(card: GuiObject, actions)
		local popup = create("Frame", {
			Name = "Actions",
			BackgroundColor3 = Theme.Colors.PanelDark,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 30,
			Parent = card,
		}, {
			Widgets.Corner(),
			create("UIListLayout", {
				Padding = UDim.new(0, 6),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
		})
		for _, action in actions do
			Widgets.Button({
				Text = action.Text,
				BackgroundColor3 = action.Color or Theme.Colors.Backpack,
				Size = UDim2.new(0.9, 0, 0, 44),
				ZIndex = 31,
				Parent = popup,
			}, function()
				popup:Destroy()
				if action.Run then
					action.Run()
				end
			end)
		end
	end

	local function card(order: number, color: Color3, icon: string, title: string, subtitle: string, actions)
		local button = Widgets.Button({
			LayoutOrder = order,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 23,
			Parent = content,
		})
		create("Frame", {
			BackgroundColor3 = color,
			Size = UDim2.new(1, -12, 0, 96),
			Position = UDim2.fromOffset(6, 6),
			ZIndex = 24,
			Parent = button,
		}, { Widgets.Corner() })
		Widgets.Label({
			Text = icon,
			Size = UDim2.fromOffset(80, 80),
			Position = UDim2.new(0.5, -40, 0, 14),
			Outline = false,
			ZIndex = 25,
			Parent = button,
		})
		Widgets.Label({
			Text = title,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			Size = UDim2.new(1, -12, 0, 30),
			Position = UDim2.fromOffset(6, 108),
			MaxTextSize = 22,
			ZIndex = 24,
			Parent = button,
		})
		Widgets.Label({
			Text = subtitle,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			Font = Theme.FontBody,
			Size = UDim2.new(1, -12, 0, 32),
			Position = UDim2.fromOffset(6, 140),
			MaxTextSize = 15,
			TextWrapped = true,
			ZIndex = 24,
			Parent = button,
		})
		button.Activated:Connect(function()
			if not button:FindFirstChild("Actions") then
				showActions(button, actions)
			end
		end)
		return button
	end

	local function soon()
		notify("Появится в следующем этапе")
	end

	local function renderSkebobs(profile)
		local pets = {}
		local onPedestal = {} -- [uid] = slot
		for slot, pedestal in profile.Pedestals do
			if pedestal.Pet then
				onPedestal[pedestal.Pet] = slot
			end
		end
		for uid, pet in profile.Pets do
			local rarity = rarityOf(pet.Id)
			if rarity then
				table.insert(pets, { Uid = uid, Pet = pet, Rarity = rarity })
			end
		end
		if #pets == 0 then
			emptyText(Strings.EmptySkebobs)
			return
		end
		table.sort(pets, function(a, b)
			if a.Rarity.Order ~= b.Rarity.Order then
				return a.Rarity.Order > b.Rarity.Order
			end
			return a.Pet.Id < b.Pet.Id
		end)
		grid()
		for order, entry in pets do
			local mutation = entry.Pet.Mutation and Balance.MutationById[entry.Pet.Mutation]
			local subtitle = entry.Rarity.Name
			if mutation then
				subtitle = mutation.Name .. " · " .. subtitle
			end
			if onPedestal[entry.Uid] then
				subtitle ..= "\nНа пьедестале"
			end
			if entry.Pet.Locked then
				subtitle = "🔒 " .. subtitle
			end
			local uid = entry.Uid
			local slot = onPedestal[uid]
			local button
			local actions = {
				if slot
					then {
						Text = Strings.Unequip,
						Run = function()
							Remotes.PedestalUnequip:FireServer(slot)
						end,
					}
					else {
						Text = Strings.Equip,
						Run = function()
							Remotes.PedestalEquip:FireServer(uid, pendingSlot)
							pendingSlot = nil
						end,
					},
				{
					Text = if entry.Pet.Locked then Strings.Unlock else Strings.Lock,
					Color = Theme.Colors.Locked,
					Run = function()
						Remotes.PetLock:FireServer(uid)
					end,
				},
			}
			if not entry.Pet.Locked then
				table.insert(actions, {
					Text = Strings.Delete,
					Color = Theme.Colors.Drop,
					Run = function()
						showActions(button, {
							{
								Text = Strings.ConfirmDelete,
								Color = Theme.Colors.Drop,
								Run = function()
									Remotes.PetDelete:FireServer(uid)
								end,
							},
						})
					end,
				})
			end
			button = card(order, entry.Rarity.Glaze, "🐸", entry.Pet.Id, subtitle, actions)
		end
	end

	local function renderFridge(profile)
		if #profile.Fridge == 0 then
			emptyText(Strings.EmptyFridge)
			return
		end
		grid()
		for order, pop in profile.Fridge do
			local rarity, skebob = rarityOf(pop.Id)
			if rarity and skebob then
				local family = Families.ById[skebob.Family]
				card(order, rarity.Glaze, "🍭", family.Name, rarity.Name, {
					{
						Text = Strings.TakeToHands,
						Run = function()
							Remotes.FridgeTake:FireServer(order)
							overlay.Visible = false
						end,
					},
					{
						Text = Strings.SendToOven,
						Color = Theme.Colors.Buy,
						Run = function()
							Remotes.OvenStart:FireServer(order)
						end,
					},
				})
			end
		end
	end

	-- Патроны + бестиарий: тап по строке Семейства раскрывает всех его Скебобсов
	local function renderPatrons(profile)
		create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
		local owned = {}
		local mutated = {} -- есть ли у игрока этот Скебобс с мутацией (звезда в бестиарии)
		for _, pet in profile.Pets do
			owned[pet.Id] = true
			if pet.Mutation then
				mutated[pet.Id] = true
			end
		end
		local order = 0
		for _, family in Families.List do
			order += 1
			local count, need = Income.FamilyProgress(profile, family.Id)
			local summoned = profile.Patrons.Summoned[family.Id] == true
			local chosen = profile.Patrons.Chosen == family.Id
			local hidden = profile.Patrons.Hidden and profile.Patrons.Hidden[family.Id]
			local ready = count >= need
			local row = Widgets.Button({
				LayoutOrder = order,
				BackgroundColor3 = Color3.new(1, 1, 1),
				Size = UDim2.new(1, -12, 0, 76),
				ZIndex = 23,
				Parent = content,
			}, function()
				expandedFamily = if expandedFamily == family.Id then nil else family.Id
				render()
			end)
			create("Frame", {
				BackgroundColor3 = family.Color,
				Size = UDim2.new(0, 10, 1, -16),
				Position = UDim2.fromOffset(8, 8),
				ZIndex = 24,
				Parent = row,
			}, { Widgets.Corner(UDim.new(1, 0)) })
			Widgets.Label({
				Text = (if expandedFamily == family.Id then "▼ " else "▶ ") .. family.Name,
				TextColor3 = Theme.Colors.TextDark,
				Outline = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0.28, 0, 0, 36),
				Position = UDim2.fromOffset(26, 6),
				MaxTextSize = 24,
				ZIndex = 24,
				Parent = row,
			})
			Widgets.Label({
				Text = "Босс: " .. family.Patron,
				TextColor3 = Theme.Colors.TextDark,
				Outline = false,
				Font = Theme.FontBody,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0.28, 0, 0, 22),
				Position = UDim2.fromOffset(26, 44),
				MaxTextSize = 16,
				ZIndex = 24,
				Parent = row,
			})
			local track = create("Frame", {
				BackgroundColor3 = Color3.fromRGB(220, 210, 200),
				Size = UDim2.new(0.25, 0, 0, 22),
				Position = UDim2.new(0.3, 10, 0.5, -11),
				ZIndex = 24,
				Parent = row,
			}, { Widgets.Corner(UDim.new(1, 0)) })
			create("Frame", {
				BackgroundColor3 = Theme.Colors.Buy,
				Size = UDim2.fromScale(math.clamp(count / need, 0, 1), 1),
				ZIndex = 25,
				Parent = track,
			}, { Widgets.Corner(UDim.new(1, 0)) })
			Widgets.Label({
				Text = count .. " / " .. need,
				Size = UDim2.fromScale(1, 1),
				MaxTextSize = 18,
				ZIndex = 26,
				Parent = track,
			})
			local buttons = {}
			if not summoned then
				table.insert(buttons, {
					Text = if ready then Strings.PatronSummon else Strings.Locked,
					Color = if ready then Theme.Colors.Buy else Theme.Colors.Locked,
					Run = if ready
						then function()
							Remotes.PatronSummon:FireServer(family.Id)
						end
						else nil,
				})
			else
				table.insert(buttons, {
					Text = if chosen then Strings.PatronChosen else Strings.PatronChoose,
					Color = if chosen then Theme.Colors.TabActive else Theme.Colors.Backpack,
					Run = function()
						Remotes.PatronChoose:FireServer(family.Id)
					end,
				})
				table.insert(buttons, {
					Text = if hidden then Strings.PatronShow else Strings.PatronHide,
					Color = Theme.Colors.Locked,
					Run = function()
						Remotes.PatronHide:FireServer(family.Id)
					end,
				})
			end
			for index, spec in buttons do
				local button = Widgets.Button({
					Text = spec.Text,
					BackgroundColor3 = spec.Color,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10 - 150 * (index - 1), 0.5, 0),
					Size = UDim2.fromOffset(140, 52),
					ZIndex = 25,
					Parent = row,
				}, spec.Run)
				button.Active = spec.Run ~= nil
			end

			if expandedFamily == family.Id then
				order += 1
				local strip = create("Frame", {
					LayoutOrder = order,
					BackgroundColor3 = Color3.fromRGB(240, 232, 220),
					Size = UDim2.new(1, -12, 0, 96),
					ZIndex = 23,
					Parent = content,
				}, {
					Widgets.Corner(),
					create("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 8),
						VerticalAlignment = Enum.VerticalAlignment.Center,
					}),
					create("UIPadding", { PaddingLeft = UDim.new(0, 10) }),
				})
				for _, member in family.Members do
					local rarity = Balance.RarityById[member.Rarity]
					local has = owned[member.Id] == true
					local tile = create("Frame", {
						BackgroundColor3 = if has then rarity.Glaze else Theme.Colors.Locked,
						Size = UDim2.fromOffset(78, 80),
						ZIndex = 24,
						Parent = strip,
					}, { Widgets.Corner(), Widgets.Stroke(2) })
					Widgets.Label({
						Text = if has then (if mutated[member.Id] then "✓★" else "✓") else "?",
						Size = UDim2.new(1, 0, 0, 40),
						Position = UDim2.fromOffset(0, 4),
						MaxTextSize = 30,
						ZIndex = 25,
						Parent = tile,
					})
					Widgets.Label({
						Text = rarity.Name,
						Font = Theme.FontBody,
						Size = UDim2.new(1, -6, 0, 30),
						Position = UDim2.fromOffset(3, 46),
						MaxTextSize = 13,
						TextWrapped = true,
						ZIndex = 25,
						Parent = tile,
					})
				end
			end
		end
	end

	-- Строка вкладки "База": текст слева, кнопки справа
	local function row(order: number, text: string, buttons, header: boolean?)
		local frame = create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = if header then Theme.Colors.TabIdle else Color3.new(1, 1, 1),
			Size = UDim2.new(1, -12, 0, 60),
			ZIndex = 23,
			Parent = content,
		}, { Widgets.Corner() })
		Widgets.Label({
			Text = text,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			Font = if header then Theme.Font else Theme.FontBody,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -24 - 190 * #buttons, 1, -12),
			Position = UDim2.fromOffset(12, 6),
			MaxTextSize = 22,
			ZIndex = 24,
			Parent = frame,
		})
		for index, spec in buttons do
			local button = Widgets.Button({
				Text = spec.Text,
				BackgroundColor3 = if spec.Run then spec.Color or Theme.Colors.Buy else Theme.Colors.Locked,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8 - 190 * (index - 1), 0.5, 0),
				Size = UDim2.fromOffset(180, 48),
				ZIndex = 24,
				Parent = frame,
			}, spec.Run)
			button.Active = spec.Run ~= nil
		end
	end

	local function renderBase(profile)
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
		local order = 0
		local function nextOrder()
			order += 1
			return order
		end
		local now = workspace:GetServerTimeNow()

		-- Пьедесталы
		for slot, pedestal in profile.Pedestals do
			local pet = pedestal.Pet and profile.Pets[pedestal.Pet]
			local text = string.format(Strings.PedestalLevel, slot, pedestal.Level)
				.. " — "
				.. (if pet then describePop(pet) else Strings.PedestalEmpty)
			local price = pedestal.Level < Balance.Pedestals.MaxLevel and Income.PedestalLevelPrice(pedestal.Level + 1)
			local buttons = {
				if price
					then {
						Text = string.format(Strings.PedestalUpgrade, NumberFormat.Short(price)),
						Run = function()
							Remotes.PedestalUpgrade:FireServer(slot)
						end,
					}
					else { Text = Strings.PedestalMax },
			}
			if pet then
				table.insert(buttons, {
					Text = Strings.PedestalTake,
					Color = Theme.Colors.Sell,
					Run = function()
						Remotes.PedestalUnequip:FireServer(slot)
					end,
				})
			end
			row(nextOrder(), text, buttons)
		end
		local nextSlot = #profile.Pedestals + 1
		local slotPrice = Prices.PedestalSlot(nextSlot)
		if nextSlot <= Balance.Pedestals.MaxFreeSlots and slotPrice then
			row(nextOrder(), string.format(Strings.PedestalBuy, NumberFormat.Short(slotPrice)), {
				{
					Text = Strings.ShopBuyTab,
					Run = function()
						Remotes.PedestalBuySlot:FireServer()
					end,
				},
			})
		elseif nextSlot <= Balance.Pedestals.MaxSlots then
			row(nextOrder(), Strings.PedestalRobux, {})
		end

		-- Тепловой шкаф
		local level = Balance.Oven.Levels[profile.OvenLevel] or Balance.Oven.Levels[1]
		local nextLevel = Balance.Oven.Levels[profile.OvenLevel + 1]
		row(nextOrder(), string.format(Strings.OvenTitle, profile.OvenLevel), {
			{
				Text = Strings.OvenOpen,
				Color = Theme.Colors.Backpack,
				Run = if screens and screens.OpenOven
					then function()
						overlay.Visible = false
						screens.OpenOven()
					end
					else nil,
			},
			if nextLevel
				then {
					Text = string.format(Strings.OvenUpgrade, NumberFormat.Short(nextLevel.Price)),
					Run = function()
						Remotes.OvenUpgrade:FireServer()
					end,
				}
				else { Text = Strings.OvenMax },
		}, true)
		for slot = 1, level.Slots do
			local entry = profile.Ovens[slot]
			if entry then
				local left = entry.StartedAt + entry.Duration - now
				if left <= 0 then
					row(nextOrder(), describePop(entry.Pop) .. ": " .. Strings.OvenReady, {
						{
							Text = Strings.OvenCollect,
							Run = function()
								Remotes.OvenCollect:FireServer(slot)
							end,
						},
					})
				else
					row(nextOrder(), describePop(entry.Pop) .. ": " .. formatTime(left), {
						{
							Text = Strings.OvenCancel,
							Color = Theme.Colors.Drop,
							Run = function()
								Remotes.OvenCancel:FireServer(slot)
							end,
						},
					})
				end
			else
				row(nextOrder(), Strings.OvenEmpty, {})
			end
		end

		-- Холодильник
		local fridgePrice = Prices.FridgeSlot(profile.FridgeSlots + 1)
		row(nextOrder(), Strings.TabFridge .. " " .. #profile.Fridge .. "/" .. profile.FridgeSlots, {
			if fridgePrice
				then {
					Text = string.format(Strings.FridgeExpand, NumberFormat.Short(fridgePrice)),
					Run = function()
						Remotes.FridgeBuySlot:FireServer()
					end,
				}
				else { Text = Strings.FridgeMax },
		}, true)

		-- АФК-корзина
		local clearText = if (profile.BasketClearAt or 0) > 0
			then " · " .. string.format(Strings.BasketClearIn, formatTime(profile.BasketClearAt - now))
			else ""
		row(nextOrder(), Strings.BasketTitle .. " (" .. #(profile.Basket or {}) .. ")" .. clearText, {}, true)
		for index, pop in profile.Basket or {} do
			row(nextOrder(), describePop(pop), {
				{
					Text = Strings.BasketTake,
					Run = function()
						Remotes.BasketTake:FireServer(index)
					end,
				},
			})
		end
	end

	function render()
		for id, button in tabButtons do
			button.BackgroundColor3 = if id == currentTab then Theme.Colors.TabActive else Theme.Colors.TabIdle
		end
		clear()
		local profile = ClientState.Profile
		if not profile then
			emptyText("...")
			return
		end
		tabButtons.Fridge.Text = Strings.TabFridge .. " " .. #profile.Fridge .. "/" .. profile.FridgeSlots
		if currentTab == "Skebobs" then
			renderSkebobs(profile)
		elseif currentTab == "Fridge" then
			renderFridge(profile)
		elseif currentTab == "Base" then
			renderBase(profile)
		elseif currentTab == "Achievements" then
			renderAchievements(content, profile)
		else
			renderPatrons(profile)
		end
	end

	ClientState.ProfileChanged:Connect(function()
		if overlay.Visible then
			render()
		end
	end)

	local menu = {}
	function menu.Open()
		overlay.Visible = true
		render()
		ClientState.Refresh()
		local scale = window:FindFirstChildOfClass("UIScale")
		scale.Scale = 0.85
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	-- Пустой свой пьедестал: открыть Скебобсов, "Экипировать" поставит на этот слот
	function menu.OpenEquip(slot: number)
		pendingSlot = slot
		currentTab = "Skebobs"
		menu.Open()
	end
	-- Таймеры шкафа и корзины во вкладке "База" обновляются раз в секунду
	task.spawn(function()
		while true do
			task.wait(1)
			if overlay.Visible and currentTab == "Base" then
				render()
			end
		end
	end)
	function menu.Toggle()
		if overlay.Visible then
			overlay.Visible = false
		else
			menu.Open()
		end
	end
	return menu
end
