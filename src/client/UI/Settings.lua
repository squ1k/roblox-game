-- Настройки (шестеренка в HUD): громкость музыки и звуков (полоса, тап задает значение),
-- переключатели и язык. Значения хранятся в data.Settings на сервере (SettingsSet).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local Screen = require(script.Parent:WaitForChild("Screen"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))
local create = Widgets.Create

local TOGGLES = { "ShowOtherPrompts", "IncomePopups", "ScreenShake", "TradeBlockAll" }
local SLIDERS = { "Music", "Sounds" }

local function setting(key: string)
	local profile = ClientState.Profile
	local value = profile and profile.Settings and profile.Settings[key]
	if value == nil then
		return Balance.DefaultSettings[key]
	end
	return value
end

return function(parent: Instance, notify)
	local overlay, window = Screen(parent, "Settings", Strings.SettingsTitle)
	local list = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(20, 80),
		Size = UDim2.new(1, -40, 1, -100),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = window,
	}, { create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local render

	local function row(order: number, text: string)
		local frame = create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(1, -12, 0, 66),
			ZIndex = 23,
			Parent = list,
		}, { Widgets.Corner(), Widgets.Stroke() })
		Widgets.Label({
			Text = text,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.5, 0, 1, -12),
			Position = UDim2.fromOffset(16, 6),
			MaxTextSize = 24,
			ZIndex = 24,
			Parent = frame,
		})
		return frame
	end

	local function slider(order: number, key: string)
		local frame = row(order, Strings["Settings" .. key])
		local value = setting(key)
		local bar = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -90, 0.5, 0),
			Size = UDim2.new(0.38, 0, 0, 24),
			BackgroundColor3 = Color3.fromRGB(220, 210, 200),
			ZIndex = 24,
			Parent = frame,
		}, { Widgets.Corner(UDim.new(1, 0)) })
		create("Frame", {
			BackgroundColor3 = Theme.Colors.Backpack,
			Size = UDim2.fromScale(value, 1),
			ZIndex = 25,
			Parent = bar,
		}, { Widgets.Corner(UDim.new(1, 0)) })
		Widgets.Label({
			Text = math.floor(value * 100 + 0.5) .. "%",
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(70, 30),
			MaxTextSize = 22,
			ZIndex = 24,
			Parent = frame,
		})
		bar.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local x = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
				Remotes.SettingsSet:FireServer(key, math.clamp(math.floor(x * 10 + 0.5) / 10, 0, 1))
			end
		end)
	end

	local function toggle(order: number, key: string)
		local frame = row(order, Strings["Settings" .. key])
		local on = setting(key) == true
		Widgets.Button({
			Text = if on then Strings.On else Strings.Off,
			BackgroundColor3 = if on then Theme.Colors.Buy else Theme.Colors.Locked,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(140, 50),
			ZIndex = 24,
			Parent = frame,
		}, function()
			Remotes.SettingsSet:FireServer(key, not on)
		end)
	end

	function render()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local order = 0
		for _, key in SLIDERS do
			order += 1
			slider(order, key)
		end
		for _, key in TOGGLES do
			order += 1
			toggle(order, key)
		end
		order += 1
		local language = row(order, Strings.SettingsLanguage)
		local current = Players.LocalPlayer:GetAttribute("Language") or "EN"
		Widgets.Button({
			Text = current,
			BackgroundColor3 = Theme.Colors.Backpack,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(140, 50),
			ZIndex = 24,
			Parent = language,
		}, function()
			Remotes.SettingsSet:FireServer("Language", if current == "RU" then "EN" else "RU")
		end)
		if Players.LocalPlayer:GetAttribute("Pass_Boombox") then
			order += 1
			local boombox = row(order, Strings.BoomboxTitle)
			local current = ClientState.Profile and ClientState.Profile.Boombox or 0
			local box = create("TextBox", {
				Text = if current > 0 then string.format("%d", current) else "",
				PlaceholderText = "1234567890",
				ClearTextOnFocus = false,
				Font = Theme.FontBody,
				TextScaled = true,
				TextColor3 = Theme.Colors.TextDark,
				BackgroundColor3 = Color3.fromRGB(240, 235, 225),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -244, 0.5, 0),
				Size = UDim2.fromOffset(200, 44),
				ZIndex = 24,
				Parent = boombox,
			}, { Widgets.Corner() })
			Widgets.Button({
				Text = Strings.BoomboxPlay,
				BackgroundColor3 = Theme.Colors.Buy,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -128, 0.5, 0),
				Size = UDim2.fromOffset(108, 50),
				ZIndex = 24,
				Parent = boombox,
			}, function()
				local id = tonumber(box.Text:match("^%s*(%d+)%s*$"))
				if id and id > 0 then
					Remotes.BoomboxSet:FireServer(id)
				else
					notify(Strings.BoomboxBadId)
				end
			end)
			Widgets.Button({
				Text = Strings.BoomboxStop,
				BackgroundColor3 = Theme.Colors.Drop,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(108, 50),
				ZIndex = 24,
				Parent = boombox,
			}, function()
				Remotes.BoomboxSet:FireServer(0)
			end)
		end
		order += 1
		local tutorial = row(order, Strings.SettingsResetTutorial)
		Widgets.Button({
			Text = Strings.SettingsSoon,
			BackgroundColor3 = Theme.Colors.Locked,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(140, 50),
			ZIndex = 24,
			Parent = tutorial,
		}, function()
			notify(Strings.SettingsSoon)
		end)
	end

	ClientState.ProfileChanged:Connect(function()
		if overlay.Visible then
			render()
		end
	end)

	local screen = {}
	function screen.Open()
		overlay.Visible = true
		render()
		ClientState.Refresh()
	end
	return screen
end
