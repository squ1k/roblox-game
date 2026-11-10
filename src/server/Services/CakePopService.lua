-- Кейк-попс как физический предмет: появляется в лотке автомата, его поднимают (ProximityPrompt),
-- несут в правой руке, бросают (DropPop) и кладут в свой Холодильник. Чужой попс можно забрать только
-- в Пшеничном поле; хозяином становится тот, кто положил попс в свой Холодильник. Таяние: MeltInHandsSeconds в руках,
-- MeltOnGroundSeconds на земле (время копится, сброс/подъем его не обнуляет).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))

local Pop = Balance.CakePop
local MapConfig = Balance.Map
local DEFAULT_STATION = "Station_South"

local CakePopService = {}

local folder -- Workspace.Skebobs_Runtime.Pops
local pops = {} -- [model] = { Model, Ball, Prompt, OwnerUserId, Station, State, Carrier, Weld, HandsTime, GroundTime, OfflineSince }
local carried = {} -- [player] = entry
local fridgePrompts = {} -- [baseIndex] = ProximityPrompt
local fridgeOpenPrompts = {} -- [baseIndex] = ProximityPrompt "Открыть" (экран Холодильника на клиенте)

-- Подсказка "Положить в Холодильник" видна только пока хозяин базы несет попс,
-- "Открыть" - пока руки свободны
local function syncFridgePrompt(player: Player)
	local index = player:GetAttribute("BaseIndex")
	local prompt = index and fridgePrompts[index]
	if prompt then
		local want = carried[player] ~= nil and player.Parent ~= nil
		if prompt.Enabled ~= want then
			prompt.Enabled = want
		end
	end
	local open = index and fridgeOpenPrompts[index]
	if open then
		local want = carried[player] == nil and player.Parent ~= nil
		if open.Enabled ~= want then
			open.Enabled = want
		end
	end
end

local function now()
	return workspace:GetServerTimeNow()
end

local function machine()
	local field = workspace:FindFirstChild(MapConfig.FieldModel)
	local zone = field and field:FindFirstChild("CenterZone")
	return zone and zone:FindFirstChild("CapsuleClawMachine")
end

-- Точка лотка выдачи, ближайшего к пульту (лотки стоят по диагоналям от пультов)
function CakePopService.TrayPosition(stationName: string?): Vector3
	local claw = machine()
	local stations = claw and claw:FindFirstChild("07_ControlStations")
	local station = stations and stations:FindFirstChild(stationName or DEFAULT_STATION)
	local deliveries = claw and claw:FindFirstChild("09_DeliveryStations")
	local from = if station then station:GetPivot().Position else MapService.IslandPivot()
	local best, bestDistance = nil, math.huge
	if deliveries then
		for _, attachment in deliveries:GetDescendants() do
			if attachment:IsA("Attachment") and attachment.Name == "CapsuleExit" then
				local distance = (attachment.WorldPosition - from).Magnitude
				if distance < bestDistance then
					best, bestDistance = attachment.WorldPosition, distance
				end
			end
		end
	end
	return (best or from) + Vector3.new(0, Pop.TrayLift, 0)
end

