-- Четыре физические клешни, по одной на пульт (Claw_East <-> Station_East и т.д.).
-- Все четыре игрока играют одновременно, каждая клешня ездит по всей куче.
-- Сервер ведет ладонь через AlignPosition (клешни толкают капсулы и друг друга),
-- пальцы крутятся на Motor6D. Игра: пульт (ProximityPrompt) -> прицеливание до AttemptSeconds ->
-- спуск до упора -> сжатие -> подъем (шанс удержания GrabHoldChance) -> к своей дыре -> разжатие.
-- Ложе квадратное, своя дыра стоит в его углу над шахтой своего лотка, выигрыш появляется в лотке этого пульта.
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
local claws = {} -- [stationName] = claw
local clawByPlayer = {} -- [player] = claw, пока у игрока идет сессия

--[[ claw = {
	Station, Palm, Align, Fingers = { { Motor, BaseC0, Sign, Tips } }, FingerAngle, FingerTarget,
	TrolleyParts = { { Part, CFrame } }, Cable, CableCFrame, DrumBottom, PalmStart, TopY, MinY,
	Prompt, State, Session = { Player, U, V, Input, EndsAt, CloseAt?, ReleaseAt?, HadCapsule? },
	Target, Grabbed = { Capsule, Weld, SlipAt }, StallSince, LastPlayer, AwardUntil, Awarded,
} ]]

local function now()
	return workspace:GetServerTimeNow()
end

local function planar(u: number, v: number, y: number): Vector3
	local center = GachaService.BedCenter()
	return Vector3.new(center.X, y, center.Z) + axisU * u + axisV * v
end

local function uvOf(position: Vector3): (number, number)
	local delta = position - GachaService.BedCenter()
	return delta:Dot(axisU), delta:Dot(axisV)
end

local function holeUV(claw): (number, number)
	return uvOf(GachaService.HoleCenter(claw.Station))
end

local function setPhase(claw, phase: string)
	claw.State = phase
	if claw.Session and claw.Session.Player then
		claw.Session.Player:SetAttribute("ClawPhase", phase)
	end
end

-- Собирает клешню художника в физическую сборку (только при запуске)
local function buildRig(claw, model: Model)
	local palm = model:WaitForChild("ClawPalm")
	claw.Palm = palm
	local display = model:FindFirstChild("ClawDisplayCapsule")
	if display then
		display:Destroy()
	end
	local trolley = model:FindFirstChild("Trolley")
	claw.Cable = model:FindFirstChild("HoistCable")
	if claw.Cable then
		claw.CableCFrame = claw.Cable.CFrame - claw.Cable.Position
	end
	local function isStatic(part: Instance): boolean
		return part == claw.Cable or (trolley ~= nil and part:IsDescendantOf(trolley))
	end

	claw.Fingers = {}
	for _, finger in model:GetChildren() do
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
			table.insert(claw.Fingers, { Motor = motor, BaseC0 = motor.C0, Sign = sign, Tips = tips })
		end
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= palm and not isStatic(part) then
			local owner = part:FindFirstAncestorWhichIsA("Model")
			if not (owner and owner ~= model and owner.Name:match("^Finger")) then
				part.Massless = true
				part.CanCollide = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = palm
				weld.Part1 = part
				weld.Parent = palm
			end
		end
	end
	palm.CanCollide = true
	palm.CustomPhysicalProperties = PhysicalProperties.new(2, 0.5, 0)

	local attachment = Instance.new("Attachment")
	attachment.Name = "ClawDrive"
	attachment.Parent = palm
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxForce = Claw.MaxForce
	align.Responsiveness = Claw.Responsiveness
	align.MaxVelocity = Claw.MoveSpeed
	align.Position = palm.Position
	align.Parent = palm
	claw.Align = align
	local orientation = Instance.new("AlignOrientation")
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.RigidityEnabled = true
	orientation.CFrame = palm.CFrame - palm.Position
	orientation.Parent = palm

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not isStatic(part) then
			part.Anchored = false
		end
	end
	palm:SetNetworkOwner(nil)
	claw.PalmStart = palm.Position
	claw.TopY = palm.Position.Y
	claw.MinY = GachaService.BedCenter().Y + Claw.ClawReach

	claw.TrolleyParts = {}
	if trolley then
		for _, part in trolley:GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(claw.TrolleyParts, { Part = part, CFrame = part.CFrame })
			end
		end
	end
	local drum = trolley and trolley:FindFirstChild("HoistDrum")
	claw.DrumBottom = if drum then drum.Position.Y - drum.Size.X / 2 else claw.TopY + 4
