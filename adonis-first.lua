wait(1.2)
loadstring(game:HttpGet("https://raw.githubusercontent.com/Pixeluted/adoniscries/main/Source.lua"))()
wait(2)
loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
wait(0.2)
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
-- IMPORTANT: This must run as a LocalScript on the client.
local player = Players.LocalPlayer
if not player then
    warn("ToolAdjuster: LocalPlayer is nil — this script must run as a LocalScript (StarterGui or StarterPlayerScripts).")
    return
end
local char = player.Character or player.CharacterAdded:Wait()
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
-- Per-instance data
local originalGrips = {} -- toolInstance -> CFrame
local offsets = {} -- toolInstance -> CFrame (live edits)
-- Serialize CFrame to table for persistence (pos + full matrix for exactness)
local function serializeCFrame(cf)
    local pos = cf.Position
    local m = {cf:GetComponents()}
    return {posX = pos.X, posY = pos.Y, posZ = pos.Z,
            r00 = m[4], r01 = m[5], r02 = m[6],
            r10 = m[7], r11 = m[8], r12 = m[9],
            r20 = m[10], r21 = m[11], r22 = m[12]}
end
local function deserializeCFrame(tbl)
    return CFrame.new(tbl.posX, tbl.posY, tbl.posZ, tbl.r00, tbl.r01, tbl.r02, tbl.r10, tbl.r11, tbl.r12, tbl.r20, tbl.r21, tbl.r22)
end
local persistentOffsets = {
    ["[AUG]"] = serializeCFrame(CFrame.new(-2.5, 0.5, -1.5)),
    ["[Flintlock]"] = serializeCFrame(CFrame.new(0.0833667815, 3.03116846, -1.90)),
    ["[LMG]"] = serializeCFrame(CFrame.new(-0.15, -1.10, -1.16938221)),
    ["[Rifle]"] = serializeCFrame(CFrame.new(3.5, 0.5, -1.5)),
    ["[Revolver]"] = serializeCFrame(CFrame.new(2.5, 0.5, -1.7)),
    ["[Double-Barrel SG]"] = serializeCFrame(CFrame.new(3.90, 2.90, -1.041011)),
    ["Boombox"] = {posX = -1.47619057, posY = -0.297619045, posZ = -2.65,
                   r00 = -0.936234891, r01 = -0.351374835, r02 = -4.37113883e-08,
                   r10 = -0.351374835, r11 = 0.936234891, r12 = 0,
                   r20 = -4.09241281e-08, r21 = -1.53590811e-08, r22 = 1},
}
-- State
local currentTool = nil
local selectedTool = nil
local toolButtons = {}
local keepAfterSpawn = true
local daHoodEnabled = false
local useExtendedRange = false
local rapidEquipEnabled = false
local rapidEquipDelay = 0.01 -- variable for delay, changes with mode
local rapidEquipModes = {"Normal", "Slower", "Slowest"}
local currentRapidModeIndex = 1 -- Starts on Normal
local orbitEnabled = false
local orbitMode = "Horizontal"
local orbitTools = {}
local orbitAngles = {}
local orbitBasePositions = {}
local orbitConn = nil
local orbitTime = 0
local orbitSpeed = 1 -- rad/s
local orbitRadiusMultiplier = 1 -- for adjustments
local aimOffset = Vector3.new(0, 0, 0) -- head-local offset (X=right, Y=up, Z=depth)
local targetMode = "Normal" -- New: Normal or Align
local noAnimsEnabled = false
local noAnimsConn = nil
local targetOffsetFrame = nil
-- UI helpers
local posAxes = {"X","Y","Z"}
local rotAxes = {"Pitch","Yaw","Roll"} -- Rotation axes (degrees)
local sliders = {}
local valueLabels = {}
local toolNameLabel
-- Da Hood detection & slots (updated to CFrames)
local DAHOOD_PATTERNS = {"aug","rifle","ak","m4","scar","shotgun","sniper","bolt","pistol","deagle","revolver","smg","lmg","flintlock","boombox"}
local DAHOOD_SLOTS = {
    left = serializeCFrame(CFrame.new(-2.5, 0.5, -1.5)),
    top = serializeCFrame(CFrame.new(-0.15, -1.10, -1.16938221)),
    back = serializeCFrame(CFrame.new(0.0833667815, 3.03116846, -1.90)),
    right = serializeCFrame(CFrame.new(3.5, 0.5, -1.5)),
    shoulder = serializeCFrame(CFrame.new(0.8,1.6,-1.2)),
}
local function isDaHoodWeapon(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local name = tool.Name:lower()
    for _, p in ipairs(DAHOOD_PATTERNS) do
        if name:find(p) then return true end
    end
    return false
end
local function getEquippedTool()
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                return child
            end
        end
    end
    return nil
end
local function getActiveTool()
    if selectedTool and selectedTool.Parent then
        return selectedTool
    end
    return currentTool
end
local function ensureOriginalGrip(tool)
    if not tool then return end
    if not originalGrips[tool] then
        originalGrips[tool] = tool.Grip or CFrame.new()
    end
end
-- FIXED BOOMBOX — NO MORE HARD OVERRIDE
local function applyOffset(tool)
    if not tool then return end
   
    -- COLOR FIX ONLY (stops weird tinting/glitching when deep behind body)
    if tool.Name == "Boombox" then
        local handle = tool:FindFirstChild("Handle")
        if handle then
            for _, part in ipairs(tool:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Material = Enum.Material.Plastic
                    part.Color = Color3.fromRGB(163, 162, 165) -- normal boombox gray
                    part.Transparency = 0
                end
            end
        end
    end
   
    -- NORMAL OFFSET LOGIC (Boombox now fully works with sliders + persistent)
    ensureOriginalGrip(tool)
    local offset = offsets[tool]
    if (not offset) and keepAfterSpawn then
        local pers = persistentOffsets[tool.Name]
        if pers then
            offset = deserializeCFrame(pers)
        end
    end
    offset = offset or CFrame.new()
    local base = originalGrips[tool] or CFrame.new()
    tool.Grip = base * offset
end
local function applyPersistentToToolIfNeeded(tool)
    if not tool or not tool:IsA("Tool") then return end
    if keepAfterSpawn and persistentOffsets[tool.Name] then
        offsets[tool] = deserializeCFrame(persistentOffsets[tool.Name])
        ensureOriginalGrip(tool)
        applyOffset(tool)
    end
end
-- Helper: get a reliable root part for character (PrimaryPart preferred, then HumanoidRootPart, then Torso)
local function getCharacterRoot(c)
    if not c then return nil end
    if c.PrimaryPart then return c.PrimaryPart end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp end
    local torso = c:FindFirstChild("Torso") or c:FindFirstChild("UpperTorso") or c:FindFirstChild("LowerTorso")
    return torso
end
-- UI: main screen + selector (height increased for rotation sliders and orbit edits)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ToolAdjusterUI"
screenGui.Parent = playerGui
screenGui.ResetOnSpawn = false
local MAIN_W, MAIN_H = 300, 700 -- Increased size
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, MAIN_W, 0, MAIN_H)
frame.Position = UDim2.new(1, -310, 0.5, -350)
frame.BackgroundColor3 = Color3.fromRGB(40,40,40)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui
frame.Visible = false -- Start hidden
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1,0,0,30)
titleLabel.Position = UDim2.new(0,0,0,0)
titleLabel.BackgroundColor3 = Color3.fromRGB(30,30,30)
titleLabel.Text = "Tool Position & Rotation Adjuster"
titleLabel.TextColor3 = Color3.fromRGB(255,255,255)
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 18
titleLabel.Parent = frame
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0,30,0,30)
closeButton.Position = UDim2.new(1,-30,0,0)
closeButton.BackgroundTransparency = 1
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255,0,0)
closeButton.Font = Enum.Font.SourceSansBold
closeButton.TextSize = 20
closeButton.Parent = frame
closeButton.MouseButton1Click:Connect(function()
    frame.Visible = false
end)
toolNameLabel = Instance.new("TextLabel")
toolNameLabel.Size = UDim2.new(1,0,0,20)
toolNameLabel.Position = UDim2.new(0,0,0,35)
toolNameLabel.BackgroundTransparency = 1
toolNameLabel.Text = "Current Tool: None"
toolNameLabel.TextColor3 = Color3.fromRGB(200,200,200)
toolNameLabel.Font = Enum.Font.SourceSans
toolNameLabel.TextSize = 14
toolNameLabel.Parent = frame
-- Sliders for Position X,Y,Z and Rotation Pitch,Yaw,Roll
local allAxes = {posAxes, rotAxes}
local axisTypes = {"Position", "Rotation"}
local sliderHeightOffset = 60
for t, axes in ipairs(allAxes) do
    local sectionLabel = Instance.new("TextLabel")
    sectionLabel.Size = UDim2.new(1,0,0,20)
    sectionLabel.Position = UDim2.new(0,0,0, 60 + (t-1)* (3*60 + 20))
    sectionLabel.BackgroundTransparency = 1
    sectionLabel.Text = axisTypes[t] .. ":"
    sectionLabel.TextColor3 = Color3.fromRGB(150,150,255)
    sectionLabel.Font = Enum.Font.SourceSansBold
    sectionLabel.TextSize = 16
    sectionLabel.Parent = frame
    for i, axis in ipairs(axes) do
        local axisFrame = Instance.new("Frame")
        axisFrame.Size = UDim2.new(1,0,0,50)
        axisFrame.Position = UDim2.new(0,0,0, 80 + (t-1)* (3*60 + 20) + (i-1)*60)
        axisFrame.BackgroundTransparency = 1
        axisFrame.Parent = frame
        local axisLabel = Instance.new("TextLabel")
        axisLabel.Size = UDim2.new(0,40,1,0)
        axisLabel.BackgroundTransparency = 1
        axisLabel.Text = axis..":"
        axisLabel.TextColor3 = Color3.fromRGB(255,255,255)
        axisLabel.Font = Enum.Font.SourceSans
        axisLabel.TextSize = 16
        axisLabel.Parent = axisFrame
        local sliderFrame = Instance.new("Frame")
        sliderFrame.Size = UDim2.new(0.7,0,0.2,0)
        sliderFrame.Position = UDim2.new(0.15,0,0.2,0)
        sliderFrame.BackgroundColor3 = Color3.fromRGB(60,60,60)
        sliderFrame.BorderSizePixel = 0
        sliderFrame.Parent = axisFrame
        local sliderButton = Instance.new("TextButton")
        sliderButton.Size = UDim2.new(0.05,0,1,0)
        sliderButton.Position = UDim2.new(0.475,0,0,0)
        sliderButton.BackgroundColor3 = Color3.fromRGB(100,100,255)
        sliderButton.BorderSizePixel = 0
        sliderButton.Text = ""
        sliderButton.Parent = sliderFrame
        local valueLabel = Instance.new("TextLabel")
        valueLabel.Size = UDim2.new(0.2,0,1,0)
        valueLabel.Position = UDim2.new(0.85,0,0,0)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Text = "0.00"
        valueLabel.TextColor3 = Color3.fromRGB(255,255,255)
        valueLabel.Font = Enum.Font.SourceSans
        valueLabel.TextSize = 14
        valueLabel.Parent = axisFrame
        valueLabels[axis] = valueLabel
        sliders[axis] = {frame = sliderFrame, button = sliderButton}
        -- slider logic
        local dragging = false
        local isRot = (t == 2)
        local function getRangeLimit()
            return isRot and 360 or (useExtendedRange and 500 or 10)
        end
        sliderButton.MouseButton1Down:Connect(function()
            if not getActiveTool() then return end
            dragging = true
        end)
        UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
        UIS.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local active = getActiveTool()
                if not active then dragging = false return end
                local rangeLimit = getRangeLimit()
                local minVal, maxVal = isRot and -rangeLimit or -rangeLimit, isRot and rangeLimit or rangeLimit
                local relativeX = math.clamp((input.Position.X - sliderFrame.AbsolutePosition.X) / sliderFrame.AbsoluteSize.X, 0, 1)
                local newVal = minVal + (maxVal - minVal) * relativeX
                local currentOffset = offsets[active] or CFrame.new()
                local pos = currentOffset.Position
                local rx, ry, rz = currentOffset:ToEulerAnglesXYZ()
                if not isRot then
                    pos = Vector3.new(
                        axis == "X" and newVal or pos.X,
                        axis == "Y" and newVal or pos.Y,
                        axis == "Z" and newVal or pos.Z
                    )
                else
                    rx = axis == "Pitch" and math.rad(newVal) or rx
                    ry = axis == "Yaw" and math.rad(newVal) or ry
                    rz = axis == "Roll" and math.rad(newVal) or rz
                end
                local newOffset = CFrame.new(pos) * CFrame.Angles(rx, ry, rz)
                offsets[active] = newOffset
                if keepAfterSpawn then
                    persistentOffsets[active.Name] = serializeCFrame(newOffset)
                end
                valueLabels[axis].Text = string.format("%.2f", newVal)
                sliderButton.Position = UDim2.new(relativeX - 0.025,0,0,0)
                applyOffset(active)
            end
        end)
        -- initial position (center for 0)
        sliderButton.Position = UDim2.new(0.5 - 0.025,0,0,0)
    end
