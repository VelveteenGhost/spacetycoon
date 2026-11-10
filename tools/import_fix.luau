-- Body of the import repair and check; tools/import_fix.py prepends PATH and the expected table E.
local model = game
for seg in string.gmatch(PATH, "[^%.]+") do
	model = model:FindFirstChild(seg)
	assert(model, "not found: " .. PATH)
end

local link = model:FindFirstChildOfClass("PackageLink")
if link then
	link:Destroy()
end

if math.abs(model:GetScale() - 1) < 1e-3 then
	model:PivotTo(CFrame.Angles(0, math.pi, 0))
	model:ScaleTo(1 / 0.28)
end

local function v(t)
	return Vector3.new(t[1], t[2], t[3])
end

local seen, missing, unexpected, mismatches = {}, {}, {}, {}
local worst = { pos = 0, size = 0, pivot = 0 }
local attachments = 0
for _, p in model:GetDescendants() do
	if not p:IsA("MeshPart") then
		continue
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CollisionFidelity = Enum.CollisionFidelity.Box
	local e = E[p.Name]
	if not e then
		table.insert(unexpected, p.Name)
		continue
	end
	seen[p.Name] = true
	if e.precise then
		p.RenderFidelity = Enum.RenderFidelity.Precise
	end
	for _, a in e.a do
		local att = p:FindFirstChild(a[1]) or Instance.new("Attachment")
		att.Name = a[1]
		att.Parent = p
		att.WorldCFrame = CFrame.new(v(a[2]))
		attachments += 1
	end
	local ws = p.CFrame:VectorToWorldSpace(p.Size)
	ws = Vector3.new(math.abs(ws.X), math.abs(ws.Y), math.abs(ws.Z))
	local dPos = (p.Position - v(e.c)).Magnitude
	local dSize = (ws - v(e.s)).Magnitude
	local dPiv = (p:GetPivot().Position - v(e.p)).Magnitude
	worst.pos = math.max(worst.pos, dPos)
	worst.size = math.max(worst.size, dSize)
	worst.pivot = math.max(worst.pivot, dPiv)
	if dPos > 0.05 or dSize > 0.05 or dPiv > 0.05 then
		table.insert(mismatches, string.format("%s pos %.3f size %.3f pivot %.3f", p.Name, dPos, dSize, dPiv))
	end
	local sas = 0
	for _, c in p:GetChildren() do
		if c:IsA("SurfaceAppearance") then
			sas += 1
		end
	end
	if sas ~= 1 then
		table.insert(mismatches, string.format("%s has %d SurfaceAppearances", p.Name, sas))
	end
end
for name in E do
	if not seen[name] then
		table.insert(missing, name)
	end
end
game:GetService("ChangeHistoryService"):SetWaypoint("Import fix: " .. PATH)
return {
	matched = #(function()
		local t = {}
		for k in seen do
			table.insert(t, k)
		end
		return t
	end)(),
	expected = #(function()
		local t = {}
		for k in E do
			table.insert(t, k)
		end
		return t
	end)(),
	attachments = attachments,
	worst = worst,
	missing = missing,
	unexpected = unexpected,
	mismatches = mismatches,
}
