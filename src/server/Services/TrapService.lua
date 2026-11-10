-- Банано-капканы: ставятся из хотбара только в Пшеничном поле, жертва поскальзывается
-- (Stunned на StunSeconds) и роняет попс. Свой капкан на владельца не срабатывает.
-- Капкан живет LifetimeSeconds и исчезает раньше, если автомат обновил ассортимент.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))
local CakePopService = require(script.Parent:WaitForChild("CakePopService"))
local GachaService = require(script.Parent:WaitForChild("GachaService"))

local Trap = Balance.BananaTrap
local ITEM_ID = "BananaTrap"

local TrapService = {}

local folder -- Workspace.Skebobs_Runtime.Traps
local traps = {} -- [model] = { Model, OwnerUserId, Position, ExpiresAt }

local function countFor(userId: number): number
	local count = 0
	for _, trap in traps do
		if trap.OwnerUserId == userId then
			count += 1
		end
	end
	return count
end

local function totalCount(): number
	local count = 0
	for _ in traps do
		count += 1
	end
	return count
end

local function removeTrap(trap)
	traps[trap.Model] = nil
	trap.Model:Destroy()
end

local function buildTrap(position: Vector3, yaw: number): Model
	local model = Instance.new("Model")
	model.Name = "BananaTrap"
	-- Заглушка кожуры: желтый "бублик" из 3 лепестков
	local center = Instance.new("Part")
	center.Name = "Peel"
	center.Shape = Enum.PartType.Cylinder
	center.Size = Vector3.new(0.3, 1.2, 1.2)
	center.Color = Color3.fromRGB(255, 220, 60)
	center.Material = Enum.Material.SmoothPlastic
	center.Anchored = true
	center.CanCollide = false
	center.CanQuery = false
	center.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, yaw, math.rad(90))
	center.Transparency = 1 - Trap.FieldOpacity
	center.Parent = model
	for i = 1, 3 do
		local petal = Instance.new("Part")
		petal.Name = "Petal"
		petal.Size = Vector3.new(0.5, 0.15, 1.4)
		petal.Color = Color3.fromRGB(240, 200, 40)
		petal.Material = Enum.Material.SmoothPlastic
		petal.Anchored = true
		petal.CanCollide = false
		petal.CanQuery = false
		petal.Transparency = 1 - Trap.FieldOpacity
		local angle = yaw + i * math.pi * 2 / 3
		petal.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0))
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, 0, -0.9)
			* CFrame.Angles(math.rad(-12), 0, 0)
		petal.Parent = model
	end
	model.PrimaryPart = center
	return model
end

-- Оглушение: персонаж падает, роняет попс, через StunSeconds встает
function TrapService.Stun(player: Player, fromDirection: Vector3?)
	if player:GetAttribute("Stunned") then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	player:SetAttribute("Stunned", true)
	CakePopService.Drop(player, false)
	humanoid.PlatformStand = true
	local back = if fromDirection then fromDirection else -root.CFrame.LookVector
	root.AssemblyLinearVelocity = back * Trap.SlipImpulse + Vector3.new(0, 18, 0)
	root.AssemblyAngularVelocity = root.CFrame.RightVector * 8
	Remotes.Notify:FireClient(player, Strings.Stunned)
	task.delay(Trap.StunSeconds, function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		player:SetAttribute("Stunned", false)
	end)
end

local function place(player: Player, data)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	if countFor(player.UserId) >= Trap.MaxActivePerPlayer or totalCount() >= Trap.MaxActivePerServer then
		Remotes.Notify:FireClient(player, Strings.TrapLimit)
		return
	end
	local front = root.Position + root.CFrame.LookVector * Trap.PlaceDistance
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, workspace:FindFirstChild(Balance.Map.RuntimeFolder) }
	local hit = workspace:Raycast(front + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
	if not hit then
		return
	end
	local position = hit.Position
	for _, trap in traps do
		if trap.OwnerUserId == player.UserId and (trap.Position - position).Magnitude < Trap.MinSpacing then
			Remotes.Notify:FireClient(player, Strings.TrapTooClose)
			return
		end
	end
	data.Items[ITEM_ID] -= 1
	data.Stats.TrapsPlaced += 1
	local _, yaw = root.CFrame:ToOrientation()
	local model = buildTrap(position, yaw)
	model:SetAttribute("OwnerUserId", player.UserId)
	model.Parent = folder
	traps[model] = {
		Model = model,
		OwnerUserId = player.UserId,
		Position = position,
		ExpiresAt = os.clock() + Trap.LifetimeSeconds,
	}
	Remotes.Notify:FireClient(player, Strings.TrapPlaced)
	Remotes.ProfileChanged:FireClient(player)
end

local function check()
	local now = os.clock()
	for _, trap in traps do
		if now >= trap.ExpiresAt then
			removeTrap(trap)
			continue
		end
		for _, player in Players:GetPlayers() do
			if player.UserId ~= trap.OwnerUserId and not player:GetAttribute("Stunned") then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local offset = root.Position - trap.Position
					local flat = Vector3.new(offset.X, 0, offset.Z)
					if flat.Magnitude <= Trap.TriggerRadius and offset.Y >= -1 and offset.Y <= Trap.VictimHeight then
						removeTrap(trap)
						TrapService.Stun(player, if flat.Magnitude > 0.1 then flat.Unit else nil)
						local owner = Players:GetPlayerByUserId(trap.OwnerUserId)
						if owner then
							local ownerData = DataService.Get(owner)
							if ownerData then
								ownerData.Stats.TrapHits += 1
							end
							Remotes.Notify:FireClient(owner, Strings.TrapTriggered)
						end
						break
					end
				end
			end
		end
	end
end

function TrapService.ClearAll()
	for _, trap in traps do
		removeTrap(trap)
	end
end

function TrapService.Start()
	local runtime = workspace:WaitForChild(Balance.Map.RuntimeFolder)
	folder = runtime:FindFirstChild("Traps")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Traps"
		folder.Parent = runtime
	end
	folder:ClearAllChildren()

	PlayerStateService.ItemHandlers[ITEM_ID] = place
	GachaService.Restocked:Connect(TrapService.ClearAll)
	Players.PlayerRemoving:Connect(function(player)
		for _, trap in traps do
			if trap.OwnerUserId == player.UserId then
				removeTrap(trap)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Trap.CheckSeconds)
			check()
		end
	end)
end

return TrapService
