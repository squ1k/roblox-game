-- Читает карту художника и строит данные баз: точки пьедесталов, спавн, габариты для зон.
-- Недостающее (пьедесталы до 12, АФК-лежак, Холодильник, Шкаф, Алтарь) создается заглушками
-- в Workspace.Skebobs_Runtime. Build можно вызвать и в режиме редактирования: заглушки
-- сохранятся в месте, и художник сможет их передвинуть. Повторный Build берет уже существующие.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))

local MapConfig = Balance.Map

local MapService = {}

local bases = {} -- [index] = { Index, Model, Folder, Origin, Forward, FloorY, Anchors = { Instance }, SpawnCFrame, BoxCFrame, BoxSize }
local pivotPosition = Vector3.zero
local built = false
local shop = nil -- { Counter, Anton, Exchange }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function boundsOf(instance: Instance): (CFrame, Vector3)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	end
	return instance.CFrame, instance.Size
end

-- Верхняя центральная точка пьедестала (куда ставится Скебобс)
function MapService.AnchorTop(anchor: Instance): Vector3
	local cf, size = boundsOf(anchor)
	return cf.Position + Vector3.new(0, size.Y / 2, 0)
end

local function sortedPedestals(pedestalsModel: Instance)
	local list = {}
	for _, child in pedestalsModel:GetChildren() do
		local number = tonumber(child.Name:match("^Pedestal(%d+)$"))
		if number then
			table.insert(list, { Number = number, Instance = child })
		end
	end
	table.sort(list, function(a, b)
		return a.Number < b.Number
	end)
	local result = {}
	for _, entry in list do
		table.insert(result, entry.Instance)
	end
	return result
end

local function makePart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addLabel(part: BasePart, text: string)
	if part:FindFirstChild("Label") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(160, 36)
	billboard.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1.5, 0)
	billboard.MaxDistance = 80
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = billboard
end

-- Ищет свободное место на полу базы: кольца вокруг origin, начиная с направления preferredDir
local function findSpot(base, raycastParams, preferredDir: Vector3, startRadius: number, avoid, clearance: number)
	local baseAngle = math.atan2(preferredDir.Z, preferredDir.X)
	for ring = 0, 5 do
		local radius = startRadius + ring * 4
		for step = 0, 23 do
			-- 0, +15, -15, +30, -30 ... градусов от предпочтительного направления
			local offset = math.ceil(step / 2) * math.rad(15) * (if step % 2 == 0 then 1 else -1)
			local angle = baseAngle + offset
			local x = base.Origin.X + math.cos(angle) * radius
			local z = base.Origin.Z + math.sin(angle) * radius
			local result = workspace:Raycast(Vector3.new(x, base.FloorY + 8, z), Vector3.new(0, -20, 0), raycastParams)
			if result and math.abs(result.Position.Y - base.FloorY) <= 2.5 then
				local ok = true
				for _, position in avoid do
					if (flat(position) - Vector3.new(x, 0, z)).Magnitude < clearance then
						ok = false
						break
					end
				end
				if ok then
					return result.Position
				end
			end
		end
	end
	return nil
end

