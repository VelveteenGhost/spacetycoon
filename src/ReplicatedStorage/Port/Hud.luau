-- Broadcast overlay after the mood study's HUD: LIVE tag and camera name, telemetry, T-clock and lower third, plus
-- a small control deck (sequence and camera) that works by touch, so the static fire can be picked on a phone.

local TweenService = game:GetService("TweenService")

local Hud = {}
Hud.__index = Hud

local INK = Color3.fromRGB(236, 231, 221)
local DIM = Color3.fromRGB(168, 162, 151)
local TALLY = Color3.fromRGB(242, 169, 59)
local LIVE = Color3.fromRGB(255, 74, 61)
local SHADE = Color3.fromRGB(5, 7, 9)

local BOLD = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Bold)
local MEDIUM = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Medium)
local MONO = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular)

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		i[k] = v
	end
	i.Parent = parent
	return i
end

local function text(parent, size, font, color, order, align)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		FontFace = font,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.75,
		LayoutOrder = order or 0,
		Text = "",
	}, parent)
end

-- A panel whose dark backing fades out toward one side, like the mood study's gradients.
local function panel(parent, anchor, position, fadeRight, padding)
	local f = new("Frame", {
		AnchorPoint = anchor,
		Position = position,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		BackgroundColor3 = SHADE,
		BorderSizePixel = 0,
	}, parent)
	new("UIGradient", {
		Rotation = fadeRight and 0 or 180,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.34),
			NumberSequenceKeypoint.new(0.7, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, f)
	new("UIPadding", {
		PaddingTop = UDim.new(0, padding[1]),
		PaddingRight = UDim.new(0, padding[2]),
		PaddingBottom = UDim.new(0, padding[3]),
		PaddingLeft = UDim.new(0, padding[4]),
	}, f)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		HorizontalAlignment = fadeRight and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right,
	}, f)
	return f
end

local function corner(parent, ax, ay)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(ax, ay),
		Position = UDim2.new(ax, ax == 0 and 10 or -10, ay, ay == 0 and 10 or -10),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
	}, parent)
	local props = { BackgroundColor3 = INK, BackgroundTransparency = 0.45, BorderSizePixel = 0 }
	local h = new("Frame", props, holder)
	h.Size = UDim2.new(1, 0, 0, 1.5)
	h.Position = UDim2.fromScale(0, ay)
	h.AnchorPoint = Vector2.new(0, ay)
	local v = new("Frame", props, holder)
	v.Size = UDim2.new(0, 1.5, 1, 0)
	v.Position = UDim2.fromScale(ax, 0)
	v.AnchorPoint = Vector2.new(ax, 0)
end

