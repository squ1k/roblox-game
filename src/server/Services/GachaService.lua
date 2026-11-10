-- Содержимое автомата: физические капсулы (Кейк-попсы), ресток раз в RestockSeconds,
-- четыре дыры для выигрыша (по одной на пульт, над шахтой своего лотка Delivery_X)
-- и выдача попса победителю (редкость + Pity, Семейство случайно).
-- Модель художника в режиме редактирования не меняется: все переделки только при запуске.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
GachaService.Collected = collectedEvent.Event -- (rarityId, mutationId?, familyId, holeStation, lastClaw?) капсула упала в дыру
local beforeRestockEvent = Instance.new("BindableEvent")
GachaService.BeforeRestock = beforeRestockEvent.Event -- перед спавном новых капсул (погода решает ивент)
local restockedEvent = Instance.new("BindableEvent")
GachaService.Restocked = restockedEvent.Event -- автомат обновил ассортимент (капканы исчезают)

local machine
local capsulesFolder
local template
local bedCenter -- центр верха ложа
local holes = {} -- [stationName] = { Station, Center, Direction }
local random = Random.new()

function GachaService.Machine()
	return machine
end

function GachaService.BedCenter(): Vector3
	return bedCenter
end

-- Центр дыры пульта stationName (Station_East и т.д.)
function GachaService.HoleCenter(stationName: string): Vector3?
	local hole = holes[stationName]
	return hole and hole.Center
end

function GachaService.Holes()
	return holes
end

local function nearHole(position: Vector3, clearance: number): boolean
	for _, hole in holes do
		if
			(Vector3.new(position.X, 0, position.Z) - Vector3.new(hole.Center.X, 0, hole.Center.Z)).Magnitude
			< clearance
		then
			return true
		end
	end
	return false
end

-- Оси автомата: U вдоль неподвижных рельсов, V поперек
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
			until not nearHole(position, Claw.SpawnHoleClearance)
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

local HOLE_COLOR = Color3.fromRGB(24, 30, 44) -- темный дымчатый графит
local HOLE_TRANSPARENCY = 0.35

