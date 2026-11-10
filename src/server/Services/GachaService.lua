-- Содержимое автомата: физические капсулы (Кейк-попсы), ресток раз в RestockSeconds,
-- дыра для выигрыша и выдача попса победителю (редкость + Pity, Семейство случайно).
-- Модель художника в режиме редактирования не меняется: все переделки только при запуске.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local CakePopService = require(script.Parent:WaitForChild("CakePopService"))

local Claw = Balance.Claw
local Gacha = Balance.Gacha

local GachaService = {}

local collectedEvent = Instance.new("BindableEvent")
GachaService.Collected = collectedEvent.Event -- (rarityId, mutationId?, familyId) капсула упала в дыру
local beforeRestockEvent = Instance.new("BindableEvent")
GachaService.BeforeRestock = beforeRestockEvent.Event -- перед спавном новых капсул (погода решает ивент)
local restockedEvent = Instance.new("BindableEvent")
GachaService.Restocked = restockedEvent.Event -- автомат обновил ассортимент (капканы исчезают)

local machine
local capsulesFolder
local template
local bedCenter -- центр верха ложа
local holeCenter
local random = Random.new()

function GachaService.Machine()
	return machine
end

function GachaService.BedCenter(): Vector3
	return bedCenter
end

function GachaService.HoleCenter(): Vector3
	return holeCenter
end

-- Оси автомата: U вдоль неподвижных рельсов, V поперек (к лотку Delivery_South)
function GachaService.Axes(): (Vector3, Vector3)
	local yaw = CFrame.Angles(0, math.rad(45), 0)
	return yaw.RightVector, -yaw.LookVector
end

local function rollRarity()
	local total = 0
	for _, rarity in Balance.Rarities do
		total += rarity.Chance
	end
	local roll = random:NextNumber(0, total)
	for _, rarity in Balance.Rarities do
		roll -= rarity.Chance
		if roll <= 0 then
			return rarity
		end
	end
	return Balance.Rarities[1]
end

