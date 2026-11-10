-- Каркас полноэкранного окна: затемнение (тап мимо закрывает), окно с заголовком и крестиком.
-- Возвращает overlay, window, setTitle.

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local create = Widgets.Create

return function(parent: Instance, name: string, title: string, onClose: (() -> ())?)
	local overlay = create("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	local window = create("Frame", {
		Name = "Window",
		Active = true, -- клики по окну не закрывают его
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.88),
		BackgroundColor3 = Theme.Colors.Panel,
		ZIndex = 21,
		Parent = overlay,
	}, {
		Widgets.Corner(UDim.new(0, 24)),
		Widgets.Stroke(4),
		create("UISizeConstraint", { MaxSize = Vector2.new(1100, 700) }),
	})
	local function close()
		overlay.Visible = false
		if onClose then
			onClose()
		end
	end
	overlay.Activated:Connect(close)
	local titleLabel = Widgets.Label({
		Text = title,
		TextColor3 = Theme.Colors.TextDark,
		Outline = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -100, 0, 50),
		Position = UDim2.fromOffset(20, 14),
		MaxTextSize = 34,
		ZIndex = 22,
		Parent = window,
	})
	Widgets.Button({
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Theme.Colors.Drop,
		ZIndex = 23,
		Parent = window,
	}, close)
	return overlay, window, function(text: string)
		titleLabel.Text = text
	end
end