local function buildContainer(bed: BasePart, folder: Folder)
	-- Квадратное ложе: невидимые стенки по его краям, стороны идут по осям мира
	local half = bed.Size.Y / 2
	for _, direction in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local wall = Instance.new("Part")
		wall.Name = "ContainerWall"
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.Size = Vector3.new(2 * half + 2, Claw.ContainerHeight, 1)
		local center = bedCenter + direction * (half + 0.5) + Vector3.new(0, Claw.ContainerHeight / 2, 0)
		wall.CFrame = CFrame.lookAt(center, center + direction)
		wall.Parent = folder
	end

	-- Дыры: квадратные трубы в углах ложа с неоновым кантом и датчиком внутри, по одной на пульт
	local inner = Claw.HoleInner
	local height = Claw.HoleWallHeight
	for _, hole in holes do
		local look = CFrame.new(hole.Center)
		local bedBottom = bedCenter.Y - bed.Size.X
		local seat = machine:FindFirstChild("UpperGoldSeat", true)
		local cabinetTop = if seat then seat.Position.Y + seat.Size.Y / 2 else bedBottom - 2
		-- в корпусе под трубой вырезан проем до потолка шахты лотка Delivery_X
		local chute = hole.Delivery and hole.Delivery:FindFirstChild("ChuteCeiling")
		local shaftBottom = if chute then chute.Position.Y - chute.Size.Y / 2 else cabinetTop
		local function sidePart(
			name: string,
			side: number,
			length: number,
			y0: number,
			y1: number,
			thick: number,
			offset: number
		)
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.CanQuery = false
			p.CastShadow = false
			p.Material = Enum.Material.SmoothPlastic
			p.Size = Vector3.new(length, y1 - y0, thick)
			p.CFrame = look
				* CFrame.Angles(0, side * math.pi / 2, 0)
				* CFrame.new(0, (y0 + y1) / 2 - hole.Center.Y, -offset)
			p.Parent = folder
			return p
		end
		for side = 0, 3 do
			local even = side % 2 == 0
			-- Стекло: одна цельная стенка от крышки корпуса до канта, сквозь вырезанный угол ложа.
			-- Стенки не заходят друг на друга в углах, чтобы полупрозрачные грани не мерцали.
			local wall = sidePart(
				"HoleWall",
				side,
				if even then inner + 0.6 else inner,
				cabinetTop,
				hole.Center.Y + height,
				0.3,
				inner / 2 + 0.15
			)
			wall.Transparency = HOLE_TRANSPARENCY
			wall.Color = HOLE_COLOR
			-- Внутри корпуса: темная непрозрачная гильза до потолка шахты лотка, закрывает срезы корпуса
			if cabinetTop - shaftBottom > 0.05 then
				local liner = sidePart(
					"HoleLiner",
					side,
					if even then inner + 0.6 else inner,
					shaftBottom,
					cabinetTop,
					0.3,
					inner / 2 + 0.15
				)
				liner.Color = Color3.fromRGB(18, 20, 28)
			end
			-- неоновый кант сверху
			local rim = sidePart(
				"HoleRim",
				side,
				inner + 0.7,
				hole.Center.Y + height,
				hole.Center.Y + height + 0.2,
				0.4,
				inner / 2 + 0.15
			)
			rim.CanCollide = false
			rim.Material = Enum.Material.Neon
			rim.Color = Color3.fromRGB(255, 210, 60)
			-- золотая рамка там, где труба входит в крышку корпуса
			local flange = sidePart(
				"HoleFlange",
				side,
				if even then inner + 1.1 else inner + 0.6,
				cabinetTop,
				cabinetTop + 0.16,
				0.25,
				inner / 2 + 0.425
			)
			flange.Color = Color3.fromRGB(226, 190, 92)
		end
		-- Потолок шахты лотка: шахта лотка повернута на 45 градусов к трубе, поэтому снизу
		-- закрываем потолок темной панелью с прямоугольным проемом по осям лотка и обводим его
		-- золотой рамкой, чтобы рамка не упиралась в боковые стенки шахты
		if chute then
			local d = hole.Direction
			local t = Vector3.yAxis:Cross(d).Unit
			local center = Vector3.new(bedCenter.X, shaftBottom, bedCenter.Z)
			local function radial(part: BasePart)
				return (part.Position - center):Dot(d)
			end
			local back = hole.Delivery:FindFirstChild("ChuteBack")
			local lintel = hole.Delivery:FindFirstChild("ChuteLintel")
			local liner = hole.Delivery:FindFirstChild("ChuteLeftLiner")
			local backFace = if back then radial(back) + back.Size.Z / 2 else Claw.HoleRadius - 1
			local frontEdge = if lintel then radial(lintel) - lintel.Size.Z / 2 else backFace + 5
			local halfWidth = if liner then math.abs((liner.Position - center):Dot(t)) - liner.Size.X / 2 else 2.9
			local openFront = Claw.HoleRadius + inner / 2 + 0.25
			local openHalf = halfWidth - 0.3
			local frame = CFrame.fromMatrix(center, t, Vector3.yAxis, d) -- X поперек лотка, +Z наружу к лотку
			local function plate(
				name: string,
				r0: number,
				r1: number,
				w0: number,
				w1: number,
				y0: number,
				y1: number,
				color: Color3
			)
				local p = Instance.new("Part")
				p.Name = name
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CastShadow = false
				p.Material = Enum.Material.SmoothPlastic
				p.Color = color
				p.Size = Vector3.new(w1 - w0, y1 - y0, r1 - r0)
				p.CFrame = frame * CFrame.new((w0 + w1) / 2, (y0 + y1) / 2, (r0 + r1) / 2)
				p.Parent = folder
			end
			local dark = Color3.fromRGB(18, 20, 28)
			local gold = Color3.fromRGB(226, 190, 92)
			-- панель потолка с проемом [backFace .. openFront] x [-openHalf .. openHalf]
			plate("ChutePanel", openFront, frontEdge, -halfWidth, halfWidth, -0.1, 0, dark)
			plate("ChutePanel", backFace, openFront, -halfWidth, -openHalf, -0.1, 0, dark)
			plate("ChutePanel", backFace, openFront, openHalf, halfWidth, -0.1, 0, dark)
			-- золотая рамка проема
			plate("HoleThroat", openFront, openFront + 0.3, -openHalf - 0.3, openHalf + 0.3, -0.22, -0.1, gold)
			plate("HoleThroat", backFace, openFront, -openHalf - 0.3, -openHalf, -0.22, -0.1, gold)
			plate("HoleThroat", backFace, openFront, openHalf, openHalf + 0.3, -0.22, -0.1, gold)
			plate("HoleThroat", backFace, backFace + 0.25, -openHalf, openHalf, -0.22, -0.1, gold)
		end
		local floor = Instance.new("Part")
		floor.Name = "HoleFloor"
		floor.Anchored = true
		-- невидимый "ловец": капсула ложится на него, ее засекает датчик, дальше она проваливается в шахту
		floor.Transparency = 1
		floor.CanQuery = false
		floor.Material = Enum.Material.SmoothPlastic
		floor.Size = Vector3.new(inner, 0.2, inner)
		floor.CFrame = look * CFrame.new(0, 0.1, 0)
		floor.Parent = folder
	end
end