end
-- Orbit editable parameters: Speed and Radius Multiplier sliders
local orbitParams = {"Speed", "Radius"}
local orbitSectionLabel = Instance.new("TextLabel")
orbitSectionLabel.Size = UDim2.new(1,0,0,20)
orbitSectionLabel.Position = UDim2.new(0,0,0, 60 + 2*(3*60 + 20))
orbitSectionLabel.BackgroundTransparency = 1
orbitSectionLabel.Text = "Orbit Params:"
orbitSectionLabel.TextColor3 = Color3.fromRGB(150,150,255)
orbitSectionLabel.Font = Enum.Font.SourceSansBold
orbitSectionLabel.TextSize = 16
orbitSectionLabel.Parent = frame
for i, param in ipairs(orbitParams) do
    local paramFrame = Instance.new("Frame")
    paramFrame.Size = UDim2.new(1,0,0,50)
    paramFrame.Position = UDim2.new(0,0,0, 80 + 2*(3*60 + 20) + (i-1)*60)
    paramFrame.BackgroundTransparency = 1
    paramFrame.Parent = frame
    local paramLabel = Instance.new("TextLabel")
    paramLabel.Size = UDim2.new(0,60,1,0)
    paramLabel.BackgroundTransparency = 1
    paramLabel.Text = param..":"
    paramLabel.TextColor3 = Color3.fromRGB(255,255,255)
    paramLabel.Font = Enum.Font.SourceSans
    paramLabel.TextSize = 16
    paramLabel.Parent = paramFrame
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0.65,0,0.2,0)
    sliderFrame.Position = UDim2.new(0.25,0,0.2,0)
    sliderFrame.BackgroundColor3 = Color3.fromRGB(60,60,60)
    sliderFrame.BorderSizePixel = 0
    sliderFrame.Parent = paramFrame
    local sliderButton = Instance.new("TextButton")
    sliderButton.Size = UDim2.new(0.05,0,1,0)
    sliderButton.Position = UDim2.new(0.475,0,0,0)
    sliderButton.BackgroundColor3 = Color3.fromRGB(100,100,255)
    sliderButton.BorderSizePixel = 0
    sliderButton.Text = ""
    sliderButton.Parent = sliderFrame
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(0.2,0,1,0)
    valueLabel.Position = UDim2.new(0.85,0,0,0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = param == "Speed" and "1.00" or "1.00"
    valueLabel.TextColor3 = Color3.fromRGB(255,255,255)
    valueLabel.Font = Enum.Font.SourceSans
    valueLabel.TextSize = 14
    valueLabel.Parent = paramFrame
    valueLabels[param] = valueLabel
    sliders[param] = {frame = sliderFrame, button = sliderButton}
    -- slider logic for orbit params
    local dragging = false
    local minVal, maxVal = param == "Speed" and 0 or 0.1, param == "Speed" and 10 or 5
    sliderButton.MouseButton1Down:Connect(function()
        dragging = true
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local relativeX = math.clamp((input.Position.X - sliderFrame.AbsolutePosition.X) / sliderFrame.AbsoluteSize.X, 0, 1)
            local newVal = minVal + (maxVal - minVal) * relativeX
            if param == "Speed" then
                orbitSpeed = newVal
            elseif param == "Radius" then
                orbitRadiusMultiplier = newVal
            end
            valueLabels[param].Text = string.format("%.2f", newVal)
            sliderButton.Position = UDim2.new(relativeX - 0.025,0,0,0)
        end
    end)
    -- initial position (for default values)
    local initialRel = (param == "Speed" and (orbitSpeed - minVal) or (orbitRadiusMultiplier - minVal)) / (maxVal - minVal)
    sliderButton.Position = UDim2.new(initialRel - 0.025,0,0,0)
end
-- Reset button
local resetButton = Instance.new("TextButton")
resetButton.Size = UDim2.new(1,0,0,30)
resetButton.Position = UDim2.new(0,0,1,-35)
resetButton.BackgroundColor3 = Color3.fromRGB(50,50,50)
resetButton.Text = "Reset Offset"
resetButton.TextColor3 = Color3.fromRGB(255,255,255)
resetButton.Font = Enum.Font.SourceSans
resetButton.TextSize = 16
resetButton.Parent = frame
resetButton.MouseButton1Click:Connect(function()
    local active = getActiveTool()
    if not active then return end
    offsets[active] = CFrame.new()
    if keepAfterSpawn then
        persistentOffsets[active.Name] = serializeCFrame(CFrame.new())
    end
    applyOffset(active)
    -- update UI labels
    for _, axis in ipairs(posAxes) do
        valueLabels[axis].Text = "0.00"
        sliders[axis].button.Position = UDim2.new(0.475,0,0,0)
    end
    for _, axis in ipairs(rotAxes) do
        valueLabels[axis].Text = "0.00"
        sliders[axis].button.Position = UDim2.new(0.475,0,0,0)
    end
end)
-- Tool selector panel (right side)
local SELECTOR_W, SELECTOR_H = 300, 700 -- Match new height
local selectorFrame = Instance.new("Frame")
selectorFrame.Size = UDim2.new(0, SELECTOR_W, 0, SELECTOR_H)
selectorFrame.Position = UDim2.new(1, -310 - SELECTOR_W - 10, 0.5, -350)
selectorFrame.BackgroundColor3 = Color3.fromRGB(34,34,34)
selectorFrame.BorderSizePixel = 0
selectorFrame.Parent = screenGui
selectorFrame.Visible = false -- Start hidden
local selectorTitle = Instance.new("TextLabel")
selectorTitle.Size = UDim2.new(1,0,0,28)
selectorTitle.Position = UDim2.new(0,0,0,0)
selectorTitle.BackgroundColor3 = Color3.fromRGB(30,30,30)
selectorTitle.Text = "Tool Selector"
selectorTitle.TextColor3 = Color3.fromRGB(255,255,255)
selectorTitle.Font = Enum.Font.SourceSansBold
selectorTitle.TextSize = 16
selectorTitle.Parent = selectorFrame
local toolListContainer = Instance.new("Frame")
toolListContainer.Size = UDim2.new(1, -12, 1, -34)
toolListContainer.Position = UDim2.new(0,6,0,30)
toolListContainer.BackgroundTransparency = 1
toolListContainer.Parent = selectorFrame
local toolListLayout = Instance.new("UIListLayout")
toolListLayout.Padding = UDim.new(0,4)
toolListLayout.FillDirection = Enum.FillDirection.Vertical
toolListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
toolListLayout.SortOrder = Enum.SortOrder.LayoutOrder
toolListLayout.Parent = toolListContainer
local function clearToolButtons()
    for _, b in ipairs(toolButtons) do
        if b and b.Parent then b:Destroy() end
    end
    toolButtons = {}
end
local function addToolButton(tool)
    if not tool or not tool:IsA("Tool") then return end
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,20)
    btn.BackgroundColor3 = Color3.fromRGB(45,45,45)
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.Font = Enum.Font.SourceSans
    btn.TextSize = 14
    btn.Text = tool.Name
    btn.Parent = toolListContainer
    btn.MouseButton1Click:Connect(function()
        selectedTool = tool
        ensureOriginalGrip(tool)
        -- update slider labels to reflect selected tool
        local off = offsets[tool] or (keepAfterSpawn and persistentOffsets[tool.Name] and deserializeCFrame(persistentOffsets[tool.Name])) or CFrame.new()
        local pos = off.Position
        valueLabels["X"].Text = string.format("%.2f", pos.X)
        valueLabels["Y"].Text = string.format("%.2f", pos.Y)
        valueLabels["Z"].Text = string.format("%.2f", pos.Z)
        local rx, ry, rz = off:ToEulerAnglesXYZ()
        valueLabels["Pitch"].Text = string.format("%.2f", math.deg(rx))
        valueLabels["Yaw"].Text = string.format("%.2f", math.deg(ry))
        valueLabels["Roll"].Text = string.format("%.2f", math.deg(rz))
        toolNameLabel.Text = "Selected Tool: " .. tool.Name
    end)
    table.insert(toolButtons, btn)
