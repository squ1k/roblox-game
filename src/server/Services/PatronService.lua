-- Патроны: призыв, когда собрано PatronUnlockShare уникальных Скебобсов Семейства (x2 к доходу
-- Семейства считает Income через data.Patrons.Summoned), главный Патрон (один, больше остальных)
-- и скрытие модели. Модели пока заглушки: кубы цвета Семейства кольцом над центром базы,
-- парение и вращение делает клиент (WorldEffects).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Income = require(Shared:WaitForChild("Income"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local MapService = require(script.Parent:WaitForChild("MapService"))

local Patrons = Balance.Patrons

local PatronService = {}

local root -- Workspace.Skebobs_Runtime.Patrons
local notified = {} -- [player] = { [familyId] = true } уже сообщили, что можно призвать

local function isReady(data, familyId: string): boolean
	local count, need = Income.FamilyProgress(data, familyId)
	return count >= need
end

local function changed(player: Player)
	EconomyService.Refresh(player)
	Remotes.ProfileChanged:FireClient(player)
	PatronService.Render(player)
end

local function familyData(player: Player, familyId)
	local data = DataService.Get(player)
	if not data or type(familyId) ~= "string" or not Families.ById[familyId] then
		return nil
	end
	return data
end

function PatronService.Summon(player: Player, familyId)
	local data = familyData(player, familyId)
	if not data or data.Patrons.Summoned[familyId] or not isReady(data, familyId) then
		return
	end
	data.Patrons.Summoned[familyId] = true
	Remotes.Notify:FireClient(player, string.format(Strings.PatronSummoned, Families.ById[familyId].Name))
	changed(player)
end

function PatronService.Choose(player: Player, familyId)
	local data = familyData(player, familyId)
	if not data or not data.Patrons.Summoned[familyId] then
		return
	end
	data.Patrons.Chosen = if data.Patrons.Chosen == familyId then false else familyId
	data.Patrons.Hidden[familyId] = nil
	changed(player)
end

function PatronService.Hide(player: Player, familyId)
	local data = familyData(player, familyId)
	if not data or not data.Patrons.Summoned[familyId] then
		return
	end
	data.Patrons.Hidden[familyId] = if data.Patrons.Hidden[familyId] then nil else true
	changed(player)
end

local function folderFor(player: Player): Folder
	local name = "Player_" .. player.UserId
	local folder = root:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
	end
	return folder
end

local function makePatron(family, chosen: boolean): Part
	local cubeSize = Balance.PetDisplay.CubeSize
	local size = if chosen
		then math.min(cubeSize * Patrons.ChosenSizeMult, Patrons.ChosenMaxSize)
		else cubeSize * Patrons.SizeMult
	local cube = Instance.new("Part")
	cube.Size = Vector3.one * size
	cube.Color = family.Color
	cube.Material = Enum.Material.Neon
	cube.Anchored = true
	cube.CanCollide = false
	cube.CanQuery = false
	cube.CanTouch = false
	cube:SetAttribute("Patron", true)
	local light = Instance.new("PointLight")
	light.Range = size * 2
	light.Color = family.Color
	light.Parent = cube
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 50)
	billboard.StudsOffset = Vector3.new(0, size / 2 + 2, 0)
	billboard.MaxDistance = 200
	billboard.Parent = cube
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = family.Color
	label.TextStrokeTransparency = 0
	label.Text = family.Patron .. "\n" .. string.format(Strings.PatronOf, family.Name)
	label.Parent = billboard
	return cube
end

-- Модели Патронов над базой игрока (по данным, без лишних пересозданий)
function PatronService.Render(player: Player)
	local data = DataService.Get(player)
	local base = MapService.GetBase(player:GetAttribute("BaseIndex") or 0)
	if not data or not base or not root then
		return
	end
	local folder = folderFor(player)
	local visible = {}
	for _, family in Families.List do
		if data.Patrons.Summoned[family.Id] and not data.Patrons.Hidden[family.Id] then
			table.insert(visible, family)
		end
	end
	local wanted = {}
	for index, family in visible do
		local chosen = data.Patrons.Chosen == family.Id
		local name = family.Id
		wanted[name] = true
		local key = (if chosen then "chosen" else "active") .. "|" .. base.Index
		local cube = folder:FindFirstChild(name)
		if cube and cube:GetAttribute("Key") ~= key then
			cube:Destroy()
			cube = nil
		end
		if not cube then
			cube = makePatron(family, chosen)
			cube.Name = name
			cube:SetAttribute("Key", key)
			local position
			if chosen then
				position = base.Origin + Vector3.new(0, Patrons.ChosenHeight, 0)
			else
				local angle = (index / #visible) * math.pi * 2
				position = base.Origin
					+ Vector3.new(
						math.cos(angle) * Patrons.RingRadius,
						Patrons.HoverHeight,
						math.sin(angle) * Patrons.RingRadius
					)
			end
			cube.Position = position
			cube.Parent = folder
		end
	end
	for _, child in folder:GetChildren() do
		if not wanted[child.Name] then
			child:Destroy()
		end
	end
end

local function checkReady(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local seen = notified[player] or {}
	notified[player] = seen
	for _, family in Families.List do
		if not data.Patrons.Summoned[family.Id] and not seen[family.Id] and isReady(data, family.Id) then
			seen[family.Id] = true
			Remotes.Notify:FireClient(player, string.format(Strings.PatronReady, family.Name))
		end
	end
end

function PatronService.Start()
	local runtime = workspace:WaitForChild(Balance.Map.RuntimeFolder)
	root = runtime:FindFirstChild("Patrons")
	if not root then
		root = Instance.new("Folder")
		root.Name = "Patrons"
		root.Parent = runtime
	end
	root:ClearAllChildren()
	Remotes.PatronSummon.OnServerEvent:Connect(PatronService.Summon)
	Remotes.PatronChoose.OnServerEvent:Connect(PatronService.Choose)
	Remotes.PatronHide.OnServerEvent:Connect(PatronService.Hide)
	DataService.ProfileLoaded:Connect(function(player)
		task.defer(PatronService.Render, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		notified[player] = nil
		local folder = root:FindFirstChild("Player_" .. player.UserId)
		if folder then
			folder:Destroy()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Patrons.RefreshSeconds)
			for _, player in Players:GetPlayers() do
				checkReady(player)
				PatronService.Render(player)
			end
		end
	end)
end

return PatronService