-- Капсула падает по трубе сквозь проем в корпусе на пандус шахты лотка и скатывается в лоток.
-- onArrive вызывается в лотке: там капсула исчезает, а CakePopService кладет на ее место попс.
local function dropIntoShaft(capsule: Model, hole, onArrive: () -> ())
	capsule:SetAttribute("Collected", true)
	for _, part in capsule:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	local start = capsule:GetPivot()
	local fall = CFrame.new(Vector3.new(hole.Center.X, hole.RampPoint.Y, hole.Center.Z)) * start.Rotation
	local value = Instance.new("CFrameValue")
	value.Value = start
	value.Changed:Connect(function(cf)
		if capsule.Parent then
			capsule:PivotTo(cf)
		end
	end)
	local fallTween = TweenService:Create(
		value,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Value = fall }
	)
	fallTween.Completed:Connect(function()
		-- скатывается по пандусу к лотку, прокручиваясь по ходу движения
		local path = hole.TrayPoint - fall.Position
		local flat = Vector3.new(path.X, 0, path.Z)
		local axis = if flat.Magnitude > 0.01 then Vector3.yAxis:Cross(flat.Unit) else Vector3.xAxis
		local turns = flat.Magnitude / (math.pi * Claw.CapsuleDiameter)
		local roll = CFrame.new(hole.TrayPoint) * CFrame.fromAxisAngle(axis, -turns * 2 * math.pi) * fall.Rotation
		local rollTween = TweenService:Create(
			value,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Value = roll }
		)
		rollTween.Completed:Connect(function()
			value:Destroy()
			capsule:Destroy()
			onArrive()
		end)
		rollTween:Play()
	end)
	fallTween:Play()
end

-- Точки пути капсулы: пандус под трубой и середина лотка выдачи
local function computeDropPath(hole)
	local radius = Claw.CapsuleDiameter / 2
	local exit = hole.Delivery and hole.Delivery:FindFirstChild("CapsuleExit", true)
	local mat = hole.Delivery and hole.Delivery:FindFirstChild("TrayRubberMat", true)
	local trayY = if mat then mat.Position.Y + mat.Size.Y / 2 else hole.Center.Y - 7
	local tray = if exit
		then Vector3.new(exit.WorldPosition.X, trayY + radius, exit.WorldPosition.Z)
		else hole.Center - Vector3.new(0, 7, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { hole.Delivery }
	local hit = hole.Delivery
		and workspace:Raycast(
			Vector3.new(hole.Center.X, hole.Center.Y - 5, hole.Center.Z),
			Vector3.new(0, -10, 0),
			rayParams
		)
	local ramp = if hit
		then hit.Position + Vector3.new(0, radius, 0)
		else Vector3.new(hole.Center.X, tray.Y + 0.6, hole.Center.Z)
	hole.RampPoint = ramp
	hole.TrayPoint = tray
end

local function watchHole()
	for _, hole in holes do
		computeDropPath(hole)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { capsulesFolder }
	local size = Vector3.new(Claw.HoleInner - 0.2, Claw.HoleWallHeight, Claw.HoleInner - 0.2)
	local boxes = {}
	for _, hole in holes do
		table.insert(boxes, {
			Station = hole.Station,
			Hole = hole,
			CFrame = CFrame.new(hole.Center) * CFrame.new(0, Claw.HoleWallHeight / 2, 0),
		})
	end
	while true do
		task.wait(0.1)
		local seen = {}
		for _, entry in boxes do
			local box = entry.CFrame
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
				if
					inside
					and not seen[capsule]
					and not capsule:GetAttribute("Grabbed")
					and not capsule:GetAttribute("Collected")
				then
					seen[capsule] = true
					local rarityId = capsule:GetAttribute("Rarity")
					local mutationId = capsule:GetAttribute("Mutation")
					local familyId = capsule:GetAttribute("Family")
					local lastClaw = capsule:GetAttribute("LastClaw")
					-- выигрыш засчитывается, когда капсула докатилась до лотка
					dropIntoShaft(capsule, entry.Hole, function()
						collectedEvent:Fire(rarityId, mutationId, familyId, entry.Station, lastClaw)
					end)
				end
			end
		end
	end
end

function GachaService.Start()
	local field = workspace:WaitForChild(Balance.Map.FieldModel)
	machine = field:WaitForChild("CenterZone"):WaitForChild("CapsuleClawMachine")
	capsulesFolder = machine:WaitForChild("06_Capsules")
	local bed = machine:WaitForChild("01_BaseAndDelivery"):WaitForChild("CapsuleBed")
	-- Ложе: квадратная плита, повернутая так, что ее высота = Size.X (Y и Z = стороны квадрата)
	bedCenter = bed.Position + Vector3.new(0, bed.Size.X / 2, 0)
	-- Дыра каждого пульта: на краю ложа в сторону своего лотка (Station_X <-> Delivery_X)
	holes = {}
	for _, delivery in machine:WaitForChild("09_DeliveryStations"):GetChildren() do
		local suffix = delivery.Name:match("^Delivery_(.+)$")
		local exit = delivery:FindFirstChild("CapsuleExit", true)
		if suffix and exit then
			local flat = Vector3.new(exit.WorldPosition.X - bedCenter.X, 0, exit.WorldPosition.Z - bedCenter.Z)
			local direction = flat.Unit
			local station = "Station_" .. suffix
			holes[station] = {
				Station = station,
				Center = bedCenter + direction * Claw.HoleRadius,
				Direction = direction,
				Delivery = delivery,
			}
		end
	end

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