end
function refreshToolList()
    clearToolButtons()
    for _, t in ipairs(player.Backpack:GetChildren()) do addToolButton(t) end
    if char then
        for _, t in ipairs(char:GetChildren()) do addToolButton(t) end
    end
    if selectedTool and (not selectedTool.Parent or not selectedTool:IsDescendantOf(game)) then
        selectedTool = nil
    end
end
-- Equip / Unequip all
local equipAllButton = Instance.new("TextButton")
equipAllButton.Size = UDim2.new(0.48,0,0,28)
equipAllButton.Position = UDim2.new(0.02,0,1,-70)
equipAllButton.Text = "Equip All"
equipAllButton.BackgroundColor3 = Color3.fromRGB(60,80,60)
equipAllButton.TextColor3 = Color3.fromRGB(255,255,255)
equipAllButton.Font = Enum.Font.SourceSans
equipAllButton.TextSize = 14
equipAllButton.Parent = frame
equipAllButton.MouseButton1Click:Connect(function()
    if not char then return end
    for _, tool in ipairs(player.Backpack:GetChildren()) do
        if tool:IsA("Tool") then
            tool.Parent = char
            ensureOriginalGrip(tool)
            applyPersistentToToolIfNeeded(tool)
        end
    end
    refreshToolList()
end)
local unequipAllButton = Instance.new("TextButton")
unequipAllButton.Size = UDim2.new(0.48,0,0,28)
unequipAllButton.Position = UDim2.new(0.5,0,1,-70)
unequipAllButton.Text = "Unequip All"
unequipAllButton.BackgroundColor3 = Color3.fromRGB(80,60,60)
unequipAllButton.TextColor3 = Color3.fromRGB(255,255,255)
unequipAllButton.Font = Enum.Font.SourceSans
unequipAllButton.TextSize = 14
unequipAllButton.Parent = frame
unequipAllButton.MouseButton1Click:Connect(function()
    if not char then return end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") then
            tool.Parent = player.Backpack
        end
    end
    refreshToolList()
end)
-- Toggle selector panel
local toggleSelectorButton = Instance.new("TextButton")
toggleSelectorButton.Size = UDim2.new(0,110,0,26)
toggleSelectorButton.Position = UDim2.new(0,10,0,35)
toggleSelectorButton.Text = "Hide Selector"
toggleSelectorButton.BackgroundColor3 = Color3.fromRGB(50,50,50)
toggleSelectorButton.TextColor3 = Color3.fromRGB(255,255,255)
toggleSelectorButton.Font = Enum.Font.SourceSans
toggleSelectorButton.TextSize = 12
toggleSelectorButton.Parent = frame
toggleSelectorButton.MouseButton1Click:Connect(function()
    selectorFrame.Visible = not selectorFrame.Visible
    toggleSelectorButton.Text = selectorFrame.Visible and "Hide Selector" or "Show Selector"
    if not selectorFrame.Visible then
        selectedTool = nil
        toolNameLabel.Text = "Current Tool: None"
    else
        refreshToolList()
    end
end)
-- Keep After Spawn toggle
local keepButton = Instance.new("TextButton")
keepButton.Size = UDim2.new(0,120,0,26)
keepButton.Position = UDim2.new(0,130,0,35)
keepButton.Text = "Keep After Spawn: " .. (keepAfterSpawn and "On" or "Off")
keepButton.BackgroundColor3 = Color3.fromRGB(50,50,50)
keepButton.TextColor3 = Color3.fromRGB(255,255,255)
keepButton.Font = Enum.Font.SourceSans
keepButton.TextSize = 12
keepButton.Parent = frame
keepButton.MouseButton1Click:Connect(function()
    keepAfterSpawn = not keepAfterSpawn
    keepButton.Text = "Keep After Spawn: " .. (keepAfterSpawn and "On" or "Off")
    if keepAfterSpawn then
        for _, tool in ipairs(player.Backpack:GetChildren()) do
            if tool:IsA("Tool") and persistentOffsets[tool.Name] then
                offsets[tool] = deserializeCFrame(persistentOffsets[tool.Name])
                ensureOriginalGrip(tool)
                applyOffset(tool)
            end
        end
        if char then
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") and persistentOffsets[tool.Name] then
                    offsets[tool] = deserializeCFrame(persistentOffsets[tool.Name])
                    ensureOriginalGrip(tool)
                    applyOffset(tool)
                end
            end
        end
    else
        for _, tool in ipairs(player.Backpack:GetChildren()) do
            if tool:IsA("Tool") then
                offsets[tool] = nil
                if originalGrips[tool] then tool.Grip = originalGrips[tool] end
            end
        end
        if char then
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") then
                    offsets[tool] = nil
                    if originalGrips[tool] then tool.Grip = originalGrips[tool] end
                end
            end
        end
        selectedTool = nil
        toolNameLabel.Text = "Current Tool: None"
    end
end)
-- Da Hood toggle + range button
local daHoodButton = Instance.new("TextButton")
daHoodButton.Size = UDim2.new(0,130,0,26)
daHoodButton.Position = UDim2.new(0,10,0,8)
daHoodButton.Text = "Da Hood Mode: Off"
daHoodButton.BackgroundColor3 = Color3.fromRGB(70,70,70)
daHoodButton.TextColor3 = Color3.fromRGB(255,255,255)
daHoodButton.Font = Enum.Font.SourceSans
daHoodButton.TextSize = 12
daHoodButton.Parent = frame
local rangeButton = Instance.new("TextButton")
rangeButton.Size = UDim2.new(0, 95, 0, 26)
rangeButton.Position = UDim2.new(0, 145, 0, 8)
rangeButton.Text = "Max Range: Normal"
rangeButton.BackgroundColor3 = Color3.fromRGB(70,70,70)
rangeButton.TextColor3 = Color3.fromRGB(255,255,255)
rangeButton.Font = Enum.Font.SourceSans
rangeButton.TextSize = 12
rangeButton.Parent = frame
rangeButton.MouseButton1Click:Connect(function()
    useExtendedRange = not useExtendedRange
    if useExtendedRange then
        rangeButton.Text = "Max Range: HUGE"
        rangeButton.BackgroundColor3 = Color3.fromRGB(150,50,50) -- Red visual indicator
    else
        rangeButton.Text = "Max Range: Normal"
        rangeButton.BackgroundColor3 = Color3.fromRGB(70,70,70)
    end
end)
local function assignDaHoodLayout()
    if not keepAfterSpawn then
        keepAfterSpawn = true
        keepButton.Text = "Keep After Spawn: On"
    end
    local found = {}
    local function collect(container)
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and isDaHoodWeapon(t) then table.insert(found, t) end
        end
    end
    collect(player.Backpack)
    if char then collect(char) end
    table.sort(found, function(a,b) return a.Name < b.Name end)
    local finalAssignments = {}
    local usedSlots = {}
    for _, t in ipairs(found) do
        if t.Name:lower():find("lmg") then
            finalAssignments[t] = DAHOOD_SLOTS.top
            usedSlots.top = true
        end
    end
    for _, t in ipairs(found) do
        if not finalAssignments[t] and t.Name:lower():find("flintlock") then
            finalAssignments[t] = DAHOOD_SLOTS.back
            usedSlots.back = true
        end
    end
    for _, t in ipairs(found) do
        local nm = t.Name:lower()
        if not finalAssignments[t] and nm:find("aug") then
            if not usedSlots.left then
                finalAssignments[t] = DAHOOD_SLOTS.left
                usedSlots.left = true
            else
                local adj = serializeCFrame(deserializeCFrame(DAHOOD_SLOTS.left) * CFrame.new(0, 0.15, -0.25))
                finalAssignments[t] = adj
            end
        end
    end
    for _, t in ipairs(found) do
        local nm = t.Name:lower()
        if not finalAssignments[t] and (nm:find("rifle") or nm:find("ak") or nm:find("m4") or nm:find("scar")) then
            if not usedSlots.right then
                finalAssignments[t] = DAHOOD_SLOTS.right
                usedSlots.right = true
            else
                local adj = serializeCFrame(deserializeCFrame(DAHOOD_SLOTS.right) * CFrame.new(0, 0.15, 0.25))
                finalAssignments[t] = adj
            end
        end
    end
    local fallbackOrder = {"shoulder", "back", "top", "left", "right"}
    for _, t in ipairs(found) do
        if not finalAssignments[t] then
            for _, slot in ipairs(fallbackOrder) do
                if not usedSlots[slot] then
                    finalAssignments[t] = DAHOOD_SLOTS[slot] or serializeCFrame(CFrame.new())
                    usedSlots[slot] = true
                    break
                end
            end
        end
    end
    for tool, ser in pairs(finalAssignments) do
        persistentOffsets[tool.Name] = ser
        offsets[tool] = deserializeCFrame(ser)
        ensureOriginalGrip(tool)
        applyOffset(tool)
    end
    refreshToolList()
