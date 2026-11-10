-- Центр справа: большая красная кнопка "БРОСИТЬ". Видна только с Кейк-попсом в руках.
-- На ПК то же самое делает клавиша Q.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Strings = require(Shared:WaitForChild("Config"):WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local create = Widgets.Create

local player = Players.LocalPlayer
local ACTION = "DropCakePop"

return function(parent: Instance)
	local function drop()
		Remotes.DropPop:FireServer()
	end

	local button = Widgets.Button({
		Name = "Drop",
		Text = Strings.Drop,
		BackgroundColor3 = Theme.Colors.Drop,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.45, 0),
		Size = UDim2.fromOffset(150, 150),
		CornerRadius = UDim.new(1, 0),
		Visible = false,
		Parent = parent,
	}, drop)
	local keyHint = Widgets.Label({
		Name = "Key",
		Text = "Q",
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0.5, -17, 1, -10),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.PanelDark,
		MaxTextSize = 24,
		Parent = button,
	})
	Widgets.Corner(UDim.new(1, 0)).Parent = keyHint
	local carryHint = Widgets.Label({
		Name = "CarryHint",
		Text = Strings.PopCarrying,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.fromOffset(220, 26),
		MaxTextSize = 20,
		Parent = button,
	})
	carryHint.Visible = true
	local scale = button:FindFirstChildOfClass("UIScale") or create("UIScale", { Parent = button })

	local function refresh()
		local carrying = player:GetAttribute("Carrying") == true
		keyHint.Visible = UserInputService.KeyboardEnabled
		if carrying and not button.Visible then
			button.Visible = true
			scale.Scale = 0.3
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			ContextActionService:BindAction(ACTION, function(_, state)
				if state == Enum.UserInputState.Begin then
					drop()
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)
		elseif not carrying and button.Visible then
			button.Visible = false
			ContextActionService:UnbindAction(ACTION)
		end
	end

	player:GetAttributeChangedSignal("Carrying"):Connect(refresh)
	refresh()
	return button
end