end

local function updateGantry(claw)
	local delta = claw.Palm.Position - claw.PalmStart
	local shift = axisU * delta:Dot(axisU) + axisV * delta:Dot(axisV)
	for _, entry in claw.TrolleyParts do
		entry.Part.CFrame = entry.CFrame + shift
	end
	local cable = claw.Cable
	if cable then
		local top = claw.DrumBottom
		local bottom = claw.Palm.Position.Y + 1.3
		local length = math.max(0.2, top - bottom)
		cable.Size = Vector3.new(length, cable.Size.Y, cable.Size.Z)
		cable.CFrame = CFrame.new(claw.Palm.Position.X, (top + bottom) / 2, claw.Palm.Position.Z) * claw.CableCFrame
	end
end

local function updateFingers(claw, dt: number)
	local step = math.rad(Claw.FingerSpeedDeg) * dt
	claw.FingerAngle += math.clamp(claw.FingerTarget - claw.FingerAngle, -step, step)
	for _, finger in claw.Fingers do
		finger.Motor.C0 = finger.BaseC0 * CFrame.Angles(claw.FingerAngle * finger.Sign, 0, 0)
	end
end

local function setFingersOpen(claw, open: boolean)
	claw.FingerTarget = if open then math.rad(Claw.FingerOpenDeg) else 0
end

local function grabPoint(claw): Vector3
	local sum = Vector3.zero
	local count = 0
	for _, finger in claw.Fingers do
		for _, tip in finger.Tips do
			sum += tip.Position
			count += 1
		end
	end
	local tips = if count > 0 then sum / count else claw.Palm.Position - Vector3.new(0, Claw.ClawReach - 1, 0)
	return tips + Vector3.new(0, 1, 0)
end

local function tryGrab(claw)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { GachaService.Machine():WaitForChild("06_Capsules") }
	local point = grabPoint(claw)
	local best, bestDistance = nil, math.huge
	for _, part in workspace:GetPartBoundsInRadius(point, Claw.GrabRadius, params) do
		local capsule = GachaService.CapsuleOf(part)
		-- капсулу, которую уже держит другая клешня, не перехватываем
		if capsule and capsule.PrimaryPart and not capsule:GetAttribute("Grabbed") then
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
	best:SetAttribute("LastClaw", claw.Station)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = claw.Palm
	weld.Part1 = best.PrimaryPart
	weld.Parent = claw.Palm
	-- Сервер бросает шанс удержания: при неудаче капсула выскользнет на подъеме
	local slipAt = nil
	if random:NextNumber() > Gacha.GrabHoldChance then
		slipAt = claw.MinY + (claw.TopY - claw.MinY) * random:NextNumber(0.3, 0.8)
	end
	claw.Grabbed = { Capsule = best, Weld = weld, SlipAt = slipAt }
end

local function release(claw)
	local grabbed = claw.Grabbed
	if grabbed then
		if grabbed.Weld then
			grabbed.Weld:Destroy()
		end
		if grabbed.Capsule.Parent then
			grabbed.Capsule:SetAttribute("Grabbed", nil)
		end
		claw.Grabbed = nil
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

local function endSession(claw)
	local session = claw.Session
	if session and session.Player then
		local player = session.Player
		freeze(player, false)
		player:SetAttribute("ClawActive", false)
		player:SetAttribute("ClawPhase", nil)
		player:SetAttribute("ClawCooldownUntil", now() + Gacha.AttemptCooldownSeconds)
		if clawByPlayer[player] == claw then
			clawByPlayer[player] = nil
		end
	end
	claw.Session = nil
	claw.State = "Idle"
	claw.AwardUntil = os.clock() + Claw.AwardWindowSeconds
	if claw.Prompt then
		claw.Prompt.Enabled = true
	end
end

local function startDrop(claw)
	if claw.State ~= "Aiming" then
		return
	end
	claw.Session.Input = Vector2.zero
	setFingersOpen(claw, true)
	claw.StallSince = nil
	setPhase(claw, "Lowering")
end

