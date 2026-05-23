-- PennyHub Wizard - clean build
local GLOBAL_ENV = (getgenv and getgenv()) or _G

local function toBool(value, defaultValue)
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "number" then
        return value ~= 0
    end
    if type(value) == "string" then
        local s = value:lower()
        if s == "true" or s == "1" or s == "yes" or s == "on" then
            return true
        end
        if s == "false" or s == "0" or s == "no" or s == "off" then
            return false
        end
    end
    return defaultValue
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local out = {}
    for k, v in pairs(value) do
        out[k] = deepCopy(v)
    end
    return out
end

local function deepMerge(defaults, overrides)
    if type(defaults) ~= "table" then
        if overrides ~= nil then
            return overrides
        end
        return defaults
    end

    local out = deepCopy(defaults)
    if type(overrides) ~= "table" then
        return out
    end

    for k, v in pairs(overrides) do
        if type(v) == "table" and type(out[k]) == "table" then
            out[k] = deepMerge(out[k], v)
        else
            out[k] = v
        end
    end

    return out
end

local DEFAULT_CONFIG = {
    General = {
        StartupDelay = 2.5,
        LoaderUrl = "https://raw.githubusercontent.com/hoangkhanhgam-dev/PennyHubWizzard/main/file.lua",
    },
    Performance = {
        FpsCap = 10,
        LowCPU = true,
        Disable3DRendering = false,
        ForceLowQuality = true,
    },
    Combat = {
        Height = 26,
        Radius = 32,
        RotateSpeed = 1.55,
        DisableOrbit = true,
        NoOrbitDistance = 0,
        TweenSpeed = 30,
        SpeedBoost = 1.0,
        ConstantTweenSpeed = true,
        MoveTweenMinTime = 0.03,
        MoveTweenMaxTime = 3.0,
        MoveTweenUpdateInterval = 0.03,
        HeadStrafeEnabled = true,
        HeadStrafeRadius = 3.5,
        HeadStrafeSpeed = 3.2,
        EnableNoclip = true,
        PinStickEnabled = false,
        PinStickDistance = 28,
        MaxTweenStepDistance = 220,
        WorldMinY = -50,
        WorldMaxY = 3000,
        WorldMaxAbsXZ = 25000,
        QuestDelay = 5,
        CompleteQuestDelay = 2,
        CancelQuestDelay = 4,
        RebirthDelay = 10,
        AttrDelay = 1,
        SkillDelay = 0.45,
        NpcTweenTime = 2.0,
        AttackBaseFlySpeed = 220,
        ReturnBaseFlySpeed = 180,
        FlySpeedDivider = 4,
        FlySpeedMultiplier = 0.25,
        SkillIds = {1, 2, 4},
    },
    AutoSell = {
        Enabled = true,
        Interval = 60,
    },
    AutoSto = {
        Enabled = true,
        Interval = 2,
        PotionEnabled = false,
        PotionInterval = 2,
    },
    AutoHop = {
        Enabled = false,
        Interval = 600,
        QueueOnTeleport = true,
    },
    Webhook = {
        Enabled = false,
        Url = "",
        Username = "PennyHub",
        Cooldown = 2,
        NotifyStart = true,
        NotifySell = true,
        NotifyError = true,
        NotifyMoney = true,
        MoneyInterval = 60,
        MoneyOnlyOnChange = true,
    },
    UI = {
        Hide = false,
    },
}

local RAW_CONFIG = {}
if type(GLOBAL_ENV.PENNY_CONFIG) == "table" then
    RAW_CONFIG = GLOBAL_ENV.PENNY_CONFIG
end

if type(GLOBAL_ENV.LowCPU) == "boolean" then
    RAW_CONFIG.Performance = RAW_CONFIG.Performance or {}
    RAW_CONFIG.Performance.LowCPU = GLOBAL_ENV.LowCPU
end

if type(GLOBAL_ENV.Hide_UI) == "boolean" then
    RAW_CONFIG.UI = RAW_CONFIG.UI or {}
    RAW_CONFIG.UI.Hide = GLOBAL_ENV.Hide_UI
end

local CONFIG = deepMerge(DEFAULT_CONFIG, RAW_CONFIG)
GLOBAL_ENV.PENNY_CONFIG = CONFIG

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Terrain = workspace:FindFirstChildOfClass("Terrain")

local ZERO = Vector3.new(0, 0, 0)

pcall(function()
    if setfpscap then
        setfpscap(tonumber(CONFIG.Performance.FpsCap) or 10)
    end
end)

task.wait(tonumber(CONFIG.General.StartupDelay) or 2.5)

local lp = Players.LocalPlayer
local Msg = ReplicatedStorage:WaitForChild("Msg")

local SkillRemote = Msg:WaitForChild("RemoteEvent"):WaitForChild("ReleaseGroupSkill")
local AttrRemote = Msg:WaitForChild("RemoteFunction"):WaitForChild("RemoteFunction")
local TalkFunc = Msg:WaitForChild("Function"):WaitForChild("TalkFunc")

local WEBHOOK_REQUEST = (syn and syn.request) or (http and http.request) or request or http_request

local QUEST6_NAME = "\228\187\187\229\138\1616"
local OPEN_SELL_POP = "\230\137\147\229\188\128\231\149\140\233\157\162"
local STO_UPGRADE_COMMAND = "\232\131\140\229\140\133\229\174\185\233\135\143\233\135\145\229\184\129\229\141\135\231\186\167"
local ADD_ATTR_COMMAND = "\229\177\158\230\128\167\229\138\160\231\130\185"
local OPEN_QUEST_COMMAND = "\229\143\145\230\148\190\228\187\187\229\138\161"
local CANCEL_QUEST_COMMAND = "\230\148\190\229\188\131\228\187\187\229\138\161"
local REBIRTH_COMMAND = "\233\135\141\231\148\159"

