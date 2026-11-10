-- Цвета, шрифты и размеры интерфейса. Мультяшный стиль: толстая обводка, скругления.

return {
	Font = Enum.Font.FredokaOne,
	FontBody = Enum.Font.GothamBold,

	Colors = {
		Panel = Color3.fromRGB(255, 248, 235),
		PanelDark = Color3.fromRGB(60, 40, 70),
		Stroke = Color3.fromRGB(45, 30, 55),
		Text = Color3.fromRGB(255, 255, 255),
		TextDark = Color3.fromRGB(45, 30, 55),
		Coin = Color3.fromRGB(255, 200, 40),
		Crystal = Color3.fromRGB(120, 200, 255),
		Plus = Color3.fromRGB(90, 210, 90),
		Drop = Color3.fromRGB(235, 60, 60),
		Backpack = Color3.fromRGB(255, 150, 60),
		Slot = Color3.fromRGB(255, 255, 255),
		Locked = Color3.fromRGB(120, 120, 130),
		TabActive = Color3.fromRGB(255, 150, 60),
		TabIdle = Color3.fromRGB(200, 190, 180),
		Buy = Color3.fromRGB(90, 210, 90),
		Sell = Color3.fromRGB(255, 150, 60),
		Afk = Color3.fromRGB(150, 120, 255),
	},

	StrokeThickness = 3,
	Corner = UDim.new(0, 14),

	-- Базовая высота экрана, под которую нарисованы размеры (в пикселях Roblox).
	-- На меньших экранах все уменьшается через UIScale.
	DesignHeight = 720,
	MinScale = 0.55,
	MaxScale = 1.25,
}
