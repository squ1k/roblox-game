-- Эффекты мира на клиенте: Патроны парят и вращаются, над своими занятыми пьедесталами раз в
-- IncomePopupSeconds всплывает "+N/сек" этого Скебобса (если включено в настройках), над своим
-- персонажем на АФК-лежаке плывут "Zzz". Громкость групп звуков берется из настроек.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local Strings = require(Shared:WaitForChild("Config"):WaitForChild("Strings"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))

local Effects = Balance.WorldEffects
local player = Players.LocalPlayer
local runtime = workspace:WaitForChild(Balance.Map.RuntimeFolder)

-- Патроны: исходная позиция запоминается, дальше только локальное смещение
local patrons = {} -- [part] = { Base = CFrame, Phase = number }
local function track(part: Instance)
	if part:IsA("BasePart") and part:GetAttribute("Patron") then
		patrons[part] = { Base = part.CFrame, Phase = math.random() * math.pi * 2 }
		part.Destroying:Connect(function()
			patrons[part] = nil
		end)
	end
end
runtime.DescendantAdded:Connect(track)
for _, d in runtime:GetDescendants() do
	track(d)
end
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for part, info in patrons do
		local bob = math.sin(t * Effects.PatronBobSpeed + info.Phase) * Effects.PatronBobHeight
		part.CFrame = info.Base * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * Effects.PatronSpinSpeed, 0)
	end
end)

local function floatText(adornee: BasePart, text: string, color: Color3, offset: Vector3)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 36)
	billboard.StudsOffsetWorldSpace = offset
	billboard.MaxDistance = 80
	billboard.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = billboard
	billboard.Parent = player:WaitForChild("PlayerGui")
	local info = TweenInfo.new(Effects.FloatSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, { StudsOffsetWorldSpace = offset + Vector3.new(0, Effects.FloatRise, 0) })
		:Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(Effects.FloatSeconds, function()
		billboard:Destroy()
	end)
end

-- "+N" над своими Скебобсами: доход куба берем из его таблички "+X/сек"
task.spawn(function()
	while true do
		task.wait(Effects.IncomePopupSeconds)
		local folder = runtime:FindFirstChild("PetDisplays")
		local mine = folder and folder:FindFirstChild("Player_" .. player.UserId)
		local settings = ClientState.Profile and ClientState.Profile.Settings
		if mine and (not settings or settings.IncomePopups ~= false) then
			for _, cube in mine:GetChildren() do
				local label = cube:FindFirstChild("Label")
				local income = label and label:FindFirstChild("Income")
				if cube:IsA("BasePart") and income and income.Text ~= "" then
					-- табличка "+2.5/сек" -> всплывает "+2.5"
					local shown = income.Text:gsub(Strings.PerSecondShort, "")
					floatText(cube, shown, Color3.fromRGB(255, 210, 60), Vector3.new(0, cube.Size.Y / 2 + 3, 0))
				end
			end
		end
	end
end)

-- "Zzz" над собой, пока лежишь на своем лежаке
task.spawn(function()
	while true do
		task.wait(Effects.ZzzSeconds)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and player:GetAttribute("AFK") then
			floatText(root, "Zzz", Color3.fromRGB(200, 190, 255), Vector3.new(math.random(-10, 10) / 10, 3, 0))
		end
	end
end)

-- Громкость по настройкам: все будущие звуки игры кладем в эти группы (SoundService)
local SoundService = game:GetService("SoundService")
local function group(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new("SoundGroup")
	created.Name = name
	created.Parent = SoundService
	return created
end
local musicGroup = group("Music")
local soundsGroup = group("Sounds")
local function applyVolume()
	local settings = ClientState.Profile and ClientState.Profile.Settings
	musicGroup.Volume = settings and settings.Music or Balance.DefaultSettings.Music
	soundsGroup.Volume = settings and settings.Sounds or Balance.DefaultSettings.Sounds
end
ClientState.ProfileChanged:Connect(applyVolume)
applyVolume()
