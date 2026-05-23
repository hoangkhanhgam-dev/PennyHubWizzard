--// FULL SCRIPT - Orbit Smooth Mode (Bay Deu)
local GLOBAL_ENV = (getgenv and getgenv()) or _G

local function deepCopy(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end
    local out = {}
    for k, v in pairs(tbl) do
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
        RotateSpeed = 6.2 / 4,
        OrbitSmooth = 0.42,
        DisableOrbit = true,
        NoOrbitDistance = 0,
        SpeedBoost = 1.0, -- >1 faster, <1 slower
        TweenSpeed = 30, -- default target movement speed, slightly below 35 studs/s
        ConstantTweenSpeed = true, -- keep movement speed stable regardless of distance
        HeadStrafeEnabled = true,
        HeadStrafeRadius = 3.5,
        HeadStrafeSpeed = 3.2,
        EnableNoclip = true,
        ReturnReachDist = 4,
        ReturnHoldTime = 0.20,
        FlySpeedDivider = 4, -- legacy
        FlySpeedMultiplier = 0.25, -- legacy
        AttackBaseFlySpeed = 220,
        ReturnBaseFlySpeed = 180,
        MoveTweenMinTime = 0.08,
        MoveTweenMaxTime = 3.00,
        MoveTweenUpdateInterval = 0.03,
        PinStickEnabled = false, -- false = always tween smoothly, true = snap/lock when near target
        PinStickDistance = 28,
        EnableReturnToLastPos = false,
        MaxTweenStepDistance = 220,
        WorldMinY = -50,
        WorldMaxY = 3000,
        WorldMaxAbsXZ = 25000,
        SkillDelay = 0.45,
        DashDelay = 0.75,
        AttrDelay = 1,
        QuestDelay = 5,
        CompleteQuestDelay = 2,
        RebirthDelay = 10,
        CancelQuestDelay = 4,
        NpcTweenTime = 2.0,
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

-- Legacy compatibility for previous external keys
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

pcall(function()
    if setfpscap then
        setfpscap(tonumber(CONFIG.Performance.FpsCap) or 10)
    end
end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Lighting = game:GetService("Lighting")
local Terrain = workspace:FindFirstChildOfClass("Terrain")

local STARTUP_DELAY = tonumber(CONFIG.General.StartupDelay) or 2.5
task.wait(STARTUP_DELAY)

local lp = Players.LocalPlayer
local Msg = ReplicatedStorage:WaitForChild("Msg")
local WEBHOOK_REQUEST = (syn and syn.request) or (http and http.request) or request or http_request
local WEBHOOK_CFG = CONFIG.Webhook or {}
local DEFAULT_LOADER_URL = tostring(
    (type(CONFIG.General) == "table" and CONFIG.General.LoaderUrl)
    or GLOBAL_ENV.PENNY_LOADER_URL
    or "https://raw.githubusercontent.com/hoangkhanhgam-dev/PennyHubWizzard/main/file.lua"
)
local webhookLastAt = 0
local webhookLastMoneyText = nil

local function webhookIsEnabled()
    return WEBHOOK_CFG.Enabled == true
        and type(WEBHOOK_CFG.Url) == "string"
        and WEBHOOK_CFG.Url ~= ""
        and WEBHOOK_REQUEST ~= nil
end

local function webhookSend(eventName, message, force)
    if not webhookIsEnabled() then
        return false
    end

    local now = tick()
    local cooldown = tonumber(WEBHOOK_CFG.Cooldown) or 2
    if cooldown < 0 then
        cooldown = 0
    end

    if (not force) and (now - webhookLastAt < cooldown) then
        return false
    end
    webhookLastAt = now

    local username = tostring(WEBHOOK_CFG.Username or "PennyHub")
    local playerName = (lp and lp.Name) or "Unknown"
    local content = string.format(
        "[PennyHub] %s\nPlayer: %s\n%s",
        tostring(eventName or "Event"),
        tostring(playerName),
        tostring(message or "")
    )

    local payload = HttpService:JSONEncode({
        username = username,
        content = content,
        allowed_mentions = { parse = {} }
    })

    local ok, res = pcall(function()
        return WEBHOOK_REQUEST({
            Url = WEBHOOK_CFG.Url,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = payload
        })
    end)
    if not ok then
        return false
    end

    local code = tonumber(res and (res.StatusCode or res.Status or res.status_code)) or 200
    return code < 400
end

local function webhookGetMoneyText()
    local ok, text = pcall(function()
        local pg = lp:FindFirstChild("PlayerGui")
        if not pg then
            return ""
        end

        local systemGui = pg:FindFirstChild("SystemGui")
        if not systemGui then
            return ""
        end

        local leftFrame = systemGui:FindFirstChild("LeftFrame")
        if not leftFrame then
            return ""
        end

        local money = leftFrame:FindFirstChild("Money")
        if not money then
            return ""
        end

        local frame = money:FindFirstChild("Frame")
        if not frame then
            return ""
        end

        local iconLabel = frame:FindFirstChild("IconLabel")
        if not iconLabel then
            return ""
        end

        if iconLabel:IsA("TextLabel") or iconLabel:IsA("TextButton") or iconLabel:IsA("TextBox") then
            return tostring(iconLabel.Text or "")
        end

        for _, d in ipairs(iconLabel:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                local t = tostring(d.Text or "")
                if t ~= "" then
                    return t
                end
            end
        end

        return ""
    end)

    if not ok then
        return ""
    end
    return tostring(text or "")
end

local function webhookSendMoney(force)
    if WEBHOOK_CFG.NotifyMoney ~= true then
        return false
    end

    local text = webhookGetMoneyText()
    if text == "" then
        return false
    end

    if WEBHOOK_CFG.MoneyOnlyOnChange ~= false and (not force) and webhookLastMoneyText == text then
        return false
    end

    webhookLastMoneyText = text
    return webhookSend(
        "Money Update",
        "SystemGui.LeftFrame.Money.Frame.IconLabel: " .. text,
        force
    )
end

-- Runtime guard: prevents old loops from previous executions from continuing.
GLOBAL_ENV.__PENNY_RUNTIME = GLOBAL_ENV.__PENNY_RUNTIME or { run_id = 0 }
GLOBAL_ENV.__PENNY_RUNTIME.run_id = (GLOBAL_ENV.__PENNY_RUNTIME.run_id or 0) + 1
local THIS_RUN_ID = GLOBAL_ENV.__PENNY_RUNTIME.run_id

local function isRunActive()
    return GLOBAL_ENV.__PENNY_RUNTIME
        and GLOBAL_ENV.__PENNY_RUNTIME.run_id == THIS_RUN_ID
end

if WEBHOOK_CFG.NotifyStart ~= false then
    task.spawn(function()
        webhookSend(
            "Script Started",
            "RunId: " .. tostring(THIS_RUN_ID) .. "\nPlaceId: " .. tostring(game.PlaceId),
            true
        )
    end)
end

if WEBHOOK_CFG.NotifyMoney == true then
    task.spawn(function()
        task.wait(2)
        if not isRunActive() then
            return
        end

        webhookSendMoney(true)

        while isRunActive() do
            local interval = tonumber(WEBHOOK_CFG.MoneyInterval) or 60
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

local function getAutoHopConfig()
    local cfg = GLOBAL_ENV.PENNY_CONFIG
    if type(cfg) == "table" and type(cfg.AutoHop) == "table" then
        return cfg.AutoHop
    end
    return CONFIG.AutoHop or {}
end

local function isAutoHopEnabled()
    local cfg = getAutoHopConfig()
    return cfg.Enabled == true
end

local function getAutoHopInterval()
    local cfg = getAutoHopConfig()
    local n = tonumber(cfg.Interval)
        or tonumber(cfg.HopInterval)
        or tonumber(cfg.Time)
        or tonumber(cfg.Delay)
        or 1800
    if n < 30 then
        n = 30
    end
    return n
end

local function shouldQueueOnTeleport()
    local cfg = getAutoHopConfig()
    return cfg.QueueOnTeleport ~= false
end

local function getAutoHopLoaderUrl()
    local cfg = getAutoHopConfig()
    local general = (type(GLOBAL_ENV.PENNY_CONFIG) == "table" and GLOBAL_ENV.PENNY_CONFIG.General) or CONFIG.General or {}
    return tostring(
        cfg.LoaderUrl
        or cfg.LoadUrl
        or general.LoaderUrl
        or general.LoadUrl
        or GLOBAL_ENV.PENNY_LOADER_URL
        or DEFAULT_LOADER_URL
    )
end

local function queueScriptForServerHop()
    if not shouldQueueOnTeleport() then
        return false
    end

    local queueFunc = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    if not queueFunc then
        return false
    end

    local ok, configJson = pcall(function()
        return HttpService:JSONEncode(GLOBAL_ENV.PENNY_CONFIG or CONFIG)
    end)
    if not ok then
        return false
    end

    local loaderUrl = getAutoHopLoaderUrl()
    local queuedSource = string.format(
        "repeat task.wait() until game:IsLoaded()\ngetgenv().PENNY_CONFIG = game:GetService(\"HttpService\"):JSONDecode(%q)\nloadstring(game:HttpGet(%q))()",
        configJson,
        loaderUrl
    )

    local queuedOk = pcall(function()
        queueFunc(queuedSource)
    end)
    return queuedOk
end

local function fetchHopServerPage(cursor)
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
            local respBody = response and (response.Body or response.body)
            if status < 400 and type(respBody) == "string" and respBody ~= "" then
                return respBody
            end
        end
    end

    return nil
end

local hopRandom = Random.new()

local function findPublicServerToHop()
    local currentJobId = tostring(game.JobId or "")
    local cursor = nil
    local candidates = {}

    for _ = 1, 5 do
        local raw = fetchHopServerPage(cursor)
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
                    table.insert(candidates, id)
                end
            end
        end

        cursor = decoded.nextPageCursor
        if not cursor or cursor == "" then
            break
        end
    end

    if #candidates <= 0 then
        return nil
    end

    return candidates[hopRandom:NextInteger(1, #candidates)]
end

local autoHopBusy = false

local function performServerHop(reason)
    if autoHopBusy then
        return false
    end
    autoHopBusy = true

    local queued = queueScriptForServerHop()
    local targetServerId = findPublicServerToHop()

    if WEBHOOK_CFG.NotifyStart ~= false then
        webhookSend(
            "AutoHop",
            "Reason: " .. tostring(reason or "interval")
                .. "\nQueued: " .. tostring(queued)
                .. "\nTargetServer: " .. tostring(targetServerId or "random"),
            true
        )
    end

    local ok = pcall(function()
        if targetServerId and targetServerId ~= "" then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, targetServerId, lp)
        else
            TeleportService:Teleport(game.PlaceId, lp)
        end
    end)

    if not ok and WEBHOOK_CFG.NotifyError ~= false then
        webhookSend("AutoHop Failed", "Teleport call failed.", true)
    end

    task.delay(5, function()
        autoHopBusy = false
    end)

    return ok
end

local STRIP_MAP_GRAPHICS = CONFIG.Performance.LowCPU == true
local DISABLE_3D_RENDERING = CONFIG.Performance.Disable3DRendering == true -- set true if you want maximum performance (white screen)
local FORCE_LOW_QUALITY_LEVEL = CONFIG.Performance.ForceLowQuality == true

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
        local char = lp.Character
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

local function stripMapGraphics()
    if not STRIP_MAP_GRAPHICS then
        return
    end

    -- Reduce expensive global effects
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 1000000
        Lighting.Brightness = 1
    end)

    for _, v in ipairs(Lighting:GetChildren()) do
        if v:IsA("Atmosphere")
            or v:IsA("BloomEffect")
            or v:IsA("BlurEffect")
            or v:IsA("ColorCorrectionEffect")
            or v:IsA("DepthOfFieldEffect")
            or v:IsA("SunRaysEffect") then
            pcall(function()
                v:Destroy()
            end)
        end
    end

    pcall(function()
        if Terrain then
            Terrain.WaterWaveSize = 0
            Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0
            Terrain.WaterTransparency = 1
        end
    end)

    for _, obj in ipairs(workspace:GetDescendants()) do
        stripVisualNode(obj)
    end
end

local function applyExtraPerformanceTweaks()
    if FORCE_LOW_QUALITY_LEVEL then
        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
    end

    if DISABLE_3D_RENDERING then
        pcall(function()
            RunService:Set3dRenderingEnabled(false)
        end)
    end
end

if STRIP_MAP_GRAPHICS then
    task.spawn(function()
        stripMapGraphics()
        applyExtraPerformanceTweaks()
    end)

    workspace.DescendantAdded:Connect(function(obj)
        stripVisualNode(obj)
    end)
else
    task.spawn(function()
        applyExtraPerformanceTweaks()
    end)
end

local SkillRemote = Msg:WaitForChild("RemoteEvent"):WaitForChild("ReleaseGroupSkill")
local AttrRemote = Msg:WaitForChild("RemoteFunction"):WaitForChild("RemoteFunction")
local TalkFunc = Msg:WaitForChild("Function"):WaitForChild("TalkFunc")

-- SETTINGS
local HEIGHT = tonumber(CONFIG.Combat.Height) or 26
local RADIUS = tonumber(CONFIG.Combat.Radius) or 32
local ROTATE_SPEED = tonumber(CONFIG.Combat.RotateSpeed) or (6.2 / 4)
local ORBIT_SMOOTH = tonumber(CONFIG.Combat.OrbitSmooth) or 0.42
local DISABLE_ORBIT = CONFIG.Combat.DisableOrbit ~= false
local NO_ORBIT_DISTANCE = math.max(tonumber(CONFIG.Combat.NoOrbitDistance) or 0, 0)
local HEAD_STRAFE_ENABLED = CONFIG.Combat.HeadStrafeEnabled ~= false
local HEAD_STRAFE_RADIUS = math.max(tonumber(CONFIG.Combat.HeadStrafeRadius) or 3.5, 0)
local HEAD_STRAFE_SPEED = math.max(tonumber(CONFIG.Combat.HeadStrafeSpeed) or 3.2, 0)
local ENABLE_NOCLIP = CONFIG.Combat.EnableNoclip ~= false
local RETURN_REACH_DIST = tonumber(CONFIG.Combat.ReturnReachDist) or 4
local RETURN_HOLD_TIME = tonumber(CONFIG.Combat.ReturnHoldTime) or 0.20
local DEFAULT_FLY_SPEED_DIVIDER = tonumber(CONFIG.Combat.FlySpeedDivider) or 4 -- legacy
local DEFAULT_FLY_SPEED_MULTIPLIER = math.clamp(tonumber(CONFIG.Combat.FlySpeedMultiplier) or 0.25, 0.01, 10) -- legacy
local DEFAULT_DIRECT_TWEEN_SPEED = tonumber(CONFIG.Combat.TweenSpeed) or tonumber(CONFIG.Combat.TwenSpeed)
local ATTACK_BASE_FLY_SPEED = tonumber(CONFIG.Combat.AttackBaseFlySpeed) or 220
local RETURN_BASE_FLY_SPEED = tonumber(CONFIG.Combat.ReturnBaseFlySpeed) or 180
local DEFAULT_MOVE_TWEEN_MIN_TIME = tonumber(CONFIG.Combat.MoveTweenMinTime) or 0.08
local DEFAULT_MOVE_TWEEN_MAX_TIME = tonumber(CONFIG.Combat.MoveTweenMaxTime) or 3.00
local DEFAULT_MOVE_TWEEN_UPDATE_INTERVAL = tonumber(CONFIG.Combat.MoveTweenUpdateInterval) or 0.03
local PIN_STICK_ENABLED = CONFIG.Combat.PinStickEnabled == true
local PIN_STICK_DISTANCE = tonumber(CONFIG.Combat.PinStickDistance) or 28
local ENABLE_RETURN_TO_LAST_POS = CONFIG.Combat.EnableReturnToLastPos == true
local MAX_TWEEN_STEP_DISTANCE = tonumber(CONFIG.Combat.MaxTweenStepDistance) or 220
local WORLD_MIN_Y = tonumber(CONFIG.Combat.WorldMinY) or -50
local WORLD_MAX_Y = tonumber(CONFIG.Combat.WorldMaxY) or 3000
local WORLD_MAX_ABS_XZ = tonumber(CONFIG.Combat.WorldMaxAbsXZ) or 25000

local function firstNumber(...)
    for i = 1, select("#", ...) do
        local n = tonumber(select(i, ...))
        if n ~= nil then
            return n
        end
    end
    return nil
end

local function getRuntimeCombatConfig()
    local cfg = GLOBAL_ENV.PENNY_CONFIG
    if type(cfg) == "table" and type(cfg.Combat) == "table" then
        return cfg.Combat
    end
    return CONFIG.Combat or {}
end

local function resolveFlyDivider()
    local runtime = getRuntimeCombatConfig()
    local divider = firstNumber(
        runtime.FlySpeedDivider,
        runtime.FlyDivider,
        GLOBAL_ENV.PENNY_FLY_SPEED_DIVIDER,
        GLOBAL_ENV.FLY_SPEED_DIVIDER,
        DEFAULT_FLY_SPEED_DIVIDER
    ) or DEFAULT_FLY_SPEED_DIVIDER
    if divider < 0.05 then
        divider = 0.05
    end
    return divider
end

local function resolveMovementSpeed(baseFlySpeed)
    local runtime = getRuntimeCombatConfig()

    -- External config compatibility:
    -- Combat.TweenSpeed / Combat.TwenSpeed / global PENNY_TWEEN_SPEED / TWEEN_SPEED
    local direct = firstNumber(
        runtime.TweenSpeed,
        runtime.TwenSpeed,
        runtime.Tween_Speed,
        GLOBAL_ENV.PENNY_TWEEN_SPEED,
        GLOBAL_ENV.TWEEN_SPEED,
        GLOBAL_ENV.TweenSpeed,
        GLOBAL_ENV.TwenSpeed,
        DEFAULT_DIRECT_TWEEN_SPEED
    )
    local speedBoost = firstNumber(
        runtime.SpeedBoost,
        runtime.SpeedScale,
        runtime.TweenSpeedBoost,
        GLOBAL_ENV.PENNY_SPEED_BOOST,
        GLOBAL_ENV.SPEED_BOOST,
        1
    ) or 1
    speedBoost = math.clamp(speedBoost, 0.05, 50)

    if direct and direct > 0 then
        return math.max(direct * speedBoost, 0.2), "direct"
    end

    -- Legacy formula path.
    local divider = resolveFlyDivider()

    local multiplier = firstNumber(
        runtime.FlySpeedMultiplier,
        runtime.FlyMultiplier,
        GLOBAL_ENV.PENNY_FLY_SPEED_MULTIPLIER,
        GLOBAL_ENV.FLY_SPEED_MULTIPLIER,
        DEFAULT_FLY_SPEED_MULTIPLIER
    ) or DEFAULT_FLY_SPEED_MULTIPLIER
    multiplier = math.clamp(multiplier, 0.01, 10)

    local speed = ((baseFlySpeed / divider) * multiplier) * speedBoost
    return math.max(speed, 0.2), "legacy"
end

local function resolveTweenTiming()
    local runtime = getRuntimeCombatConfig()
    local minTime = firstNumber(
        runtime.MoveTweenMinTime,
        runtime.MinTweenTime,
        runtime.TweenMinTime,
        GLOBAL_ENV.PENNY_TWEEN_MIN_TIME,
        DEFAULT_MOVE_TWEEN_MIN_TIME
    ) or DEFAULT_MOVE_TWEEN_MIN_TIME
    local maxTime = firstNumber(
        runtime.MoveTweenMaxTime,
        runtime.MaxTweenTime,
        runtime.TweenMaxTime,
        GLOBAL_ENV.PENNY_TWEEN_MAX_TIME,
        DEFAULT_MOVE_TWEEN_MAX_TIME
    ) or DEFAULT_MOVE_TWEEN_MAX_TIME
    local updateInterval = firstNumber(
        runtime.MoveTweenUpdateInterval,
        runtime.TweenUpdateInterval,
        GLOBAL_ENV.PENNY_TWEEN_UPDATE_INTERVAL,
        DEFAULT_MOVE_TWEEN_UPDATE_INTERVAL
    ) or DEFAULT_MOVE_TWEEN_UPDATE_INTERVAL

    minTime = math.clamp(minTime, 0.01, 10)
    maxTime = math.clamp(maxTime, minTime, 20)
    updateInterval = math.clamp(updateInterval, 0.005, 0.5)

    return minTime, maxTime, updateInterval
end

local function toBool(v, defaultValue)
    if type(v) == "boolean" then
        return v
    end
    if type(v) == "number" then
        return v ~= 0
    end
    if type(v) == "string" then
        local s = v:lower()
        if s == "true" or s == "1" or s == "yes" or s == "on" then
            return true
        end
        if s == "false" or s == "0" or s == "no" or s == "off" then
            return false
        end
    end
    return defaultValue
end

local function useConstantTweenSpeed()
    local runtime = getRuntimeCombatConfig()
    local raw = runtime.ConstantTweenSpeed
    if raw == nil then
        raw = runtime.FixedTweenSpeed
    end
    if raw == nil then
        raw = GLOBAL_ENV.PENNY_CONSTANT_TWEEN_SPEED
    end
    if raw == nil then
        return true
    end
    return toBool(raw, true)
end

local __initSpeed, __initMode = resolveMovementSpeed(ATTACK_BASE_FLY_SPEED)
local __runtimeCombat = getRuntimeCombatConfig()
local __initBoost = firstNumber(
    __runtimeCombat.SpeedBoost,
    __runtimeCombat.SpeedScale,
    __runtimeCombat.TweenSpeedBoost,
    GLOBAL_ENV.PENNY_SPEED_BOOST,
    GLOBAL_ENV.SPEED_BOOST,
    1
) or 1
print(string.format(
    "[PennyHub] Combat config: Height=%.2f | NoOrbitDistance=%.2f | SpeedBoost=%.2f | TweenSpeedRaw=%s | FlyDividerRaw=%.2f | FlyMultRaw=%.2f | MoveSpeed=%.2f (%s)",
    HEIGHT,
    NO_ORBIT_DISTANCE,
    __initBoost,
    tostring(DEFAULT_DIRECT_TWEEN_SPEED),
    DEFAULT_FLY_SPEED_DIVIDER,
    DEFAULT_FLY_SPEED_MULTIPLIER,
    __initSpeed,
    tostring(__initMode)
))

-- AUTO STO TOGGLE
local AUTO_STO_SETTINGS = GLOBAL_ENV.PENNY_AUTO_STO
if type(AUTO_STO_SETTINGS) ~= "table" then
    AUTO_STO_SETTINGS = {
        ENABLED = CONFIG.AutoSto.Enabled ~= false,   -- true = bat auto nang sto, false = tat
        INTERVAL = tonumber(CONFIG.AutoSto.Interval) or 2, -- so giay moi lan auto nang
        POTION_ENABLED = CONFIG.AutoSto.PotionEnabled == true,
        POTION_INTERVAL = tonumber(CONFIG.AutoSto.PotionInterval) or tonumber(CONFIG.AutoSto.Interval) or 2,
    }
else
    if AUTO_STO_SETTINGS.ENABLED == nil then
        AUTO_STO_SETTINGS.ENABLED = CONFIG.AutoSto.Enabled ~= false
    end
    if AUTO_STO_SETTINGS.INTERVAL == nil then
        AUTO_STO_SETTINGS.INTERVAL = tonumber(CONFIG.AutoSto.Interval) or 2
    end
    if AUTO_STO_SETTINGS.POTION_ENABLED == nil and AUTO_STO_SETTINGS.PotionEnabled == nil then
        AUTO_STO_SETTINGS.POTION_ENABLED = CONFIG.AutoSto.PotionEnabled == true
    end
    if AUTO_STO_SETTINGS.POTION_INTERVAL == nil and AUTO_STO_SETTINGS.PotionInterval == nil then
        AUTO_STO_SETTINGS.POTION_INTERVAL = tonumber(CONFIG.AutoSto.PotionInterval) or tonumber(CONFIG.AutoSto.Interval) or 2
    end
end
GLOBAL_ENV.PENNY_AUTO_STO = AUTO_STO_SETTINGS

local function isAutoStoEnabled()
    local cfgA = GLOBAL_ENV.PENNY_AUTO_STO
    local cfgB = GLOBAL_ENV.PENNY_CONFIG and GLOBAL_ENV.PENNY_CONFIG.AutoSto

    local aEnabled = true
    if cfgA ~= nil then
        if type(cfgA) == "table" then
            local raw = cfgA.ENABLED
            if raw == nil then
                raw = cfgA.Enabled
            end
            if raw ~= nil then
                aEnabled = toBool(raw, true)
            end
        else
            aEnabled = toBool(cfgA, true)
        end
    end

    local bEnabled = true
    if cfgB ~= nil then
        if type(cfgB) == "table" then
            local raw = cfgB.Enabled
            if raw == nil then
                raw = cfgB.ENABLED
            end
            if raw ~= nil then
                bEnabled = toBool(raw, true)
            end
        else
            -- Allow shorthand external config: PENNY_CONFIG.AutoSto = false
            bEnabled = toBool(cfgB, true)
        end
    end

    return aEnabled and bEnabled
end

local function getAutoStoInterval()
    local cfgA = GLOBAL_ENV.PENNY_AUTO_STO
    local cfgB = GLOBAL_ENV.PENNY_CONFIG and GLOBAL_ENV.PENNY_CONFIG.AutoSto

    local n = nil
    if type(cfgA) == "table" then
        n = tonumber(cfgA.INTERVAL)
    end
    if type(cfgB) == "table" then
        if cfgB.Interval ~= nil then
            n = tonumber(cfgB.Interval)
        end
        if (not n) and cfgB.INTERVAL ~= nil then
            n = tonumber(cfgB.INTERVAL)
        end
    elseif type(cfgB) == "number" then
        n = cfgB
    end
    if not n or n < 0.2 then
        return 0.2
    end
    return n
end

local function isAutoStoPotionEnabled()
    local cfgA = GLOBAL_ENV.PENNY_AUTO_STO
    local cfgB = GLOBAL_ENV.PENNY_CONFIG and GLOBAL_ENV.PENNY_CONFIG.AutoSto

    local aEnabled = false
    if type(cfgA) == "table" then
        local raw = cfgA.POTION_ENABLED
        if raw == nil then
            raw = cfgA.PotionEnabled
        end
        if raw ~= nil then
            aEnabled = toBool(raw, false)
        end
    end

    local bEnabled = false
    if type(cfgB) == "table" then
        local raw = cfgB.PotionEnabled
        if raw == nil then
            raw = cfgB.POTION_ENABLED
        end
        if raw ~= nil then
            bEnabled = toBool(raw, false)
        end
    end

    return aEnabled and bEnabled
end

local function getAutoStoPotionInterval()
    local cfgA = GLOBAL_ENV.PENNY_AUTO_STO
    local cfgB = GLOBAL_ENV.PENNY_CONFIG and GLOBAL_ENV.PENNY_CONFIG.AutoSto

    local n = nil
    if type(cfgA) == "table" then
        n = tonumber(cfgA.POTION_INTERVAL)
        if not n and cfgA.PotionInterval ~= nil then
            n = tonumber(cfgA.PotionInterval)
        end
    end

    if type(cfgB) == "table" then
        if cfgB.PotionInterval ~= nil then
            n = tonumber(cfgB.PotionInterval)
        end
        if (not n) and cfgB.POTION_INTERVAL ~= nil then
            n = tonumber(cfgB.POTION_INTERVAL)
        end
    end

    if not n then
        n = getAutoStoInterval()
    end
    if not n or n < 0.2 then
        return 0.2
    end
    return n
end

local SKILL_DELAY = tonumber(CONFIG.Combat.SkillDelay) or 0.45
local DASH_DELAY = tonumber(CONFIG.Combat.DashDelay) or 0.75
local ATTR_DELAY = tonumber(CONFIG.Combat.AttrDelay) or 1
local QUEST_DELAY = tonumber(CONFIG.Combat.QuestDelay) or 5
local COMPLETE_QUEST_DELAY = tonumber(CONFIG.Combat.CompleteQuestDelay) or 2
local REBIRTH_DELAY = tonumber(CONFIG.Combat.RebirthDelay) or 10
local CANCEL_QUEST_DELAY = tonumber(CONFIG.Combat.CancelQuestDelay) or 4

local NPC_TWEEN_TIME = tonumber(CONFIG.Combat.NpcTweenTime) or 2.0
local SKILL_IDS = type(CONFIG.Combat.SkillIds) == "table" and CONFIG.Combat.SkillIds or {1, 2, 4}
local QUEST6_NAME = "\228\187\187\229\138\1616"

local currentTarget = nil
local currentTargetType = "Unknown"

local lastSkill = 0
local lastDash = 0
local lastAttr = 0
local lastQuest = 0
local lastCompleteQuest = 0
local lastRebirth = 0
local lastCancelQuest = 0

local angle = 0
local isBusy = false
local lastTargetPos = nil
local returnToDeathPos = nil
local returnHoldUntil = 0
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
    if not pos then
        return false
    end
    if pos.Y < WORLD_MIN_Y or pos.Y > WORLD_MAX_Y then
        return false
    end
    if math.abs(pos.X) > WORLD_MAX_ABS_XZ or math.abs(pos.Z) > WORLD_MAX_ABS_XZ then
        return false
    end
    return true
end

local function limitTargetCFStep(fromPos, targetCF, maxStep)
    local targetPos = targetCF.Position
    local delta = targetPos - fromPos
    local dist = delta.Magnitude
    if dist <= maxStep then
        return targetCF
    end

    local newPos = fromPos + delta.Unit * maxStep
    return CFrame.new(newPos, newPos + targetCF.LookVector)
end

local function tweenMoveTo(hrp, targetCF, baseFlySpeed, allowPinStick)
    if not hrp or not hrp.Parent then
        return
    end

    if not isWorldPosSafe(hrp.Position) then
        return
    end

    if not isWorldPosSafe(targetCF.Position) then
        return
    end

    local now = tick()
    local rawDist = (hrp.Position - targetCF.Position).Magnitude

    -- Hard lock when near target to prevent gravity pull.
    if PIN_STICK_ENABLED and allowPinStick and rawDist <= PIN_STICK_DISTANCE then
        stopMoveTween()
        hrp.CFrame = targetCF
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
        lastMoveUpdateAt = now
        lastMoveTargetCF = targetCF
        return
    end

    targetCF = limitTargetCFStep(hrp.Position, targetCF, MAX_TWEEN_STEP_DISTANCE)

    local minTweenTime, maxTweenTime, moveUpdateInterval = resolveTweenTiming()

    if now - lastMoveUpdateAt < moveUpdateInterval then
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

    local speed = resolveMovementSpeed(baseFlySpeed)
    local duration
    if useConstantTweenSpeed() then
        duration = math.max(dist / speed, 0.01)
    else
        duration = math.clamp(dist / speed, minTweenTime, maxTweenTime)
    end

    stopMoveTween()

    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    activeMoveTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCF})
    activeMoveTween:Play()
end

local function getChar()
    local char = lp.Character or lp.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart")
    return char, hrp
end

local function stabilizeCharacter(char, hrp)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.PlatformStand = false
        hum.Sit = false
        hum:ChangeState(Enum.HumanoidStateType.Physics)
    end
end

local function applyNoclip(char)
    if not ENABLE_NOCLIP then
        return
    end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
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

local function nameHas(obj, keyword)
    return tostring(obj.Name):find(keyword) ~= nil
end

local function descendantNameHas(root, keyword)
    for _, v in ipairs(root:GetDescendants()) do
        if nameHas(v, keyword) then
            return true
        end
    end
    return false
end

local function hasAnyQuest()
    local taskFolder = lp:FindFirstChild("Task")
    if not taskFolder then
        return false
    end
    return #taskFolder:GetChildren() > 0
end

local guiTextCache = ""
local guiTextCacheAt = 0
local GUI_TEXT_CACHE_TTL = 0.4
local function getGuiTextAll()
    -- Cache GUI scan to reduce expensive full-descendant scans every tick.
    local now = tick()
    if guiTextCache ~= "" and (now - guiTextCacheAt <= GUI_TEXT_CACHE_TTL) then
        return guiTextCache
    end

    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then
        return ""
    end

    local all = ""
    for _, v in ipairs(pg:GetDescendants()) do
        if v:IsA("TextLabel") or v:IsA("TextButton") or v:IsA("TextBox") then
            all = all .. " " .. tostring(v.Text)
        end
    end
    all = string.lower(all)
    guiTextCache = all
    guiTextCacheAt = now
    return guiTextCache
end

local function isDwarfKingQuest()
    local text = getGuiTextAll()
    return text:find("dwarf king") ~= nil
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

    if text:find("exp")
        or text:find("gold")
        or text:find("coin")
        or text:find("reward")
        or text:find("gem")
        or text:find("item")
        or text:find("beri")
        or text:find("money")
        or text:find("cash") then
        return true
    end
    return false
end

local function activateGoodbyeFromGui()
    local text = getGuiTextAll()
    if text:find("goodbye") then
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.One, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.One, false, game)
        end)
        return true
    end
    return false
