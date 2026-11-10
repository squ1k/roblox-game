-- Скебобсы на пьедесталах базы. Пока моделей нет, это цветные кубы цвета глазури редкости
-- с подписью: имя, редкость, мутация и доход "+N/сек" с этого пьедестала.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Families = require(Config:WaitForChild("Families"))
local Strings = require(Config:WaitForChild("Strings"))
local Income = require(Shared:WaitForChild("Income"))
local NumberFormat = require(Shared:WaitForChild("NumberFormat"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local MapService = require(script.Parent:WaitForChild("MapService"))

local Display = Balance.PetDisplay

local PetDisplayService = {}

local root -- Workspace.Skebobs_Runtime.PetDisplays

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

local function makeCube(skebob, rarity, mutation, position: Vector3): Part
	local size = Display.CubeSize
	local cube = Instance.new("Part")
	cube.Size = Vector3.one * size
	cube.Color = rarity.Glaze
	cube.Material = Enum.Material.SmoothPlastic
	cube.Anchored = true
	cube.CanCollide = false
	cube.CanQuery = false
	cube.CanTouch = false
	cube.Position = position + Vector3.new(0, size / 2, 0)

	if mutation then
		local light = Instance.new("PointLight")
		light.Range = 8
		light.Brightness = 2
		light.Color = Color3.fromRGB(255, 240, 160)
		light.Parent = cube
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 240, 160)
		sparkles.Parent = cube
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(150, 54)
	billboard.StudsOffset = Vector3.new(0, size / 2 + 1.6, 0)
	billboard.MaxDistance = Display.LabelMaxDistance
	billboard.Parent = cube
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
		return label
	end
	line("Title", skebob.Name, Color3.new(1, 1, 1), 20)
	line("Rarity", (if mutation then mutation.Name .. " · " else "") .. rarity.Name, rarity.Glaze, 16)
	line("Income", "", Color3.fromRGB(255, 200, 40), 18)
	return cube
end

local function render(player: Player)
	local data = DataService.Get(player)
	local baseIndex = player:GetAttribute("BaseIndex")
	local base = baseIndex and MapService.GetBase(baseIndex)
	if not data or not base then
		return
	end
	local folder = folderFor(player)
	local _, perPedestal = Income.Compute(data, EconomyService.Context(player))

	local wanted = {}
	for slot, pedestal in data.Pedestals do
		local pet = pedestal.Pet and data.Pets[pedestal.Pet]
		local skebob = pet and Families.SkebobById[pet.Id]
		local anchor = base.Anchors[slot]
		if skebob and anchor then
			local name = "Slot" .. slot
			wanted[name] = true
			local key = pedestal.Pet .. "|" .. (pet.Mutation or "") .. "|" .. baseIndex
			local cube = folder:FindFirstChild(name)
			if cube and cube:GetAttribute("Key") ~= key then
				cube:Destroy()
				cube = nil
			end
			if not cube then
				local rarity = Balance.RarityById[skebob.Rarity]
				local mutation = pet.Mutation and Balance.MutationById[pet.Mutation]
				cube = makeCube(skebob, rarity, mutation, MapService.AnchorTop(anchor))
				cube.Name = name
				cube:SetAttribute("Key", key)
				cube.Parent = folder
			end
			cube.Label.Income.Text = "+" .. NumberFormat.Short(perPedestal[slot] or 0) .. Strings.PerSecondShort
		end
	end
	for _, child in folder:GetChildren() do
		if not wanted[child.Name] then
			child:Destroy()
		end
	end
end

function PetDisplayService.Refresh(player: Player)
	render(player)
end

function PetDisplayService.Start()
	local runtime = workspace:WaitForChild(Balance.Map.RuntimeFolder)
	root = runtime:FindFirstChild("PetDisplays")
	if not root then
		root = Instance.new("Folder")
		root.Name = "PetDisplays"
		root.Parent = runtime
	end
	-- в сохраненном месте могли остаться кубы от прошлого запуска в Studio
	root:ClearAllChildren()

	DataService.ProfileLoaded:Connect(function(player)
		task.defer(render, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local folder = root:FindFirstChild("Player_" .. player.UserId)
		if folder then
			folder:Destroy()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Display.RefreshSeconds)
			for _, player in Players:GetPlayers() do
				task.spawn(render, player)
			end
		end
	end)
end

return PetDisplayService