local SELL_EXCLUDE = {
    FurnaceCore = true,
}

local runtimeState = GLOBAL_ENV.__PENNY_RUNTIME or { run_id = 0 }
runtimeState.run_id = (runtimeState.run_id or 0) + 1
GLOBAL_ENV.__PENNY_RUNTIME = runtimeState
local THIS_RUN_ID = runtimeState.run_id

local function isRunActive()
    return GLOBAL_ENV.__PENNY_RUNTIME and GLOBAL_ENV.__PENNY_RUNTIME.run_id == THIS_RUN_ID
end

local function getRootConfig()
    local cfg = GLOBAL_ENV.PENNY_CONFIG
    if type(cfg) == "table" then
        return cfg
    end
    return CONFIG
end

local function getSection(name)
    local root = getRootConfig()
    if type(root[name]) == "table" then
        return root[name]
    end
    return DEFAULT_CONFIG[name] or {}
end

local function getNumber(section, key, defaultValue)
    local n = tonumber(getSection(section)[key])
    if n == nil then
        return defaultValue
    end
    return n
end

local function getBool(section, key, defaultValue)
    return toBool(getSection(section)[key], defaultValue)
end

local function getString(section, key, defaultValue)
    local value = getSection(section)[key]
    if type(value) == "string" and value ~= "" then
        return value
    end
    return defaultValue
end

local function getSkillIds()
    local ids = getSection("Combat").SkillIds
    if type(ids) == "table" and #ids > 0 then
        return ids
    end
    return DEFAULT_CONFIG.Combat.SkillIds
end

local function webhookConfig()
    return getSection("Webhook")
end

local webhookLastAt = 0
local webhookLastMoneyText = nil

local function webhookIsEnabled()
    local cfg = webhookConfig()
    return cfg.Enabled == true
        and type(cfg.Url) == "string"
        and cfg.Url ~= ""
        and WEBHOOK_REQUEST ~= nil
end

local function webhookSend(eventName, message, force)
    if not webhookIsEnabled() then
        return false
    end

    local cfg = webhookConfig()
    local cooldown = tonumber(cfg.Cooldown) or 2
    if cooldown < 0 then
        cooldown = 0
    end

    local now = tick()
    if not force and now - webhookLastAt < cooldown then
        return false
    end
    webhookLastAt = now

    local ok, result = pcall(function()
        return WEBHOOK_REQUEST({
            Url = cfg.Url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = HttpService:JSONEncode({
                username = tostring(cfg.Username or "PennyHub"),
                content = string.format(
                    "[PennyHub] %s\nPlayer: %s\n%s",
                    tostring(eventName or "Event"),
                    tostring(lp and lp.Name or "Unknown"),
                    tostring(message or "")
                ),
                allowed_mentions = { parse = {} },
            }),
        })
    end)

    if not ok then
        return false
    end

    local code = tonumber(result and (result.StatusCode or result.Status or result.status_code)) or 200
    return code < 400
end

local function getMoneyText()
    local playerGui = lp and lp:FindFirstChild("PlayerGui")
    if not playerGui then
        return ""
    end

    local iconLabel = playerGui:FindFirstChild("SystemGui")
    iconLabel = iconLabel and iconLabel:FindFirstChild("LeftFrame")
    iconLabel = iconLabel and iconLabel:FindFirstChild("Money")
    iconLabel = iconLabel and iconLabel:FindFirstChild("Frame")
    iconLabel = iconLabel and iconLabel:FindFirstChild("IconLabel")
    if not iconLabel then
        return ""
    end

    local text = ""
    pcall(function()
        text = tostring(iconLabel.Text or "")
    end)

    if text ~= "" then
        return text
    end

    for _, item in ipairs(iconLabel:GetDescendants()) do
        if item:IsA("TextLabel") or item:IsA("TextButton") then
            local itemText = tostring(item.Text or "")
            if itemText ~= "" then
                return itemText
            end
        end
    end

    return ""
end

local function webhookSendMoney(force)
    local cfg = webhookConfig()
    if cfg.NotifyMoney ~= true then
        return
    end

    local text = getMoneyText()
    if text == "" then
        return
    end

    if not force and cfg.MoneyOnlyOnChange ~= false and webhookLastMoneyText == text then
        return
    end

    webhookLastMoneyText = text
    webhookSend("Money Update", "SystemGui.LeftFrame.Money.Frame.IconLabel: " .. text, force)
end

local function stripVisualNode(obj)
    if obj:IsA("Decal")
        or obj:IsA("Texture")
        or obj:IsA("SurfaceAppearance")
        or obj:IsA("ParticleEmitter")
        or obj:IsA("Trail")
        or obj:IsA("Beam")
        or obj:IsA("Smoke")
        or obj:IsA("Fire")
        or obj:IsA("Sparkles") then
        pcall(function()
            obj:Destroy()
        end)
        return
    end

    if obj:IsA("BasePart") then
        local char = lp and lp.Character
        if char and obj:IsDescendantOf(char) then
            return
        end

        pcall(function()
            obj.Material = Enum.Material.SmoothPlastic
            obj.Reflectance = 0
            obj.CastShadow = false
        end)
    end
end