local function buildBase(index: number, model: Model, runtime: Folder, raycastParams)
	local pedestalsModel = model:FindFirstChild("Pedestals")
	local pedestals = sortedPedestals(pedestalsModel)

	-- Пол базы = низ существующих пьедесталов, центр = их среднее (или атрибут Origin)
	local sum = Vector3.zero
	local floorY = math.huge
	for _, pedestal in pedestals do
		local cf, size = boundsOf(pedestal)
		sum += cf.Position
		floorY = math.min(floorY, cf.Position.Y - size.Y / 2)
	end
	local centroid = if #pedestals > 0 then sum / #pedestals else boundsOf(model).Position
	if floorY == math.huge then
		floorY = centroid.Y
	end
	local originAttr = model:GetAttribute("Origin")
	local origin = if typeof(originAttr) == "Vector3"
		then Vector3.new(originAttr.X, floorY, originAttr.Z)
		else Vector3.new(centroid.X, floorY, centroid.Z)
	local forwardAttr = model:GetAttribute("FrontDir") or model:GetAttribute("EntranceDir")
	local forward = if typeof(forwardAttr) == "Vector3"
		then flat(forwardAttr).Unit
		else flat(pivotPosition - origin).Unit

	local base = {
		Index = index,
		Model = model,
		Origin = origin,
		Forward = forward,
		FloorY = floorY,
		Anchors = {},
	}

	CollectionService:AddTag(model, "PlayerBase")
	model:SetAttribute("BaseIndex", index)

	local folder = runtime:FindFirstChild("Base_" .. index)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Base_" .. index
		folder.Parent = runtime
	end
	folder:SetAttribute("BaseModel", model.Name)
	base.Folder = folder

	local slots = folder:FindFirstChild("Slots")
	if not slots then
		slots = Instance.new("Folder")
		slots.Name = "Slots"
		slots.Parent = folder
	end

	local color = Balance.RarityById.Common.Glaze
	local used = {}
	for _, pedestal in pedestals do
		table.insert(used, MapService.AnchorTop(pedestal))
	end

	for slot = 1, Balance.Pedestals.MaxSlots do
		local ref = slots:FindFirstChild("Slot" .. slot)
		local anchor = ref and ref.Value
		if not anchor then
			anchor = pedestals[slot]
			if not anchor then
				local position = findSpot(base, raycastParams, -forward, 8, used, MapConfig.PedestalSpacing)
				if not position then
					warn("[MapService] нет места для пьедестала", model.Name, slot)
					position = origin + Vector3.new(slot * 3, 0, 0)
				end
				local size = MapConfig.PlaceholderPedestalSize
				local part = makePart("PlaceholderPedestal" .. slot, size, color, folder)
				part.Position = position + Vector3.new(0, size.Y / 2, 0)
				anchor = part
				table.insert(used, position)
			end
			if not ref then
				ref = Instance.new("ObjectValue")
				ref.Name = "Slot" .. slot
				ref.Parent = slots
			end
			ref.Value = anchor
		end
		base.Anchors[slot] = anchor
	end

	-- Объекты базы: ставим, только если их еще нет (художник мог передвинуть)
	local avoid = table.clone(used)
	local function facility(name: string, size: Vector3, color: Color3, dir: Vector3, radius: number, label: string?)
		local part = folder:FindFirstChild(name)
		if not part then
			local position = findSpot(base, raycastParams, dir, radius, avoid, math.max(size.X, size.Z) / 2 + 3)
				or (origin + dir * radius)
			part = makePart(name, size, color, folder)
			part.Position = position + Vector3.new(0, size.Y / 2, 0)
		end
		table.insert(avoid, part.Position)
		if label then
			addLabel(part, label)
		end
		return part
	end
	local side = Vector3.new(-forward.Z, 0, forward.X)
	local spawnPart = facility("Spawn", Vector3.new(4, 1, 4), Color3.new(1, 1, 1), forward, 6)
	spawnPart.Transparency = 1
	spawnPart.CanCollide = false
	spawnPart.CanQuery = false
	spawnPart.CanTouch = false

	local afkBed = facility("AfkBed", MapConfig.AfkBedSize, MapConfig.AfkBedColor, -forward, 12, Strings.AfkBedLabel)
	afkBed.CanCollide = false
	afkBed.Transparency = 0.5
	afkBed:SetAttribute("BaseIndex", index)
	CollectionService:AddTag(afkBed, "AfkZone")

	local fridge = facility(
		"Fridge",
		MapConfig.FacilitySize,
		Color3.fromRGB(120, 200, 255),
		(forward + side).Unit,
		8,
		Strings.FridgeLabel
	)
	local oven = facility(
		"Oven",
		MapConfig.FacilitySize,
		Color3.fromRGB(255, 140, 60),
		(forward - side).Unit,
		8,
		Strings.OvenLabel
	)
	local altar = facility("Altar", MapConfig.FacilitySize, Color3.fromRGB(200, 120, 255), side, 10, Strings.AltarLabel)
	for _, part in { fridge, oven, altar } do
		part:SetAttribute("BaseIndex", index)
	end

	base.SpawnCFrame = CFrame.lookAt(
		spawnPart.Position + Vector3.new(0, MapConfig.SpawnHeight, 0),
		spawnPart.Position + Vector3.new(0, MapConfig.SpawnHeight, 0) + forward
	)

	-- Габариты базы для зон: модель + заглушки
	local boxCFrame, boxSize = model:GetBoundingBox()
	local minV = boxCFrame.Position - boxSize / 2
	local maxV = boxCFrame.Position + boxSize / 2
	for _, child in folder:GetDescendants() do
		if child:IsA("BasePart") and child.Name ~= "Spawn" then
			minV = minV:Min(child.Position - child.Size / 2)
			maxV = maxV:Max(child.Position + child.Size / 2)
		end
	end
	base.BoxMin = minV
	base.BoxMax = maxV
	return base