end
daHoodButton.MouseButton1Click:Connect(function()
    daHoodEnabled = not daHoodEnabled
    daHoodButton.Text = "Da Hood Mode: " .. (daHoodEnabled and "On" or "Off")
    if daHoodEnabled then
        assignDaHoodLayout()
    else
        for _, tool in ipairs(player.Backpack:GetChildren()) do
            if tool:IsA("Tool") then
                offsets[tool] = nil
                if originalGrips[tool] then tool.Grip = originalGrips[tool] end
            end
        end
        if char then
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") then
                    offsets[tool] = nil
                    if originalGrips[tool] then tool.Grip = originalGrips[tool] end
                end
            end
        end
        selectedTool = nil
        toolNameLabel.Text = "Current Tool: None"
        refreshToolList()
    end
end)
local function equipAllDHWeapons()
    if not char then return end
    for _, tool in ipairs(player.Backpack:GetChildren()) do
        if tool:IsA("Tool") and isDaHoodWeapon(tool) then
            tool.Parent = char
            ensureOriginalGrip(tool)
            if persistentOffsets[tool.Name] then
                offsets[tool] = deserializeCFrame(persistentOffsets[tool.Name])
            end
            applyOffset(tool)
        end
    end
    refreshToolList()
end
-- New helper: equip the Double-Barrel specifically
local function equipDoubleBarrel()
    if not char then return end
    for _, tool in ipairs(player.Backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.Name == "[Double-Barrel SG]" then
            tool.Parent = char
            ensureOriginalGrip(tool)
            if persistentOffsets[tool.Name] then
                offsets[tool] = deserializeCFrame(persistentOffsets[tool.Name])
            end
            applyOffset(tool)
            break
        end
    end
    refreshToolList()
end
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.F then
            equipAllDHWeapons()
            equipDoubleBarrel()
        elseif input.KeyCode == Enum.KeyCode.RightShift then
            frame.Visible = not frame.Visible
            selectorFrame.Visible = frame.Visible and (toggleSelectorButton.Text == "Hide Selector")
        end
    end
end)
-- Monitor equipped tool changes
RunService.Heartbeat:Connect(function()
    local tool = getEquippedTool()
    if tool ~= currentTool then
        if tool then
            ensureOriginalGrip(tool)
            currentTool = tool
            if not selectedTool then
                applyPersistentToToolIfNeeded(tool)
                applyOffset(tool)
                toolNameLabel.Text = "Current Tool: " .. tool.Name
            else
                applyOffset(tool)
            end
        else
            currentTool = nil
            if not selectedTool then
                toolNameLabel.Text = "Current Tool: None"
            end
        end
    end
end)
player.Backpack.ChildAdded:Connect(function(child)
    if child:IsA("Tool") then
        if daHoodEnabled then
            assignDaHoodLayout()
        else
            applyPersistentToToolIfNeeded(child)
            refreshToolList()
        end
    end
end)
player.Backpack.ChildRemoved:Connect(function()
    if daHoodEnabled then
        assignDaHoodLayout()
    else
        refreshToolList()
    end
end)
local originalAnimate = char:WaitForChild("Animate"):Clone()
local multiEquippedNames = {} -- Persist multi-equip names for respawn
local multiTools = {}
local lastEquipTime = 0
local holdingF1 = false
local multiEquipChildAdded = nil
local multiEquipChildRemoved = nil
local multiEquipBackpackAdded = nil
-- Multi-equip setup function (called on every spawn so it ALWAYS works)
local function setupMultiEquipConnections(newChar)
    if multiEquipChildAdded then multiEquipChildAdded:Disconnect() end
    if multiEquipChildRemoved then multiEquipChildRemoved:Disconnect() end
    if multiEquipBackpackAdded then multiEquipBackpackAdded:Disconnect() end
    multiEquipChildAdded = newChar.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and holdingF1 then
            lastEquipTime = tick()
            if not table.find(multiTools, child) then
                table.insert(multiTools, child)
                table.insert(multiEquippedNames, child.Name)
            end
        end
    end)
    multiEquipChildRemoved = newChar.ChildRemoved:Connect(function(child)
        if not child:IsA("Tool") or not holdingF1 then return end
        task.defer(function()
            task.wait(0.06)
            local isSwitch = (tick() - lastEquipTime) < 0.13
            if isSwitch then
                if child and child.Parent ~= newChar and holdingF1 then
                    child.Parent = newChar
                end
            else
                for i = #multiTools, 1, -1 do
                    if multiTools[i] == child then table.remove(multiTools, i) break end
                end
                for i = #multiEquippedNames, 1, -1 do
                    if multiEquippedNames[i] == child.Name then table.remove(multiEquippedNames, i) break end
                end
                for _, tool in ipairs(multiTools) do
                    if tool and tool.Parent ~= newChar then
                        tool.Parent = newChar
                    end
                end
            end
        end)
    end)
    multiEquipBackpackAdded = player.Backpack.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and holdingF1 then
            task.defer(function()
                if child.Parent == player.Backpack and holdingF1 then
                    child.Parent = newChar
                end
            end)
        end
    end)
end
local function onCharacterAdded(newChar)
    char = newChar
    currentTool = nil
    selectedTool = nil
    if keepAfterSpawn then
        if daHoodEnabled then
            assignDaHoodLayout()
        end
        for _, t in ipairs(player.Backpack:GetChildren()) do
            if t:IsA("Tool") and persistentOffsets[t.Name] then
                offsets[t] = deserializeCFrame(persistentOffsets[t.Name])
                ensureOriginalGrip(t)
            end
        end
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then
                if persistentOffsets[t.Name] then
                    offsets[t] = deserializeCFrame(persistentOffsets[t.Name])
                end
                ensureOriginalGrip(t)
                applyOffset(t)
            end
        end
    else
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then
                ensureOriginalGrip(t)
                applyOffset(t)
            end
        end
    end
    newChar.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            if daHoodEnabled then
                assignDaHoodLayout()
            else
                applyPersistentToToolIfNeeded(child)
                refreshToolList()
            end
        end
    end)
    newChar.ChildRemoved:Connect(function()
        if daHoodEnabled then
            assignDaHoodLayout()
        else
            refreshToolList()
        end
    end)
    refreshToolList()
    -- Re-equip multi tools + re-setup connections so F1 multi-equip ALWAYS works after respawn
    multiTools = {}
    for _, name in ipairs(multiEquippedNames) do
        for _, tool in ipairs(player.Backpack:GetChildren()) do
            if tool:IsA("Tool") and tool.Name == name then
                tool.Parent = newChar
                ensureOriginalGrip(tool)
                applyPersistentToToolIfNeeded(tool)
                table.insert(multiTools, tool)
                task.wait(0.05) -- tiny delay so Roblox registers the tool properly
                break
            end
        end
    end
    setupMultiEquipConnections(newChar)