local function nearestStation(position: Vector3): string
	local claw = machine()
	local stations = claw and claw:FindFirstChild("07_ControlStations")
	local best, bestDistance = DEFAULT_STATION, math.huge
	if stations then
		for _, station in stations:GetChildren() do
			local distance = (station:GetPivot().Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = station.Name, distance
			end
		end
	end
	return best
end

local function describe(petId: string, mutationId: string?)
	local skebob = Families.SkebobById[petId]
	local rarity = skebob and Balance.RarityById[skebob.Rarity] or Balance.Rarities[1]
	local family = skebob and Families.ById[skebob.Family]
	local mutation = mutationId and Balance.MutationById[mutationId]
	return rarity, family, mutation
end

local function setPhysical(entry, physical: boolean)
	for _, part in entry.Model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Massless = not physical or part ~= entry.Ball
		end
	end
	entry.Ball.CanCollide = physical
end

local function giveToServer(ball: BasePart)
	task.defer(function()
		if ball.Parent and not ball.Anchored and ball:CanSetNetworkOwnership() then
			ball:SetNetworkOwner(nil)
		end
	end)
end

local function placeAt(entry, position: Vector3, anchorSeconds: number?)
	entry.Ball.Anchored = true
	entry.Model:PivotTo(CFrame.new(position))
	entry.State = "Ground"
	entry.Prompt.Enabled = true
	setPhysical(entry, true)
	task.delay(anchorSeconds or Pop.TrayAnchorSeconds, function()
		if pops[entry.Model] and entry.State == "Ground" and entry.Ball.Anchored then
			entry.Ball.Anchored = false
			entry.Ball.AssemblyLinearVelocity = Vector3.new(math.random() - 0.5, 6, math.random() - 0.5)
			giveToServer(entry.Ball)
		end
	end)
end

local function build(ownerUserId: number, pop): Model
	local rarity, family, mutation = describe(pop.Id, pop.Mutation)
	local model = Instance.new("Model")
	model.Name = "CakePop"

	-- Эффекты погодных мутаций попса: Neon маленький, Frozen скользит дальше
	local diameter = if pop.Mutation == "Neon" then Pop.Diameter * Balance.Weather.NeonPopScale else Pop.Diameter
	local friction = if pop.Mutation == "Frozen" then Balance.Weather.FrozenPopFriction else 0.6
	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * diameter
	ball.Color = rarity.Glaze
	ball.Material = Enum.Material.SmoothPlastic
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.8, friction, 0.2, 100, 1)
	ball.Parent = model

	local stick = Instance.new("Part")
	stick.Name = "Stick"
	stick.Shape = Enum.PartType.Cylinder
	stick.Size = Vector3.new(Pop.StickLength, 0.25, 0.25)
	stick.Color = Color3.fromRGB(245, 235, 210)
	stick.Material = Enum.Material.SmoothPlastic
	stick.CanCollide = false
	stick.CanQuery = false
	stick.Massless = true
	stick.CFrame = ball.CFrame
		* CFrame.new(0, -(Pop.Diameter / 2 + Pop.StickLength / 2 - 0.3), 0)
		* CFrame.Angles(0, 0, math.rad(90))
	stick.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ball
	weld.Part1 = stick
	weld.Parent = ball

	if mutation then
		local light = Instance.new("PointLight")
		light.Range = 8
		light.Brightness = 2
		light.Color = Color3.fromRGB(255, 240, 160)
		light.Parent = ball
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 240, 160)
		sparkles.Parent = ball
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(160, 58)
	billboard.StudsOffset = Vector3.new(0, Pop.Diameter / 2 + 1.8, 0)
	billboard.MaxDistance = 60
	billboard.Parent = ball
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = billboard
	local function line(name: string, text: string, color: Color3, height: number)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, height)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = billboard
	end
	line("Family", if family then family.Name else "?", Color3.new(1, 1, 1), 20)
	line("Rarity", (if mutation then mutation.Name .. " · " else "") .. rarity.Name, rarity.Glaze, 16)
	line("Timer", "", Color3.fromRGB(180, 220, 255), 16)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUpPrompt"
	prompt.ActionText = Strings.PickUp
	prompt.ObjectText = Strings.PopObject
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Pop.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = ball

	model.PrimaryPart = ball
	model:SetAttribute("PetId", pop.Id)
	model:SetAttribute("Rarity", rarity.Id)
	model:SetAttribute("Mutation", pop.Mutation)
	model:SetAttribute("Sleeping", pop.Sleeping)
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("SpawnedAt", now())
	return model
end

