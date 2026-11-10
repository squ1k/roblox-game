-- Одна физическая клешня. Сервер ведет ладонь через AlignPosition (клешня толкает капсулы),
-- пальцы крутятся на Motor6D. Игра: пульт (ProximityPrompt) -> прицеливание до AttemptSeconds ->
-- спуск до упора -> сжатие -> подъем (шанс удержания GrabHoldChance) -> к дыре -> разжатие.
-- Клиент только присылает направление и "drop" через ClawInput.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Strings = require(Config:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local GachaService = require(script.Parent:WaitForChild("GachaService"))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))

local Claw = Balance.Claw
local Gacha = Balance.Gacha

local ClawService = {}

local random = Random.new()
local axisU, axisV
local palm: BasePart
local align: AlignPosition
local fingers = {} -- { Motor, BaseC0, Sign, Tips = { BasePart } }
local fingerAngle = 0
local fingerTarget = 0
local trolleyParts = {} -- двигаются вместе с клешней по U и V
local railParts = {} -- двигаются только по U
local cable, cableCFrame, drumBottomOffset
local palmStart: Vector3
local topY, minY
local prompts = {}

local state = "Idle"
local session = nil -- { Player, Station, U, V, Input = Vector2, EndsAt }
local target: Vector3
local grabbed = nil -- { Capsule, Weld, SlipAt }
local stallSince = nil
local lastPlayer = nil
local lastStation = nil
local awardUntil = 0 -- капсула в дыре засчитывается, пока идет игра и AwardWindowSeconds после нее
local awardedThisGame = false -- за одну попытку выдается не больше одного попса

local function now()
	return workspace:GetServerTimeNow()
end

local function planar(u: number, v: number, y: number): Vector3
	local center = GachaService.BedCenter()
	return Vector3.new(center.X, y, center.Z) + axisU * u + axisV * v
end

local function holeUV(): (number, number)
	local delta = GachaService.HoleCenter() - GachaService.BedCenter()
	return delta:Dot(axisU), delta:Dot(axisV)
end

local function setPhase(phase: string)
	state = phase
	if session and session.Player then
		session.Player:SetAttribute("ClawPhase", phase)
	end
end

-- Собирает клешню художника в физическую сборку (только при запуске)
local function buildRig(machine: Model)
	local assembly = machine:WaitForChild("05_ClawAssembly")
	palm = assembly:WaitForChild("ClawPalm")
	local display = assembly:FindFirstChild("ClawDisplayCapsule")
	if display then
		display:Destroy()
	end
	cable = assembly:FindFirstChild("HoistCable")
	if cable then
		cable.Parent = machine:WaitForChild("04_Gantry")
		cableCFrame = cable.CFrame - cable.Position
	end

	for _, finger in assembly:GetChildren() do
		if finger:IsA("Model") and finger.Name:match("^Finger") then
			-- Шарнир пальца = верхний HingeBarrel
			local root
			for _, part in finger:GetChildren() do
				if
					part:IsA("BasePart")
					and part.Name == "HingeBarrel"
					and (not root or part.Position.Y > root.Position.Y)
				then
					root = part
				end
			end
			local tips = {}
			for _, part in finger:GetDescendants() do
				if part:IsA("BasePart") then
					part.Massless = true
					part.CanCollide = part.Name == "InwardTip" or part.Name == "LowerHook" or part.Name == "UpperArm"
					if part.Name == "InwardTip" then
						table.insert(tips, part)
					end
					if part ~= root then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = root
						weld.Part1 = part
						weld.Parent = root
					end
				end
			end
			local motor = Instance.new("Motor6D")
			motor.Name = "FingerHinge"
			motor.Part0 = palm
			motor.Part1 = root
			motor.C0 = palm.CFrame:ToObjectSpace(root.CFrame)
			motor.C1 = CFrame.identity
			motor.Parent = palm
			-- Знак поворота, при котором кончик уходит от оси ладони (раскрытие)
			local tip = tips[1]
			local sign = 1
			if tip then
				local tipLocal = root.CFrame:ToObjectSpace(tip.CFrame)
				local function radiusAt(angle)
					local world = palm.CFrame * motor.C0 * CFrame.Angles(angle, 0, 0) * tipLocal
					local offset = world.Position - palm.Position
					return Vector3.new(offset.X, 0, offset.Z).Magnitude
				end
				sign = if radiusAt(math.rad(20)) > radiusAt(math.rad(-20)) then 1 else -1
			end
			table.insert(fingers, { Motor = motor, BaseC0 = motor.C0, Sign = sign, Tips = tips })
		end
	end

	for _, part in assembly:GetDescendants() do
		if
			part:IsA("BasePart")
			and part ~= palm
			and not part:FindFirstAncestorWhichIsA("Model").Name:match("^Finger")
		then
			part.Massless = true
			part.CanCollide = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = palm
			weld.Part1 = part
			weld.Parent = palm
		end
	end
	palm.CanCollide = true
	palm.CustomPhysicalProperties = PhysicalProperties.new(2, 0.5, 0)

	local attachment = Instance.new("Attachment")
	attachment.Name = "ClawDrive"
	attachment.Parent = palm
	align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxForce = Claw.MaxForce
	align.Responsiveness = Claw.Responsiveness
	align.MaxVelocity = Claw.MoveSpeed
	align.Position = palm.Position
	align.Parent = palm
	local orientation = Instance.new("AlignOrientation")
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.RigidityEnabled = true
	orientation.CFrame = palm.CFrame - palm.Position
	orientation.Parent = palm

	for _, part in assembly:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	palm:SetNetworkOwner(nil)
	palmStart = palm.Position
	topY = palm.Position.Y
	minY = GachaService.BedCenter().Y + Claw.ClawReach

	local gantry = machine:WaitForChild("04_Gantry")
	for _, part in gantry:GetChildren() do
		if part:IsA("BasePart") then
			if part.Name == "TrolleyBody" or part.Name == "TrolleyCreamCap" or part.Name == "HoistDrum" then
				table.insert(trolleyParts, { Part = part, CFrame = part.CFrame })
			elseif part.Name == "MovingZGuideRail" or part.Name == "XSlidingBearing" or part.Name == "BearingWheel" then
				table.insert(railParts, { Part = part, CFrame = part.CFrame })
			end
		end
	end
	local drum = gantry:FindFirstChild("HoistDrum")
	drumBottomOffset = if drum then drum.Position.Y - drum.Size.X / 2 else topY + 4
