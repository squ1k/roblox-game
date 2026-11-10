-- Мелкие фабрики UI: панели, текст, кнопки с анимацией нажатия.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Widgets = {}

-- Ключи props, которые не являются свойствами Instance
local CUSTOM_PROPS = { Parent = true, Outline = true, MaxTextSize = true, CornerRadius = true }

function Widgets.Create(className: string, props, children)
	local instance = Instance.new(className)
	local parent
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	instance.Parent = parent
	return instance
end

local create = Widgets.Create

function Widgets.Corner(radius: UDim?)
	return create("UICorner", { CornerRadius = radius or Theme.Corner })
end

function Widgets.Stroke(thickness: number?, color: Color3?)
	return create("UIStroke", {
		Thickness = thickness or Theme.StrokeThickness,
		Color = color or Theme.Colors.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Widgets.TextStroke(thickness: number?)
	return create("UIStroke", {
		Thickness = thickness or 2,
		Color = Theme.Colors.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

function Widgets.Label(props)
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		Text = "",
	})
	for key, value in props do
		if not CUSTOM_PROPS[key] then
			label[key] = value
		end
	end
	if props.Outline ~= false then
		Widgets.TextStroke().Parent = label
	end
	create("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 48, Parent = label })
	label.Parent = props.Parent
	return label
end

-- Кнопка с "пружинкой" при нажатии. onClick вызывается на отпускание.
function Widgets.Button(props, onClick)
	local button = create("TextButton", {
		AutoButtonColor = false,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		Text = "",
		BorderSizePixel = 0,
	})
	for key, value in props do
		if not CUSTOM_PROPS[key] then
			button[key] = value
		end
	end
	Widgets.Corner(props.CornerRadius).Parent = button
	Widgets.Stroke().Parent = button
	if button.Text ~= "" then
		Widgets.TextStroke().Parent = button
		create("UITextSizeConstraint", { MaxTextSize = 40, Parent = button })
		create("UIPadding", {
			PaddingLeft = UDim.new(0.08, 0),
			PaddingRight = UDim.new(0.08, 0),
			PaddingTop = UDim.new(0.12, 0),
			PaddingBottom = UDim.new(0.12, 0),
			Parent = button,
		})
	end
	local scale = create("UIScale", { Parent = button })
	local pressInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad)
	local releaseInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, pressInfo, { Scale = 0.9 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, releaseInfo, { Scale = 1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, releaseInfo, { Scale = 1 }):Play()
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	button.Parent = props.Parent
	return button
end

-- Короткий "подпрыг" элемента, например при изменении счетчика
function Widgets.Pop(instance: GuiObject)
	local scale = instance:FindFirstChildOfClass("UIScale") or create("UIScale", { Parent = instance })
	scale.Scale = 1.15
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

return Widgets