local function applyPerformanceTweaks()
    if getBool("Performance", "ForceLowQuality", true) then
        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
    end

    if getBool("Performance", "Disable3DRendering", false) then
        pcall(function()
            RunService:Set3dRenderingEnabled(false)
        end)
    end

    if getBool("Performance", "LowCPU", true) then
        pcall(function()
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 1000000
            Lighting.Brightness = 1
        end)

        for _, item in ipairs(Lighting:GetChildren()) do
            if item:IsA("Atmosphere")
                or item:IsA("BloomEffect")
                or item:IsA("BlurEffect")
                or item:IsA("ColorCorrectionEffect")
                or item:IsA("DepthOfFieldEffect")
                or item:IsA("SunRaysEffect") then
                pcall(function()
                    item:Destroy()
                end)
            end
        end

        if Terrain then
            pcall(function()
                Terrain.WaterWaveSize = 0
                Terrain.WaterWaveSpeed = 0
                Terrain.WaterReflectance = 0
                Terrain.WaterTransparency = 1
            end)
        end

        for _, item in ipairs(workspace:GetDescendants()) do
            stripVisualNode(item)
        end

        workspace.DescendantAdded:Connect(function(item)
            stripVisualNode(item)
        end)
    end
end

applyPerformanceTweaks()

local function getCombatMoveSpeed(baseFallback)
    local combat = getSection("Combat")
    local boost = tonumber(combat.SpeedBoost) or 1
    local direct = tonumber(combat.TweenSpeed)
    if boost < 0.05 then
        boost = 0.05
    end

    if direct and direct > 0 then
        return math.max(direct * boost, 0.2)
    end

    local divider = tonumber(combat.FlySpeedDivider) or 4
    local multiplier = tonumber(combat.FlySpeedMultiplier) or 0.25
    if divider < 0.05 then
        divider = 0.05
    end
    if multiplier < 0.01 then
        multiplier = 0.01
    end

    local fallback = tonumber(baseFallback) or tonumber(combat.AttackBaseFlySpeed) or 220
    return math.max((fallback / divider) * multiplier * boost, 0.2)
end

local function useConstantTweenSpeed()
    return getBool("Combat", "ConstantTweenSpeed", true)
end

local function getTweenTiming()
    local minTime = getNumber("Combat", "MoveTweenMinTime", 0.03)
    local maxTime = getNumber("Combat", "MoveTweenMaxTime", 3.0)
    local updateInterval = getNumber("Combat", "MoveTweenUpdateInterval", 0.03)

    if minTime < 0.01 then
        minTime = 0.01
    end
    if maxTime < minTime then
        maxTime = minTime
    end
    if updateInterval < 0.005 then
        updateInterval = 0.005
    end

    return minTime, maxTime, updateInterval
end

print(string.format(
    "[PennyHub] Start | Height=%.2f | TweenSpeed=%.2f | Constant=%s | AutoSell=%s | AutoHop=%s",
    getNumber("Combat", "Height", 26),
    getCombatMoveSpeed(getNumber("Combat", "AttackBaseFlySpeed", 220)),
    tostring(useConstantTweenSpeed()),
    tostring(getBool("AutoSell", "Enabled", true)),
    tostring(getBool("AutoHop", "Enabled", false))
))

if webhookConfig().NotifyStart ~= false then
    task.spawn(function()
        webhookSend(
            "Script Started",
            "RunId: " .. tostring(THIS_RUN_ID) .. "\nPlaceId: " .. tostring(game.PlaceId),
            true
        )
    end)
end

if webhookConfig().NotifyMoney == true then
    task.spawn(function()
        task.wait(2)
        if not isRunActive() then
            return
        end

        webhookSendMoney(true)

        while isRunActive() do
            local interval = tonumber(webhookConfig().MoneyInterval) or 60
            if interval < 5 then
                interval = 5
            end

            task.wait(interval)
            if not isRunActive() then
                break
            end

            webhookSendMoney(false)
        end
    end)
end

local function getCharacter()
    local char = lp.Character or lp.CharacterAdded:Wait()
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
    return char, hrp, hum
end

local function applyNoclip(char)
    if not getBool("Combat", "EnableNoclip", true) then
        return
    end

    for _, item in ipairs(char:GetDescendants()) do
        if item:IsA("BasePart") then
            item.CanCollide = false
        end
    end
end

local function stabilizeCharacter(hrp)
    pcall(function()
        hrp.AssemblyAngularVelocity = ZERO
    end)
end

local function hasChild(model, name)
    return model:FindFirstChild(name) ~= nil
end

local function hasAllBodyParts(model)
    return model:IsA("Model")
        and hasChild(model, "Head")
        and hasChild(model, "HumanoidRootPart")
        and hasChild(model, "Left Arm")
        and hasChild(model, "Right Arm")
        and hasChild(model, "Left Leg")
        and hasChild(model, "Right Leg")
        and hasChild(model, "Torso")
end

local function descendantNameHas(root, keyword)
    for _, item in ipairs(root:GetDescendants()) do
        if tostring(item.Name):find(keyword) then
            return true
        end
    end
    return false
end

local guiTextCache = ""
local guiTextCacheAt = 0
local GUI_TEXT_CACHE_TTL = 0.4

local function getGuiTextAll()
    local now = tick()
    if guiTextCache ~= "" and now - guiTextCacheAt <= GUI_TEXT_CACHE_TTL then
        return guiTextCache
    end

    local playerGui = lp:FindFirstChild("PlayerGui")
    if not playerGui then
        return ""
    end

    local chunks = {}
    for _, item in ipairs(playerGui:GetDescendants()) do
        if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
            chunks[#chunks + 1] = tostring(item.Text or "")
        end
    end

    guiTextCache = string.lower(table.concat(chunks, " "))
    guiTextCacheAt = now
    return guiTextCache
end

local function hasAnyQuest()
    local taskFolder = lp:FindFirstChild("Task")
    return taskFolder and #taskFolder:GetChildren() > 0 or false
end

local function isDwarfKingQuest()
    return getGuiTextAll():find("dwarf king") ~= nil
end

local function shouldReturnToHarryint()
    local text = getGuiTextAll()
    if not text:find("dwarf king") then
        return false
    end
    return text:find("talk to harryint") ~= nil
        or text:find("talk to harryin") ~= nil
        or text:find("harryint") ~= nil
end

local function hasQuestReward()
    local text = getGuiTextAll()
    if not text:find("quest rewards") then
        return false
    end
    return text:find("exp")
        or text:find("gold")
        or text:find("coin")
        or text:find("reward")
        or text:find("gem")
        or text:find("item")
        or text:find("beri")
        or text:find("money")
        or text:find("cash")
end

local function activateGoodbyeFromGui()
    if not getGuiTextAll():find("goodbye") then
        return false
    end

    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.One, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.One, false, game)
    end)
    return true
