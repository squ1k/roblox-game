-- Верхний правый угол: прогресс до Спящего попса. Виден только на АФК-лежаке.
-- Плюс мягкое пульсирующее свечение экрана, как в диздоке.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local Strings = require(Shared:WaitForChild("Config"):WaitForChild("Strings"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local create = Widgets.Create

local player = Players.LocalPlayer

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

return function(parent: Instance, glowParent: Instance)
	local panel = create("Frame", {
		Name = "AfkBar",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(280, 64),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = parent,
	}, { Widgets.Corner(), Widgets.Stroke() })

	local title = Widgets.Label({
		Text = "💤 " .. Strings.AfkTitle,
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.fromOffset(8, 4),
		MaxTextSize = 20,
		Parent = panel,
	})
	local track = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(30, 20, 40),
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 34),
		Parent = panel,
	}, { Widgets.Corner(UDim.new(1, 0)) })
	local fill = create("Frame", {
		BackgroundColor3 = Theme.Colors.Afk,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	}, { Widgets.Corner(UDim.new(1, 0)) })
	local timeLabel = Widgets.Label({
		Text = "",
		Size = UDim2.fromScale(1, 1),
		MaxTextSize = 16,
		ZIndex = 2,
		Parent = track,
	})

	local glow = create("Frame", {
		Name = "AfkGlow",
		BackgroundColor3 = Theme.Colors.Afk,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 0,
		Parent = glowParent,
	})

	local connection
	local function refresh()
		local afk = player:GetAttribute("AFK") == true
		panel.Visible = afk
		glow.Visible = afk
		if afk and not connection then
			connection = RunService.Heartbeat:Connect(function()
				local since = player:GetAttribute("AfkSince") or workspace:GetServerTimeNow()
				local period = if player:GetAttribute("VIP")
					then Balance.Afk.SleepingPopSecondsVip
					else Balance.Afk.SleepingPopSeconds
				local elapsed = (workspace:GetServerTimeNow() - since) % period
				fill.Size = UDim2.fromScale(elapsed / period, 1)
				timeLabel.Text = formatTime(period - elapsed)
				glow.BackgroundTransparency = 0.93 + 0.04 * math.sin(os.clock() * 1.5)
			end)
		elseif not afk and connection then
			connection:Disconnect()
			connection = nil
		end
	end

	player:GetAttributeChangedSignal("AFK"):Connect(refresh)
	refresh()
	return panel, title
end
