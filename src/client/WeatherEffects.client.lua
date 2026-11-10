-- Погода на клиенте: по workspace.WeatherEvent меняет Lighting (исходные значения запоминаются и
-- возвращаются), включает дождь / звезды / неон мельницы и показывает баннер ивента с таймером.
-- Заодно X-Ray: у владельца геймпасса над капсулами в автомате видно Семейство.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))

local UI = script.Parent:WaitForChild("UI")
local Widgets = require(UI:WaitForChild("Widgets"))
local create = Widgets.Create

local player = Players.LocalPlayer
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local original = {
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	FogColor = Lighting.FogColor,
	FogEnd = Lighting.FogEnd,
	ClockTime = Lighting.ClockTime,
	Haze = atmosphere and atmosphere.Haze,
	AtmosphereColor = atmosphere and atmosphere.Color,
}

local extras = {} -- временные объекты ивента (дождь, искры, подсветка)

local function millCenter(): Vector3?
	local field = workspace:FindFirstChild(Balance.Map.FieldModel)
	local pivot = field and field:FindFirstChild(Balance.Map.IslandPivot)
	return pivot and pivot.Position
end

local function clearExtras()
	for _, instance in extras do
		instance:Destroy()
	end
	table.clear(extras)
end

local function restore()
	Lighting.Ambient = original.Ambient
	Lighting.OutdoorAmbient = original.OutdoorAmbient
	Lighting.FogColor = original.FogColor
	Lighting.FogEnd = original.FogEnd
	Lighting.ClockTime = original.ClockTime
	if atmosphere then
		atmosphere.Haze = original.Haze
		atmosphere.Color = original.AtmosphereColor
	end
	clearExtras()
end

-- Невидимая плита над мельницей, из которой идет дождь или сыплются искры
local function skyEmitter(kind: string, color: Color3)
	local center = millCenter()
	if not center then
		return
	end
	local part = Instance.new("Part")
	part.Name = "WeatherSky"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(160, 1, 160)
	part.Position = center + Vector3.new(0, 70, 0)
	part.Parent = workspace
	if kind == "Rain" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(170, 200, 230))
		emitter.Size = NumberSequence.new(0.15)
		emitter.Rate = 400
		emitter.Lifetime = NumberRange.new(1.5, 2)
		emitter.Speed = NumberRange.new(60, 70)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Parent = part
	else
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.LightEmission = 1
		sparkles.Color = ColorSequence.new(color)
		sparkles.Size = NumberSequence.new(0.6)
		sparkles.Rate = 40
		sparkles.Lifetime = NumberRange.new(3, 4)
		sparkles.Speed = NumberRange.new(20, 25)
		sparkles.EmissionDirection = Enum.NormalId.Bottom
		sparkles.Parent = part
	end
	table.insert(extras, part)
end

local function apply(eventId: string?)
	restore()
	local event = eventId and Balance.Weather.Events[eventId]
	if not event then
		return
	end
	if event.Ambient then
		Lighting.Ambient = event.Ambient
		Lighting.OutdoorAmbient = event.Ambient
	end
	if event.FogColor then
		Lighting.FogColor = event.FogColor
		Lighting.FogEnd = event.FogEnd or Lighting.FogEnd
	end
	if event.ClockTime then
		Lighting.ClockTime = event.ClockTime
	end
	if atmosphere and event.Haze then
		atmosphere.Haze = event.Haze
		atmosphere.Color = event.FogColor or event.Color
	end
	if event.Rain then
		skyEmitter("Rain", event.Color)
	end
	if event.Sparkles then
		skyEmitter("Sparkles", event.Color)
	end
	if event.MillGlow then
		local field = workspace:FindFirstChild(Balance.Map.FieldModel)
		local zone = field and field:FindFirstChild("CenterZone")
		local machine = zone and zone:FindFirstChild("CapsuleClawMachine")
		if machine then
			local highlight = Instance.new("Highlight")
			highlight.FillTransparency = 0.85
			highlight.FillColor = event.Color
			highlight.OutlineColor = event.Color
			highlight.Adornee = machine
			highlight.Parent = player:WaitForChild("PlayerGui")
			table.insert(extras, highlight)
		end
	end
end

-- Баннер ивента под панелью валют сверху по центру
local gui = create("ScreenGui", {
	Name = "WeatherBanner",
	ResetOnSpawn = false,
	DisplayOrder = 4,
	Parent = player:WaitForChild("PlayerGui"),
})
local banner = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.fromOffset(420, 40),
	BackgroundColor3 = Color3.fromRGB(40, 30, 50),
	BackgroundTransparency = 0.15,
	Visible = false,
	Parent = gui,
}, { Widgets.Corner(UDim.new(1, 0)), Widgets.Stroke() })
local bannerText = Widgets.Label({
	Size = UDim2.new(1, -20, 1, -8),
	Position = UDim2.fromOffset(10, 4),
	MaxTextSize = 22,
	Parent = banner,
})

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

RunService.Heartbeat:Connect(function()
	local eventId = workspace:GetAttribute("WeatherEvent")
	local event = eventId and Balance.Weather.Events[eventId]
	banner.Visible = event ~= nil
	if event then
		local left = (workspace:GetAttribute("WeatherEndsAt") or 0) - workspace:GetServerTimeNow()
		bannerText.Text =
			string.format(Strings.WeatherBanner, Strings.WeatherNames[eventId] or eventId, formatTime(left))
		bannerText.TextColor3 = event.Color
	end
end)

workspace:GetAttributeChangedSignal("WeatherEvent"):Connect(function()
	apply(workspace:GetAttribute("WeatherEvent"))
end)
apply(workspace:GetAttribute("WeatherEvent"))

-- X-Ray: подписи Семейства у капсул (BillboardGui "XRay" создает сервер выключенным)
local function setXRay(billboard: Instance)
	if billboard:IsA("BillboardGui") and billboard.Name == "XRay" then
		billboard.Enabled = player:GetAttribute("XRay") == true
	end
end
task.spawn(function()
	local field = workspace:WaitForChild(Balance.Map.FieldModel)
	local machine = field:WaitForChild("CenterZone"):WaitForChild("CapsuleClawMachine")
	local capsules = machine:WaitForChild("06_Capsules")
	capsules.DescendantAdded:Connect(setXRay)
	for _, d in capsules:GetDescendants() do
		setXRay(d)
	end
	player:GetAttributeChangedSignal("XRay"):Connect(function()
		for _, d in capsules:GetDescendants() do
			setXRay(d)
		end
	end)
end)