-- Капсула из шаблона художника: невидимый шар-коллайдер + приваренные детали.
-- Семейство решается сразу (его видно с X-Ray), мутация есть только у капсул погодного ивента.
local function makeCapsule(rarity, position: Vector3, mutationId: string?, eventId: string?): Model
	local capsule = template:Clone()
	local collider = Instance.new("Part")
	collider.Name = "Collider"
	collider.Shape = Enum.PartType.Ball
	collider.Size = Vector3.one * Claw.CapsuleDiameter
	collider.Transparency = 1
	collider.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.6, 0.15)
	collider.CFrame = CFrame.new(capsule:GetBoundingBox().Position)
	collider.Parent = capsule
	for _, part in capsule:GetDescendants() do
		if part:IsA("BasePart") and part ~= collider then
			part.CanCollide = false
			part.CanQuery = false
			part.Massless = true
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = collider
			weld.Part1 = part
			weld.Parent = collider
			if part.Name == "ColoredTop" then
				part.Color = rarity.Glaze
			end
		end
	end
	capsule.PrimaryPart = collider
	capsule:SetAttribute("Rarity", rarity.Id)
	local family = Families.List[random:NextInteger(1, #Families.List)]
	capsule:SetAttribute("Family", family.Id)
	-- Подпись Семейства: включает только клиент владельца X-Ray Визора
	local xray = Instance.new("BillboardGui")
	xray.Name = "XRay"
	xray.Size = UDim2.fromOffset(110, 26)
	xray.StudsOffset = Vector3.new(0, Claw.CapsuleDiameter / 2 + 0.8, 0)
	xray.MaxDistance = 60
	xray.Enabled = false
	xray.Parent = collider
	local xrayLabel = Instance.new("TextLabel")
	xrayLabel.BackgroundTransparency = 1
	xrayLabel.Size = UDim2.fromScale(1, 1)
	xrayLabel.Font = Enum.Font.FredokaOne
	xrayLabel.TextScaled = true
	xrayLabel.TextColor3 = family.Color
	xrayLabel.TextStrokeTransparency = 0
	xrayLabel.Text = family.Name
	xrayLabel.Parent = xray
	if mutationId then
		capsule:SetAttribute("Mutation", mutationId)
		local event = eventId and Balance.Weather.Events[eventId]
		local color = if event then event.Color else Color3.new(1, 1, 1)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 6
		light.Brightness = 2
		light.Parent = collider
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = color
		sparkles.Parent = collider
	end
	local spin = CFrame.Angles(random:NextNumber(0, 6.28), random:NextNumber(0, 6.28), random:NextNumber(0, 6.28))
	capsule:PivotTo(CFrame.new(position) * spin)
	capsule.Parent = capsulesFolder
	collider:SetNetworkOwner(nil)
	return capsule
end

function GachaService.CapsuleOf(part: Instance): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model.Parent == capsulesFolder then
		return model
	end
	return nil
end

-- Мутация текущего погодного ивента (workspace.WeatherEvent ставит WeatherService)
local function eventMutation(): (string?, string?)
	local eventId = workspace:GetAttribute("WeatherEvent")
	if not eventId then
		return nil, nil
	end
	for _, mutation in Balance.WeatherMutations do
		if mutation.Event == eventId then
			return mutation.Id, eventId
		end
	end
	return nil, eventId
end

function GachaService.Restock()
	beforeRestockEvent:Fire()
	local mutationId, eventId = eventMutation()
	local mutatedCount = if mutationId then math.floor(Gacha.Capacity * Balance.Weather.MutatedPopShare) else 0
	for _, capsule in capsulesFolder:GetChildren() do
		if not capsule:GetAttribute("Grabbed") then
			capsule:Destroy()
		end
	end
	local u, v = GachaService.Axes()
	task.spawn(function()
		for i = 1, Gacha.Capacity do
			local position
			repeat
				local angle = random:NextNumber(0, math.pi * 2)
				local radius = math.sqrt(random:NextNumber()) * Claw.SpawnRadius
				position = bedCenter + u * math.cos(angle) * radius + v * math.sin(angle) * radius
			until (Vector3.new(position.X, 0, position.Z) - Vector3.new(holeCenter.X, 0, holeCenter.Z)).Magnitude
				> Claw.SpawnHoleClearance
			local mutation = if i <= mutatedCount then mutationId else nil
			makeCapsule(
				rollRarity(),
				position + Vector3.new(0, Claw.SpawnDropHeight + (i % 5) * 0.8, 0),
				mutation,
				eventId
			)
			task.wait(0.05)
		end
	end)
	workspace:SetAttribute("GachaRestockAt", workspace:GetServerTimeNow() + Gacha.RestockSeconds)
	restockedEvent:Fire()
end

-- Попс для победителя: редкость капсулы, поднятая Pity, если пора; Семейство и мутация капсулы.
-- Попс появляется в лотке у пульта stationName, донести до Холодильника нужно руками.
function GachaService.Award(
	player: Player,
	rarityId: string,
	stationName: string?,
	mutationId: string?,
	familyId: string?
)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local rarity = Balance.RarityById[rarityId] or Balance.Rarities[1]
	for index = #Balance.Rarities, rarity.Order + 1, -1 do
		local candidate = Balance.Rarities[index]
		if candidate.Pity and (data.Pity[candidate.Id] or 0) + 1 >= candidate.Pity then
			rarity = candidate
			break
		end
	end
	for _, candidate in Balance.Rarities do
		if candidate.Pity then
			data.Pity[candidate.Id] = if rarity.Order >= candidate.Order then 0 else (data.Pity[candidate.Id] or 0) + 1
		end
	end
	local family = Families.ById[familyId or ""] or Families.List[random:NextInteger(1, #Families.List)]
	local skebob = family.Members[rarity.Order]
	data.Stats.Grabs += 1
	CakePopService.SpawnInTray(player, { Id = skebob.Id, Mutation = mutationId }, stationName)
	Remotes.Notify:FireClient(player, string.format(Strings.ClawWin, rarity.Name))
	EconomyService.Refresh(player)
end

local function buildContainer(bed: BasePart, folder: Folder)
	local u, v = GachaService.Axes()
	local segments = Claw.ContainerSegments
	local radius = Claw.ContainerRadius
	local width = 2 * math.pi * radius / segments + 0.4
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local direction = u * math.cos(angle) + v * math.sin(angle)
		local wall = Instance.new("Part")
		wall.Name = "ContainerWall"
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.Size = Vector3.new(width, Claw.ContainerHeight, 1)
		local center = bedCenter + direction * (radius + 0.5) + Vector3.new(0, Claw.ContainerHeight / 2, 0)
		wall.CFrame = CFrame.lookAt(center, center + direction)
		wall.Parent = folder
	end

	-- Дыра: квадратная труба с неоновым кантом и датчиком внутри
	local inner = Claw.HoleInner
	local height = Claw.HoleWallHeight
	local look = CFrame.lookAt(holeCenter, holeCenter + v)
	for side = 0, 3 do
		local wall = Instance.new("Part")
		wall.Name = "HoleWall"
		wall.Anchored = true
		wall.Material = Enum.Material.Glass
		wall.Transparency = 0.4
		wall.Color = Color3.fromRGB(40, 60, 80)
		wall.Size = Vector3.new(inner + 0.6, height, 0.3)
		local offset = CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, height / 2, -(inner / 2 + 0.15))
		wall.CFrame = look * offset
		wall.Parent = folder
		local rim = Instance.new("Part")
		rim.Name = "HoleRim"
		rim.Anchored = true
		rim.CanCollide = false
		rim.CanQuery = false
		rim.Material = Enum.Material.Neon
		rim.Color = Color3.fromRGB(255, 210, 60)
		rim.Size = Vector3.new(inner + 0.7, 0.2, 0.4)
		rim.CFrame = look * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, height + 0.1, -(inner / 2 + 0.15))
		rim.Parent = folder
	end
	local floor = Instance.new("Part")
	floor.Name = "HoleFloor"
	floor.Anchored = true
	floor.Material = Enum.Material.Neon
	floor.Color = Color3.fromRGB(20, 20, 30)
	floor.Size = Vector3.new(inner, 0.2, inner)
	floor.CFrame = look * CFrame.new(0, 0.1, 0)
	floor.Parent = folder
end

local function watchHole()
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { capsulesFolder }
	local size = Vector3.new(Claw.HoleInner - 0.2, Claw.HoleWallHeight, Claw.HoleInner - 0.2)
	local _, v = GachaService.Axes()
	local box = CFrame.lookAt(holeCenter, holeCenter + v) * CFrame.new(0, Claw.HoleWallHeight / 2, 0)
	while true do
		task.wait(0.1)
		local seen = {}
		for _, part in workspace:GetPartBoundsInBox(box, size, params) do
			local capsule = GachaService.CapsuleOf(part)
			-- GetPartBoundsInBox грубый (габариты), поэтому проверяем, что центр капсулы внутри трубы
			local inside = false
			if capsule and capsule.PrimaryPart then
				local localPos = box:PointToObjectSpace(capsule.PrimaryPart.Position)
				inside = math.abs(localPos.X) < size.X / 2
					and math.abs(localPos.Z) < size.Z / 2
					and math.abs(localPos.Y) < size.Y / 2 + 0.5
			end
			if inside and not seen[capsule] and not capsule:GetAttribute("Grabbed") then
				seen[capsule] = true
				local rarityId = capsule:GetAttribute("Rarity")
				local mutationId = capsule:GetAttribute("Mutation")
				local familyId = capsule:GetAttribute("Family")
				capsule:Destroy()
				collectedEvent:Fire(rarityId, mutationId, familyId)
			end
		end
	end
end

function GachaService.Start()
	local field = workspace:WaitForChild(Balance.Map.FieldModel)
	machine = field:WaitForChild("CenterZone"):WaitForChild("CapsuleClawMachine")
	capsulesFolder = machine:WaitForChild("06_Capsules")
	local bed = machine:WaitForChild("01_BaseAndDelivery"):WaitForChild("CapsuleBed")
	-- Ложе: цилиндр, повернутый осью вверх, его высота = Size.X
	bedCenter = bed.Position + Vector3.new(0, bed.Size.X / 2, 0)
	local _, v = GachaService.Axes()
	holeCenter = bedCenter + v * Claw.HoleOffset

	local first = capsulesFolder:FindFirstChildWhichIsA("Model")
	template = first:Clone()
	for _, part in template:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	capsulesFolder:ClearAllChildren()

	local runtime = workspace:WaitForChild(Balance.Map.RuntimeFolder)
	local folder = runtime:FindFirstChild("ClawMachine") or Instance.new("Folder")
	folder.Name = "ClawMachine"
	folder:ClearAllChildren()
	folder.Parent = runtime
	buildContainer(bed, folder)

	GachaService.Restock()
	task.spawn(function()
		while true do
			task.wait(Gacha.RestockSeconds)
			GachaService.Restock()
		end
	end)
	task.spawn(watchHole)
end

return GachaService