end
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end
-- initial refresh & open animation
refreshToolList()
frame.Position = UDim2.new(1, 0, 0.5, -350)
local tween = TweenService:Create(frame, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(1, -310, 0.5, -350)})
tween:Play()
-- -------------------------
-- TARGETING MODE: additions + X/Z inversion fix (position only; rotation manual)
-- -------------------------
local targeting = false
local lockedTargetPlayer = nil
local lockedTargetHead = nil
local mouse = player:GetMouse()
-- Target Button (placed in the main frame)
local targetButton = Instance.new("TextButton")
targetButton.Size = UDim2.new(0, 110, 0, 26)
targetButton.Position = UDim2.new(0, MAIN_W/2 - 55, 0, 8) -- center-ish along top
targetButton.Text = "Target: Off"
targetButton.BackgroundColor3 = Color3.fromRGB(60,60,120)
targetButton.TextColor3 = Color3.fromRGB(255,255,255)
targetButton.Font = Enum.Font.SourceSans
targetButton.TextSize = 12
targetButton.Parent = frame
-- Rapid Equip Button (adjusted position for taller UI)
local rapidEquipButton = Instance.new("TextButton")
rapidEquipButton.Size = UDim2.new(0, 110, 0, 26)
rapidEquipButton.Position = UDim2.new(0, MAIN_W/2 - 55, 0, 620)
rapidEquipButton.Text = "Rapid Equip: Off"
rapidEquipButton.BackgroundColor3 = Color3.fromRGB(80,60,120)
rapidEquipButton.TextColor3 = Color3.fromRGB(255,255,255)
rapidEquipButton.Font = Enum.Font.SourceSans
rapidEquipButton.TextSize = 12
rapidEquipButton.Parent = frame
rapidEquipButton.MouseButton1Click:Connect(function()
    rapidEquipEnabled = not rapidEquipEnabled
    rapidEquipButton.Text = "Rapid Equip: " .. (rapidEquipEnabled and "On" or "Off")
end)
-- NEW: Rapid Equip Mode Button (little button to cycle speeds)
local rapidEquipModeButton = Instance.new("TextButton")
rapidEquipModeButton.Size = UDim2.new(0, 110, 0, 26)
rapidEquipModeButton.Position = UDim2.new(0, MAIN_W/2 + 60, 0, 620) -- Right next to the toggle
rapidEquipModeButton.Text = "Speed: Normal"
rapidEquipModeButton.BackgroundColor3 = Color3.fromRGB(100,100,60)
rapidEquipModeButton.TextColor3 = Color3.fromRGB(255,255,255)
rapidEquipModeButton.Font = Enum.Font.SourceSans
rapidEquipModeButton.TextSize = 12
rapidEquipModeButton.Parent = frame
rapidEquipModeButton.MouseButton1Click:Connect(function()
    currentRapidModeIndex = (currentRapidModeIndex % #rapidEquipModes) + 1
    local mode = rapidEquipModes[currentRapidModeIndex]
    rapidEquipModeButton.Text = "Speed: " .. mode
    if mode == "Normal" then
        rapidEquipDelay = 0.01
    elseif mode == "Slower" then
        rapidEquipDelay = 0.05
    elseif mode == "Slowest" then
        rapidEquipDelay = 0.1
    end
end)
-- NEW: Fix Tools Button (resets rapid/orbit bugs without resetting character)
local fixToolsButton = Instance.new("TextButton")
fixToolsButton.Size = UDim2.new(0, 220, 0, 30)
fixToolsButton.Position = UDim2.new(0, MAIN_W/2 - 110, 0, 660) -- Below rapid equip row
fixToolsButton.Text = "Fix Tools (Reset Bugs)"
fixToolsButton.BackgroundColor3 = Color3.fromRGB(120,60,60)
fixToolsButton.TextColor3 = Color3.fromRGB(255,255,255)
fixToolsButton.Font = Enum.Font.SourceSansBold
fixToolsButton.TextSize = 14
fixToolsButton.Parent = frame
fixToolsButton.MouseButton1Click:Connect(function()
    -- Disable rapid and orbit
    rapidEquipEnabled = false
    rapidEquipButton.Text = "Rapid Equip: Off"
    rapidEquipDelay = 0.01 -- Reset to normal
    rapidEquipModeButton.Text = "Speed: Normal"
    currentRapidModeIndex = 1
    orbitEnabled = false
    orbitButton.Text = "Orbit: Off"
    if orbitConn then
        orbitConn:Disconnect()
        orbitConn = nil
    end
    orbitTools = {}
    orbitAngles = {}
    orbitBasePositions = {}
    -- Refresh all equipped tools (re-parent once + re-apply offset)
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                -- One-time re-parent to force refresh (fixes desync from spam)
                child.Parent = player.Backpack
                task.wait(0.01) -- Tiny wait to let Roblox process
                child.Parent = char
                ensureOriginalGrip(child)
                applyOffset(child) -- Re-apply custom grip
            end
        end
    end
    -- Optional: refresh UI/tool list
    refreshToolList()
    print("Tools fixed — rapid/orbit disabled, grips refreshed.")
end)
-- Rapid equip loop (uses variable delay, works with orbit)
spawn(function()
    while true do
        if rapidEquipEnabled and currentTool then
            local tool = currentTool
            tool.Parent = player.Backpack
            tool.Parent = char
            applyOffset(tool)
        end
        task.wait(rapidEquipDelay)
    end
end)
-- Bottom-left temporary message UI (hidden until used)
local msgGui = Instance.new("ScreenGui")
msgGui.Name = "TargetMessageGui"
msgGui.Parent = playerGui
msgGui.ResetOnSpawn = false
local msgFrame = Instance.new("Frame")
msgFrame.Size = UDim2.new(0, 220, 0, 60)
msgFrame.Position = UDim2.new(0, 10, 1, -80)
msgFrame.BackgroundColor3 = Color3.fromRGB(20,20,20)
msgFrame.BorderSizePixel = 0
msgFrame.AnchorPoint = Vector2.new(0, 0)
msgFrame.Visible = false
msgFrame.Parent = msgGui
local avatar = Instance.new("ImageLabel")
avatar.Name = "Avatar"
avatar.Size = UDim2.new(0, 48, 0, 48)
avatar.Position = UDim2.new(0, 6, 0, 6)
avatar.BackgroundTransparency = 1
avatar.Parent = msgFrame
local nameLabel = Instance.new("TextLabel")
nameLabel.Size = UDim2.new(1, -64, 0, 24)
nameLabel.Position = UDim2.new(0, 64, 0, 8)
nameLabel.BackgroundTransparency = 1
nameLabel.TextColor3 = Color3.fromRGB(255,255,255)
nameLabel.Font = Enum.Font.SourceSansBold
nameLabel.TextSize = 16
nameLabel.Text = ""
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.Parent = msgFrame
local subLabel = Instance.new("TextLabel")
subLabel.Size = UDim2.new(1, -64, 0, 20)
subLabel.Position = UDim2.new(0, 64, 0, 30)
subLabel.BackgroundTransparency = 1
subLabel.TextColor3 = Color3.fromRGB(200,200,200)
subLabel.Font = Enum.Font.SourceSans
subLabel.TextSize = 14
subLabel.Text = "Target locked"
subLabel.TextXAlignment = Enum.TextXAlignment.Left
subLabel.Parent = msgFrame
local function showTargetMessage(targetPlayer)
    if not targetPlayer then return end
    local ok, thumbUrl = pcall(function()
        return Players:GetUserThumbnailAsync(targetPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
    end)
    if ok and thumbUrl then
        avatar.Image = thumbUrl
    else
        avatar.Image = ""
    end
    nameLabel.Text = targetPlayer.Name
    msgFrame.Position = UDim2.new(0, 10, 1, -80)
    msgFrame.Visible = true
    msgFrame.BackgroundTransparency = 1
    msgFrame.BackgroundTransparency = 0
    task.spawn(function()
        task.wait(3)
        local hideTween = TweenService:Create(msgFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
        hideTween:Play()
        hideTween.Completed:Wait()
        msgFrame.Visible = false
    end)
end
-- Find the player whose head is nearest to mouse pointer (in 2D screen distance)
local function findNearestPlayerToMouse(mx, my)
    local best, bestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and p.Character.Parent and p.Character:FindFirstChild("Head") and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
            local head = p.Character.Head
            local screenPos, onScreen = camera:WorldToViewportPoint(head.Position)
            local sx, sy = screenPos.X, screenPos.Y
            local d = (Vector2.new(sx, sy) - Vector2.new(mx, my)).Magnitude
            if d < bestDist then
                bestDist = d
                best = p
            end
        end
    end
    return best
end
-- Activate targeting mode: wait for next left click and select nearest player head
local function startTargetingMode()
    if targeting then return end
    targeting = true
    targetButton.Text = "Targeting... click a player"
    local conn
    conn = mouse.Button1Down:Connect(function()
        local mx, my = mouse.X, mouse.Y
        local found = findNearestPlayerToMouse(mx, my)
        if found and found.Character and found.Character:FindFirstChild("Head") then
            lockedTargetPlayer = found
            lockedTargetHead = found.Character.Head
            targetButton.Text = "Target: " .. found.Name
            showTargetMessage(found)
            targetOffsetFrame.Visible = true
        else
            targetButton.Text = "Target: None"
            lockedTargetPlayer = nil
            lockedTargetHead = nil
        end
        targeting = false
        conn:Disconnect()
        task.wait(0.07)
        if not lockedTargetPlayer then
            targetButton.Text = "Target: Off"
        end
    end)
end
-- Target button toggles/clears lock
targetButton.MouseButton1Click:Connect(function()
    if targeting then return end
    if lockedTargetPlayer then
        lockedTargetPlayer = nil
        lockedTargetHead = nil
        targetButton.Text = "Target: Off"
        targetOffsetFrame.Visible = false
        aimOffset = Vector3.new(0,0,0)
    else
        startTargetingMode()
    end
end)
-- Silent Aim Setup
local SilentAim = {
    Enabled = true,
    WallCheck = true,
    Prediction = 0.157,
    HitChance = 100,
    AutoPrediction = true
}
local function CalculateChance(Percentage)
    return math.random(1, 100) <= Percentage
end
spawn(function()
    while SilentAim.AutoPrediction do
        task.wait(0.05)
        local pingStr = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValueString()
        local pingSplit = string.split(pingStr, '(')
        local ping = tonumber(pingSplit[1])
        if ping > 200 and ping < 300 then
            SilentAim.Prediction = 0.18742
        elseif ping > 180 and ping < 195 then
            SilentAim.Prediction = 0.16779123
        elseif ping > 140 and ping < 180 then
            SilentAim.Prediction = 0.16
        elseif ping > 110 and ping < 140 then
            SilentAim.Prediction = 0.15934
        elseif ping < 105 then
            SilentAim.Prediction = 0.138
        elseif ping < 90 then
            SilentAim.Prediction = 0.136
        elseif ping < 80 then
            SilentAim.Prediction = 0.134
        elseif ping < 70 then
            SilentAim.Prediction = 0.131
        elseif ping < 60 then
            SilentAim.Prediction = 0.1229
        elseif ping < 50 then
            SilentAim.Prediction = 0.1225
        elseif ping < 40 then
            SilentAim.Prediction = 0.1256
        end
    end
end)
if not getgenv().DaHoodSilentAim then
    getgenv().DaHoodSilentAim = true
    local oldIndex = nil
    oldIndex = hookmetamethod(game, "__index", function(self, index)
        if SilentAim.Enabled and lockedTargetHead and CalculateChance(SilentAim.HitChance) and self:IsA("Mouse") and (index == "Hit" or index == "Target") then
            local visible = true
            if SilentAim.WallCheck then
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                rayParams.FilterDescendantsInstances = {char, camera}
                local direction = lockedTargetHead.Position - camera.CFrame.Position
                local result = workspace:Raycast(camera.CFrame.Position, direction, rayParams)
                visible = result and result.Instance:IsDescendantOf(lockedTargetPlayer.Character)
            end
            if visible then
                local velocity = lockedTargetHead.AssemblyLinearVelocity
                local aimPos = lockedTargetHead.Position + lockedTargetHead.CFrame:VectorToWorldSpace(aimOffset)
                local predPos = aimPos + velocity * SilentAim.Prediction
                local Hit = CFrame.new(predPos)
                if index == "Hit" then
                    return Hit
                elseif index == "Target" then
                    return lockedTargetHead
                end
            end
        end
        return oldIndex(self, index)
    end)
end
-- Orbit feature (reworked for FE-friendly: client-side visual only, smoother positions)
local orbitModes = {"Horizontal", "VerticalFront", "VerticalSide", "Sphere", "Helix", "Chaotic"}
local currentOrbitModeIndex = 1
local orbitButton = Instance.new("TextButton")
orbitButton.Size = UDim2.new(0, 110, 0, 26)
orbitButton.Position = UDim2.new(0, 10, 1, -105)
orbitButton.Text = "Orbit: Off"
orbitButton.BackgroundColor3 = Color3.fromRGB(120,120,60)
orbitButton.TextColor3 = Color3.fromRGB(255,255,255)
orbitButton.Font = Enum.Font.SourceSans
orbitButton.TextSize = 12
orbitButton.Parent = frame
local modeButton = Instance.new("TextButton")
modeButton.Size = UDim2.new(0, 120, 0, 26)
modeButton.Position = UDim2.new(0, 130, 1, -105)
modeButton.Text = "Orbit Mode: Horizontal"
modeButton.BackgroundColor3 = Color3.fromRGB(120,60,120)
modeButton.TextColor3 = Color3.fromRGB(255,255,255)
modeButton.Font = Enum.Font.SourceSans
modeButton.TextSize = 12
modeButton.Parent = frame
modeButton.MouseButton1Click:Connect(function()
    currentOrbitModeIndex = (currentOrbitModeIndex % #orbitModes) + 1
    orbitMode = orbitModes[currentOrbitModeIndex]
    modeButton.Text = "Orbit Mode: " .. orbitMode
end)
local function getSpherePositions(n, r)
    local positions = {}
    local inc = math.pi * (3 - math.sqrt(5))
    local off = 2 / n
    for i = 0, n - 1 do
        local y = i * off - 1 + (off / 2)
        local rad = math.sqrt(1 - y * y)
        local phi = i * inc
        local x = math.cos(phi) * rad
        local z = math.sin(phi) * rad
        table.insert(positions, Vector3.new(x, y, z) * r)
    end
    return positions
end
local handles = {}
local orbitParts = {}
local movers = {}
local connections = {}
local toolNames = {}
local offset = 8
local speed = 1
local orbitNumericMode = 1 -- Renamed to avoid conflict with other mode vars
local rot = 0
local toolRotSpeed = 1
local lerpSpeed = 1
local targetHRP = char:WaitForChild("HumanoidRootPart")
local tweenEnabled = false
local tweenDelay = 0.5
local lastTargetChange = os.clock()
local function cleanupTool(h)
    local index = table.find(handles, h)
    if index then
        if orbitParts[index] then orbitParts[index]:Destroy() end
        if movers[h] then
            if movers[h].align then movers[h].align:Destroy() end
            if movers[h].angular then movers[h].angular:Destroy() end
            movers[h] = nil
        end
        if connections[h] then connections[h]:Disconnect() connections[h] = nil end
        table.remove(orbitParts, index)
        table.remove(handles, index)
        table.remove(toolNames, index)
    end
end
local function setupTool(v)
    if not v or not v:IsA("Tool") then return end
    local h = v:FindFirstChild("Handle")
    if not h or table.find(handles, h) then return end
    v.Parent = char
    v.Parent = player.Backpack
    v.Parent = workspace
    v.Parent = char
    local ra = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
    if ra then
        local grip = ra:FindFirstChild("RightGrip")
        if grip then grip:Destroy() end
    end
    connections[h] = v.AncestryChanged:Connect(function(_, parent)
        if parent ~= char then cleanupTool(h) end
    end)
    table.insert(handles, h)
    table.insert(toolNames, v.Name)
    local index = #handles
    local p = Instance.new("Part", workspace)
    p.Name = "OrbitReference_" .. v.Name
    p.Anchored, p.CanCollide, p.Transparency = true, false, 1
    p.Size = Vector3.new(0.2, 0.2, 0.2)
    p.Position = targetHRP.Position
    orbitParts[index] = p
    local av = Instance.new("BodyAngularVelocity", h)
    av.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    av.P = 1250
    local ap = Instance.new("AlignPosition", h)
    ap.MaxForce, ap.MaxVelocity, ap.Responsiveness = math.huge, math.huge, 200
    ap.Attachment0 = Instance.new("Attachment", h)
    ap.Attachment1 = Instance.new("Attachment", p)
    movers[h] = {align = ap, angular = av}
end
local function handleCharacter(character)
    local function destroyGrip()
        for _, obj in ipairs(character:GetDescendants()) do
            if obj:IsA("Motor6D") and obj.Name == "RightGrip" then
                obj:Destroy()
            end
        end
    end
    destroyGrip()
    character.DescendantAdded:Connect(function(obj)
        if obj:IsA("Motor6D") and obj.Name == "RightGrip" then
            obj:Destroy()
        end
    end)
end
if player.Character then
    handleCharacter(player.Character)
end
local SETTINGS = {
    VelocityY = 220.290009,
    SimulationRadius = 2147483647
}
local lastHRPPos = targetHRP.Position
local hrpVel = Vector3.zero
RunService.Stepped:Connect(function()
    settings().Physics.AllowSleep = false
    player.SimulationRadius = SETTINGS.SimulationRadius
end)
RunService.PostSimulation:Connect(function(dt)
    if not targetHRP or not targetHRP.Parent then return end
    local currentTime = os.clock()
    local currentPos = targetHRP.Position
    if dt > 0 then
        hrpVel = (currentPos - lastHRPPos) / dt
    end
    lastHRPPos = currentPos
    local predictedHRPPos = currentPos + hrpVel * 0.1
    local antiSleep = Vector3.new(0, math.sin(currentTime * 15) * 0.0015, 0)
    local gravityAxis = SETTINGS.VelocityY + math.sin(currentTime)
    for _, h in ipairs(handles) do
        if h and h:IsA("BasePart") then
            if h.ReceiveAge == 0 then
                local dir = predictedHRPPos - h.Position
                local xz = Vector3.new(dir.X, 0, dir.Z)
                local velXZ = Vector3.zero
                if xz.Magnitude > 0 then
                    velXZ = xz.Unit * xz.Magnitude * 2
                end
                h.AssemblyLinearVelocity = Vector3.new(velXZ.X, gravityAxis, velXZ.Z)
                h.AssemblyAngularVelocity = Vector3.new(0, math.huge, math.huge)
                h.CFrame = h.CFrame + antiSleep
            end
        end
    end
end)
local childAddedConn = nil
orbitButton.MouseButton1Click:Connect(function()
    orbitEnabled = not orbitEnabled
    orbitButton.Text = "Orbit: " .. (orbitEnabled and "On" or "Off")
    if orbitEnabled then
        if lockedTargetPlayer then
            targetHRP = lockedTargetPlayer.Character:FindFirstChild("HumanoidRootPart") or targetHRP
        else
            targetHRP = char:WaitForChild("HumanoidRootPart")
        end
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") then
                setupTool(tool)
            end
        end
        childAddedConn = char.ChildAdded:Connect(function(c)
            if c:IsA("Tool") then
                task.wait()
                setupTool(c)
            end
        end)
        if orbitConn then orbitConn:Disconnect() end
        orbitConn = RunService.RenderStepped:Connect(function()
            if not orbitEnabled then return end
            if not targetHRP or not targetHRP.Parent then targetHRP = char:WaitForChild("HumanoidRootPart") end
            rot = rot + speed
            local time = os.clock()
            local numTools = #orbitParts
            for i, p in ipairs(orbitParts) do
                if p and p.Parent then
                    local angle = math.rad(rot + (360 / numTools) * i)
                    local targetCFrame = CFrame.new()
                    if orbitNumericMode == 1 then
                        targetCFrame = targetHRP.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(offset, 0, 0)
                    elseif orbitNumericMode == 2 then
                        targetCFrame = targetHRP.CFrame * CFrame.new(math.cos(angle) * offset, math.sin(time * 2 + i) * 2, math.sin(angle) * offset)
                    elseif orbitNumericMode == 3 then
                        targetCFrame = targetHRP.CFrame * CFrame.Angles(angle, angle, 0) * CFrame.new(offset, 0, 0)
                    elseif orbitNumericMode == 4 then
                        targetCFrame = CFrame.new(targetHRP.Position) * CFrame.Angles(0, angle, 0) * CFrame.new(offset, 0, 0)
                    elseif orbitNumericMode == 5 then
                        targetCFrame = targetHRP.CFrame * CFrame.new(math.cos(angle) * offset, math.sin(angle) * offset, math.sin(angle) * offset)
                    elseif orbitNumericMode == 6 then
                        targetCFrame = targetHRP.CFrame * CFrame.Angles(angle, 0, angle) * CFrame.new(offset, 0, 0)
                    else
                        local subType = orbitNumericMode % 8
                        local safeSpeed = time * (1 + (orbitNumericMode % 5) / 10)
                        if subType == 0 then
                            local petalCount = (orbitNumericMode % 5) + 3
                            local wave = math.sin(angle * petalCount + safeSpeed)
                            local currentOffset = offset + (wave * (offset / 3))
                            targetCFrame = targetHRP.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(currentOffset, 0, 0)
                        elseif subType == 1 then
                            local tiltX = math.rad((orbitNumericMode * 15) % 360) + (time * 0.5)
                            local tiltZ = math.rad((orbitNumericMode * 45) % 360)
                            targetCFrame = targetHRP.CFrame * CFrame.Angles(tiltX, angle, tiltZ) * CFrame.new(offset, 0, 0)
                        elseif subType == 2 then
                            local height = math.sin(angle + (time * 2)) * (offset * 0.8)
                            local twist = math.cos(safeSpeed + (i/2)) * 2
                            targetCFrame = targetHRP.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(offset + twist, height, 0)
                        elseif subType == 3 then
                            local noiseX = math.sin(angle * ((orbitNumericMode % 3) + 1))
                            local noiseY = math.cos(angle * ((orbitNumericMode % 2) + 1))
                            targetCFrame = targetHRP.CFrame * CFrame.Angles(angle, 0, angle) * CFrame.new(offset * noiseX, offset * noiseY, 0)
                        elseif subType == 4 then
                            local fig8X = math.cos(angle) * offset
                            local fig8Z = math.sin(angle * 2) * offset
                            targetCFrame = targetHRP.CFrame * CFrame.new(fig8X, 0, fig8Z)
                        elseif subType == 5 then
                            local spikeFreq = (orbitNumericMode % 4) + 3
                            local height = math.abs(math.sin(angle * spikeFreq)) * (offset * 0.8)
                            targetCFrame = targetHRP.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(offset, height - (offset/2), 0)
                        elseif subType == 6 then
                            local band = (i % 3)
                            local tiltAngle = math.rad(60 * band)
                            targetCFrame = targetHRP.CFrame * CFrame.Angles(tiltAngle, angle, 0) * CFrame.new(offset, 0, 0)
                        elseif subType == 7 then
                            local pulse = math.sin(safeSpeed * 2) * (offset * 0.4)
                            targetCFrame = targetHRP.CFrame * CFrame.Angles(0, angle, 0) * CFrame.new(offset + pulse, 0, 0)
                        end
                        if orbitNumericMode > 20 then
                            local slowWobble = math.rad(math.sin(time) * 15)
                            targetCFrame = targetCFrame * CFrame.Angles(slowWobble, 0, slowWobble)
                        end
                    end
                    local dt = RunService.RenderStepped:Wait()
                    local alpha = 1 - math.exp(-lerpSpeed * dt)
                    p.CFrame = p.CFrame:Lerp(targetCFrame, alpha)
                    local h = handles[i]
                    if h and movers[h] then
                        local spinVar = (orbitNumericMode % 30)
                        movers[h].angular.AngularVelocity = Vector3.new(0, toolRotSpeed * (10 + spinVar), 0)
                    end
                end
            end
            if sethiddenproperty then pcall(function() sethiddenproperty(player, "SimulationRadius", math.huge) end) end
        end)
    else
        if orbitConn then orbitConn:Disconnect() end
        if childAddedConn then childAddedConn:Disconnect() end
        for _, h in ipairs(handles) do
            cleanupTool(h)
        end
        handles = {}
        orbitParts = {}
        movers = {}
        connections = {}
        toolNames = {}
    end
end)
-- Little toggle button for UI
local toggleUIButton = Instance.new("TextButton")
toggleUIButton.Size = UDim2.new(0, 50, 0, 50)
toggleUIButton.Position = UDim2.new(0, 10, 0, 10)
toggleUIButton.Text = "UI"
toggleUIButton.BackgroundColor3 = Color3.fromRGB(100,100,100)
toggleUIButton.TextColor3 = Color3.fromRGB(255,255,255)
toggleUIButton.Font = Enum.Font.SourceSansBold
toggleUIButton.TextSize = 20
toggleUIButton.Parent = screenGui
toggleUIButton.MouseButton1Click:Connect(function()
    frame.Visible = not frame.Visible
    selectorFrame.Visible = frame.Visible and toggleSelectorButton.Text == "Hide Selector"
end)
print("Tool adjuster loaded. Added 'Fix Tools' button to reset rapid/orbit bugs without resetting character.")
-- TARGETING FIXES
local originalRightGripC1 = nil
-- UPDATED: head snap with LIVE offset (still butter smooth)
RunService.Heartbeat:Connect(function()
    local rightGrip = char and char:FindFirstChild("RightGrip", true)
    if lockedTargetHead and lockedTargetHead.Parent and rightGrip and char then
        if originalRightGripC1 == nil then
            originalRightGripC1 = rightGrip.C1
        end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local aimPos = lockedTargetHead.Position + lockedTargetHead.CFrame:VectorToWorldSpace(aimOffset)
            local desired
            if targetMode == "Normal" then
                desired = CFrame.lookAt(aimPos, hrp.Position)
            else
                desired = lockedTargetHead.CFrame * CFrame.new(aimOffset)
            end
            local p0 = rightGrip.Part0.CFrame
            local c0 = rightGrip.C0
            local temp = p0 * c0
            local c1_inv = temp:Inverse() * desired
            rightGrip.C1 = c1_inv:Inverse()
        end
    else
        if rightGrip and originalRightGripC1 then
            rightGrip.C1 = originalRightGripC1
            originalRightGripC1 = nil
        end
    end
end)
-- Silent Aim (always enabled when locked)
local SilentAim = {
    Enabled = true,
    WallCheck = true,
    Prediction = 0.157,
    HitChance = 100,
    AutoPrediction = true
}
local function CalculateChance(Percentage)
    return math.random(1, 100) <= Percentage
end
spawn(function()
    while SilentAim.AutoPrediction do
        task.wait(0.05)
        local pingStr = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValueString()
        local ping = tonumber(string.split(pingStr, '(')[1])
        if ping > 200 then SilentAim.Prediction = 0.18742
        elseif ping > 180 then SilentAim.Prediction = 0.16779123
        elseif ping > 140 then SilentAim.Prediction = 0.16
        elseif ping > 110 then SilentAim.Prediction = 0.15934
        elseif ping < 105 then SilentAim.Prediction = 0.138
        elseif ping < 90 then SilentAim.Prediction = 0.136
        elseif ping < 80 then SilentAim.Prediction = 0.134
        elseif ping < 70 then SilentAim.Prediction = 0.131
        elseif ping < 60 then SilentAim.Prediction = 0.1229
        elseif ping < 50 then SilentAim.Prediction = 0.1225
        elseif ping < 40 then SilentAim.Prediction = 0.1256
        end
    end
end)
if not getgenv().DaHoodSilentAim then
    getgenv().DaHoodSilentAim = true
    local oldIndex = nil
    oldIndex = hookmetamethod(game, "__index", function(self, index)
        if SilentAim.Enabled and lockedTargetHead and CalculateChance(SilentAim.HitChance) and self:IsA("Mouse") and (index == "Hit" or index == "Target") then
            local visible = true
            if SilentAim.WallCheck then
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                rayParams.FilterDescendantsInstances = {char, camera}
                local direction = lockedTargetHead.Position - camera.CFrame.Position
                local result = workspace:Raycast(camera.CFrame.Position, direction, rayParams)
                visible = result and result.Instance:IsDescendantOf(lockedTargetPlayer.Character)
            end
            if visible then
                local velocity = lockedTargetHead.AssemblyLinearVelocity
                local aimPos = lockedTargetHead.Position + lockedTargetHead.CFrame:VectorToWorldSpace(aimOffset)
                local predPos = aimPos + velocity * SilentAim.Prediction
                local Hit = CFrame.new(predPos)
                if index == "Hit" then return Hit end
                if index == "Target" then return lockedTargetHead end
            end
        end
        return oldIndex(self, index)
    end)
end
-- NEW: Under feature integration
local underEnabled = false
local underConnection = nil
local noclipConnection = nil
local originalCollides = {}
local originalHumanoidState = nil
local savedPosition = nil
-- Function to enable/disable full noclip
local function setNoClip(enable)
    local localChar = player.Character
    if not localChar then return end
    local humanoid = localChar:FindFirstChildOfClass("Humanoid")
    if enable then
        originalCollides = {}
        originalHumanoidState = humanoid and humanoid:GetState() or nil
        for _, descendant in ipairs(localChar:GetDescendants()) do
            if descendant:IsA("BasePart") then
                originalCollides[descendant] = descendant.CanCollide
            end
        end
        if noclipConnection then noclipConnection:Disconnect() end
        noclipConnection = RunService.Stepped:Connect(function()
            for _, descendant in ipairs(localChar:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    descendant.CanCollide = false
                end
            end
        end)
        if humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        end
    else
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
        for part, value in pairs(originalCollides) do
            if part.Parent then -- If part still exists
                part.CanCollide = value
            end
        end
        originalCollides = {}
        if humanoid and originalHumanoidState then
            humanoid:ChangeState(originalHumanoidState)
        elseif humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end
end
-- Under button (appears when target is locked)
local underButton = Instance.new("TextButton")
underButton.Size = UDim2.new(0, 110, 0, 26)
underButton.Position = UDim2.new(0, MAIN_W/2 - 55, 0, 40) -- Below targetButton
underButton.Text = "Under: Off"
underButton.BackgroundColor3 = Color3.fromRGB(60,120,60)
underButton.TextColor3 = Color3.fromRGB(255,255,255)
underButton.Font = Enum.Font.SourceSans
underButton.TextSize = 12
underButton.Parent = frame
underButton.MouseButton1Click:Connect(function()
    if not lockedTargetPlayer then return end -- Only if targeted
    underEnabled = not underEnabled
    underButton.Text = "Under: " .. (underEnabled and "On" or "Off")
    if underEnabled then
        local localChar = player.Character
        if localChar then
            local hrp = localChar:FindFirstChild("HumanoidRootPart")
            if hrp then
                savedPosition = hrp.CFrame
            end
        end
        setNoClip(true)
        local dist = 15 -- Default 15 studs
        local targetHRP = lockedTargetPlayer.Character:WaitForChild("HumanoidRootPart")
        if underConnection then underConnection:Disconnect() end
        underConnection = RunService.Heartbeat:Connect(function()
            if not underEnabled or not lockedTargetPlayer or not lockedTargetPlayer.Character or not targetHRP.Parent then
                if underConnection then underConnection:Disconnect() end
                return
            end
            local localChar = player.Character
            if localChar then
                local hrp = localChar:FindFirstChild("HumanoidRootPart")
                if hrp then
                    -- Calculate position under target: target's HRP - distance below feet
                    -- Assume ~3 studs from target HRP to feet, then -dist below that
                    local offset = - (3 + dist)
                    hrp.CFrame = targetHRP.CFrame * CFrame.new(0, offset, 0)
                end
            end
        end)
    else
        if underConnection then underConnection:Disconnect() underConnection = nil end
        local localChar = player.Character
        if localChar and savedPosition then
            local hrp = localChar:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = savedPosition
            end
            savedPosition = nil
        end
        setNoClip(false)
    end
end)
-- === TARGET OFFSET ADJUSTER UI (pops when you lock target) ===
local targetOffsetGui = Instance.new("ScreenGui")
targetOffsetGui.Name = "TargetOffsetUI"
targetOffsetGui.ResetOnSpawn = false
targetOffsetGui.Parent = playerGui
targetOffsetFrame = Instance.new("Frame")
targetOffsetFrame.Size = UDim2.new(0, 260, 0, 420)
targetOffsetFrame.Position = UDim2.new(0, 340, 0.5, -190)
targetOffsetFrame.BackgroundColor3 = Color3.fromRGB(28,28,35)
targetOffsetFrame.BorderSizePixel = 0
targetOffsetFrame.Active = true
targetOffsetFrame.Draggable = true
targetOffsetFrame.Visible = false
targetOffsetFrame.Parent = targetOffsetGui
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,0,0,35)
title.BackgroundColor3 = Color3.fromRGB(20,20,28)
title.Text = "🎯 LIVE HEAD OFFSET"
title.TextColor3 = Color3.fromRGB(0,255,120)
title.Font = Enum.Font.GothamBold
title.TextSize = 17
title.Parent = targetOffsetFrame
local sub = Instance.new("TextLabel")
sub.Size = UDim2.new(1,0,0,20)
sub.Position = UDim2.new(0,0,0,35)
sub.BackgroundTransparency = 1
sub.Text = "drag while locked - tool follows perfectly"
sub.TextColor3 = Color3.fromRGB(170,170,170)
sub.TextSize = 13
sub.Parent = targetOffsetFrame
local offsetSliders = {}
local function makeSlider(name, yPos, col)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,-20,0,55)
    f.Position = UDim2.new(0,10,0,yPos)
    f.BackgroundTransparency = 1
    f.Parent = targetOffsetFrame
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0,50,0,20)
    lbl.Position = UDim2.new(0,0,0,8)
    lbl.Text = name..":"
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(255,255,255)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 16
    lbl.Parent = f
    local sF = Instance.new("Frame")
    sF.Size = UDim2.new(0.68,0,0,8)
    sF.Position = UDim2.new(0.2,0,0,28)
    sF.BackgroundColor3 = Color3.fromRGB(45,45,55)
    sF.BorderSizePixel = 0
    sF.Parent = f
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0,14,0,14)
    btn.Position = UDim2.new(0.5,-7,0,-3)
    btn.BackgroundColor3 = col
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.Parent = sF
    local val = Instance.new("TextLabel")
    val.Size = UDim2.new(0,60,0,20)
    val.Position = UDim2.new(0.88,0,0,8)
    val.BackgroundTransparency = 1
    val.Text = "0.00"
    val.TextColor3 = Color3.fromRGB(255,255,255)
    val.Font = Enum.Font.Gotham
    val.TextSize = 15
    val.Parent = f
    local dragging = false
    btn.MouseButton1Down:Connect(function() dragging = true end)
    UIS.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local rel = math.clamp((inp.Position.X - sF.AbsolutePosition.X) / sF.AbsoluteSize.X, 0, 1)
            local newVal = -4 + rel * 8
            if name == "X" then aimOffset = Vector3.new(newVal, aimOffset.Y, aimOffset.Z)
            elseif name == "Y" then aimOffset = Vector3.new(aimOffset.X, newVal, aimOffset.Z)
            else aimOffset = Vector3.new(aimOffset.X, aimOffset.Y, newVal) end
            val.Text = string.format("%.2f", newVal)
            btn.Position = UDim2.new(rel, -7, 0, -3)
        end
    end)
    UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    offsetSliders[name] = {btn = btn, label = val}