end

local function updateGantry()
	local delta = palm.Position - palmStart
	local du, dv = delta:Dot(axisU), delta:Dot(axisV)
	local shiftUV = axisU * du + axisV * dv
	for _, entry in trolleyParts do
		entry.Part.CFrame = entry.CFrame + shiftUV
	end
	for _, entry in railParts do
		entry.Part.CFrame = entry.CFrame + axisU * du
	end
	if cable then
		local top = drumBottomOffset
		local bottom = palm.Position.Y + 1.3
		local length = math.max(0.2, top - bottom)
		cable.Size = Vector3.new(length, cable.Size.Y, cable.Size.Z)
		cable.CFrame = CFrame.new(palm.Position.X, (top + bottom) / 2, palm.Position.Z) * cableCFrame
	end
end

local function updateFingers(dt: number)
	local step = math.rad(Claw.FingerSpeedDeg) * dt
	fingerAngle += math.clamp(fingerTarget - fingerAngle, -step, step)
	for _, finger in fingers do
		finger.Motor.C0 = finger.BaseC0 * CFrame.Angles(fingerAngle * finger.Sign, 0, 0)
	end
end

local function setFingersOpen(open: boolean)
	fingerTarget = if open then math.rad(Claw.FingerOpenDeg) else 0
end

local function grabPoint(): Vector3
	local sum = Vector3.zero
	local count = 0
	for _, finger in fingers do
		for _, tip in finger.Tips do
			sum += tip.Position
			count += 1
		end
	end
	local tips = if count > 0 then sum / count else palm.Position - Vector3.new(0, Claw.ClawReach - 1, 0)
	return tips + Vector3.new(0, 1, 0)
end

local function tryGrab()
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { GachaService.Machine():WaitForChild("06_Capsules") }
	local point = grabPoint()
	local best, bestDistance = nil, math.huge
	for _, part in workspace:GetPartBoundsInRadius(point, Claw.GrabRadius, params) do
		local capsule = GachaService.CapsuleOf(part)
		if capsule and capsule.PrimaryPart then
			local distance = (capsule.PrimaryPart.Position - point).Magnitude
			if distance < bestDistance then
				best, bestDistance = capsule, distance
			end
		end
	end
	if not best then
		return
	end
	best:SetAttribute("Grabbed", true)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = palm
	weld.Part1 = best.PrimaryPart
	weld.Parent = palm
	-- Сервер бросает шанс удержания: при неудаче капсула выскользнет на подъеме
	local slipAt = nil
	if random:NextNumber() > Gacha.GrabHoldChance then
		slipAt = minY + (topY - minY) * random:NextNumber(0.3, 0.8)
	end
	grabbed = { Capsule = best, Weld = weld, SlipAt = slipAt }