end

local function cancelAllCurrentQuests()
    local taskFolder = lp:FindFirstChild("Task")
    if not taskFolder then
        return
    end

    for _, quest in ipairs(taskFolder:GetChildren()) do
        local args = {
            "\230\148\190\229\188\131\228\187\187\229\138\161",
            quest.Name
        }
        pcall(function()
            AttrRemote:InvokeServer(unpack(args))
        end)
        task.wait(0.15)
    end
end

local function isKingDwarf(model)
    if not hasAllBodyParts(model) then
        return false
    end

    local modelName = string.lower(tostring(model.Name or ""))
    if modelName:find("dwarf king")
        or modelName:find("king dwarf")
        or (modelName:find("king") and modelName:find("dwarf")) then
        return true
    end

    -- Robust fallback: detect by stable asset markers on king weapon.
    if descendantNameHas(model, "8347")
        or descendantNameHas(model, "8350")
        or descendantNameHas(model, "8351")
        or descendantNameHas(model, "Box40013")
        or descendantNameHas(model, "Box40015")
        or descendantNameHas(model, "Ham01")
        or descendantNameHas(model, "Plane007")
        or descendantNameHas(model, "Plane010") then
        return true
    end

    return false
end

local function isArcherGoblin(model)
    if not hasAllBodyParts(model) then
        return false
    end

    local ranger = model:FindFirstChild("Ranger")
    local head = model:FindFirstChild("Head")
    local leftArm = model:FindFirstChild("Left Arm")
    if not ranger or not head or not leftArm then
        return false
    end

    if head:FindFirstChild("tou") == nil then
        return false
    end

    local lowerName = string.lower(tostring(model.Name or ""))
    if lowerName:find("archer") or lowerName:find("ranger") then
        return true
    end

    for _, v in ipairs(leftArm:GetChildren()) do
        local n = tostring(v.Name)
        if n:find("Handle008") or n:lower():find("bow") then
            return true
        end
    end

    return false
