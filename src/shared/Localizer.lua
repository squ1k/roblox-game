-- Перевод готового английского текста на русский. Весь код (и сервер, и клиент) пишет тексты из
-- Strings.lua, клиент с языком RU прогоняет каждый текст на экране через Translate.
-- Словарь строится из пар Strings/StringsRU с одинаковыми ключами:
--   точные строки -> прямая замена; строки с %d/%s -> шаблон, захваченные куски переводятся рекурсивно;
--   склейки ("Family 1 · Rare", "🛒 Shop", "...\n...") переводятся по частям.
-- Нет перевода -> текст остается английским (основной язык), ничего не ломается.

local Localizer = {}

local SEPARATORS = { "\n", " · ", " — ", ": ", " ⇄ " }
local MAX_DEPTH = 4
local CACHE_LIMIT = 4000

-- "Won: %s pop! (%d%%)" -> "^Won: (.-) pop! %((%-?%d+)%%%)$", { "s", "d" }
local function toPattern(format: string): (string, { string })
	local parts, kinds = { "^" }, {}
	local i = 1
	while i <= #format do
		local c = format:sub(i, i)
		if c == "%" then
			local spec = format:sub(i + 1, i + 1)
			if spec == "d" then
				table.insert(parts, "(%-?%d+)")
				table.insert(kinds, "d")
			elseif spec == "s" then
				table.insert(parts, "(.-)")
				table.insert(kinds, "s")
			else
				table.insert(parts, "%" .. spec)
			end
			i += 2
		else
			table.insert(parts, if c:match("[%^%$%(%)%%%.%[%]%*%+%-%?]") then "%" .. c else c)
			i += 1
		end
	end
	table.insert(parts, "$")
	return table.concat(parts), kinds
end

local function literalLength(format: string): number
	return #(format:gsub("%%[ds]", ""))
end

-- en, ru: таблицы Strings и StringsRU. Возвращает translate(text) -> text на русском.
function Localizer.Build(en, ru)
	local exact = {}
	local formats = {}
	local function walk(a, b)
		for key, value in a do
			local other = b[key]
			if type(value) == "table" and type(other) == "table" then
				walk(value, other)
			elseif type(value) == "string" and type(other) == "string" and value ~= "" then
				if value:find("%%[ds]") then
					local pattern, kinds = toPattern(value)
					table.insert(
						formats,
						{ Pattern = pattern, Kinds = kinds, Ru = other, Weight = literalLength(value) }
					)
				elseif exact[value] == nil then
					exact[value] = other
				end
			end
		end
	end
	walk(en, ru)
	for name, translated in ru.Names or {} do
		exact[name] = exact[name] or translated
	end
	-- длинные шаблоны первыми: "Patron · %s" раньше, чем "%s pop"
	table.sort(formats, function(a, b)
		return a.Weight > b.Weight
	end)

	local cache, cacheSize = {}, 0
	local translate

	local function viaFormat(text: string, depth: number): string?
		for _, format in formats do
			local captures = { text:match(format.Pattern) }
			if captures[1] ~= nil then
				for index, kind in format.Kinds do
					if kind == "d" then
						captures[index] = tonumber(captures[index]) or 0
					else
						captures[index] = translate(captures[index], depth + 1)
					end
				end
				return string.format(format.Ru, table.unpack(captures, 1, #format.Kinds))
			end
		end
		return nil
	end

	function translate(text: string, depth: number?): string
		depth = depth or 0
		if text == "" or depth > MAX_DEPTH then
			return text
		end
		local hit = exact[text]
		if hit then
			return hit
		end
		local formatted = viaFormat(text, depth)
		if formatted then
			return formatted
		end
		for _, separator in SEPARATORS do
			if text:find(separator, 1, true) then
				local pieces = text:split(separator)
				for index, piece in pieces do
					pieces[index] = translate(piece, depth + 1)
				end
				return table.concat(pieces, separator)
			end
		end
		-- эмодзи, стрелки, звездочки и пробелы в начале: "🛒 Shop", "▶ Family 2"
		local prefix, rest = text:match("^([^%w]+)(%w.*)$")
		if prefix and rest then
			local translated = translate(rest, depth + 1)
			if translated ~= rest then
				return prefix .. translated
			end
		end
		return text
	end

	return function(text: string): string
		local cached = cache[text]
		if cached then
			return cached
		end
		local result = translate(text, 0)
		if cacheSize >= CACHE_LIMIT then
			table.clear(cache)
			cacheSize = 0
		end
		cache[text] = result
		cacheSize += 1
		return result
	end
end

return Localizer
