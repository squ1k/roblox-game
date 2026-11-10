-- Вкладка "Достижения" в рюкзаке: иконка, название, условие, полоска прогресса, награда и
-- кнопка "Забрать" (выдает сервер, AchievementService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Achievements = require(Shared:WaitForChild("Achievements"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local create = Widgets.Create

return function(content: Instance, profile)
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	for order, achievement in Balance.Achievements do
		local value = Achievements.Value(profile, achievement)
		local done = value >= achievement.Goal
		local claimed = profile.Achievements and profile.Achievements[achievement.Id] == "claimed"
		local row = create("Frame", {
			LayoutOrder = order,
			BackgroundColor3 = if claimed then Color3.fromRGB(225, 240, 220) else Color3.new(1, 1, 1),
			Size = UDim2.new(1, -12, 0, 80),
			ZIndex = 23,
			Parent = content,
		}, { Widgets.Corner(), Widgets.Stroke() })
		Widgets.Label({
			Text = achievement.Icon,
			Outline = false,
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromOffset(10, 10),
			ZIndex = 24,
			Parent = row,
		})
		Widgets.Label({
			Text = Strings.AchievementNames[achievement.Id] or achievement.Id,
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.4, 0, 0, 30),
			Position = UDim2.fromOffset(80, 6),
			MaxTextSize = 24,
			ZIndex = 24,
			Parent = row,
		})
		Widgets.Label({
			Text = Strings.AchievementInfo[achievement.Id] or "",
			TextColor3 = Theme.Colors.TextDark,
			Outline = false,
			Font = Theme.FontBody,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.4, 0, 0, 22),
			Position = UDim2.fromOffset(80, 40),
			MaxTextSize = 16,
			ZIndex = 24,
			Parent = row,
		})
		local track = create("Frame", {
			BackgroundColor3 = Color3.fromRGB(220, 210, 200),
			Size = UDim2.new(0.22, 0, 0, 22),
			Position = UDim2.new(0.48, 40, 0.5, -11),
			ZIndex = 24,
			Parent = row,
		}, { Widgets.Corner(UDim.new(1, 0)) })
		create("Frame", {
			BackgroundColor3 = Theme.Colors.Buy,
			Size = UDim2.fromScale(math.clamp(value / achievement.Goal, 0, 1), 1),
			ZIndex = 25,
			Parent = track,
		}, { Widgets.Corner(UDim.new(1, 0)) })
		Widgets.Label({
			Text = NumberFormat.Short(math.min(value, achievement.Goal)) .. " / " .. NumberFormat.Short(
				achievement.Goal
			),
			Size = UDim2.fromScale(1, 1),
			MaxTextSize = 16,
			ZIndex = 26,
			Parent = track,
		})
		local reward = if achievement.Crystals
			then "💎 " .. achievement.Crystals
			else "💰 " .. NumberFormat.Short(achievement.Coins or 0)
		local button = Widgets.Button(
			{
				Text = if claimed then Strings.Claimed else Strings.Claim .. " " .. reward,
				BackgroundColor3 = if done and not claimed then Theme.Colors.Buy else Theme.Colors.Locked,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(190, 54),
				ZIndex = 24,
				Parent = row,
			},
			if done and not claimed
				then function()
					Remotes.AchievementClaim:FireServer(achievement.Id)
				end
				else nil
		)
		button.Active = done and not claimed
	end
end