end

local function cancelAllCurrentQuests()
    local taskFolder = lp:FindFirstChild("Task")
    if not taskFolder then
        return
    end

    for _, quest in ipairs(taskFolder:GetChildren()) do
        pcall(function()
            AttrRemote:InvokeServer(CANCEL_QUEST_COMMAND, quest.Name)
        end)
        task.wait(0.15)
    end
end

local function isKingDwarf(model)
    if not hasAllBodyParts(model) then
        return false
    end

    local name = string.lower(tostring(model.Name or ""))
    if name:find("dwarf king") or name:find("king dwarf") or (name:find("king") and name:find("dwarf")) then
        return true
    end

    return descendantNameHas(model, "8347")
        or descendantNameHas(model, "8350")
        or descendantNameHas(model, "8351")
        or descendantNameHas(model, "Box40013")
        or descendantNameHas(model, "Box40015")
        or descendantNameHas(model, "Ham01")
        or descendantNameHas(model, "Plane007")
        or descendantNameHas(model, "Plane010")
end

local function isArcherGoblin(model)
    if not hasAllBodyParts(model) then
        return false
    end

    if model:FindFirstChild("Ranger") == nil then
        return false
    end

    local head = model:FindFirstChild("Head")
    local leftArm = model:FindFirstChild("Left Arm")
    if not head or not leftArm or head:FindFirstChild("tou") == nil then
        return false
    end

    local name = string.lower(tostring(model.Name or ""))
    if name:find("archer") or name:find("ranger") then
        return true
    end

    for _, item in ipairs(leftArm:GetChildren()) do
        local itemName = tostring(item.Name)
        if itemName:find("Handle008") or itemName:lower():find("bow") then
            return true
        end
    end

    return false
end

local function isWarhammerDwarf(model)
    if not hasAllBodyParts(model) or isArcherGoblin(model) then
        return false
    end

    local name = string.lower(tostring(model.Name or ""))
    if name:find("warhammer") or name:find("hammer") or (name:find("dwarf") and name:find("war")) then
        return true
    end

    return descendantNameHas(model, "Hammer")
        or descendantNameHas(model, "ham")
        or descendantNameHas(model, "Box40013")
        or descendantNameHas(model, "Box40015")
        or descendantNameHas(model, "Ham01")
end

local function isPickaxeDwarf(model)
    if not hasAllBodyParts(model) or isArcherGoblin(model) or isWarhammerDwarf(model) or isKingDwarf(model) then
        return false
    end

    return descendantNameHas(model, "Pick")
        or descendantNameHas(model, "pick")
        or descendantNameHas(model, "NGon")
        or descendantNameHas(model, "83410012")
        or descendantNameHas(model, "8341")
end

local function getNPCType(model)
    if isKingDwarf(model) then
        return "King Dwarf"
    end
    if isWarhammerDwarf(model) then
        return "Warhammer Dwarf"
    end
    if isArcherGoblin(model) then
        return "Archer Goblin"
    end
    if isPickaxeDwarf(model) then
        return "Pickaxe Dwarf"
    end
    if hasAllBodyParts(model) then
        return "Other"
    end
    return nil
end

local function getTargetAnchorPosition(model)
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        return head.Position
    end

    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp.Position
    end

    return nil
end

local function getNearestTarget(myHrp)
    local monsterFolder = workspace:FindFirstChild("Monster")
    if not monsterFolder then
        return nil
    end

    local bestKing = nil
    local bestWarhammer = nil
    local bestOther = nil
    local bestKingDist = math.huge
    local bestWarhammerDist = math.huge
    local bestOtherDist = math.huge

    for _, mob in ipairs(monsterFolder:GetChildren()) do
        local npcType = getNPCType(mob)
        if npcType and npcType ~= "Archer Goblin" then
            local mobHrp = mob:FindFirstChild("HumanoidRootPart")
            if mobHrp then
                local dist = (myHrp.Position - mobHrp.Position).Magnitude
                if npcType == "King Dwarf" then
                    if dist < bestKingDist then
                        bestKingDist = dist
                        bestKing = mob
                    end
                elseif npcType == "Warhammer Dwarf" then
                    if dist < bestWarhammerDist then
                        bestWarhammerDist = dist
                        bestWarhammer = mob
                    end
                else
                    if dist < bestOtherDist then
                        bestOtherDist = dist
                        bestOther = mob
                    end
                end
            end
        end
    end

    if bestKing then
        return bestKing
    end
    if bestWarhammer then
        return bestWarhammer
    end
    return bestOther
end

local function castSkill(skillId, target, hrp)
    local targetHrp = target and target:FindFirstChild("HumanoidRootPart")
    if not targetHrp then
        return
    end

    pcall(function()
        SkillRemote:FireServer(
            skillId,
            {
                targetCF = targetHrp.CFrame,
                moveDirectionStr = "Forward",
                clientPredictCastId = HttpService:GenerateGUID(false),
                characterType = "Player",
                releaseCF = hrp.CFrame,
                characterId = lp.UserId,
                trackTargetId = tostring(target.Name),
            }
        )
    end)
end

local function autoAddPoint()
    pcall(function()
        AttrRemote:InvokeServer(
            ADD_ATTR_COMMAND,
            {
                AttrTp = 1,
                PointNum = 1,
            }
        )
    end)