function Hud.new(playerGui, callbacks)
	local self = setmetatable({}, Hud)
	local gui = new("ScreenGui", {
		Name = "Broadcast",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	self.gui = gui
	self.cut = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, gui)

	local overlay = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	self.overlay = overlay
	self.scale = new("UIScale", {}, overlay)
	for _, c in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		corner(overlay, c[1], c[2])
	end

	-- top left: LIVE, camera, telemetry
	local feed = panel(overlay, Vector2.new(0, 0), UDim2.fromOffset(26, 20), true, { 6, 26, 7, 8 })
	local line = new("Frame", { AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), BackgroundTransparency = 1 }, feed)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, line)
	local pill = new("Frame", {
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		BackgroundColor3 = Color3.fromRGB(5, 6, 8),
		BackgroundTransparency = 0.45,
	}, line)
	new("UIStroke", { Color = LIVE, Transparency = 0.4, Thickness = 1 }, pill)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 7),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 2),
	}, pill)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}, pill)
	self.dot = new("Frame", { Size = UDim2.fromOffset(7, 7), BackgroundColor3 = LIVE, BorderSizePixel = 0 }, pill)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, self.dot)
	text(pill, 12, BOLD, INK, 1).Text = "LIVE"
	self.camLabel = text(line, 15, BOLD, INK, 2)
	self.telemetry = text(feed, 12, MONO, Color3.fromRGB(217, 211, 200), 2)

	-- top right: T-clock
	local clock = panel(overlay, Vector2.new(1, 0), UDim2.new(1, -26, 0, 20), false, { 6, 8, 7, 26 })
	self.clockLabel = text(clock, 12, BOLD, TALLY, 1, Enum.TextXAlignment.Right)
	self.tclock = text(clock, 27, MONO, INK, 2, Enum.TextXAlignment.Right)
	self.vtel = text(clock, 12, MONO, Color3.fromRGB(217, 211, 200), 3, Enum.TextXAlignment.Right)

	-- bottom left: lower third
	local lower = panel(overlay, Vector2.new(0, 1), UDim2.new(0, 26, 1, -24), true, { 10, 28, 10, 12 })
	self.kicker = text(lower, 12, BOLD, TALLY, 1)
	self.main = text(lower, 30, BOLD, INK, 2)
	self.meta = text(lower, 12, MEDIUM, DIM, 3)
	self.meta.Text = "PAD 2, KESTREL POINT     WIND 7 KT SSE     18 °C     VIS 9 SM"

	-- bottom right: control deck
	local deck = new("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -26, 1, -24),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		BackgroundColor3 = Color3.fromRGB(8, 10, 13),
		BackgroundTransparency = 0.24,
	}, gui)
	self.deck = deck
	new("UIStroke", { Color = INK, Transparency = 0.78 }, deck)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, deck)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(92, 30),
		CellPadding = UDim2.fromOffset(6, 6),
		FillDirectionMaxCells = 3,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, deck)
	self.deckScale = new("UIScale", {}, deck)
	self.buttons = {}
	local function button(key, label, order, onClick)
		local b = new("TextButton", {
			Text = label,
			FontFace = BOLD,
			TextSize = 13,
			TextColor3 = DIM,
			BackgroundColor3 = TALLY,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			LayoutOrder = order,
		}, deck)
		new("UIStroke", { Color = INK, Transparency = 0.78, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		b.Activated:Connect(onClick)
		self.buttons[key] = b
	end
	button("hold", "PROP LOAD", 1, function() callbacks.onSequence("hold") end)
	button("static", "STATIC FIRE", 2, function() callbacks.onSequence("static") end)
	button("launch", "LAUNCH", 3, function() callbacks.onSequence("launch") end)
	button("auto", "AUTO CAM", 4, function() callbacks.onCamera("auto") end)
	button("next", "NEXT CAM", 5, function() callbacks.onCamera("next") end)
	button("hide", "HIDE", 6, function() callbacks.onToggleOverlay() end)
	return self
end

function Hud:layout(viewport)
	local s = math.clamp(viewport.Y / 900, 0.55, 1.5)
	self.scale.Scale = s
	self.overlay.Size = UDim2.fromScale(1 / s, 1 / s) -- UIScale scales the frame too; this keeps it full-screen
	self.deckScale.Scale = math.max(s, 0.75) -- keep buttons tappable on phones
end

function Hud:setDeck(seqMode, auto)
	for key, b in self.buttons do
		local on = key == seqMode or (key == "auto" and auto)
		b.BackgroundTransparency = on and 0.84 or 1
		b.TextColor3 = on and INK or DIM
		b:FindFirstChildOfClass("UIStroke").Color = on and TALLY or INK
		b:FindFirstChildOfClass("UIStroke").Transparency = on and 0 or 0.78
	end
end

function Hud:setOverlayVisible(on)
	self.overlay.Visible = on
	self.buttons.hide.Text = on and "HIDE" or "SHOW"
end

function Hud:setEvent(kicker, main)
	self.kicker.Text = string.upper(kicker)
	if self.main.Text ~= string.upper(main) then
		self.main.Text = string.upper(main)
		self.main.TextColor3 = TALLY
		TweenService:Create(self.main, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = INK }):Play()
	end
end

function Hud:update(t, camLabel, telemetry, clockLabel, clock, vtel)
	self.dot.BackgroundTransparency = (t % 1.6) < 0.8 and 0 or 0.75
	self.camLabel.Text = string.upper(camLabel)
	self.telemetry.Text = telemetry
	self.clockLabel.Text = string.upper(clockLabel)
	self.tclock.Text = clock
	self.vtel.Text = vtel
	self.vtel.Visible = vtel ~= ""
end

function Hud:setCut(alpha)
	self.cut.BackgroundTransparency = 1 - alpha
end

return Hud