end

local function isWarhammerDwarf(model)
    if not hasAllBodyParts(model) then
        return false
    end

    local modelName = string.lower(tostring(model.Name or ""))
    if modelName:find("warhammer")
        or modelName:find("hammer")
        or (modelName:find("dwarf") and modelName:find("war")) then
        if not isArcherGoblin(model) then
            return true
        end
    end

    local hasDwarfWeapon =
        descendantNameHas(model, "Hammer")
        or descendantNameHas(model, "ham")
        or descendantNameHas(model, "Box40013")
        or descendantNameHas(model, "Box40015")
        or descendantNameHas(model, "Ham01")

    if hasDwarfWeapon and not isArcherGoblin(model) then
        return true
    end

    return false
end

local function isPickaxeDwarf(model)
    if not hasAllBodyParts(model) then
        return false
    end

    local hasPickaxeWeapon =
        descendantNameHas(model, "Pick")
        or descendantNameHas(model, "pick")
        or descendantNameHas(model, "NGon")
        or descendantNameHas(model, "83410012")
        or descendantNameHas(model, "8341")

    if not hasPickaxeWeapon then
        return false
    end

    if isArcherGoblin(model) or isWarhammerDwarf(model) or isKingDwarf(model) then
        return false
    end

    return true
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

local function isValidNPC(model)
    return getNPCType(model) ~= nil