end

local function release()
	if grabbed then
		if grabbed.Weld then
			grabbed.Weld:Destroy()
		end
		if grabbed.Capsule.Parent then
			grabbed.Capsule:SetAttribute("Grabbed", nil)
		end
		grabbed = nil
	end
end

local function freeze(player: Player, frozen: boolean)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if frozen then
		humanoid:SetAttribute("SavedWalkSpeed", humanoid.WalkSpeed)
		humanoid:SetAttribute("SavedJumpPower", humanoid.JumpPower)
		humanoid:SetAttribute("SavedJumpHeight", humanoid.JumpHeight)
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	else
		humanoid.WalkSpeed = humanoid:GetAttribute("SavedWalkSpeed") or Balance.Player.BaseSpeed
		humanoid.JumpPower = humanoid:GetAttribute("SavedJumpPower") or 50
		humanoid.JumpHeight = humanoid:GetAttribute("SavedJumpHeight") or 7.2
	end
end

local function setPromptsEnabled(enabled: boolean)
	for _, prompt in prompts do
		prompt.Enabled = enabled
	end
end

local function endSession()
	if session and session.Player then
		local player = session.Player
		freeze(player, false)
		player:SetAttribute("ClawActive", false)
		player:SetAttribute("ClawPhase", nil)
		player:SetAttribute("ClawCooldownUntil", now() + Gacha.AttemptCooldownSeconds)
	end
	session = nil
	state = "Idle"
	awardUntil = os.clock() + Claw.AwardWindowSeconds
	setPromptsEnabled(true)
end

local function startDrop()
	if state ~= "Aiming" then
		return
	end
	session.Input = Vector2.zero
	setFingersOpen(true)
	stallSince = nil
	setPhase("Lowering")
end

local function startSession(player: Player, station: Model)
	local operator = station:FindFirstChild("OperatorAnchor", true)
	local character = player.Character
	if operator and character then
		local center = GachaService.BedCenter()
		local position = operator.WorldPosition + Vector3.new(0, 3, 0)
		character:PivotTo(CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)))
	end
	freeze(player, true)
	local u, v = holeUV()
	session = {
		Player = player,
		Station = station.Name,
		U = u,
		V = v,
		Input = Vector2.zero,
		EndsAt = now() + Gacha.AttemptSeconds,
	}
	lastPlayer = player
	lastStation = station.Name
	awardedThisGame = false
	player:SetAttribute("ClawStation", station.Name)
	player:SetAttribute("ClawEndsAt", session.EndsAt)
	player:SetAttribute("ClawActive", true)
	setPromptsEnabled(false)
	setFingersOpen(false)
	setPhase("Aiming")
end

local function onPrompt(player: Player, station: Model)
	if state ~= "Idle" then
		Remotes.Notify:FireClient(player, Strings.ClawBusy)
		return
	end
	local cooldown = (player:GetAttribute("ClawCooldownUntil") or 0) - now()
	if cooldown > 0 then
		Remotes.Notify:FireClient(player, string.format(Strings.ClawCooldown, math.ceil(cooldown)))
		return
	end
	if PlayerStateService.IsBusy(player) then
		Remotes.Notify:FireClient(player, Strings.ClawCarrying)
		return
	end
	startSession(player, station)
end

