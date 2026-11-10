-- Локальная видимость объектов мира: пока в руках попс, кнопки "Поднять" у других попсов скрыты;
-- кнопки объектов чужих баз не показываются;
-- свои банано-капканы игрок видит лучше, чем чужие (в пшенице они почти прозрачные).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Balance"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))

local player = Players.LocalPlayer
local runtime = workspace:WaitForChild(Balance.Map.RuntimeFolder)

local function refreshPrompt(prompt: ProximityPrompt)
	local model = prompt:FindFirstAncestorOfClass("Model")
	local free = model ~= nil and model:GetAttribute("CarriedBy") == nil
	local want = free and player:GetAttribute("Carrying") ~= true
	if prompt.Enabled ~= want then
		prompt.Enabled = want
	end
end

local function watchPrompt(prompt: ProximityPrompt)
	-- Сервер тоже меняет Enabled; после каждой репликации применяем свое правило заново
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		task.defer(refreshPrompt, prompt)
	end)
	local model = prompt:FindFirstAncestorOfClass("Model")
	if model then
		model:GetAttributeChangedSignal("CarriedBy"):Connect(function()
			refreshPrompt(prompt)
		end)
	end
	refreshPrompt(prompt)
end

local function styleTrap(model: Model)
	if model:GetAttribute("OwnerUserId") ~= player.UserId then
		return
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = 1 - Balance.BananaTrap.OwnOpacity
		end
	end
end

-- Кнопки объектов чужих баз (пьедесталы, Холодильник, шкаф, Алтарь, лежак) у себя скрываем
local function baseIndexOf(prompt: ProximityPrompt): number?
	local node = prompt.Parent
	while node and node ~= runtime do
		local index = node:GetAttribute("BaseIndex")
		if index then
			return index
		end
		node = node.Parent
	end
	return nil
end

local function watchBasePrompt(prompt: ProximityPrompt)
	local index = baseIndexOf(prompt)
	if not index then
		return
	end
	local function apply()
		local settings = ClientState.Profile and ClientState.Profile.Settings
		local showOthers = settings and settings.ShowOtherPrompts == true
		if not showOthers and index ~= player:GetAttribute("BaseIndex") and prompt.Enabled then
			prompt.Enabled = false
		end
	end
	ClientState.ProfileChanged:Connect(apply)
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		task.defer(apply)
	end)
	player:GetAttributeChangedSignal("BaseIndex"):Connect(apply)
	apply()
end

local function onDescendant(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance.Name ~= "PickUpPrompt" then
		watchBasePrompt(instance)
	end
	if instance:IsA("ProximityPrompt") and instance.Name == "PickUpPrompt" then
		watchPrompt(instance)
	elseif instance:IsA("Model") and instance.Name == "BananaTrap" then
		task.defer(styleTrap, instance)
	end
end

runtime.DescendantAdded:Connect(onDescendant)
for _, instance in runtime:GetDescendants() do
	onDescendant(instance)
end

player:GetAttributeChangedSignal("Carrying"):Connect(function()
	for _, instance in runtime:GetDescendants() do
		if instance:IsA("ProximityPrompt") and instance.Name == "PickUpPrompt" then
			refreshPrompt(instance)
		end
	end
end)