end

local function autoQuest()
    pcall(function()
        TalkFunc:InvokeServer(OPEN_QUEST_COMMAND, { QUEST6_NAME })
    end)
end

local function autoRebirth()
    pcall(function()
        AttrRemote:InvokeServer(REBIRTH_COMMAND)
    end)
end

local function completeQuestByNPC(hrp)
    local npc = nil
    pcall(function()
        npc = workspace["\229\156\186\230\153\175"]["1"].NPC["\229\147\136\229\136\169\229\155\160\231\137\185"]
    end)
    if not npc then
        return
    end

    local npcHrp = npc:FindFirstChild("HumanoidRootPart")
    local prompt = npcHrp and npcHrp:FindFirstChild("TalkPrompt")
    if not npcHrp or not prompt then
        return
    end

    local targetCF = npcHrp.CFrame * CFrame.new(0, 0, -5)
    local dist = (hrp.Position - targetCF.Position).Magnitude
    local speed = getCombatMoveSpeed(getNumber("Combat", "ReturnBaseFlySpeed", 180))
    local minTime, maxTime = getTweenTiming()
    local duration
    if useConstantTweenSpeed() then
        duration = math.max(dist / speed, 0.01)
    else
        duration = math.clamp(dist / speed, minTime, math.max(maxTime, 0.25))
    end

    local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
        CFrame = targetCF,
    })
    tween:Play()
    pcall(function()
        tween.Completed:Wait()
    end)
    hrp.CFrame = targetCF

    task.wait(0.35)
    pcall(function()
        fireproximityprompt(prompt)
    end)
    task.wait(0.6)
    activateGoodbyeFromGui()
end

local activeMoveTween = nil
local lastMoveUpdateAt = 0
local lastMoveTargetCF = nil

local function stopMoveTween()
    if activeMoveTween then
        pcall(function()
            activeMoveTween:Cancel()
        end)
        activeMoveTween = nil
    end
end

local function isWorldPosSafe(pos)
    return pos
        and pos.Y >= getNumber("Combat", "WorldMinY", -50)
        and pos.Y <= getNumber("Combat", "WorldMaxY", 3000)
        and math.abs(pos.X) <= getNumber("Combat", "WorldMaxAbsXZ", 25000)
        and math.abs(pos.Z) <= getNumber("Combat", "WorldMaxAbsXZ", 25000)
end

local function limitTargetCFStep(fromPos, targetCF)
    local maxStep = getNumber("Combat", "MaxTweenStepDistance", 220)
    local delta = targetCF.Position - fromPos
    local dist = delta.Magnitude
    if dist <= maxStep then
        return targetCF
    end

    local newPos = fromPos + delta.Unit * maxStep
    return CFrame.new(newPos, newPos + targetCF.LookVector)
end

local function tweenMoveTo(hrp, targetCF, baseSpeed, allowPinStick)
    if not hrp or not hrp.Parent then
        return
    end
    if not isWorldPosSafe(hrp.Position) or not isWorldPosSafe(targetCF.Position) then
        return
    end

    local now = tick()
    local rawDist = (hrp.Position - targetCF.Position).Magnitude

    if getBool("Combat", "PinStickEnabled", false)
        and allowPinStick
        and rawDist <= getNumber("Combat", "PinStickDistance", 28) then
        stopMoveTween()
        hrp.CFrame = targetCF
        pcall(function()
            hrp.AssemblyLinearVelocity = ZERO
            hrp.AssemblyAngularVelocity = ZERO
        end)
        lastMoveUpdateAt = now
        lastMoveTargetCF = targetCF
        return
    end

    targetCF = limitTargetCFStep(hrp.Position, targetCF)
    local minTime, maxTime, updateInterval = getTweenTiming()
    if now - lastMoveUpdateAt < updateInterval then
        return
    end

    local dist = (hrp.Position - targetCF.Position).Magnitude
    if dist < 0.3 then
        return
    end
    if lastMoveTargetCF and (lastMoveTargetCF.Position - targetCF.Position).Magnitude < 0.2 then
        return
    end

    lastMoveUpdateAt = now
    lastMoveTargetCF = targetCF

    local speed = getCombatMoveSpeed(baseSpeed)
    local duration
    if useConstantTweenSpeed() then
        duration = math.max(dist / speed, 0.01)
    else
        duration = math.clamp(dist / speed, minTime, maxTime)
    end

    stopMoveTween()
    activeMoveTween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
        CFrame = targetCF,
    })
    activeMoveTween:Play()
end

local currentTarget = nil
local lastSkillAt = 0
local lastQuestAt = 0
local lastCompleteQuestAt = 0
local lastCancelQuestAt = 0
local lastRebirthAt = 0
local lastAttrAt = 0
local orbitAngle = 0
local isBusy = false