end

local function getTargetAnchorPosition(model)
    if not model then
        return nil
    end

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

local function getNearestNPC(hrp)
    local bestKing, bestKingDist = nil, math.huge
    local bestWarhammer, bestWarhammerDist = nil, math.huge
    local bestOther, bestOtherDist = nil, math.huge

    local monsterFolder = workspace:FindFirstChild("Monster")
    if not monsterFolder then
        return nil
    end

    for _, mob in ipairs(monsterFolder:GetChildren()) do
        local npcType = getNPCType(mob)
        if npcType then
            local mobHrp = mob:FindFirstChild("HumanoidRootPart")
            if mobHrp then
                local d = (hrp.Position - mobHrp.Position).Magnitude

                if npcType == "King Dwarf" then
                    if d < bestKingDist then
                        bestKingDist, bestKing = d, mob
                    end
                elseif npcType == "Warhammer Dwarf" then
                    if d < bestWarhammerDist then
                        bestWarhammerDist, bestWarhammer = d, mob
                    end
                elseif npcType == "Archer Goblin" then
                    -- Skip archer targets entirely
                else
                    if d < bestOtherDist then
                        bestOtherDist, bestOther = d, mob
                    end
                end
            end
        end
    end

    if bestKing then
        currentTargetType = "King Dwarf"
        return bestKing
    end
    if bestWarhammer then
        currentTargetType = "Warhammer Dwarf"
        return bestWarhammer
    end

    currentTargetType = "Other"
    return bestOther
