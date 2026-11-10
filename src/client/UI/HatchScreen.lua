-- Экран вылупления: большой куб цвета редкости, Семейство, редкость и мутация, конфетти.
-- Если вылупление открыло Патрона, добавляется строка и окно трясется.

local TweenService = game:GetService("TweenService")
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

local CONFETTI = 40
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(90, 210, 90),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(190, 110, 255),
}

return function(parent: Instance)
	local overlay = create("TextButton", {
		Name = "HatchScreen",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 50,
		Parent = parent,
	})
	local window = create("Frame", {
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 470),
		BackgroundColor3 = Theme.Colors.Panel,
		ZIndex = 51,
		Parent = overlay,
	}, { Widgets.Corner(UDim.new(0, 24)), Widgets.Stroke(4), create("UIScale") })
	local title = Widgets.Label({
		Text = Strings.HatchTitle,
		TextColor3 = Theme.Colors.TextDark,
		Outline = false,
		Size = UDim2.new(1, -24, 0, 48),
		Position = UDim2.fromOffset(12, 12),
		MaxTextSize = 36,
		ZIndex = 52,
		Parent = window,
	})
	local cube = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.fromOffset(150, 150),
		ZIndex = 52,
		Parent = window,
	}, { Widgets.Corner(UDim.new(0, 18)), Widgets.Stroke(4) })
	local name = Widgets.Label({
		TextColor3 = Theme.Colors.TextDark,
		Outline = false,
		Size = UDim2.new(1, -24, 0, 40),
		Position = UDim2.fromOffset(12, 236),
		MaxTextSize = 32,
		ZIndex = 52,
		Parent = window,
	})
	local rarityLabel = Widgets.Label({
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.fromOffset(12, 278),
		MaxTextSize = 28,
		ZIndex = 52,
		Parent = window,
	})
	local patronLabel = Widgets.Label({
		TextColor3 = Theme.Colors.Coin,
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.fromOffset(12, 318),
		MaxTextSize = 24,
		ZIndex = 52,
		Parent = window,
	})
	local scale = window:FindFirstChildOfClass("UIScale")

	local function close()
		overlay.Visible = false
	end
	Widgets.Button({
		Text = Strings.HatchOk,
		BackgroundColor3 = Theme.Colors.Buy,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(220, 70),
		ZIndex = 53,
		Parent = window,
	}, close)
	overlay.Activated:Connect(close)

	local function confetti()
		for _ = 1, CONFETTI do
			local piece = create("Frame", {
				BackgroundColor3 = CONFETTI_COLORS[math.random(#CONFETTI_COLORS)],
				Size = UDim2.fromOffset(math.random(8, 16), math.random(12, 22)),
				Position = UDim2.new(math.random(), 0, 0, -30),
				Rotation = math.random(0, 360),
				ZIndex = 54,
				Parent = overlay,
			})
			local info = TweenInfo.new(math.random(16, 28) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(piece, info, {
				Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.3, 0, 1.05, 0),
				Rotation = piece.Rotation + math.random(-360, 360),
			}):Play()
			task.delay(info.Time, function()
				piece:Destroy()
			end)
		end
	end

	local function shake()
		local origin = window.Position
		for i = 1, 8 do
			window.Position = origin + UDim2.fromOffset(math.random(-12, 12), math.random(-8, 8))
			task.wait(0.04)
		end
		window.Position = origin
	end

	Remotes.PetHatched.OnClientEvent:Connect(function(petId: string, mutationId: string?, readyFamilyId: string?)
		local skebob = Families.SkebobById[petId]
		local rarity = skebob and Balance.RarityById[skebob.Rarity] or Balance.Rarities[1]
		local family = skebob and Families.ById[skebob.Family]
		local mutation = mutationId and Balance.MutationById[mutationId]
		cube.BackgroundColor3 = rarity.Glaze
		name.Text = (if family then family.Name .. " · " else "") .. petId
		rarityLabel.Text = (if mutation then mutation.Name .. " · " else "") .. rarity.Name
		rarityLabel.TextColor3 = rarity.Glaze
		local readyFamily = readyFamilyId and Families.ById[readyFamilyId]
		patronLabel.Text = if readyFamily then string.format(Strings.PatronReady, readyFamily.Name) else ""
		title.Text = Strings.HatchTitle
		overlay.Visible = true
		scale.Scale = 0.4
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		confetti()
		local settings = ClientState.Profile and ClientState.Profile.Settings
		if readyFamily and (not settings or settings.ScreenShake ~= false) then
			task.delay(0.35, shake)
		end
	end)
end
