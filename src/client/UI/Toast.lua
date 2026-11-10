-- Всплывающие уведомления сверху по центру.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Widgets = require(script.Parent:WaitForChild("Widgets"))
local create = Widgets.Create

return function(parent: Instance)
	local stack = create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56), -- ниже баннера погодного ивента
		Size = UDim2.fromOffset(460, 200),
		BackgroundTransparency = 1,
		ZIndex = 40,
		Parent = parent,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local counter = 0

	return function(text: string)
		counter += 1
		local toast = create("Frame", {
			LayoutOrder = counter,
			BackgroundColor3 = Theme.Colors.PanelDark,
			Size = UDim2.fromOffset(440, 48),
			ZIndex = 40,
			Parent = stack,
		}, { Widgets.Corner(), Widgets.Stroke(), create("UIScale", { Scale = 0.6 }) })
		local label = Widgets.Label({
			Text = text,
			Size = UDim2.new(1, -20, 1, -12),
			Position = UDim2.fromOffset(10, 6),
			MaxTextSize = 22,
			ZIndex = 41,
			Parent = toast,
		})
		TweenService:Create(toast.UIScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(2.5, function()
			local fade = TweenInfo.new(0.3)
			TweenService:Create(toast, fade, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
			task.wait(0.3)
			toast:Destroy()
		end)
	end
end