end

local function castSkill(skillId, target, hrp)
    local targetPart = target and target:FindFirstChild("HumanoidRootPart")
    if not targetPart then
        return
    end

    local args = {
        skillId,
        {
            targetCF = targetPart.CFrame,
            moveDirectionStr = "Forward",
            clientPredictCastId = HttpService:GenerateGUID(false),
            characterType = "Player",
            releaseCF = hrp.CFrame,
            characterId = lp.UserId,
            trackTargetId = tostring(target.Name)
        }
    }

    pcall(function()
        SkillRemote:FireServer(unpack(args))
    end)
end

local function castDash(target, hrp)
    local targetPart = target and target:FindFirstChild("HumanoidRootPart")
    if not targetPart then
        return
    end

    local args = {
        3,
        {
            targetCF = targetPart.CFrame,
            moveDirectionStr = "Forward",
            clientPredictCastId = HttpService:GenerateGUID(false),
            characterType = "Player",
            releaseCF = hrp.CFrame,
            characterId = lp.UserId,
            trackTargetId = tostring(target.Name)
        }
    }

    pcall(function()
        SkillRemote:FireServer(unpack(args))
    end)
end

local function autoAddPoint()
    local args = {
        "\229\177\158\230\128\167\229\138\160\231\130\185",
        {
            AttrTp = 1,
            PointNum = 1
        }
    }
    pcall(function()
        AttrRemote:InvokeServer(unpack(args))
    end)