end

-- Лавка Антона и ящик обмена (заглушки). Внутри мельницы места нет (автомат и пульты),
-- поэтому они стоят снаружи у стены мельницы со стороны первой базы; вокруг безопасная зона.
local function findShopSpots(runtime: Folder, raycastParams)
	local probe = Instance.new("Part")
	probe.Anchored = true
	probe.CanCollide = false
	probe.Size = Vector3.new(6, 4.5, 6)
	probe.Parent = runtime
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { runtime }
	local firstBase = bases[1]
	local toward = if firstBase then flat(firstBase.Origin - pivotPosition).Unit else Vector3.new(0, 0, -1)
	local baseAngle = math.atan2(toward.Z, toward.X)
	local spots = {}
	for step = 0, 24 do
		local offset = math.ceil(step / 2) * math.rad(5) * (if step % 2 == 0 then 1 else -1)
		local direction = Vector3.new(math.cos(baseAngle + offset), 0, math.sin(baseAngle + offset))
		for radius = 34, 40, 2 do
			local point = pivotPosition + direction * radius
			local hit = workspace:Raycast(
				Vector3.new(point.X, pivotPosition.Y + 30, point.Z),
				Vector3.new(0, -40, 0),
				raycastParams
			)
			if hit then
				probe.CFrame = CFrame.new(hit.Position + Vector3.new(0, 2.6, 0))
				local blocked = false
				for _, part in workspace:GetPartsInPart(probe, overlap) do
					if part.CanCollide then
						blocked = true
						break
					end
				end
				local farEnough = true
				for _, spot in spots do
					if (flat(spot.Position) - flat(hit.Position)).Magnitude < 9 then
						farEnough = false
					end
				end
				if not blocked and farEnough then
					table.insert(spots, { Position = hit.Position, Direction = direction })
					break
				end
			end
		end
		if #spots >= 2 then
			break
		end
	end
	probe:Destroy()
	return spots
end

local function makeAnton(folder: Folder, position: Vector3, facing: Vector3): BasePart
	local model = Instance.new("Model")
	model.Name = "Anton"
	local look = CFrame.lookAt(position, position + facing)
	local function block(name, size, color, offset)
		local part = makePart(name, size, color, model)
		part.Material = Enum.Material.SmoothPlastic
		part.CFrame = look * offset
		return part
	end
	local body = block("Body", Vector3.new(2, 2.4, 1.6), Color3.fromRGB(130, 130, 140), CFrame.new(0, 1.2, 0))
	block("Head", Vector3.new(1.8, 1.5, 1.5), Color3.fromRGB(150, 150, 160), CFrame.new(0, 3.1, 0))
	block("Mask", Vector3.new(1.9, 0.45, 0.1), Color3.fromRGB(40, 40, 50), CFrame.new(0, 3.2, -0.76))
	block("EarL", Vector3.new(0.4, 0.5, 0.3), Color3.fromRGB(60, 60, 70), CFrame.new(-0.6, 4.05, 0))
	block("EarR", Vector3.new(0.4, 0.5, 0.3), Color3.fromRGB(60, 60, 70), CFrame.new(0.6, 4.05, 0))
	block("Tail", Vector3.new(0.5, 0.5, 1.8), Color3.fromRGB(90, 90, 100), CFrame.new(0, 0.8, 1.6))
	block("Apron", Vector3.new(1.6, 1.6, 0.1), Color3.fromRGB(120, 70, 40), CFrame.new(0, 1.1, -0.82))
	for _, part in model:GetChildren() do
		part.Material = Enum.Material.SmoothPlastic
	end
	model.PrimaryPart = body
	model.Parent = folder
	addLabel(body, Strings.ShopNpc)
	body.Label.StudsOffset = Vector3.new(0, 4.2, 0)
	local glow = Instance.new("Highlight")
	glow.FillTransparency = 1
	glow.OutlineColor = Color3.fromRGB(255, 210, 60)
	glow.Parent = model
	return body
end

