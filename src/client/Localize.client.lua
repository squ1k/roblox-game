-- Язык интерфейса на клиенте. Все тексты в коде английские (Strings.lua), здесь они заменяются на
-- русские (StringsRU.lua), если в настройках выбран RU. Следим за всеми надписями в PlayerGui и в мире
-- (таблички, ProximityPrompt): при каждой смене текста запоминаем английский оригинал и ставим перевод.
-- Смена языка перерисовывает все из оригиналов, перезаходить не нужно.
-- Язык приходит атрибутом игрока "Language" (ставит SettingsService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Localizer = require(Shared:WaitForChild("Localizer"))
local translateRu = Localizer.Build(require(Config:WaitForChild("Strings")), require(Config:WaitForChild("StringsRU")))

local player = Players.LocalPlayer

local PROPS = {
	TextLabel = { "Text" },
	TextButton = { "Text" },
	TextBox = { "PlaceholderText" }, -- то, что ввел игрок (Audio ID и т.п.), не трогаем
	ProximityPrompt = { "ActionText", "ObjectText" },
}

local tracked = setmetatable({}, { __mode = "k" }) -- [instance] = { [prop] = { Source, Shown } }

local function language(): string
	return player:GetAttribute("Language") or "EN"
end

local function translate(text: string): string
	if language() == "RU" then
		return translateRu(text)
	end
	return text
end

local function apply(instance: Instance, prop: string)
	local state = tracked[instance][prop]
	local current = (instance :: any)[prop]
	if current == state.Shown then
		return -- это наша же запись
	end
	state.Source = current
	local shown = translate(current)
	state.Shown = shown
	if shown ~= current then
		(instance :: any)[prop] = shown
	end
end

local function watch(instance: Instance)
	local props = PROPS[instance.ClassName]
	if not props or tracked[instance] then
		return
	end
	tracked[instance] = {}
	for _, prop in props do
		tracked[instance][prop] = {}
		apply(instance, prop)
		instance:GetPropertyChangedSignal(prop):Connect(function()
			apply(instance, prop)
		end)
	end
end

local function retranslateAll()
	for instance, states in tracked do
		for prop, state in states do
			if state.Source then
				local shown = translate(state.Source)
				state.Shown = shown
				if (instance :: any)[prop] ~= shown then
					(instance :: any)[prop] = shown
				end
			end
		end
	end
end

local function watchTree(root: Instance)
	root.DescendantAdded:Connect(watch)
	for _, instance in root:GetDescendants() do
		watch(instance)
	end
end

player:GetAttributeChangedSignal("Language"):Connect(retranslateAll)
watchTree(player:WaitForChild("PlayerGui"))
watchTree(workspace)