local function startSession(player: Player, claw, station: Model)
	local operator = station:FindFirstChild("OperatorAnchor", true)
	local character = player.Character
	if operator and character then
		local center = GachaService.BedCenter()
		local position = operator.WorldPosition + Vector3.new(0, 3, 0)
		character:PivotTo(CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)))
	end
	freeze(player, true)
	local u, v = uvOf(claw.Palm.Position)
	claw.Session = { Player = player, U = u, V = v, Input = Vector2.zero, EndsAt = now() + Gacha.AttemptSeconds }
	claw.LastPlayer = player
	claw.Awarded = false
	clawByPlayer[player] = claw
	player:SetAttribute("ClawStation", claw.Station)
	player:SetAttribute("ClawEndsAt", claw.Session.EndsAt)
	player:SetAttribute("ClawActive", true)
	claw.Prompt.Enabled = false
	setFingersOpen(claw, false)
	setPhase(claw, "Aiming")
end

local function onPrompt(player: Player, claw, station: Model)
	if clawByPlayer[player] then
		return
	end
	if claw.State ~= "Idle" then
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
	startSession(player, claw, station)
end

-- Прицел не выходит за квадрат AimHalf вокруг центра ложа (стороны ложа идут по осям мира)
local function clampAim(u: number, v: number): (number, number)
	local center = GachaService.BedCenter()
	local point = planar(u, v, center.Y)
	local x = math.clamp(point.X - center.X, -Claw.AimHalf, Claw.AimHalf)
	local z = math.clamp(point.Z - center.Z, -Claw.AimHalf, Claw.AimHalf)
	return uvOf(Vector3.new(center.X + x, center.Y, center.Z + z))
end

-- Не даем прицелу заехать в другую клешню ближе ClawSeparation
local function keepApart(claw, u: number, v: number): (number, number)
	for _, other in claws do
		if other ~= claw then
			local ou, ov = uvOf(other.Palm.Position)
			local du, dv = u - ou, v - ov
			local distance = math.sqrt(du * du + dv * dv)
			if distance < Claw.ClawSeparation then
				if distance < 1e-3 then
					du, dv, distance = 1, 0, 1
				end
				u = ou + du / distance * Claw.ClawSeparation
				v = ov + dv / distance * Claw.ClawSeparation
			end
		end
	end
	return u, v
end