end
makeSlider("X", 70, Color3.fromRGB(255,80,80))
makeSlider("Y", 135, Color3.fromRGB(80,255,80))
makeSlider("Z", 200, Color3.fromRGB(80,80,255))
-- NEW: Mode switch button
local modeBtn = Instance.new("TextButton")
modeBtn.Size = UDim2.new(0.9,0,0,36)
modeBtn.Position = UDim2.new(0.05,0,0,260)
modeBtn.BackgroundColor3 = Color3.fromRGB(60,60,70)
modeBtn.Text = "Mode: " .. targetMode
modeBtn.TextColor3 = Color3.new(1,1,1)
modeBtn.Font = Enum.Font.GothamBold
modeBtn.TextSize = 15
modeBtn.Parent = targetOffsetFrame
modeBtn.MouseButton1Click:Connect(function()
    targetMode = targetMode == "Normal" and "Align" or "Normal"
    modeBtn.Text = "Mode: " .. targetMode
end)
-- NEW: No Anims button
local noAnimsBtn = Instance.new("TextButton")
noAnimsBtn.Size = UDim2.new(0.9,0,0,36)
noAnimsBtn.Position = UDim2.new(0.05,0,0,310)
noAnimsBtn.BackgroundColor3 = Color3.fromRGB(60,60,70)
noAnimsBtn.Text = "No Anims: Off"
noAnimsBtn.TextColor3 = Color3.new(1,1,1)
noAnimsBtn.Font = Enum.Font.GothamBold
noAnimsBtn.TextSize = 15
noAnimsBtn.Parent = targetOffsetFrame
-- === AUTO NO ANIMS ON TARGET (exactly what you wanted) ===
local function enableNoAnims()
    noAnimsEnabled = true
    noAnimsBtn.Text = "No Anims: On"
    local animate = char and char:FindFirstChild("Animate")
    if animate then animate:Destroy() end
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
            track:Stop()
        end
    end
    if noAnimsConn then noAnimsConn:Disconnect() end
    noAnimsConn = RunService.Heartbeat:Connect(function()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
                track:Stop()
            end
        end
    end)