local function root(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function attach(player: Player, entry): boolean
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not hand then
		return false
	end
	entry.Ball.Anchored = false
	setPhysical(entry, false)
	entry.Ball.Massless = true
	-- Поза с поднятой рукой рисуется на клиентах (CarryPose) по атрибуту Carrying
	-- Палочка в кулаке, шар сверху: рука согнута на HoldArmAngle, поэтому сначала поворачиваем
	-- обратно к вертикали, потом поднимаем шар на длину палочки
	local diameter = entry.Ball.Size.X
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = hand
	weld.Part1 = entry.Ball
	weld.C0 = CFrame.Angles(-math.rad(Pop.HoldArmAngle), 0, 0)
		* CFrame.new(0, diameter / 2 + Pop.StickLength - 0.3 - Pop.GripInset, 0)
	weld.Parent = entry.Ball
	entry.Weld = weld
	entry.State = "Carried"
	entry.Carrier = player
	entry.Prompt.Enabled = false
	entry.Model:SetAttribute("CarriedBy", player.UserId)
	carried[player] = entry
	PlayerStateService.SetCarrying(player, true)
	syncFridgePrompt(player)
	return true
end

local function remove(entry)
	if entry.Carrier then
		carried[entry.Carrier] = nil
		PlayerStateService.SetCarrying(entry.Carrier, false)
		syncFridgePrompt(entry.Carrier)
	end
	pops[entry.Model] = nil
	entry.Model:Destroy()
end

local function register(owner: Player, pop, stationName: string?, ownerUserId: number?)
	ownerUserId = ownerUserId or owner.UserId
	local model = build(ownerUserId, pop)
	local entry = {
		Model = model,
		Ball = model.PrimaryPart,
		Prompt = model.PrimaryPart.PickUpPrompt,
		OwnerUserId = ownerUserId,
		Station = stationName or DEFAULT_STATION,
		State = "Ground",
		HandsTime = 0,
		GroundTime = 0,
	}
	model:SetAttribute("Station", entry.Station)
	pops[model] = entry
	entry.Prompt.Triggered:Connect(function(player)
		CakePopService.TryPickUp(player, entry)
	end)
	model.Parent = folder
	return entry
end

-- Выигрыш из автомата: попс в лотке того пульта, где играл победитель
function CakePopService.SpawnInTray(owner: Player, pop, stationName: string?)
	local entry = register(owner, pop, stationName)
	placeAt(entry, CakePopService.TrayPosition(entry.Station))
	return entry.Model
end

-- Тестовый попс прямо перед игроком (ownerUserId: чей попс, по умолчанию самого игрока)
function CakePopService.SpawnNear(owner: Player, pop, ownerUserId: number?)
	local hrp = root(owner)
	local position = if hrp then (hrp.CFrame * CFrame.new(0, 0, -4)).Position else MapService.IslandPivot()
	local entry = register(owner, pop, nearestStation(position), ownerUserId)
	placeAt(entry, position)
	return entry.Model
end

-- Попс в заданной точке (результат Алтаря Слияния). groundSeconds переопределяет таяние на земле.
function CakePopService.SpawnAt(owner: Player, pop, position: Vector3, groundSeconds: number?)
	local entry = register(owner, pop, nearestStation(position))
	entry.GroundLimit = groundSeconds
	placeAt(entry, position)
	return entry.Model
end

-- Попс сразу в руки (из Холодильника)
function CakePopService.GiveToHands(player: Player, pop): boolean
	if carried[player] then
		return false
	end
	local entry = register(player, pop, nil)
	if not attach(player, entry) then
		remove(entry)
		return false
	end
	return true
end

function CakePopService.IsCarrying(player: Player): boolean
	return carried[player] ~= nil
end

-- Забрать попс из рук в объект базы (Тепловой шкаф): модель удаляется, возвращаются данные попса
-- и id прежнего владельца (для статистики краж)
function CakePopService.ConsumeCarried(player: Player)
	local entry = carried[player]
	if not entry then
		return nil
	end
	local pop = {
		Id = entry.Model:GetAttribute("PetId"),
		Mutation = entry.Model:GetAttribute("Mutation"),
		Sleeping = entry.Model:GetAttribute("Sleeping"),
	}
	local ownerUserId = entry.OwnerUserId
	remove(entry)
	return pop, ownerUserId
end

function CakePopService.TryPickUp(player: Player, entry)
	if not pops[entry.Model] or entry.State == "Carried" then
		return
	end
	local hrp = root(player)
	if not hrp or (hrp.Position - entry.Ball.Position).Magnitude > Pop.PromptDistance + 2 then
		return
	end
	if entry.StickyUntil and os.clock() < entry.StickyUntil then
		Remotes.Notify:FireClient(player, Strings.PopSticky)
		return
	end
	if entry.OwnerUserId ~= player.UserId and player:GetAttribute("Zone") ~= "Field" then
		Remotes.Notify:FireClient(player, Strings.StealOnlyInField)
		return
	end
	if carried[player] or PlayerStateService.IsBusy(player) or player:GetAttribute("ClawActive") then
		Remotes.Notify:FireClient(player, Strings.HandsBusy)
		return
	end
	attach(player, entry)
end

-- Сброс: throw = толчок вперед (кнопка "Бросить"), без него просто падает (смерть, оглушение, падение)
function CakePopService.Drop(player: Player, throw: boolean?)
	local entry = carried[player]
	if not entry then
		if player:GetAttribute("Carrying") then
			PlayerStateService.SetCarrying(player, false)
		end
		return
	end
	carried[player] = nil
	if entry.Weld then
		entry.Weld:Destroy()
		entry.Weld = nil
	end
	entry.Carrier = nil
	entry.State = "Ground"
	entry.Model:SetAttribute("CarriedBy", nil)
	setPhysical(entry, true)
	entry.Prompt.Enabled = true
	local hrp = root(player)
	if hrp then
		entry.Model:PivotTo(hrp.CFrame * CFrame.new(0, 1, -2.5))
		local velocity = if throw then hrp.CFrame.LookVector * Pop.ThrowSpeed + Vector3.new(0, 6, 0) else Vector3.zero
		entry.Ball.AssemblyLinearVelocity = velocity
	end
	giveToServer(entry.Ball)
	-- Токсичный попс прилипает к земле: ToxicStickSeconds его не может поднять никто
	if entry.Model:GetAttribute("Mutation") == "Toxic" then
		entry.StickyUntil = os.clock() + Balance.Weather.ToxicStickSeconds
		entry.Prompt.Enabled = false
		task.delay(Balance.Weather.ToxicStickSeconds, function()
			if pops[entry.Model] and entry.State == "Ground" then
				entry.Prompt.Enabled = true
			end
		end)
	end
	-- TODO Epic 8: Bubble (телепорт при попадании), Stormy ("брыкается"), Mirage (зависает), Melted (-40% скорости)
	PlayerStateService.SetCarrying(player, false)
	syncFridgePrompt(player)
end

local function onFridgePrompt(player: Player, baseIndex: number)
	if player:GetAttribute("BaseIndex") ~= baseIndex then
		Remotes.Notify:FireClient(player, Strings.OwnBaseOnly)
		return
	end
	local entry = carried[player]
	if not entry then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	if #data.Fridge >= data.FridgeSlots then
		Remotes.Notify:FireClient(player, Strings.FridgeFull)
		return
	end
	local petId = entry.Model:GetAttribute("PetId")
	local mutation = entry.Model:GetAttribute("Mutation")
	table.insert(data.Fridge, { Id = petId, Mutation = mutation })
	if entry.OwnerUserId ~= player.UserId then
		data.Stats.Steals += 1
	end
	local rarity = describe(petId, mutation)
	remove(entry)
	Remotes.Notify:FireClient(player, string.format(Strings.PopStored, rarity.Name .. " попс"))
	Remotes.ProfileChanged:FireClient(player)
end

local function setupFridges()
	for index = 1, MapService.BaseCount() do
		local base = MapService.GetBase(index)
		local fridge = base and base.Folder:FindFirstChild("Fridge")
		if fridge then
			local prompt = fridge:FindFirstChild("FridgePrompt") or Instance.new("ProximityPrompt")
			prompt.Name = "FridgePrompt"
			prompt.ActionText = Strings.PutInFridge
			prompt.ObjectText = Strings.FridgeLabel
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = Pop.PromptDistance
			prompt.RequiresLineOfSight = false
			prompt.Enabled = false -- включается, когда владелец несет попс
			prompt.Parent = fridge
			fridgePrompts[index] = prompt
			local open = fridge:FindFirstChild("FridgeOpenPrompt") or Instance.new("ProximityPrompt")
			open.Name = "FridgeOpenPrompt"
			open.ActionText = Strings.FridgeOpen
			open.ObjectText = Strings.FridgeLabel
			open.HoldDuration = 0
			open.MaxActivationDistance = Pop.PromptDistance
			open.RequiresLineOfSight = false
			open.Enabled = false
			open.Parent = fridge
			fridgeOpenPrompts[index] = open
			prompt.Triggered:Connect(function(player)
				local hrp = root(player)
				if hrp and (hrp.Position - fridge.Position).Magnitude <= Pop.PromptDistance + 3 then
					onFridgePrompt(player, index)
				end
			end)
		end
	end
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function tick(dt: number)
	local pivot = MapService.IslandPivot()
	for model, entry in pops do
		if entry.State == "Carried" then
			entry.HandsTime += dt
		else
			entry.GroundTime += dt
		end
		local groundLimit = entry.GroundLimit or Pop.MeltOnGroundSeconds
		local left = math.min(Pop.MeltInHandsSeconds - entry.HandsTime, groundLimit - entry.GroundTime)
		if left <= 0 then
			local owner = Players:GetPlayerByUserId(entry.OwnerUserId)
			if owner then
				Remotes.Notify:FireClient(owner, Strings.PopMelted)
			end
			remove(entry)
			continue
		end
		entry.Ball.Label.Timer.Text = formatTime(left)

		if entry.State ~= "Carried" then
			-- Упал с острова: возвращаем в лоток своего пульта
			local position = entry.Ball.Position
			local radius = Vector3.new(position.X - pivot.X, 0, position.Z - pivot.Z).Magnitude
			if position.Y < MapConfig.FallMinY or radius > MapConfig.FallMaxRadius then
				placeAt(entry, CakePopService.TrayPosition(entry.Station))
			end
			-- Владелец вышел: удаляем через OwnerOfflineSeconds
			if Players:GetPlayerByUserId(entry.OwnerUserId) then
				entry.OfflineSince = nil
			else
				entry.OfflineSince = entry.OfflineSince or os.clock()
				if os.clock() - entry.OfflineSince > Pop.OwnerOfflineSeconds then
					remove(entry)
				end
			end
		end
	end

	-- Замедление с попсом только в Пшеничном поле
	for _, player in Players:GetPlayers() do
		syncFridgePrompt(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and not player:GetAttribute("ClawActive") then
			local entry = carried[player]
			local slow = entry ~= nil
				and player:GetAttribute("Zone") == "Field"
				and entry.Model:GetAttribute("Mutation") ~= "Neon" -- неоновый попс без замедления
			local speed = Balance.Player.BaseSpeed * (if slow then Pop.CarrySpeedMult else 1)
			if humanoid.WalkSpeed ~= speed then
				humanoid.WalkSpeed = speed
			end
		end
	end
end

function CakePopService.Start()
	local runtime = workspace:WaitForChild(MapConfig.RuntimeFolder)
	folder = runtime:FindFirstChild("Pops")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Pops"
		folder.Parent = runtime
	end
	folder:ClearAllChildren()
	setupFridges()

	Remotes.DropPop.OnServerEvent:Connect(function(player)
		if not carried[player] then
			return
		end
		if player:GetAttribute("Zone") == "Center" then
			Remotes.Notify:FireClient(player, Strings.NoLitterMill)
			return
		end
		CakePopService.Drop(player, true)
	end)

	Remotes.FridgeTake.OnServerEvent:Connect(function(player, index)
		if type(index) ~= "number" or index ~= index or index % 1 ~= 0 then
			return
		end
		if player:GetAttribute("Zone") ~= "Base" then
			Remotes.Notify:FireClient(player, Strings.OwnBaseOnly)
			return
		end
		if carried[player] or PlayerStateService.IsBusy(player) then
			Remotes.Notify:FireClient(player, Strings.HandsBusy)
			return
		end
		local data = DataService.Get(player)
		local pop = data and data.Fridge[index]
		if not pop then
			return
		end
		table.remove(data.Fridge, index)
		if not CakePopService.GiveToHands(player, { Id = pop.Id, Mutation = pop.Mutation }) then
			table.insert(data.Fridge, index, pop)
		end
		Remotes.ProfileChanged:FireClient(player)
	end)

	local function watchCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				CakePopService.Drop(player, false)
			end)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			CakePopService.Drop(player, false)
		end)
	end)
	for _, player in Players:GetPlayers() do
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			CakePopService.Drop(player, false)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		CakePopService.Drop(player, false)
		local index = player:GetAttribute("BaseIndex")
		for _, prompt in { fridgePrompts[index], fridgeOpenPrompts[index] } do
			prompt.Enabled = false
		end
	end)

	-- 4 раза в секунду хватает: таймер на табличке и проверки не нужны каждый кадр
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local t = os.clock()
			tick(t - last)
			last = t
		end
	end)
end

return CakePopService