local function step(claw, dt: number)
	updateFingers(claw, dt)
	local palmPosition = claw.Palm.Position
	local session = claw.Session
	local state = claw.State

	if state == "Idle" then
		-- без игрока клешня висит над своей дырой
		local u, v = holeUV(claw)
		claw.Target = planar(u, v, claw.TopY)
		claw.Align.MaxVelocity = Claw.MoveSpeed
	elseif state == "Aiming" then
		local input = session.Input
		local u = session.U + input.X * Claw.MoveSpeed * dt
		local v = session.V + input.Y * Claw.MoveSpeed * dt
		u, v = keepApart(claw, clampAim(u, v))
		u, v = clampAim(u, v)
		session.U, session.V = u, v
		claw.Target = planar(u, v, claw.TopY)
		claw.Align.MaxVelocity = Claw.MoveSpeed
		if now() >= session.EndsAt or not session.Player or not session.Player.Parent then
			startDrop(claw)
		end
	elseif state == "Lowering" then
		claw.Align.MaxVelocity = Claw.LowerSpeed
		local target = claw.Target
		local y = math.max(claw.MinY, target.Y - Claw.LowerSpeed * dt)
		claw.Target = Vector3.new(target.X, y, target.Z)
		local lag = palmPosition.Y - y
		if lag > Claw.StallDistance then
			claw.StallSince = claw.StallSince or os.clock()
		else
			claw.StallSince = nil
		end
		local stalled = claw.StallSince and os.clock() - claw.StallSince > Claw.StallSeconds
		if y <= claw.MinY and lag < 0.3 or stalled then
			claw.Target = Vector3.new(target.X, palmPosition.Y, target.Z)
			setFingersOpen(claw, false)
			session.CloseAt = os.clock() + Claw.CloseSeconds
			setPhase(claw, "Closing")
		end
	elseif state == "Closing" then
		if os.clock() >= session.CloseAt then
			tryGrab(claw)
			setPhase(claw, "Raising")
		end
	elseif state == "Raising" then
		claw.Align.MaxVelocity = Claw.RaiseSpeed
		local target = claw.Target
		claw.Target = Vector3.new(target.X, math.min(claw.TopY, target.Y + Claw.RaiseSpeed * dt), target.Z)
		local grabbed = claw.Grabbed
		if grabbed and grabbed.SlipAt and palmPosition.Y >= grabbed.SlipAt then
			setFingersOpen(claw, true)
			release(claw)
		end
		if palmPosition.Y >= claw.TopY - 0.3 then
			setPhase(claw, "ToHole")
		end
	elseif state == "ToHole" then
		claw.Align.MaxVelocity = Claw.MoveSpeed
		local holeU, holeV = holeUV(claw)
		local du, dv = holeU - session.U, holeV - session.V
		local distance = math.sqrt(du * du + dv * dv)
		local move = Claw.MoveSpeed * dt
		if distance <= move then
			session.U, session.V = holeU, holeV
		else
			session.U += du / distance * move
			session.V += dv / distance * move
		end
		claw.Target = planar(session.U, session.V, claw.TopY)
		local target = claw.Target
		local miss = (Vector3.new(palmPosition.X, 0, palmPosition.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude
		-- страховка: если клешню что-то держит почти над дырой, разжимаемся через ArriveTimeout
		if distance <= move and miss < Claw.ArriveTolerance then
			session.NearHoleSince = session.NearHoleSince or os.clock()
		else
			session.NearHoleSince = nil
		end
		local stuck = session.NearHoleSince and os.clock() - session.NearHoleSince > Claw.ArriveTimeout
		if distance <= move and miss < 0.4 or stuck then
			setFingersOpen(claw, true)
			local hadCapsule = claw.Grabbed ~= nil
			release(claw)
			session.ReleaseAt = os.clock() + Claw.ReleaseSeconds
			session.HadCapsule = hadCapsule
			setPhase(claw, "Releasing")
		end
	elseif state == "Releasing" then
		if os.clock() >= session.ReleaseAt then
			if not session.HadCapsule and session.Player and session.Player.Parent then
				Remotes.Notify:FireClient(session.Player, Strings.ClawMiss)
			end
			setFingersOpen(claw, false)
			endSession(claw)
		end
	end

	if claw.Target then
		claw.Align.Position = claw.Target
	end
	updateGantry(claw)
end

-- Выигрыш игроку клешни claw, если он сейчас играет (или только что закончил) и еще не получил попс
local function tryAward(claw, rarityId, mutationId, familyId): boolean
	if not claw then
		return false
	end
	local player = claw.LastPlayer
	local inGame = claw.Session ~= nil or os.clock() < claw.AwardUntil
	if inGame and not claw.Awarded and player and player.Parent then
		claw.Awarded = true
		GachaService.Award(player, rarityId, claw.Station, mutationId, familyId)
		return true
	end
	return false
end

function ClawService.Start()
	axisU, axisV = GachaService.Axes()
	local machine = GachaService.Machine()
	local assembly = machine:WaitForChild("05_ClawAssembly")

	for _, station in machine:WaitForChild("07_ControlStations"):GetChildren() do
		local suffix = station.Name:match("^Station_(.+)$")
		local model = suffix and assembly:FindFirstChild("Claw_" .. suffix)
		if not model or not GachaService.HoleCenter(station.Name) then
			warn("[ClawService] нет клешни или дыры для пульта", station.Name)
			continue
		end
		local claw = {
			Station = station.Name,
			State = "Idle",
			FingerAngle = 0,
			FingerTarget = 0,
			AwardUntil = 0,
			Awarded = false,
		}
		buildRig(claw, model)
		claws[station.Name] = claw

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
				onPrompt(player, claw, station)
			end)
			claw.Prompt = prompt
		end
	end

	Remotes.ClawInput.OnServerEvent:Connect(function(player, kind, a, b)
		local claw = clawByPlayer[player]
		if not claw or not claw.Session or claw.Session.Player ~= player then
			return
		end
		if kind == "move" and claw.State == "Aiming" then
			if type(a) ~= "number" or type(b) ~= "number" or a ~= a or b ~= b then
				return
			end
			local input = Vector2.new(math.clamp(a, -1, 1), math.clamp(b, -1, 1))
			if input.Magnitude > 1 then
				input = input.Unit
			end
			claw.Session.Input = input
		elseif kind == "drop" then
			startDrop(claw)
		end
	end)

	-- Капсула в дыре: выигрыш хозяину дыры, а если он не играет, тому, чья клешня ее последней брала
	GachaService.Collected:Connect(function(rarityId, mutationId, familyId, holeStation, lastClaw)
		if tryAward(claws[holeStation], rarityId, mutationId, familyId) then
			return
		end
		if lastClaw and lastClaw ~= holeStation then
			tryAward(claws[lastClaw], rarityId, mutationId, familyId)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local claw = clawByPlayer[player]
		if claw and claw.Session and claw.Session.Player == player then
			claw.Session.Player = nil
		end
		clawByPlayer[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		for _, claw in claws do
			step(claw, dt)
		end
	end)
end

return ClawService