local function step(dt: number)
	updateFingers(dt)
	local palmPosition = palm.Position

	if state == "Aiming" then
		local input = session.Input
		local u = session.U + input.X * Claw.MoveSpeed * dt
		local v = session.V + input.Y * Claw.MoveSpeed * dt
		local length = math.sqrt(u * u + v * v)
		if length > Claw.AimRadius then
			u, v = u / length * Claw.AimRadius, v / length * Claw.AimRadius
		end
		session.U, session.V = u, v
		target = planar(u, v, topY)
		align.MaxVelocity = Claw.MoveSpeed
		if now() >= session.EndsAt or not session.Player or not session.Player.Parent then
			startDrop()
		end
	elseif state == "Lowering" then
		align.MaxVelocity = Claw.LowerSpeed
		local y = math.max(minY, target.Y - Claw.LowerSpeed * dt)
		target = Vector3.new(target.X, y, target.Z)
		local lag = palmPosition.Y - target.Y
		if lag > Claw.StallDistance then
			stallSince = stallSince or os.clock()
		else
			stallSince = nil
		end
		local stalled = stallSince and os.clock() - stallSince > Claw.StallSeconds
		if y <= minY and lag < 0.3 or stalled then
			target = Vector3.new(target.X, palmPosition.Y, target.Z)
			setFingersOpen(false)
			session.CloseAt = os.clock() + Claw.CloseSeconds
			setPhase("Closing")
		end
	elseif state == "Closing" then
		if os.clock() >= session.CloseAt then
			tryGrab()
			setPhase("Raising")
		end
	elseif state == "Raising" then
		align.MaxVelocity = Claw.RaiseSpeed
		target = Vector3.new(target.X, math.min(topY, target.Y + Claw.RaiseSpeed * dt), target.Z)
		if grabbed and grabbed.SlipAt and palmPosition.Y >= grabbed.SlipAt then
			setFingersOpen(true)
			release()
		end
		if palmPosition.Y >= topY - 0.3 then
			setPhase("ToHole")
		end
	elseif state == "ToHole" then
		align.MaxVelocity = Claw.MoveSpeed
		local holeU, holeV = holeUV()
		local du, dv = holeU - session.U, holeV - session.V
		local distance = math.sqrt(du * du + dv * dv)
		local move = Claw.MoveSpeed * dt
		if distance <= move then
			session.U, session.V = holeU, holeV
		else
			session.U += du / distance * move
			session.V += dv / distance * move
		end
		target = planar(session.U, session.V, topY)
		if
			distance <= move
			and (Vector3.new(palmPosition.X, 0, palmPosition.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude
				< 0.4
		then
			setFingersOpen(true)
			local hadCapsule = grabbed ~= nil
			release()
			session.ReleaseAt = os.clock() + Claw.ReleaseSeconds
			session.HadCapsule = hadCapsule
			setPhase("Releasing")
		end
	elseif state == "Releasing" then
		if os.clock() >= session.ReleaseAt then
			if not session.HadCapsule and session.Player and session.Player.Parent then
				Remotes.Notify:FireClient(session.Player, Strings.ClawMiss)
			end
			setFingersOpen(false)
			endSession()
		end
	end

	if target then
		align.Position = target
	end
	updateGantry()
end

function ClawService.Start()
	axisU, axisV = GachaService.Axes()
	local machine = GachaService.Machine()
	buildRig(machine)
	target = planar(holeUV(), select(2, holeUV()), topY)

	for _, station in machine:WaitForChild("07_ControlStations"):GetChildren() do
		local display = station:FindFirstChild("ControlDisplay") or station:FindFirstChildWhichIsA("BasePart")
		if display then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "ClawPrompt"
			prompt.ActionText = Strings.ClawPlay
			prompt.ObjectText = Strings.ClawObject
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.Parent = display
			prompt.Triggered:Connect(function(player)
				onPrompt(player, station)
			end)
			table.insert(prompts, prompt)
		end
	end

	Remotes.ClawInput.OnServerEvent:Connect(function(player, kind, a, b)
		if not session or session.Player ~= player then
			return
		end
		if kind == "move" and state == "Aiming" then
			if type(a) ~= "number" or type(b) ~= "number" or a ~= a or b ~= b then
				return
			end
			local input = Vector2.new(math.clamp(a, -1, 1), math.clamp(b, -1, 1))
			if input.Magnitude > 1 then
				input = input.Unit
			end
			session.Input = input
		elseif kind == "drop" then
			startDrop()
		end
	end)

	-- Капсула в дыре: выигрыш тому, кто играл последним
	GachaService.Collected:Connect(function(rarityId, mutationId, familyId)
		local player = lastPlayer
		local inGame = session ~= nil or os.clock() < awardUntil
		if inGame and not awardedThisGame and player and player.Parent then
			awardedThisGame = true
			GachaService.Award(player, rarityId, lastStation, mutationId, familyId)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if session and session.Player == player then
			session.Player = nil
		end
	end)

	RunService.Heartbeat:Connect(step)
end

return ClawService