local function buildShop(runtime: Folder, raycastParams)
	local folder = runtime:FindFirstChild("Shop")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Shop"
		folder.Parent = runtime
	end
	local counter = folder:FindFirstChild("Counter")
	local anton = folder:FindFirstChild("Anton")
	local exchange = folder:FindFirstChild("SkebobsExchange")
	if not counter or not anton or not exchange then
		local spots = findShopSpots(runtime, raycastParams)
		local fallback = pivotPosition + Vector3.new(0, 0, -36)
		local shopSpot = spots[1] or { Position = fallback, Direction = Vector3.new(0, 0, -1) }
		local exchangeSpot = spots[2]
			or { Position = fallback + Vector3.new(9, 0, 0), Direction = Vector3.new(0, 0, -1) }
		local facing = shopSpot.Direction -- лицом от мельницы к базам
		if not counter then
			counter = makePart("Counter", Vector3.new(6, 2.6, 2), Color3.fromRGB(150, 100, 60), folder)
			counter.Material = Enum.Material.WoodPlanks
			local center = shopSpot.Position + facing * 1.6 + Vector3.new(0, 1.3, 0)
			counter.CFrame = CFrame.lookAt(center, center + facing)
			addLabel(counter, Strings.ShopTitle)
			counter.Label.StudsOffset = Vector3.new(0, 6.5, 0)
		end
		if not anton then
			makeAnton(folder, shopSpot.Position - facing * 0.8, facing)
		end
		if not exchange then
			exchange = makePart("SkebobsExchange", Vector3.new(3, 4.5, 2.5), Color3.fromRGB(60, 200, 120), folder)
			exchange.Material = Enum.Material.SmoothPlastic
			local center = exchangeSpot.Position + Vector3.new(0, 2.25, 0)
			exchange.CFrame = CFrame.lookAt(center, center + exchangeSpot.Direction)
			addLabel(exchange, Strings.ExchangeTitle)
		end
	end
	-- Терминал Черного рынка (Epic 8) рядом с ящиком обмена
	local exchangePart = folder:FindFirstChild("SkebobsExchange")
	if exchangePart and not folder:FindFirstChild("BlackMarket") then
		local market = makePart("BlackMarket", Vector3.new(3, 4.5, 2.5), Color3.fromRGB(40, 30, 50), folder)
		market.Material = Enum.Material.SmoothPlastic
		market.CFrame = exchangePart.CFrame * CFrame.new(-4.5, 0, 0)
		addLabel(market, Strings.BlackMarketTitle)
	end
	anton = folder:FindFirstChild("Anton")
	shop = {
		Counter = folder:FindFirstChild("Counter"),
		Anton = anton and anton.PrimaryPart,
		Exchange = exchangePart,
		BlackMarket = folder:FindFirstChild("BlackMarket"),
	}
end

-- Заглушки лавки: { Counter, Anton (тело), Exchange, BlackMarket }
function MapService.Shop()
	return shop
end

function MapService.Build()
	local field = workspace:WaitForChild(MapConfig.FieldModel)
	pivotPosition = field:WaitForChild(MapConfig.IslandPivot).Position

	local runtime = workspace:FindFirstChild(MapConfig.RuntimeFolder)
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = MapConfig.RuntimeFolder
		runtime.Parent = workspace
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { runtime }

	table.clear(bases)
	for index, name in MapConfig.BaseOrder do
		local model = field:WaitForChild(name, 10)
		if model and model:FindFirstChild("Pedestals") then
			bases[index] = buildBase(index, model, runtime, raycastParams)
		else
			warn("[MapService] база не найдена", name)
		end
	end
	buildShop(runtime, raycastParams)
	built = true
	return bases
end

function MapService.GetBase(index: number)
	return bases[index]
end

function MapService.BaseCount(): number
	return #MapConfig.BaseOrder
end

function MapService.IslandPivot(): Vector3
	return pivotPosition
end

-- Индекс базы, в габаритах которой точка (с запасом BaseMargin), или nil
function MapService.BaseAt(position: Vector3): number?
	local margin = Vector3.one * Balance.Zones.BaseMargin
	for index, base in bases do
		local minV = base.BoxMin - margin
		local maxV = base.BoxMax + margin
		if
			position.X >= minV.X
			and position.X <= maxV.X
			and position.Z >= minV.Z
			and position.Z <= maxV.Z
			and position.Y >= minV.Y - 10
			and position.Y <= maxV.Y + 10
		then
			return index
		end
	end
	return nil
end

function MapService.Start()
	if not built then
		MapService.Build()
	end
end

return MapService
