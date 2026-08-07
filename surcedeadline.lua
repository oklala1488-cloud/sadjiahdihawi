local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local Config = {
    TriggerbotEnabled = true,
    EspEnabled = true,
    TeamCheck = true,

    ShootDelay = 0.04,
    MaxDistance = 2000,

    TargetHitboxes = {
        head = true,
        torso = true,
        left_arm = true,
        right_arm = true,
        left_leg = true,
        right_leg = true,
    },

    EnemyColor = Color3.fromRGB(255, 50, 50),
    TeammateColor = Color3.fromRGB(50, 150, 255),

    ToggleEspKey = Enum.KeyCode.F1,
    ToggleTriggerKey = Enum.KeyCode.F2,
    ToggleTeamCheckKey = Enum.KeyCode.F3,
}

local State = {
    MyCharacter = nil,
    MyTeam = nil,               -- "defend" / "attack"
    CanShoot = true,
    EspObjects = {},            -- [model] = Highlight
    TeamByCid = {},             -- cid -> "defend"/"attack"
}

local CharactersFolder = Workspace:FindFirstChild("characters") or Workspace
local IgnoreFolder = Workspace:FindFirstChild("ignore")


local DefendSpawns = {}
local AttackSpawns = {}

local function loadSpawns()
    if not IgnoreFolder then return end
    DefendSpawns = {}
    AttackSpawns = {}
    local function collect(folder, tbl)
        if not folder then return end
        for _, d in ipairs(folder:GetDescendants()) do
            if d:IsA("BasePart") then
                table.insert(tbl, d.Position)
            end
        end
    end
    collect(IgnoreFolder:FindFirstChild("defend_spawns"), DefendSpawns)
    collect(IgnoreFolder:FindFirstChild("attack_spawns"), AttackSpawns)
    print("Спавны загружены: защита " .. #DefendSpawns .. ", атака " .. #AttackSpawns)
end
loadSpawns()

local function ClassifyModel(model)
    if #DefendSpawns == 0 and #AttackSpawns == 0 then return nil end
    if not model then return nil end
    local root = model:FindFirstChild("humanoid_root_part") or model:FindFirstChild("Head")
    if not root then return nil end
    local pos = root.Position

    local distDef = math.huge
    local distAtt = math.huge
    for _, s in ipairs(DefendSpawns) do
        local d = (s - pos).Magnitude
        if d < distDef then distDef = d end
    end
    for _, s in ipairs(AttackSpawns) do
        local d = (s - pos).Magnitude
        if d < distAtt then distAtt = d end
    end

    if distDef < 35 and distDef < distAtt then return "defend" end
    if distAtt < 35 and distAtt < distDef then return "attack" end
    return nil 
end

local function IsTeammate(cid)
    if not Config.TeamCheck then return false end
    local team = State.TeamByCid[cid]
    if not team or not State.MyTeam then return false end
    return team == State.MyTeam
end

local function GetEspColor(cid)
    return IsTeammate(cid) and Config.TeammateColor or Config.EnemyColor
end

local function FindBarrel()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local camPos = cam.CFrame.Position
    if not IgnoreFolder then return nil end
    for _, obj in ipairs(IgnoreFolder:GetChildren()) do
        if obj:IsA("Model") and obj.Name:match("^viewmodel_") then
            for _, part in ipairs(obj:GetDescendants()) do
                if part:IsA("BasePart") and part.Name:lower():match("barrel") then
                    if (part.Position - camPos).Magnitude <= 10 then
                        return part
                    end
                end
            end
        end
    end
    return nil
end

local function FindGameLaserEndpoints()
    local lasers = {}
    if not IgnoreFolder then return lasers end
    local cam = Workspace.CurrentCamera
    if not cam then return lasers end
    local camPos = cam.CFrame.Position
    local bestVM, bestDist = nil, math.huge
    for _, obj in ipairs(IgnoreFolder:GetChildren()) do
        if obj:IsA("Model") and obj.Name:match("^viewmodel_") then
            local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if pp then
                local d = (pp.Position - camPos).Magnitude
                if d < bestDist and d <= 10 then
                    bestDist = d
                    bestVM = obj
                end
            end
        end
    end
    if not bestVM then return lasers end
    for _, child in ipairs(bestVM:GetDescendants()) do
        if child:IsA("Attachment") and child.Name == "current" then
            if child.Parent and child.Parent.Name == "display" then
                table.insert(lasers, child)
            end
        end
    end
    return lasers
end

local function DoBarrelRaycast(barrel, laserEndpoints)
    if not barrel or not laserEndpoints or #laserEndpoints == 0 then return nil end
    local barrelPos = barrel.Position
    local myChar = State.MyCharacter

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local ignoreList = {}
    if IgnoreFolder then table.insert(ignoreList, IgnoreFolder) end
    if myChar then table.insert(ignoreList, myChar) end

    local mapF = Workspace:FindFirstChild("map")
    if mapF then
        local main = mapF:FindFirstChild("main")
        if main then
            local env = main:FindFirstChild("environment")
            if env then
                local glass = env:FindFirstChild("glass")
                if glass then table.insert(ignoreList, glass) end
            end
        end
    end
    if CharactersFolder then
        for _, cm in ipairs(CharactersFolder:GetChildren()) do
            local hb = cm:FindFirstChild("hitbox")
            if hb then table.insert(ignoreList, hb) end
        end
    end
    rayParams.FilterDescendantsInstances = ignoreList

    local mainLaserPos = laserEndpoints[1].WorldPosition
    local mainDir = (mainLaserPos - barrelPos).Unit
    local mainResult = Workspace:Raycast(barrelPos, mainDir * Config.MaxDistance, rayParams)

    local function CheckResult(result)
        if not result or not result.Instance or result.Instance.Name == "hitbox" then
            return false, nil
        end
        local hitChar = result.Instance:FindFirstAncestorOfClass("Model")
        if not hitChar or hitChar.Parent ~= CharactersFolder then return false, nil end
        if hitChar == myChar then return false, nil end

        if IsTeammate(hitChar.Name) then
            return false, nil
        end

        local pn = result.Instance.Name:lower()
        local valid = false
        if pn:find("head") and Config.TargetHitboxes.head then valid = true
        elseif pn:find("torso") and Config.TargetHitboxes.torso then valid = true
        elseif pn:find("left") and (pn:find("arm") or pn:find("hand")) and Config.TargetHitboxes.left_arm then valid = true
        elseif pn:find("right") and (pn:find("arm") or pn:find("hand")) and Config.TargetHitboxes.right_arm then valid = true
        elseif pn:find("left") and (pn:find("leg") or pn:find("foot")) and Config.TargetHitboxes.left_leg then valid = true
        elseif pn:find("right") and (pn:find("leg") or pn:find("foot")) and Config.TargetHitboxes.right_leg then valid = true
        end
        if valid then return true, hitChar end
        return false, nil
    end

    local hit, target = CheckResult(mainResult)
    if hit then return { hit = true, endPos = mainResult.Position } end

    local perp1 = Vector3.new(-mainDir.Z, 0, mainDir.X)
    if perp1.Magnitude > 0.01 then perp1 = perp1.Unit else perp1 = Vector3.new(1,0,0) end
    local perp2 = mainDir:Cross(perp1).Unit
    local cr = 0.15
    local offsets = {
        perp1 * cr, -perp1 * cr,
        perp2 * cr, -perp2 * cr,
        (perp1 + perp2).Unit * cr, (perp1 - perp2).Unit * cr,
        (-perp1 + perp2).Unit * cr, (-perp1 - perp2).Unit * cr
    }
    for _, off in ipairs(offsets) do
        local dir = (mainLaserPos + off - barrelPos).Unit * Config.MaxDistance
        local res = Workspace:Raycast(barrelPos, dir, rayParams)
        local h, _ = CheckResult(res)
        if h then return { hit = true, endPos = res.Position } end
    end

    return { hit = false }
end

local function AutoShoot()
    if not State.CanShoot then return end
    State.CanShoot = false

    if mouse1press and mouse1release then
        pcall(function()
            mouse1press()
            task.wait(0.05)
            mouse1release()
        end)
    elseif mouse1click then
        pcall(function() mouse1click() end)
    elseif VirtualInputManager then
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end)
    end

    task.delay(Config.ShootDelay, function()
        State.CanShoot = true
    end)
