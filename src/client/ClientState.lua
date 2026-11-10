-- Кэш данных игрока на клиенте. Кошельки идут через атрибуты (обновляются каждую секунду),
-- инвентарь через снимок GetProfile, который перезапрашивается по ProfileChanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local ClientState = {}
ClientState.Profile = nil

local changed = Instance.new("BindableEvent")
ClientState.ProfileChanged = changed.Event

local refreshing = false
function ClientState.Refresh()
	if refreshing then
		return
	end
	refreshing = true
	local ok, data = pcall(function()
		return Remotes.GetProfile:InvokeServer()
	end)
	refreshing = false
	if ok and type(data) == "table" then
		ClientState.Profile = data
		changed:Fire(data)
	end
end

Remotes.ProfileChanged.OnClientEvent:Connect(function()
	ClientState.Refresh()
end)

return ClientState
