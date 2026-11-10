-- Собирает полный плейс: карта (аргумент 1) + код из build/*.rbxm (аргумент 2 = папка build),
-- результат в аргумент 3. Старые деревья кода в карте заменяются целиком.
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local process = require("@lune/process")

local mapPath, buildDir, outPath = process.args[1], process.args[2], process.args[3]
local place = roblox.deserializePlace(fs.readFile(mapPath))

local function replace(parent: Instance, modelFile: string)
	local tree = roblox.deserializeModel(fs.readFile(buildDir .. "/" .. modelFile))[1]
	local old = parent:FindFirstChild(tree.Name)
	local oldCount = if old then #old:GetDescendants() else 0
	if old then
		old:Destroy()
	end
	tree.Parent = parent
	print(string.format("%s.%s: %d -> %d descendants", parent.Name, tree.Name, oldCount, #tree:GetDescendants()))
end

replace(place:GetService("ReplicatedStorage"), "Shared.rbxm")
replace(place:GetService("ServerScriptService"), "Server.rbxm")
replace(place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"), "Client.rbxm")

-- Workspace.Skebobs_Runtime оставляем как есть: MapService переиспользует уже расставленные
-- объекты (лавка, обмен, пьедесталы), а недостающие достраивает сам.

fs.writeFile(outPath, roblox.serializePlace(place))
print("written", outPath)