RunService.Heartbeat:Connect(function(dt)
    if not isRunActive() or isBusy then
        return
    end

    local char, hrp, hum = getCharacter()
    if hum.Health <= 0 then
        currentTarget = nil
        stopMoveTween()
        return
    end

    applyNoclip(char)
    stabilizeCharacter(hrp)

    if tick() - lastQuestAt >= getNumber("Combat", "QuestDelay", 5) then
        lastQuestAt = tick()
        if not hasAnyQuest() then
            autoQuest()
        end
    end

    if tick() - lastCompleteQuestAt >= getNumber("Combat", "CompleteQuestDelay", 2) then
        lastCompleteQuestAt = tick()
        if hasAnyQuest() and shouldReturnToHarryint() then
            isBusy = true
            task.spawn(function()
                completeQuestByNPC(hrp)
                task.wait(1)
                isBusy = false
            end)
            return
        end
    end

    if hasAnyQuest()
        and (not isDwarfKingQuest() or not hasQuestReward())
        and tick() - lastCancelQuestAt >= getNumber("Combat", "CancelQuestDelay", 4) then
        lastCancelQuestAt = tick()
        cancelAllCurrentQuests()
    end

    if tick() - lastRebirthAt >= getNumber("Combat", "RebirthDelay", 10) then
        lastRebirthAt = tick()
        autoRebirth()
    end

    if tick() - lastAttrAt >= getNumber("Combat", "AttrDelay", 1) then
        lastAttrAt = tick()
        autoAddPoint()
    end

    if not currentTarget
        or not currentTarget.Parent
        or currentTarget:FindFirstChild("HumanoidRootPart") == nil
        or getNPCType(currentTarget) == nil then
        currentTarget = getNearestTarget(hrp)
        orbitAngle = 0
    end

    local target = currentTarget
    local targetHrp = target and target:FindFirstChild("HumanoidRootPart")
    if not target or not targetHrp or not isWorldPosSafe(targetHrp.Position) then
        currentTarget = nil
        return
    end

    local anchorPos = getTargetAnchorPosition(target) or targetHrp.Position
    local moveCF
    local height = getNumber("Combat", "Height", 26)
    local noOrbitDistance = getNumber("Combat", "NoOrbitDistance", 0)

    if getBool("Combat", "DisableOrbit", true) then
        orbitAngle = orbitAngle + math.min(dt, 1 / 20) * getNumber("Combat", "HeadStrafeSpeed", 3.2)
        local movePos = anchorPos + Vector3.new(0, height, 0)
        if noOrbitDistance ~= 0 then
            movePos = movePos - targetHrp.CFrame.LookVector * noOrbitDistance
        end

        if getBool("Combat", "HeadStrafeEnabled", true) then
            local strafeRadius = getNumber("Combat", "HeadStrafeRadius", 3.5)
            local sideOffset = math.sin(orbitAngle) * strafeRadius
            local forwardOffset = math.cos(orbitAngle * 0.5) * (strafeRadius * 0.25)
            movePos = movePos
                + targetHrp.CFrame.RightVector * sideOffset
                + targetHrp.CFrame.LookVector * forwardOffset
        end

        moveCF = CFrame.lookAt(movePos, anchorPos)
    else
        orbitAngle = orbitAngle + math.min(dt, 1 / 20) * getNumber("Combat", "RotateSpeed", 1.55)
        local radius = getNumber("Combat", "Radius", 32)
        local movePos = anchorPos + Vector3.new(
            math.cos(orbitAngle) * radius,
            height,
            math.sin(orbitAngle) * radius
        )
        moveCF = CFrame.lookAt(movePos, anchorPos)
    end

    tweenMoveTo(hrp, moveCF, getNumber("Combat", "AttackBaseFlySpeed", 220), true)

    if tick() - lastSkillAt >= getNumber("Combat", "SkillDelay", 0.45) then
        lastSkillAt = tick()
        local skillIds = getSkillIds()
        task.spawn(function()
            for i = 1, #skillIds do
                castSkill(skillIds[i], target, hrp)
                task.wait(0.03)
            end
        end)
    end
end)

local function parseMoneyText(raw)
    local s = tostring(raw or ""):lower()
    s = s:gsub(",", "")
    s = s:gsub("%s+", "")

    local num, suffix = s:match("([%d%.]+)([kmb])")
    if num then
        local value = tonumber(num) or 0
        local mult = 1
        if suffix == "k" then
            mult = 1000
        elseif suffix == "m" then
            mult = 1000000
        elseif suffix == "b" then
            mult = 1000000000
        end
        return math.floor(value * mult)
    end

    local clean = s:gsub("[^%d%.%-]", "")
    local parsed = tonumber(clean)
    if parsed then
        return math.floor(parsed)
    end
    return 0
end

local function getCurrentGold()
    return parseMoneyText(getMoneyText())
end

local function invokeStoUpgrade(itemTp)
    local ok, err = pcall(function()
        AttrRemote:InvokeServer(STO_UPGRADE_COMMAND, { itemTp = itemTp })
    end)
    if not ok then
        warn("[PennyHub] STO upgrade failed:", err)
    end
end

local function cleanName(text)
    text = tostring(text or "")
    text = text:gsub("%s+", "")
    text = text:gsub("[^%w]", "")
    return text
end

local function clickGui(obj)
    if not obj then
        return false
    end

    local clicked = false
    if firesignal then
        pcall(function()
            firesignal(obj.MouseButton1Down)
        end)
        task.wait(0.02)
        pcall(function()
            firesignal(obj.MouseButton1Up)
        end)
        pcall(function()
            firesignal(obj.MouseButton1Click)
            clicked = true
        end)
        pcall(function()
            firesignal(obj.Activated)
            clicked = true
        end)
    end

    pcall(function()
        obj:Activate()
        clicked = true
    end)

    if not clicked and obj:IsA("GuiObject") then
        local pos = obj.AbsolutePosition + (obj.AbsoluteSize / 2)
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            task.wait(0.03)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
            clicked = true
        end)
    end

    return clicked
end

local function getScreenGui()
    return lp:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
end

local function getSellPop()
    return getScreenGui():WaitForChild("SellPop")
end

local function getSellAll()
    return getScreenGui():WaitForChild("SellAll")
end

local function getSellBagFrame()
    return getSellPop():WaitForChild("ContentClip"):WaitForChild("Main"):WaitForChild("_BagFrame")
end

local function getSellAllBagFrame()
    return getSellAll():WaitForChild("ContentClip"):WaitForChild("Frame"):WaitForChild("_BagFrame")
end

local sellPopOpenedAt = nil
local SELLPOP_TIMEOUT = 30

local function isSellPopOpen()
    local ok, visible = pcall(function()
        return getSellPop().Visible
    end)
    return ok and visible == true