end

task.spawn(function()
    while true do
        if Config.TriggerbotEnabled then
            local barrel = FindBarrel()
            local laserEndpoints = FindGameLaserEndpoints()
            if barrel and laserEndpoints and #laserEndpoints > 0 then
                local rayData = DoBarrelRaycast(barrel, laserEndpoints)
                if rayData and rayData.hit then
                    AutoShoot()
                end
            end
        end
        task.wait(1/60)
    end
end)

local function removeEsp(model)
    local hl = State.EspObjects[model]
    if hl then
        pcall(function() hl:Destroy() end)
        State.EspObjects[model] = nil
    end
end

local function updateEsp(model)
    if not Config.EspEnabled or not model or not model.Parent then
        removeEsp(model)
        return
    end
    if IgnoreFolder then
        local ragdolls = IgnoreFolder:FindFirstChild("ragdolls")
        if ragdolls and model:IsDescendantOf(ragdolls) then
            removeEsp(model)
            return
        end
    end
    local hum = model:FindFirstChildWhichIsA("Humanoid")
    if hum and hum.Health <= 0 then
        removeEsp(model)
        return
    end

    local hl = State.EspObjects[model]
    if not hl then
        hl = Instance.new("Highlight")
        hl.Adornee = model
        hl.FillTransparency = 0.3
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = model
        State.EspObjects[model] = hl
    end
    hl.FillColor = GetEspColor(model.Name)
