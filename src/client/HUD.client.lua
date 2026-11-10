-- Собирает HUD. Джойстик и кнопку прыжка на мобилках рисует сам Roblox,
-- поэтому наши элементы обходят нижние углы.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Config"):WaitForChild("Strings"))

local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local create = Widgets.Create

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local glowGui = create("ScreenGui", {
	Name = "HUDGlow",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 0,
	Parent = playerGui,
})
local gui = create("ScreenGui", {
	Name = "HUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 5,
	Parent = playerGui,
})

-- Масштаб под размер экрана: телефон получает те же элементы, только мельче
local uiScale = create("UIScale", { Parent = gui })
local root = create("Frame", {
	Name = "Root",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Parent = gui,
})
local function rescale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local scale = math.clamp(math.min(viewport.X, viewport.Y) / Theme.DesignHeight, Theme.MinScale, Theme.MaxScale)
	uiScale.Scale = scale
	-- UIScale уменьшает и сам Root, поэтому растягиваем его обратно на весь экран
	root.Size = UDim2.fromScale(1 / scale, 1 / scale)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(rescale)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end
rescale()

local notify = require(UI:WaitForChild("Toast"))(root)
Remotes.Notify.OnClientEvent:Connect(notify)

local donateUI = require(UI:WaitForChild("DonateShop"))(root)
require(UI:WaitForChild("CurrencyPanel"))(root, notify, donateUI.Open)
require(UI:WaitForChild("Hotbar"))(root)
require(UI:WaitForChild("DropButton"))(root)
require(UI:WaitForChild("AfkBar"))(root, glowGui)
local fridgeScreen = require(UI:WaitForChild("FridgeScreen"))(root, notify)
local ovenScreen = require(UI:WaitForChild("OvenScreen"))(root, notify)
local settingsScreen = require(UI:WaitForChild("Settings"))(root, notify)
local menu = require(UI:WaitForChild("MainMenu"))(root, notify, { OpenOven = ovenScreen.Open })
-- Лавка Антона и ящик обмена открываются своими ProximityPrompt
local shopUI = require(UI:WaitForChild("Shop"))(root, notify)
local tradeUI = require(UI:WaitForChild("Trade"))(root, notify)
local mergeUI = require(UI:WaitForChild("Merge"))(root, notify)
require(UI:WaitForChild("HatchScreen"))(root)
local blackMarketUI = require(UI:WaitForChild("BlackMarket"))(root, notify)
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
	if prompt.Name == "ShopPrompt" then
		shopUI.Open()
	elseif prompt.Name == "TradePrompt" then
		tradeUI.OpenPicker()
	elseif prompt.Name == "AltarPrompt" then
		mergeUI.Open()
	elseif prompt.Name == "BlackMarketPrompt" then
		blackMarketUI.Open()
	elseif prompt.Name == "FridgeOpenPrompt" then
		fridgeScreen.Open()
	elseif prompt.Name == "OvenOpenPrompt" then
		ovenScreen.Open()
	elseif prompt.Name == "PedestalPrompt" and prompt.Parent:GetAttribute("State") == "Empty" then
		-- пустой свой пьедестал: выбрать, кого поставить
		menu.OpenEquip(prompt.Parent:GetAttribute("Slot"))
	end
end)

-- Левый край по центру: Рюкзак
local backpack = Widgets.Button({
	Name = "Backpack",
	BackgroundColor3 = Theme.Colors.Backpack,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(88, 88),
	Parent = root,
}, menu.Toggle)
Widgets.Label({
	Text = "🎒",
	Size = UDim2.fromScale(0.62, 0.62),
	Position = UDim2.fromScale(0.19, 0.06),
	Outline = false,
	Parent = backpack,
})
Widgets.Label({
	Text = Strings.Backpack,
	Size = UDim2.new(1, -8, 0, 20),
	Position = UDim2.new(0, 4, 1, -24),
	MaxTextSize = 16,
	Parent = backpack,
})

-- Над Рюкзаком: настройки
Widgets.Button({
	Name = "SettingsButton",
	Text = "⚙️",
	BackgroundColor3 = Theme.Colors.PanelDark,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, -82),
	Size = UDim2.fromOffset(60, 60),
	Parent = root,
}, settingsScreen.Open)

-- Под Рюкзаком: донат-магазин
local donateButton = Widgets.Button({
	Name = "Donate",
	Text = "🛒 " .. Strings.DonateButton,
	BackgroundColor3 = Theme.Colors.Plus,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 78),
	Size = UDim2.fromOffset(88, 52),
	Parent = root,
}, donateUI.Open)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		menu.Toggle()
	end
	-- Тестовые клавиши, сервер выполняет их только в Studio
	if RunService:IsStudio() then
		if input.KeyCode == Enum.KeyCode.K then
			Remotes.DevCommand:FireServer("coins")
		elseif input.KeyCode == Enum.KeyCode.F then
			Remotes.DevCommand:FireServer("carry")
		elseif input.KeyCode == Enum.KeyCode.P then
			Remotes.DevCommand:FireServer("seed")
		elseif input.KeyCode == Enum.KeyCode.G then
			Remotes.DevCommand:FireServer("pop")
		elseif input.KeyCode == Enum.KeyCode.Y then
			Remotes.DevCommand:FireServer("foreignpop")
		elseif input.KeyCode == Enum.KeyCode.T then
			Remotes.DevCommand:FireServer("stun")
		elseif input.KeyCode == Enum.KeyCode.U then
			Remotes.DevCommand:FireServer("afkfast")
		elseif input.KeyCode == Enum.KeyCode.O then
			Remotes.DevCommand:FireServer("ovenfast")
		elseif input.KeyCode == Enum.KeyCode.N then
			Remotes.DevCommand:FireServer("family")
		elseif input.KeyCode == Enum.KeyCode.J then
			Remotes.DevCommand:FireServer("weather")
		end
	end
end)

-- Первый снимок данных, когда сервер загрузит профиль
if not player:GetAttribute("DataLoaded") then
	player:GetAttributeChangedSignal("DataLoaded"):Wait()
end
ClientState.Refresh()