end

local function closeBlockingPopups()
    local playerGui = lp:FindFirstChild("PlayerGui")
    if not playerGui then
        return
    end

    for _, item in ipairs(playerGui:GetDescendants()) do
        if item:IsA("TextButton") or item:IsA("ImageButton") then
            local name = string.lower(tostring(item.Name or ""))
            local text = ""
            pcall(function()
                text = string.lower(tostring(item.Text or ""))
            end)

            if name:find("close")
                or name:find("exit")
                or name:find("refuse")
                or name:find("cancel")
                or text == "x"
                or text:find("close")
                or text:find("cancel")
                or text:find("not now") then
                clickGui(item)
            end
        end
    end
end

local function closeSellPopIfStuck()
    local ok, sellPop = pcall(function()
        return getSellPop()
    end)
    if not ok or not sellPop then
        sellPopOpenedAt = nil
        return
    end

    if sellPop.Visible then
        if not sellPopOpenedAt then
            sellPopOpenedAt = tick()
            return
        end
        if tick() - sellPopOpenedAt >= SELLPOP_TIMEOUT then
            clickGui(sellPop.ContentClip.Top._Exit.Button)
            sellPopOpenedAt = nil
        end
    else
        sellPopOpenedAt = nil
    end
end

local function openSellPopIfNeeded()
    if isSellPopOpen() then
        return true
    end

    pcall(function()
        TalkFunc:InvokeServer(OPEN_SELL_POP, {"SellPop"})
    end)
    task.wait(0.35)
    if isSellPopOpen() then
        return true
    end

    pcall(function()
        TalkFunc:InvokeServer(OPEN_SELL_POP, "SellPop")
    end)
    task.wait(0.35)
    if isSellPopOpen() then
        return true
    end

    pcall(function()
        TalkFunc:InvokeServer(OPEN_SELL_POP)
    end)
    task.wait(0.35)
    return isSellPopOpen()
end

local function selectMaterialTab()
    clickGui(getSellPop().ContentClip.Main._Tab.Tab_Material.Button)
    task.wait(0.2)
end

local function enableMultiSelect()
    clickGui(getSellPop().ContentClip.Bottom._Btns1._MultiSelect.Btn)
    task.wait(0.2)
end