end

local function autoQuest()
    local args = {
        "\229\143\145\230\148\190\228\187\187\229\138\161",
        {
            QUEST6_NAME
        }
    }
    pcall(function()
        TalkFunc:InvokeServer(unpack(args))
    end)
end

local function autoRebirth()
    local args = {
        "\233\135\141\231\148\159"
    }
    pcall(function()
        AttrRemote:InvokeServer(unpack(args))
    end)
end

local function completeQuestByNPC(hrp)
    local npc
    pcall(function()
        npc = workspace["\229\156\186\230\153\175"]["1"].NPC["\229\147\136\229\136\169\229\155\160\231\137\185"]
    end)

    if not npc then
        return
    end

    local npcHRP = npc:FindFirstChild("HumanoidRootPart")
    if not npcHRP then
        return
    end

    local prompt = npcHRP:FindFirstChild("TalkPrompt")
    if not prompt then
        return
    end

    currentTarget = nil

    local targetCF = npcHRP.CFrame * CFrame.new(0, 0, -5)
    stopMoveTween()
    local npcDist = (hrp.Position - targetCF.Position).Magnitude
    local npcSpeed = resolveMovementSpeed(RETURN_BASE_FLY_SPEED)
    local minTweenTime, maxTweenTime = resolveTweenTiming()
    local npcDuration
    if useConstantTweenSpeed() then
        npcDuration = math.max(npcDist / npcSpeed, 0.01)
    else
        npcDuration = math.clamp(npcDist / npcSpeed, minTweenTime, math.max(maxTweenTime, 0.25))
    end
    local tweenInfo = TweenInfo.new(npcDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    local toNpcTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCF})
    toNpcTween:Play()
    pcall(function()
        toNpcTween.Completed:Wait()
    end)
    hrp.CFrame = targetCF

    task.wait(0.4)

    pcall(function()
        fireproximityprompt(prompt)
    end)

    task.wait(0.6)
    activateGoodbyeFromGui()
end

RunService.Heartbeat:Connect(function(dt)
    if not isRunActive() then
        return
    end

    if isBusy then
        return
    end

    local char, hrp = getChar()
    stabilizeCharacter(char, hrp)
    applyNoclip(char)

    if not isWorldPosSafe(hrp.Position) then
        stopMoveTween()
        returnToDeathPos = nil
        currentTarget = nil
        lastTargetPos = nil
        return
    end

    if tick() - lastQuest >= QUEST_DELAY then
        lastQuest = tick()
        if not hasAnyQuest() then
            autoQuest()
        end
    end

    if tick() - lastCompleteQuest >= COMPLETE_QUEST_DELAY then
        lastCompleteQuest = tick()
        if hasAnyQuest() then
            if shouldReturnToHarryint() then
                if not isBusy then
                    isBusy = true
                    task.spawn(function()
                        completeQuestByNPC(hrp)
                        task.wait(1)
                        isBusy = false
                    end)
                end
                return
            end

            if not isDwarfKingQuest() or not hasQuestReward() then
                if tick() - lastCancelQuest >= CANCEL_QUEST_DELAY then
                    lastCancelQuest = tick()
                    cancelAllCurrentQuests()
                end
            end
        end
    end

    if tick() - lastRebirth >= REBIRTH_DELAY then
        lastRebirth = tick()
        autoRebirth()
    end

    if returnToDeathPos then
        if not isWorldPosSafe(returnToDeathPos) then
            returnToDeathPos = nil
            returnHoldUntil = 0
        else
        local returnOrbitPos = returnToDeathPos + Vector3.new(0, HEIGHT, 0)
        local returnCF = CFrame.lookAt(
            returnOrbitPos,
            returnToDeathPos
        )
        tweenMoveTo(hrp, returnCF, RETURN_BASE_FLY_SPEED, false)

        local dist = (hrp.Position - returnOrbitPos).Magnitude
        if dist <= RETURN_REACH_DIST then
            if returnHoldUntil == 0 then
                returnHoldUntil = tick() + RETURN_HOLD_TIME
            elseif tick() >= returnHoldUntil then
                returnToDeathPos = nil
                returnHoldUntil = 0
                lastTargetPos = nil
                currentTarget = getNearestNPC(hrp)
                angle = 0
            end
        else
            returnHoldUntil = 0
        end

        return
        end
    end

    if not currentTarget
        or not currentTarget.Parent
        or not currentTarget:IsDescendantOf(workspace.Monster)
        or not isValidNPC(currentTarget)
        or not currentTarget:FindFirstChild("HumanoidRootPart") then
        if currentTarget then
            local oldPart = currentTarget:FindFirstChild("HumanoidRootPart")
            if oldPart then
                lastTargetPos = oldPart.Position
            end
        end

        if ENABLE_RETURN_TO_LAST_POS and lastTargetPos and isWorldPosSafe(lastTargetPos) then
            returnToDeathPos = lastTargetPos
            currentTarget = nil
            angle = 0
            return
        end

        currentTarget = getNearestNPC(hrp)
        angle = 0
    end

    if currentTarget and currentTarget:FindFirstChild("HumanoidRootPart") then
        local targetPart = currentTarget.HumanoidRootPart
        if not isWorldPosSafe(targetPart.Position) then
            currentTarget = nil
            return
        end
        local targetAnchorPos = getTargetAnchorPosition(currentTarget) or targetPart.Position
        lastTargetPos = targetPart.Position
        local safeDt = math.min(dt, 1 / 20)
        local orbitCF

        if DISABLE_ORBIT then
            -- Keep above target but strafe slightly left-right for smoother combat movement.
            local fixedPos = targetAnchorPos + Vector3.new(0, HEIGHT, 0)
            if NO_ORBIT_DISTANCE > 0 then
                fixedPos = fixedPos - targetPart.CFrame.LookVector * NO_ORBIT_DISTANCE
            end
            if HEAD_STRAFE_ENABLED and HEAD_STRAFE_RADIUS > 0 then
                angle += safeDt * HEAD_STRAFE_SPEED
                local sideOffset = math.sin(angle) * HEAD_STRAFE_RADIUS
                local forwardOffset = math.cos(angle * 0.5) * (HEAD_STRAFE_RADIUS * 0.25)
                local strafePos = fixedPos
                    + targetPart.CFrame.RightVector * sideOffset
                    + targetPart.CFrame.LookVector * forwardOffset
                orbitCF = CFrame.lookAt(strafePos, targetAnchorPos)
            else
                orbitCF = CFrame.new(fixedPos) * CFrame.Angles(0, math.rad(targetPart.Orientation.Y), 0)
            end
        else
            angle += safeDt * ROTATE_SPEED
            local x = math.cos(angle) * RADIUS
            local z = math.sin(angle) * RADIUS
            local orbitPos = targetAnchorPos + Vector3.new(x, HEIGHT, z)
            orbitCF = CFrame.lookAt(orbitPos, targetAnchorPos)
        end

        tweenMoveTo(hrp, orbitCF, ATTACK_BASE_FLY_SPEED, true)

        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)

        if tick() - lastSkill >= SKILL_DELAY then
            lastSkill = tick()
            task.spawn(function()
                for _, skillId in ipairs(SKILL_IDS) do
                    castSkill(skillId, currentTarget, hrp)
                    task.wait(0.03)
                end
            end)
        end

        -- Auto dash is disabled by request.

        if tick() - lastAttr >= ATTR_DELAY then
            lastAttr = tick()
            autoAddPoint()
        end
    end