end
local function disableNoAnims()
    noAnimsEnabled = false
    noAnimsBtn.Text = "No Anims: Off"
    if noAnimsConn then
        noAnimsConn:Disconnect()
        noAnimsConn = nil
    end
    if char and originalAnimate and not char:FindFirstChild("Animate") then
        originalAnimate:Clone().Parent = char
    end
end
-- manual button still works
noAnimsBtn.MouseButton1Click:Connect(function()
    if noAnimsEnabled then
        disableNoAnims()
    else
        enableNoAnims()
    end
end)
-- AUTO MAGIC: enables when you target, disables when you untarget
local lastTargetState = false
RunService.Heartbeat:Connect(function()
    local currentlyTargeted = lockedTargetPlayer ~= nil
    if currentlyTargeted ~= lastTargetState then
        lastTargetState = currentlyTargeted
        if currentlyTargeted then
            enableNoAnims()
        else
            disableNoAnims()
        end
    end
end)
-- reset
local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(0.9,0,0,36)
resetBtn.Position = UDim2.new(0.05,0,0,360)
resetBtn.BackgroundColor3 = Color3.fromRGB(60,60,70)
resetBtn.Text = "RESET TO CENTER"
resetBtn.TextColor3 = Color3.new(1,1,1)
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 15
resetBtn.Parent = targetOffsetFrame
resetBtn.MouseButton1Click:Connect(function()
    aimOffset = Vector3.new(0,0,0)
    for _,s in pairs(offsetSliders) do
        s.label.Text = "0.00"
        s.btn.Position = UDim2.new(0.5,-7,0,-3)
    end
end)
targetOffsetFrame.Visible = false
-- F1 hold for multi-equip (now fully respawn-proof)
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F1 then
        holdingF1 = true
        multiTools = {}
        multiEquippedNames = {}
        for _, item in char:GetChildren() do
            if item:IsA("Tool") then
                table.insert(multiTools, item)
                table.insert(multiEquippedNames, item.Name)
            end
        end
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.F1 then
        holdingF1 = false
    end
end)

-- === BOOMBOX FORCE FIX (this is what actually makes it work) ===
local boomboxForceConn = RunService.Heartbeat:Connect(function()
    if not char then return end
    
    local boombox = char:FindFirstChild("Boombox")
    if boombox then
        ensureOriginalGrip(boombox)
        
        local offset = offsets[boombox]
        if not offset and keepAfterSpawn then
            local pers = persistentOffsets["Boombox"]
            if pers then
                offset = deserializeCFrame(pers)
            end
        end
        offset = offset or CFrame.new()
        
        local base = originalGrips[boombox] or CFrame.new()
        boombox.Grip = base * offset   -- FORCE EVERY FRAME
    end
end)

print("✅ EVERYTHING LOADED (supposingly)")
