-- 1234 -> "1.23K", 5e15 -> "5Qa"

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local NumberFormat = {}

function NumberFormat.Short(value: number): string
	if value ~= value then
		return "0"
	end
	local negative = value < 0
	value = math.abs(value)
	if value < 1000 then
		local text = if value == math.floor(value) then tostring(value) else string.format("%.1f", value)
		return (negative and "-" or "") .. text
	end
	local tier = math.min(math.floor(math.log10(value) / 3), #SUFFIXES - 1)
	local scaled = value / 10 ^ (tier * 3)
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return (negative and "-" or "") .. text .. SUFFIXES[tier + 1]
end

return NumberFormat
