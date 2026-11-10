-- Управление клешней на клиенте: камера сбоку колбы, направление из джойстика/WASD
-- (Humanoid.MoveDirection работает на всех платформах), "хватать" = прыжок или большая кнопка.
-- Сервер сам решает все остальное, клиент только шлет ClawInput.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UI = script.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Widgets = require(UI:WaitForChild("Widgets"))
local create = Widgets.Create

local Claw = Balance.Claw
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local yaw = CFrame.Angles(0, math.rad(45), 0)
local AXIS_U = yaw.RightVector
local AXIS_V = -yaw.LookVector

local gui = create("ScreenGui", {
	Name = "ClawHUD",
	ResetOnSpawn = false,
	Enabled = false,
	DisplayOrder = 10,
	Parent = player:WaitForChild("PlayerGui"),
})
local timerLabel = Widgets.Label({
	Name = "Timer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(160, 60),
	Text = "10",
	TextColor3 = Theme.Colors.Coin,
	Parent = gui,
})
Widgets.Label({
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 132),
	Size = UDim2.fromOffset(520, 28),
	Text = Strings.ClawHint,
	MaxTextSize = 22,
	Parent = gui,
})
local grabButton = Widgets.Button({
	Name = "Grab",
	Text = Strings.ClawGrab,
	BackgroundColor3 = Theme.Colors.Drop,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -30, 1, -40),
	Size = UDim2.fromOffset(170, 170),
	CornerRadius = UDim.new(1, 0),
	Parent = gui,
}, function()
	Remotes.ClawInput:FireServer("drop")
end)
grabButton.Visible = true

local active = false
local lastSent = Vector2.zero
local lastSendTime = 0
local connections = {}

local function machineModel(): Instance?
	local field = workspace:FindFirstChild(Balance.Map.FieldModel)
	local zone = field and field:FindFirstChild("CenterZone")
	return zone and zone:FindFirstChild("CapsuleClawMachine")
end

local function machineCenter(): Vector3?
	local field = workspace:FindFirstChild(Balance.Map.FieldModel)
	local machine = machineModel()
	local bed = machine and machine:FindFirstChild("CapsuleBed", true)
	if bed then
		return bed.Position + Vector3.new(0, bed.Size.X / 2, 0)
	end
	local pivot = field and field:FindFirstChild(Balance.Map.IslandPivot)
	return pivot and pivot.Position + Vector3.new(0, 11, 0)
end

local function placeCamera()
	local center = machineCenter()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not center or not root then
		return
	end
	local outward = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
	outward = if outward.Magnitude > 0.1 then outward.Unit else Vector3.new(0, 0, 1)
	local look = center + Vector3.new(0, Claw.CameraLookHeight, 0)
	local eye = center + outward * Claw.CameraDistance + Vector3.new(0, Claw.CameraHeight, 0)
	-- Если между автоматом и камерой стена мельницы, подъезжаем ближе
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- невидимые стенки контейнера и дыры лежат в Skebobs_Runtime, их тоже пропускаем
	params.FilterDescendantsInstances =
		{ player.Character, machineModel(), workspace:FindFirstChild(Balance.Map.RuntimeFolder) }
	local hit = workspace:Raycast(look, eye - look, params)
	if hit then
		eye = look + (eye - look).Unit * math.max(4, hit.Distance - 1.5)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(eye, look)
end

local function send(input: Vector2)
	local t = os.clock()
	if (input - lastSent).Magnitude < 0.05 and t - lastSendTime < 0.5 then
		return
	end
	if t - lastSendTime < 1 / Claw.InputRate then
		return
	end
	lastSent = input
	lastSendTime = t
	Remotes.ClawInput:FireServer("move", input.X, input.Y)
end

local function stop()
	active = false
	gui.Enabled = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function start()
	if active then
		return
	end
	active = true
	gui.Enabled = true
	lastSent = Vector2.zero
	placeCamera()
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function()
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local phase = player:GetAttribute("ClawPhase")
			local aiming = phase == "Aiming"
			grabButton.Visible = aiming
			local left = math.max(0, (player:GetAttribute("ClawEndsAt") or 0) - workspace:GetServerTimeNow())
			timerLabel.Text = if aiming then tostring(math.ceil(left)) else ""
			if aiming and humanoid then
				local direction = humanoid.MoveDirection
				send(Vector2.new(direction:Dot(AXIS_U), direction:Dot(AXIS_V)))
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.JumpRequest:Connect(function()
			if player:GetAttribute("ClawPhase") == "Aiming" then
				Remotes.ClawInput:FireServer("drop")
			end
		end)
	)
end

player:GetAttributeChangedSignal("ClawActive"):Connect(function()
	if player:GetAttribute("ClawActive") then
		start()
	else
		stop()
	end
end)