end

local function classifyIfInSpawn(model)
    local cid = model.Name
    if not State.TeamByCid[cid] then
        local team = ClassifyModel(model)
        if team then
            State.TeamByCid[cid] = team
            print("Классифицирован " .. cid .. " -> " .. team)
        end
    end
end

local function radarTick()
    local cam = Workspace.CurrentCamera
    if cam then
        local camPos = cam.CFrame.Position
        local best, bestDist = nil, math.huge
        for _, obj in ipairs(CharactersFolder:GetChildren()) do
            if obj:IsA("Model") then
                local root = obj:FindFirstChild("humanoid_root_part") or obj:FindFirstChild("Head") or obj:FindFirstChild("head")
                if root and root:IsA("BasePart") then
                    local d = (root.Position - camPos).Magnitude
                    if d < bestDist then
                        bestDist = d
                        best = obj
                    end
                end
            end
        end
        State.MyCharacter = (best and bestDist < 20) and best or nil
    else
        State.MyCharacter = nil
    end

    if State.MyTeam == nil and State.MyCharacter then
        local myTeam = ClassifyModel(State.MyCharacter)
        if myTeam then
            State.MyTeam = myTeam
            print("Моя команда определена: " .. myTeam)
        end
    end

    local aliveModels = {}
    for _, model in ipairs(CharactersFolder:GetChildren()) do
        if model:IsA("Model") then
            aliveModels[model] = true
            classifyIfInSpawn(model)
            updateEsp(model)
        end
    end

    for model, _ in pairs(State.EspObjects) do
        if not aliveModels[model] then
            removeEsp(model)
            State.TeamByCid[model.Name] = nil
        end
    end
end

task.spawn(function()
    while true do
        radarTick()
        task.wait(0.3)
    end
end)

CharactersFolder.ChildAdded:Connect(function(model)
    if model:IsA("Model") then
        classifyIfInSpawn(model)
        updateEsp(model)
    end
end)
CharactersFolder.ChildRemoved:Connect(function(model)
    removeEsp(model)
    State.TeamByCid[model.Name] = nil
end)

if IgnoreFolder then
    local ragdolls = IgnoreFolder:FindFirstChild("ragdolls")
    if ragdolls then
        ragdolls.ChildAdded:Connect(function(rag)
            for _, model in ipairs(CharactersFolder:GetChildren()) do
                if model.Name == rag.Name then
                    removeEsp(model)
                    State.TeamByCid[model.Name] = nil
                end
            end
        end)
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode
    if key == Config.ToggleEspKey then
        Config.EspEnabled = not Config.EspEnabled
        if not Config.EspEnabled then
            for model, _ in pairs(State.EspObjects) do
                removeEsp(model)
            end
        end
        print("ESP: " .. (Config.EspEnabled and "ON" or "OFF"))
    elseif key == Config.ToggleTriggerKey then
        Config.TriggerbotEnabled = not Config.TriggerbotEnabled
        print("Triggerbot: " .. (Config.TriggerbotEnabled and "ON" or "OFF"))
    elseif key == Config.ToggleTeamCheckKey then
        Config.TeamCheck = not Config.TeamCheck
        print("TeamCheck: " .. (Config.TeamCheck and "ON" or "OFF"))
    end
end)

print("F1 - ESP | F2 - Triggerbot | F3 - TeamCheck ")