local function getItemName(slot)
    local nameObj = slot:FindFirstChild("Name")
    if nameObj and nameObj:IsA("TextLabel") then
        local text = tostring(nameObj.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" then
            return text
        end
    end

    for _, item in ipairs(slot:GetDescendants()) do
        if item:IsA("TextLabel") or item:IsA("TextButton") then
            local text = tostring(item.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if text ~= "" and not text:match("^x%d+$") then
                return text
            end
        end
    end

    return nil
end

local function clickSellSlot(slot)
    local target = slot:FindFirstChild("ItemClickScale", true) or slot:FindFirstChild("BG") or slot
    return clickGui(target)
end

local function selectSellItems()
    local count = 0
    for _, slot in ipairs(getSellBagFrame():GetChildren()) do
        if slot.Name:match("^SellSlot_%d+$") then
            local itemName = getItemName(slot)
            local key = cleanName(itemName)
            if itemName and not SELL_EXCLUDE[key] then
                clickSellSlot(slot)
                count = count + 1
                task.wait(0.08)
            end
        end
    end
    return count
end

local function unselectExcludedInSellAll()
    local sellBag = getSellBagFrame()
    local sellAllBag = getSellAllBagFrame()

    for _, itemBtn in ipairs(sellAllBag:GetChildren()) do
        local id = itemBtn.Name:match("^Item_(%d+)$")
        if id and itemBtn.Visible ~= false then
            local slot = sellBag:FindFirstChild("SellSlot_" .. id)
            if slot then
                local key = cleanName(getItemName(slot))
                if SELL_EXCLUDE[key] then
                    clickGui(itemBtn)
                    task.wait(0.05)
                end
            end
        end
    end
end

local function countSellAllItems()
    local total = 0
    for _, item in ipairs(getSellAllBagFrame():GetChildren()) do
        if item.Name:match("^Item_%d+$") and item.Visible ~= false then
            total = total + 1
        end
    end
    return total
end

local function confirmSell()
    local sellPop = getSellPop()
    local sellAll = getSellAll()
    local finalCount = 0

    closeBlockingPopups()
    clickGui(sellPop.ContentClip.Bottom._Btns2._SellBtn.Btn)
    task.wait(0.15)

    if sellAll.Visible then
        unselectExcludedInSellAll()
        task.wait(0.1)
        finalCount = countSellAllItems()
        clickGui(sellAll.ContentClip.Frame.Btns._OkBtn.Btn)
        task.wait(0.2)
    end

    if sellPop.Visible then
        clickGui(sellPop.ContentClip.Top._Exit.Button)
    end

    return sellAll.Visible == false, finalCount
end

local function runAutoSellOnce()
    if not getBool("AutoSell", "Enabled", true) then
        return
    end

    local soldCount = 0
    local success = false

    local ok, err = pcall(function()
        local attempt = 1
        while attempt <= 3 do
            if openSellPopIfNeeded() then
                closeBlockingPopups()
                selectMaterialTab()
                enableMultiSelect()
                selectSellItems()
                task.wait(0.2)

                local confirmed, total = confirmSell()
                if confirmed then
                    success = true
                    soldCount = tonumber(total) or 0
                    break
                end
            end

            local sellPop = getSellPop()
            if sellPop.Visible then
                clickGui(sellPop.ContentClip.Top._Exit.Button)
            end
            task.wait(0.5)
            attempt = attempt + 1
        end
    end)

    if not ok then
        warn("[PennyHub] Auto sell failed:", err)
        if webhookConfig().NotifyError ~= false then
            webhookSend("AutoSell Error", tostring(err), true)
        end
        return
    end

    if success then
        if webhookConfig().NotifySell ~= false then
            webhookSend("AutoSell Success", "Sold items: " .. tostring(soldCount), true)
        end
    else
        if webhookConfig().NotifyError ~= false then
            webhookSend("AutoSell Failed", "Could not confirm sell after retries.", true)
        end
    end
end

local function autoSellLoop()
    task.spawn(function()
        while isRunActive() do
            closeSellPopIfStuck()
            task.wait(1)
        end
    end)

    task.spawn(function()
        task.wait(5)
        while isRunActive() do
            runAutoSellOnce()
            task.wait(math.max(getNumber("AutoSell", "Interval", 60), 5))
        end
    end)
end

local function autoStoLoop()
    task.spawn(function()
        task.wait(1)
        while isRunActive() do
            if getBool("AutoSto", "Enabled", true) then
                invokeStoUpgrade(2)
                task.wait(0.15)
                if getBool("AutoSto", "Enabled", true) then
                    invokeStoUpgrade(2)
                end
                task.wait(math.max(getNumber("AutoSto", "Interval", 2), 0.2))
            else
                task.wait(0.5)
            end
        end
    end)

    task.spawn(function()
        task.wait(1)
        while isRunActive() do
            if getBool("AutoSto", "PotionEnabled", false) then
                invokeStoUpgrade(9)
                task.wait(math.max(getNumber("AutoSto", "PotionInterval", getNumber("AutoSto", "Interval", 2)), 0.2))
            else
                task.wait(0.5)
            end
        end
    end)
end

local function queueScriptForHop()
    if not getBool("AutoHop", "QueueOnTeleport", true) then
        return false
    end

    local queueFunc = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    if not queueFunc then
        return false
    end

    local ok, configJson = pcall(function()
        return HttpService:JSONEncode(getRootConfig())
    end)
    if not ok then
        return false
    end

    local loaderUrl = getString("AutoHop", "LoaderUrl", getString("General", "LoaderUrl", DEFAULT_CONFIG.General.LoaderUrl))
    local source = string.format(
        "repeat task.wait() until game:IsLoaded()\ngetgenv().PENNY_CONFIG = game:GetService(\"HttpService\"):JSONDecode(%q)\nloadstring(game:HttpGet(%q))()",
        configJson,
        loaderUrl
    )

    return pcall(function()
        queueFunc(source)
    end)
end

local function fetchServerPage(cursor)
    local url = string.format(
        "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100",
        tostring(game.PlaceId)
    )
    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
    end

    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(body) == "string" and body ~= "" then
        return body
    end

    if WEBHOOK_REQUEST then
        local requestOk, response = pcall(function()
            return WEBHOOK_REQUEST({
                Url = url,
                Method = "GET",
            })
        end)
        if requestOk then
            local status = tonumber(response and (response.StatusCode or response.Status or response.status_code)) or 200
            local responseBody = response and (response.Body or response.body)
            if status < 400 and type(responseBody) == "string" and responseBody ~= "" then
                return responseBody
            end
        end
    end

    return nil
end

local hopRandom = Random.new()

local function findHopServer()
    local currentJobId = tostring(game.JobId or "")
    local candidates = {}
    local cursor = nil

    local page = 1
    while page <= 5 do
        local raw = fetchServerPage(cursor)
        if not raw then
            break
        end

        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(raw)
        end)
        if not ok or type(decoded) ~= "table" then
            break
        end

        for _, server in ipairs(decoded.data or {}) do
            if type(server) == "table" then
                local id = tostring(server.id or "")
                local playing = tonumber(server.playing) or 0
                local maxPlayers = tonumber(server.maxPlayers) or 0
                if id ~= "" and id ~= currentJobId and playing < maxPlayers and maxPlayers > 0 then
                    candidates[#candidates + 1] = id
                end
            end
        end

        cursor = decoded.nextPageCursor
        if not cursor or cursor == "" then
            break
        end
        page = page + 1
    end

    if #candidates <= 0 then
        return nil
    end
    return candidates[hopRandom:NextInteger(1, #candidates)]
end

local autoHopBusy = false

local function performServerHop(reason)
    if autoHopBusy then
        return
    end
    autoHopBusy = true

    local queued = queueScriptForHop()
    local targetServer = findHopServer()

    if webhookConfig().NotifyStart ~= false then
        webhookSend(
            "AutoHop",
            "Reason: " .. tostring(reason or "interval")
                .. "\nQueued: " .. tostring(queued)
                .. "\nTarget: " .. tostring(targetServer or "random"),
            true
        )
    end

    local ok, err = pcall(function()
        if targetServer and targetServer ~= "" then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, targetServer, lp)
        else
            TeleportService:Teleport(game.PlaceId, lp)
        end
    end)

    if not ok and webhookConfig().NotifyError ~= false then
        webhookSend("AutoHop Failed", tostring(err), true)
    end

    task.delay(5, function()
        autoHopBusy = false
    end)
end

local function autoHopLoop()
    task.spawn(function()
        task.wait(5)
        local nextHopAt = nil

        while isRunActive() do
            if getBool("AutoHop", "Enabled", false) then
                local interval = math.max(getNumber("AutoHop", "Interval", 600), 30)
                if not nextHopAt then
                    nextHopAt = tick() + interval
                end

                if tick() >= nextHopAt then
                    performServerHop("interval:" .. tostring(interval))
                    nextHopAt = tick() + interval
                    task.wait(2)
                else
                    task.wait(1)
                end
            else
                nextHopAt = nil
                task.wait(1)
            end
        end
    end)
end

if getBool("AutoSell", "Enabled", true) then
    autoSellLoop()
end

autoStoLoop()
autoHopLoop()
