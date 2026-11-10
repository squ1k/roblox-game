-- Поза переноса попса: у всех игроков с атрибутом Carrying правое плечо каждый кадр получает
-- Transform "рука согнута перед собой" (поверх анимаций), с легким покачиванием при ходьбе.
-- Работает и с Motor6D, и с новыми суставами AnimationConstraint. Каждый клиент рисует позу
-- всех несущих, поэтому ее видят все. Можно заменить на загруженную анимацию
-- (Balance.CakePop.CarryAnimationId).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Balance"))

local Pop = Balance.CakePop

local blend = {} -- [player] = 0..1 насколько рука поднята

local function shoulderOf(character: Model?)
	if not character then
		return nil
	end
	return character:FindFirstChild("RightShoulder", true) or character:FindFirstChild("Right Shoulder", true)
end

RunService.Stepped:Connect(function(_, dt)
	local t = os.clock()
	for _, player in Players:GetPlayers() do
		local carrying = player:GetAttribute("Carrying") == true
		local value = blend[player] or 0
		local step = dt / Pop.CarryBlendSeconds
		value = math.clamp(value + (if carrying then step else -step), 0, 1)
		blend[player] = if value > 0 then value else nil
		if value > 0 then
			local character = player.Character
			local shoulder = shoulderOf(character)
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if shoulder and (shoulder:IsA("Motor6D") or shoulder:IsA("AnimationConstraint")) then
				local moving = if humanoid then math.min(humanoid.MoveDirection.Magnitude, 1) else 0
				local angle = Pop.HoldArmAngle * value
					+ math.sin(t * Pop.CarrySwaySpeed) * Pop.CarrySwayDeg * moving * value
				if shoulder.Name == "Right Shoulder" then
					shoulder.Transform = CFrame.Angles(0, 0, math.rad(angle)) -- R6
				else
					shoulder.Transform = CFrame.Angles(math.rad(angle), 0, 0) -- R15
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	blend[player] = nil
end)