end)

--====================================================
-- AUTO SELL LOOP (Merged)
--====================================================

local AUTO_SELL_ENABLED = true
local AUTO_SELL_INTERVAL = tonumber(CONFIG.AutoSell.Interval) or 60 -- seconds
AUTO_SELL_ENABLED = CONFIG.AutoSell.Enabled ~= false

local SELL_ITEM_NAME = {
    ["LightShard"] = true,
    ["DarkShard"] = true,
    ["EarthShard"] = true,
    ["IceShard"] = true,
    ["FireShard"] = true,
    ["WindShard"] = true,
    ["CopperEarring"] = true,
    ["GoblinBone"] = true,
    ["FlameCrest"] = true,
    ["GoblinFinger"] = true,
    ["GoldenTooth"] = true,
    ["DwarfEmblem"] = true,
    ["SeagullEgg"] = true,
    ["WitheredMushroom"] = true,
    ["Blueberry"] = true,
}

local EXCLUDE_ITEM_NAME = {
    ["FurnaceCore"] = true,
}

local OPEN_SELL_POP = "\230\137\147\229\188\128\231\149\140\233\157\162"
local STO_UPGRADE_ARGS = {
    "\232\131\140\229\140\133\229\174\185\233\135\143\233\135\145\229\184\129\229\141\135\231\186\167",
    {
        itemTp = 2
    }
}
local STO_POTION_UPGRADE_ARGS = {
    "\232\131\140\229\140\133\229\174\185\233\135\143\233\135\145\229\184\129\229\141\135\231\186\167",
    {
        itemTp = 9
    }
}

local function as_parseMoneyText(raw)
    local s = tostring(raw or ""):lower()
    s = s:gsub(",", "")
    s = s:gsub("%s+", "")

    local num, suffix = s:match("([%d%.]+)([kmb])")
    if num then
        local n = tonumber(num) or 0
        local mul = 1
        if suffix == "k" then
            mul = 1000
        elseif suffix == "m" then
            mul = 1000000
        elseif suffix == "b" then
            mul = 1000000000
        end
        return math.floor(n * mul)
    end

    local clean = s:gsub("[^%d%.%-]", "")
    local n = tonumber(clean)
    if not n then
        return 0
    end
    return math.floor(n)
end

local function as_getCurrentGold()
    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then
        return 0
    end

    local systemGui = pg:FindFirstChild("SystemGui")
    if not systemGui then
        return 0
    end

    local leftFrame = systemGui:FindFirstChild("LeftFrame")
    if not leftFrame then
        return 0
    end

    local money = leftFrame:FindFirstChild("Money")
    if not money then
        return 0
    end

    local frame = money:FindFirstChild("Frame")
    if not frame then
        return 0
    end

    local iconLabel = frame:FindFirstChild("IconLabel")
    if not iconLabel then
        return 0
    end

    local text = nil
    pcall(function()
        text = iconLabel.Text
    end)

    if text and text ~= "" then
        return as_parseMoneyText(text)
    end

    for _, d in ipairs(iconLabel:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local t = tostring(d.Text or "")
            if t ~= "" then
                return as_parseMoneyText(t)
            end
        end
    end

    return 0
end

local function as_upgradeBagCapacity()
    local ok, err = pcall(function()
        game:GetService("ReplicatedStorage")
            :WaitForChild("Msg")
            :WaitForChild("RemoteFunction")
            :WaitForChild("RemoteFunction")
            :InvokeServer(unpack(STO_UPGRADE_ARGS))
    end)

    if not ok then
        warn("[AutoSTO] Invoke failed:", err)
    end

    return ok
end

local function as_upgradePotionCapacity()
    local ok, err = pcall(function()
        game:GetService("ReplicatedStorage")
            :WaitForChild("Msg")
            :WaitForChild("RemoteFunction")
            :WaitForChild("RemoteFunction")
            :InvokeServer(unpack(STO_POTION_UPGRADE_ARGS))
    end)

    if not ok then
        warn("[AutoSTO-Potion] Invoke failed:", err)
    end

    return ok
end

local function as_cleanName(txt)
    txt = tostring(txt or "")
    txt = txt:gsub("%s+", "")
    txt = txt:gsub("[^%w]", "")
    return txt
end

local function as_clickGui(obj)
    if not obj then return false end
    pcall(function() firesignal(obj.MouseButton1Down) end)
    task.wait(0.02)
    pcall(function() firesignal(obj.MouseButton1Up) end)
    pcall(function() firesignal(obj.MouseButton1Click) end)
    pcall(function() firesignal(obj.Activated) end)
    pcall(function() obj:Activate() end)
    return true
end

local function as_getScreenGui()
    return lp:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
end

local function as_getSellPop()
    return as_getScreenGui():WaitForChild("SellPop")
end

local function as_getSellPopBagFrame()
    return as_getSellPop():WaitForChild("ContentClip"):WaitForChild("Main"):WaitForChild("_BagFrame")
end

local function as_getSellAll()
    return as_getScreenGui():WaitForChild("SellAll")
end

local function as_getSellAllBagFrame()
    return as_getSellAll():WaitForChild("ContentClip"):WaitForChild("Frame"):WaitForChild("_BagFrame")
end
local SELLPOP_TIMEOUT = 20
local sellPopOpenedAt = nil

local function as_closeSellPopIfStuck()
    local ok, sp = pcall(function()
        return as_getSellPop()
    end)
    if not ok or not sp then
        sellPopOpenedAt = nil
        return
    end

    if sp.Visible then
        if not sellPopOpenedAt then
            sellPopOpenedAt = tick()
            return
        end

        if tick() - sellPopOpenedAt >= SELLPOP_TIMEOUT then
            local exitBtn = sp.ContentClip.Top._Exit.Button
            as_clickGui(exitBtn)
            task.wait(0.1)
            sellPopOpenedAt = nil
            warn("[AutoSellLoop] SellPop open > 30s, auto closed.")
        end
    else
        sellPopOpenedAt = nil
    end
end


local function as_closeBlockingPopups()
    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then return end

    local function tryClickClose(root)
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("TextButton") or d:IsA("ImageButton") then
                local n = tostring(d.Name):lower()
                local t = ""
                pcall(function() t = tostring(d.Text):lower() end)
                if n:find("close") or n:find("exit") or n:find("refuse") or n:find("cancel")
                    or t == "x" or t:find("close") or t:find("cancel") or t:find("not now") then
                    as_clickGui(d)
                    task.wait(0.05)
                end
            end
        end
    end

    -- Ã†Â°u tiÃƒÂªn popup hay chÃ¡ÂºÂ·n: Event/Notice/Announcement
    for _, gui in ipairs(pg:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled ~= false then
            local nm = tostring(gui.Name):lower()
            if nm:find("event") or nm:find("notice") or nm:find("announcement") or nm:find("update") then
                tryClickClose(gui)
            end
        end
    end

    -- quÃƒÂ©t rÃ¡Â»â„¢ng thÃƒÂªm 1 lÃ†Â°Ã¡Â»Â£t
    tryClickClose(pg)
end
local function as_isSellPopOpen()
    local ok, result = pcall(function()
        return as_getSellPop().Visible
    end)
    return ok and result == true
end

local function as_openSellPopIfNeeded()
    if as_isSellPopOpen() then return true end
    pcall(function()
        TalkFunc:InvokeServer(OPEN_SELL_POP, {"SellPop"})
    end)
    task.wait(0.4)
    return as_isSellPopOpen()
end

local function as_selectMaterialTab()
    local btn = as_getSellPop().ContentClip.Main._Tab.Tab_Material.Button
    as_clickGui(btn)
    task.wait(0.25)
end

local function as_enableMultiSelect()
    local btn = as_getSellPop().ContentClip.Bottom._Btns1._MultiSelect.Btn
    as_clickGui(btn)
    task.wait(0.25)
end

local function as_getItemName(slot)
    local nameObj = slot:FindFirstChild("Name")
    if nameObj and nameObj:IsA("TextLabel") then
        local txt = tostring(nameObj.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if txt ~= "" then return txt end
    end

    for _, d in ipairs(slot:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local txt = tostring(d.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if txt ~= "" and not txt:match("^x%d+$") then
                return txt
            end
        end
    end
    return nil
end

local function as_clickSlot(slot)
    local clickObj = slot:FindFirstChild("ItemClickScale", true)
    if clickObj then return as_clickGui(clickObj) end
    local bg = slot:FindFirstChild("BG")
    if bg then return as_clickGui(bg) or as_clickGui(slot) end
    return as_clickGui(slot)
end

local function as_pickItemsByWhitelist()
    local bagFrame = as_getSellPopBagFrame()
    local picked = 0

    for _, slot in ipairs(bagFrame:GetChildren()) do
        if slot.Name:match("^SellSlot_%d+$") then
            local itemName = as_getItemName(slot)
            if itemName then
                local key = as_cleanName(itemName)
                if SELL_ITEM_NAME[key] then
                    as_clickSlot(slot)
                    picked += 1
                    task.wait(0.08)
                end
            end
        end
    end

    return picked
end

local function as_forceClickAllSellSlots()
    local gui = as_getSellPop()
    local bag = gui.ContentClip.Main._BagFrame

    for _, slot in ipairs(bag:GetChildren()) do
        if slot.Name:match("^SellSlot_") then
            local itemName = as_getItemName(slot)
            local key = as_cleanName(itemName)
            if not EXCLUDE_ITEM_NAME[key] then
                pcall(function() firesignal(slot.MouseButton1Click) end)
                pcall(function() firesignal(slot.Activated) end)
                task.wait(0.15)
            end
        end
    end
end

local function as_unselectExcludedInSellAll()
    local sellAllBag = as_getSellAllBagFrame()
    local sellPopBag = as_getSellPopBagFrame()

    for _, itemBtn in ipairs(sellAllBag:GetChildren()) do
        local id = itemBtn.Name:match("^Item_(%d+)$")
        if id and (itemBtn:IsA("TextButton") or itemBtn:IsA("ImageButton")) and itemBtn.Visible then
            local slot = sellPopBag:FindFirstChild("SellSlot_" .. id)
            if slot then
                local itemName = as_getItemName(slot)
                local key = as_cleanName(itemName)
                if EXCLUDE_ITEM_NAME[key] then
                    as_clickGui(itemBtn)
                    task.wait(0.08)
                end
            end
        end
    end
end

local function as_countSellAllItems()
    local bag = as_getSellAllBagFrame()
    local n = 0
    for _, c in ipairs(bag:GetChildren()) do
        if c.Name:match("^Item_%d+$") and c.Visible ~= false then
            n += 1
        end
    end
    return n
end

local function as_confirmSell()
    local sellPop = as_getSellPop()
    local sellAll = as_getSellAll()
    local finalCount = 0

    -- step 1 (confirm thá»© 1): dung dung block click ban dua, goi ngay sau khi select xong
    as_closeBlockingPopups()
    local sellBtn = sellPop.ContentClip.Bottom._Btns2._SellBtn.Btn
    local function clickSellBtnExact()
        if not sellBtn then
            warn("[AutoSellLoop] Khong tim thay SellBtn")
            return false
        end

        if firesignal then
            pcall(function()
                firesignal(sellBtn.MouseButton1Click)
            end)
            pcall(function()
                firesignal(sellBtn.Activated)
            end)
        else
            local vim = game:GetService("VirtualInputManager")
            local pos = sellBtn.AbsolutePosition + (sellBtn.AbsoluteSize / 2)
            vim:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            task.wait(0.05)
            vim:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
        end

        return true
    end

    as_closeBlockingPopups()
    clickSellBtnExact()
    task.wait(0.15)

    -- Ä‘Ã£ má»Ÿ bÆ°á»›c confirm Ä‘áº§u, giá» má»›i unselect exclude trong SellAll
    if sellAll.Visible then
        as_unselectExcludedInSellAll()
        task.wait(0.1)
        finalCount = as_countSellAllItems()
    end

    -- step 2 (confirm thá»© 2): báº¥m OK 1 láº§n
    if sellAll.Visible then
        local okBtn = sellAll.ContentClip.Frame.Btns._OkBtn.Btn
        as_closeBlockingPopups()
        as_clickGui(okBtn)
        task.wait(0.2)
    end

    -- step 3: close SellPop if still open
    if sellPop.Visible then
        local exitBtn = sellPop.ContentClip.Top._Exit.Button
        as_clickGui(exitBtn)
    end

    return sellAll.Visible == false, finalCount
end

local function runAutoSellOnce()
    local soldCount = 0
    local sellSuccess = false
    local ok, err = pcall(function()
        local MAX_SELL_RETRY = 3
        for attempt = 1, MAX_SELL_RETRY do
            if not as_openSellPopIfNeeded() then
                task.wait(0.4)
                continue
            end

            as_closeBlockingPopups()
            as_selectMaterialTab()
            as_enableMultiSelect()

            as_closeBlockingPopups()
            as_pickItemsByWhitelist()
            as_forceClickAllSellSlots()

            task.wait(0.2)

            local confirmOk, finalCount = as_confirmSell()
            if confirmOk then
                sellSuccess = true
                soldCount = tonumber(finalCount) or 0
                break
            end

            -- confirm fail: Ä‘Ã³ng popup vÃ  thá»­ láº¡i vÃ²ng má»›i
            local sp = as_getSellPop()
            if sp.Visible then
                as_clickGui(sp.ContentClip.Top._Exit.Button)
            end
            task.wait(0.5)
        end
    end)

    if not ok then
        warn("[AutoSellLoop] error:", err)
        if WEBHOOK_CFG.NotifyError ~= false then
            webhookSend("AutoSell Error", tostring(err))
        end
        return
    end

    if sellSuccess then
        if WEBHOOK_CFG.NotifySell ~= false then
            webhookSend("AutoSell Success", "Sold items: " .. tostring(soldCount))
        end
    else
        if WEBHOOK_CFG.NotifyError ~= false then
            webhookSend("AutoSell Failed", "Could not confirm sell after retries.")
        end
    end
end

if AUTO_SELL_ENABLED then
    -- watchdog cháº¡y Ä‘á»™c láº­p: luÃ´n check SellPop timeout
    task.spawn(function()
        while isRunActive() do
            as_closeSellPopIfStuck()
            task.wait(1)
        end
    end)

    -- vÃ²ng auto sell theo chu ká»³
    task.spawn(function()
        task.wait(5)
        while isRunActive() do
            runAutoSellOnce()
            task.wait(AUTO_SELL_INTERVAL)
        end
    end)
end

task.spawn(function()
    task.wait(1)
    while isRunActive() do
        if isAutoStoEnabled() then
            -- call 2 quick times each cycle for reliability
            as_upgradeBagCapacity()
            task.wait(0.15)
            if isAutoStoEnabled() then
                as_upgradeBagCapacity()
                task.wait(getAutoStoInterval())
            else
                task.wait(0.2)
            end
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    task.wait(1)
    while isRunActive() do
        if isAutoStoPotionEnabled() then
            as_upgradePotionCapacity()
            task.wait(getAutoStoPotionInterval())
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    task.wait(5)
    local nextHopAt = nil

    while isRunActive() do
        if isAutoHopEnabled() then
            if not nextHopAt then
                nextHopAt = tick() + getAutoHopInterval()
            end

            if tick() >= nextHopAt then
                performServerHop("interval:" .. tostring(getAutoHopInterval()))
                nextHopAt = tick() + getAutoHopInterval()
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












