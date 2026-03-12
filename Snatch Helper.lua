---@diagnostic disable: undefined-global, need-check-nil, lowercase-global, cast-local-type, unused-local

script_name("Snatch Helper")
math.randomseed(os.time() + math.floor(os.clock() * 1000))

script_author("StepD")
script_version("5.2") -- óâåëè÷èë âåðñèþ

require('lib.moonloader')
require('encoding').default = 'CP1251'
local u8 = require('encoding').UTF8
local ffi = require('ffi')
local imgui = require 'mimgui'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local bit = require 'bit'
local memory = require 'memory'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local new, str, sizeof = imgui.new, ffi.string, ffi.sizeof
local sizeX, sizeY = getScreenResolution()

-- ==================== ËÎÊÀËÜÍÛÅ ÃËÎÁÀËÜÍÛÅ ÏÅÐÅÌÅÍÍÛÅ ====================
local isActiveCommand = false
local isActiveWantedCommand = false
local activeBinder = false
local stopCurrentBind = false
local stoppause = false
local pauseText = nil
local pauseKey = nil
local pauseCommand = nil
local script_advanced_list = {}
local selectorActive = false
local selectorTargetId = nil

-- ==================== ÀÍÈÌÀÖÈß ÎÊÍÀ ====================
local ui_meta = {
    __index = function(self, v)
        if v == "switch" then
            local switch = function()
                if self.process and self.process:status() ~= "dead" then return false end
                self.timer = os.clock()
                self.state = not self.state
                self.process = lua_thread.create(function()
                    local bringFloatTo = function(from, to, start_time, duration)
                        local timer = os.clock() - start_time
                        if timer >= 0.00 and timer <= duration then
                            local count = timer / (duration / 100)
                            return count * ((to - from) / 100)
                        end
                        return (timer > duration) and to or from
                    end
                    while true do wait(0)
                        local a = bringFloatTo(0.00, 1.00, self.timer, self.duration)
                        self.alpha = self.state and a or 1.00 - a
                        if a == 1.00 then break end
                    end
                end)
                return true
            end
            return switch
        end
        if v == "alpha" then return self.state and 1.00 or 0.00 end
        if v == "switch2" then
            return function() self.state = not self.state; self.alpha = self.state and 1.00 or 0.00 end
        end
    end
}

local mainWindow = { state = false, duration = 0.2 }
setmetatable(mainWindow, ui_meta)
local mainWindowOpen = imgui.new.bool(false)  -- äëÿ ñèíõðîíèçàöèè ñ êðåñòèêîì
local keyBindContext = nil -- "bind", "stop", "selector"

-- ==================== ÊÎÍÔÈÃÓÐÀÖÈß ====================
local configDirectory = getWorkingDirectory():gsub('\\','/') .. "/Snatch Helper"
local settings = {
    defaultDelay = 1500,
    stopKey = 0x7B,        -- F12 ïî óìîë÷àíèþ
    stopKeyMod = 0,
    selectorKey = 0x12,     -- Alt
    selectorKeyMod = 0,
    currentTheme = "default"
}
local settingsIni = configDirectory .. "/config.ini"

function loadSettings()
    local cfg = inicfg.load(nil, settingsIni)
    if cfg and cfg.Settings then
        settings.defaultDelay = tonumber(cfg.Settings.defaultDelay) or 1500
        settings.stopKey = tonumber(cfg.Settings.stopKey) or 0x7B
        settings.stopKeyMod = tonumber(cfg.Settings.stopKeyMod) or 0
        settings.selectorKey = tonumber(cfg.Settings.selectorKey) or 0x12
        settings.selectorKeyMod = tonumber(cfg.Settings.selectorKeyMod) or 0
        settings.currentTheme = cfg.Settings.currentTheme or "default"
    end
end
function saveSettings()
    local cfg = { Settings = settings }
    inicfg.save(cfg, settingsIni)
end
loadSettings()
function trimAll(s)
    if not s then return s end
    return s:gsub("^[%s%c]*", ""):gsub("[%s%c]*$", "")
end
-- ==================== ÖÂÅÒÎÂÛÅ ÒÅÌÛ ====================
local colorThemes = {
    default = {
        bg_dark      = imgui.ImVec4(0.08, 0.08, 0.08, 0.98),
        bg_medium    = imgui.ImVec4(0.11, 0.11, 0.11, 0.95),
        accent_primary   = imgui.ImVec4(0.85, 0.18, 0.18, 1.00),
        accent_secondary = imgui.ImVec4(0.95, 0.30, 0.30, 1.00),
        accent_dark      = imgui.ImVec4(0.65, 0.12, 0.12, 1.00),
        accent_gradient  = imgui.ImVec4(0.90, 0.22, 0.22, 0.90),
        text_primary     = imgui.ImVec4(0.98, 0.98, 0.98, 1.00),
        text_secondary   = imgui.ImVec4(0.70, 0.70, 0.70, 1.00),
    },
    dark = {
        bg_dark      = imgui.ImVec4(0.02, 0.02, 0.02, 0.98),
        bg_medium    = imgui.ImVec4(0.05, 0.05, 0.05, 0.95),
        accent_primary   = imgui.ImVec4(0.20, 0.60, 1.00, 1.00),
        accent_secondary = imgui.ImVec4(0.40, 0.70, 1.00, 1.00),
        accent_dark      = imgui.ImVec4(0.10, 0.40, 0.80, 1.00),
        accent_gradient  = imgui.ImVec4(0.30, 0.65, 1.00, 0.90),
        text_primary     = imgui.ImVec4(1.00, 1.00, 1.00, 1.00),
        text_secondary   = imgui.ImVec4(0.70, 0.70, 0.70, 1.00),
    },
    light = {
        bg_dark      = imgui.ImVec4(0.90, 0.90, 0.90, 0.98),
        bg_medium    = imgui.ImVec4(0.85, 0.85, 0.85, 0.95),
        accent_primary   = imgui.ImVec4(0.20, 0.60, 1.00, 1.00),
        accent_secondary = imgui.ImVec4(0.40, 0.70, 1.00, 1.00),
        accent_dark      = imgui.ImVec4(0.10, 0.40, 0.80, 1.00),
        accent_gradient  = imgui.ImVec4(0.30, 0.65, 1.00, 0.90),
        text_primary     = imgui.ImVec4(0.05, 0.05, 0.05, 1.00),
        text_secondary   = imgui.ImVec4(0.30, 0.30, 0.30, 1.00),
    },
    green = {
        bg_dark      = imgui.ImVec4(0.05, 0.10, 0.05, 0.98),
        bg_medium    = imgui.ImVec4(0.08, 0.13, 0.08, 0.95),
        accent_primary   = imgui.ImVec4(0.20, 0.80, 0.20, 1.00),
        accent_secondary = imgui.ImVec4(0.30, 0.90, 0.30, 1.00),
        accent_dark      = imgui.ImVec4(0.10, 0.60, 0.10, 1.00),
        accent_gradient  = imgui.ImVec4(0.25, 0.85, 0.25, 0.90),
        text_primary     = imgui.ImVec4(0.95, 0.95, 0.95, 1.00),
        text_secondary   = imgui.ImVec4(0.70, 0.70, 0.70, 1.00),
    },
    blue = {
        bg_dark      = imgui.ImVec4(0.05, 0.05, 0.15, 0.98),
        bg_medium    = imgui.ImVec4(0.08, 0.08, 0.18, 0.95),
        accent_primary   = imgui.ImVec4(0.30, 0.50, 1.00, 1.00),
        accent_secondary = imgui.ImVec4(0.40, 0.60, 1.00, 1.00),
        accent_dark      = imgui.ImVec4(0.20, 0.30, 0.80, 1.00),
        accent_gradient  = imgui.ImVec4(0.35, 0.55, 1.00, 0.90),
        text_primary     = imgui.ImVec4(0.98, 0.98, 0.98, 1.00),
        text_secondary   = imgui.ImVec4(0.70, 0.70, 0.70, 1.00),
    }
}

local function getActiveTheme()
    return colorThemes[settings.currentTheme] or colorThemes.default
end

    local theme = getActiveTheme()
        primary = theme.accent_primary,
        primary_dark = theme.accent_dark,
        primary_light = theme.accent_secondary,
        gradient = theme.accent_gradient,
        text = theme.text_primary
    local theme = getActiveTheme()
        imgui.PushStyleColor(imgui.Col.Text, theme.accent_primary)
        imgui.PushStyleColor(imgui.Col.Text, theme.accent_secondary)
        imgui.PushStyleColor(imgui.Col.Text, theme.accent_gradient)
    imgui.GetStyle().Colors[imgui.Col.Separator] = getActiveTheme().accent_gradient
local idCounter = 0
    idCounter = (idCounter + 1) % 0xFFFFFF
    return string.format("%x%x%x", os.time(), math.floor(os.clock() * 100000), idCounter)
end

local function normalizeBind(bind)
    if type(bind) ~= "table" then return nil end
    local normalized = {
        id = tostring(bind.id or generateId()),
        name = trimAll(tostring(bind.name or "")),
        cmd = trimAll(tostring(bind.cmd or "")):gsub("^/", ""),
        steps = type(bind.steps) == "table" and bind.steps or splitSteps(tostring(bind.steps or "")),
        delay = math.max(0, tonumber(bind.delay) or settings.defaultDelay),
        key = tonumber(bind.key) or 0,
        key_mod = tonumber(bind.key_mod) or 0,
    }
    return normalized
    local loaded = {}
    local usedIds = {}
                    for _, bind in ipairs(data) do
                        local normalized = normalizeBind(bind)
                        if normalized then
                            while usedIds[normalized.id] do
                                normalized.id = generateId()
                            end
                            usedIds[normalized.id] = true
                            table.insert(loaded, normalized)
                        end
                    binds = loaded
    else
    local normalizedBinds = {}
    for _, bind in ipairs(binds) do
        local normalized = normalizeBind(bind)
        if normalized then
            table.insert(normalizedBinds, normalized)
        end
    end
    binds = normalizedBinds
        buttonColor = colors.secondary
        hoverColor = colors.gradient
        activeColor = colors.primary_dark
    end
    local originalButton = imgui.GetStyle().Colors[imgui.Col.Button]
    local originalButtonHovered = imgui.GetStyle().Colors[imgui.Col.ButtonHovered]
    local originalButtonActive = imgui.GetStyle().Colors[imgui.Col.ButtonActive]
    local originalText = imgui.GetStyle().Colors[imgui.Col.Text]
    local originalFrameRounding = imgui.GetStyle().FrameRounding
    imgui.GetStyle().Colors[imgui.Col.Button] = buttonColor
    imgui.GetStyle().Colors[imgui.Col.ButtonHovered] = hoverColor
    imgui.GetStyle().Colors[imgui.Col.ButtonActive] = activeColor
    imgui.GetStyle().Colors[imgui.Col.Text] = colors.text
    imgui.GetStyle().FrameRounding = 10.0
    local originalFrameBorderSize = imgui.GetStyle().FrameBorderSize
    local originalBorderColor = imgui.GetStyle().Colors[imgui.Col.Border]
    imgui.GetStyle().FrameBorderSize = 1.0
    imgui.GetStyle().Colors[imgui.Col.Border] = imgui.ImVec4(0.0, 0.0, 0.0, 0.3)
    local result = false
    if width and height then
        result = imgui.Button(u8(label), imgui.ImVec2(width, height))
    else
        result = imgui.Button(u8(label))
    end
    imgui.GetStyle().Colors[imgui.Col.Button] = originalButton
    imgui.GetStyle().Colors[imgui.Col.ButtonHovered] = originalButtonHovered
    imgui.GetStyle().Colors[imgui.Col.ButtonActive] = originalButtonActive
    imgui.GetStyle().Colors[imgui.Col.Text] = originalText
    imgui.GetStyle().FrameRounding = originalFrameRounding
    imgui.GetStyle().FrameBorderSize = originalFrameBorderSize
    imgui.GetStyle().Colors[imgui.Col.Border] = originalBorderColor
    return result
end

function createStyledHeader(text, size)
    local originalTextColor = imgui.GetStyle().Colors[imgui.Col.Text]
    if size == "large" then
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.85, 0.18, 0.18, 1.00))
        imgui.TextWrapped(u8(text))
        imgui.PopStyleColor()
    elseif size == "medium" then
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.95, 0.30, 0.30, 1.00))
        imgui.TextWrapped(u8(text))
        imgui.PopStyleColor()
    else
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.95, 0.35, 0.35, 1.00))
        imgui.TextWrapped(u8(text))
        imgui.PopStyleColor()
    end
    imgui.GetStyle().Colors[imgui.Col.Text] = originalTextColor
end

function createStyledSeparator()
    local originalSeparatorColor = imgui.GetStyle().Colors[imgui.Col.Separator]
    imgui.GetStyle().Colors[imgui.Col.Separator] = imgui.ImVec4(0.85, 0.18, 0.18, 0.5)
    imgui.Separator()
    imgui.GetStyle().Colors[imgui.Col.Separator] = originalSeparatorColor
end

-- ==================== ÁÈÍÄÅÐ ====================
local binds = {}
local bindsConfigFile = configDirectory .. "/binds.json"

-- Ïåðåìåííûå èíòåðôåéñà
local searchBuf = ffi.new("char[64]")
local selectedBindIndex = nil
local editNameBuf = ffi.new("char[256]")
local editCmdBuf = ffi.new("char[64]")
local editStepsBuf = ffi.new("char[4096]")
local editDelayBuf = ffi.new("int[1]", 1500)
local editKeyBuf = ffi.new("int[1]", 0)
local editKeyModBuf = ffi.new("int[1]", 0)

-- Äëÿ îêíà âûáîðà êëàâèøè
local keyBindPopupActive = false
local tempKey = 0
local tempMod = 0
local waitingForKey = false

-- Èíäåêñ äëÿ áûñòðîãî ïîèñêà ïî êîìàíäå
local cmdToBind = {}
local keyToBind = {}  -- äëÿ ãîðÿ÷èõ êëàâèø
local registeredCommands = {} -- ñïèñîê çàðåãèñòðèðîâàííûõ êîìàíä

-- Ïîäòâåðæäåíèå óäàëåíèÿ
local deleteConfirmation = { active = false, index = nil }

function splitSteps(text)
    local steps = {}
    if text and text ~= "" then
        for line in text:gmatch("([^\r\n]+)") do
            line = line:gsub("^%s*(.-)%s*$", "%1")
            if line ~= "" then table.insert(steps, line) end
        end
    end
    return steps
end
function joinSteps(steps)
    return table.concat(steps, "\n")
end

local function generateId()
    return string.format("%x", os.time()*1000 + math.random(0,999))
end

function rebuildCommandIndex()
    cmdToBind = {}
    keyToBind = {}
    for _, bind in ipairs(binds) do
        if bind.cmd and bind.cmd ~= "" then
            local cmd = "/" .. bind.cmd:gsub("^/", "")
            cmdToBind[cmd:lower()] = bind
        end
        if bind.key and bind.key ~= 0 then
            keyToBind[bind.key] = keyToBind[bind.key] or {}
            table.insert(keyToBind[bind.key], {bind = bind, mod = bind.key_mod or 0})
        end
    end
end

function unregisterBindCommands()
    for _, cmd in ipairs(registeredCommands) do
        sampUnregisterChatCommand(cmd)
    end
    registeredCommands = {}
end

function registerBindCommands()
    unregisterBindCommands()
    for _, bind in ipairs(binds) do
        if bind.cmd and bind.cmd ~= "" then
            local cmd = bind.cmd  -- óæå áåç ñëåøà
            local success = sampRegisterChatCommand(cmd, function(args)
                if activeBinder then
                    sampAddChatMessage("[Snatch Helper] Áèíä óæå âûïîëíÿåòñÿ", 0xFF0000)
                    return
                end
                local argList = {}
                if args and args ~= "" then
                    for word in args:gmatch("%S+") do
                        table.insert(argList, word)
                    end
                end
                lua_thread.create(function() performBind(bind, argList) end)
            end)
            if success then
                table.insert(registeredCommands, cmd)
            end
        end
    end
end

function loadBinds()
    if doesFileExist(bindsConfigFile) then
        local file = io.open(bindsConfigFile, 'r')
        if file then
            local content = file:read('*a')
            file:close()
            if content and #content > 0 then
                local success, data = pcall(decodeJson, content)
                if success and type(data) == "table" then
                    binds = data
                    for _, bind in ipairs(binds) do
                        if not bind.id then bind.id = generateId() end
                        if not bind.delay then bind.delay = 1500 end
                        if not bind.key then bind.key = 0 end
                        if not bind.key_mod then bind.key_mod = 0 end
                    end
                    print("[Snatch Helper] Çàãðóæåíî áèíäîâ: " .. #binds)
                else
                    binds = {}
                end
            else
                binds = {}
            end
        else
            binds = {}
        end
    else
        binds = {}
    end
    rebuildCommandIndex()
    registerBindCommands()
end
function saveBinds()
    if not doesDirectoryExist(configDirectory) then createDirectory(configDirectory) end
    local file = io.open(bindsConfigFile, 'w')
    if file then
        local success, json = pcall(encodeJson, binds, {indent = true})
        if success then file:write(json) end
        file:close()
    end
    rebuildCommandIndex()
    registerBindCommands()
end

loadBinds()
-- Òàáëèöà ïðîñòûõ ïåðåìåííûõ {var}
local simpleVariables = {
    my_id = function() return select(2, sampGetPlayerIdByCharHandle(playerPed)) end,
    my_nick = function() return sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(playerPed))) end,
    my_rpnick = function() return string.gsub(sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(playerPed))), "_", " ") end,
    my_skin = function() return getCharModel(playerPed) end,
    my_X = function() return tostring(getCharCoordinates(playerPed)) end,
    my_Y = function() return tostring(select(2, getCharCoordinates(playerPed))) end,
    my_Z = function() return tostring(select(3, getCharCoordinates(playerPed))) end,
    my_armor = function() return sampGetPlayerArmor(select(2, sampGetPlayerIdByCharHandle(playerPed))) end,
    my_hp = function() return sampGetPlayerHealth(select(2, sampGetPlayerIdByCharHandle(playerPed))) end,
    my_lvl = function() return sampGetPlayerScore(select(2, sampGetPlayerIdByCharHandle(playerPed))) end,
    my_name = function()
        local nick = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(playerPed)))
        return nick:match("^(.-)_") or nick
    end,
    my_surname = function()
        local nick = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(playerPed)))
        return nick:match("_(.+)$") or ""
    end,
    my_fps = function() return math.floor(memory.getfloat(0xB7CB50, true)) end,
    city = function()
        local c = getCityPlayerIsIn(playerPed)
        if c == 1 then return "Los-Santos"
        elseif c == 2 then return "San-Fierro"
        elseif c == 3 then return "Las-Venturas"
        else return "San-Andreas" end
    end,
    time = function() return os.date("%H:%M:%S") end,
    data = function() return os.date("%d.%m.%Y") end,
    my_gun = function() return getCurrentCharWeapon(playerPed) end,
    my_gun_weapon = function() return getAmmoInCharWeapon(playerPed, getCurrentCharWeapon(playerPed)) end,
    car_id_nearest = function() return getClosestCarId() end,
    car_driverid_nearest = function()
        local id = getClosestCarId()
        if id then
            local car = sampGetCarHandleBySampVehicleId(id)
            if car then
                local driver = getDriverOfCar(car)
                if driver then
                    return select(2, sampGetPlayerIdByCharHandle(driver))
                end
            end
        end
        return "{car_driverid_nearest}"
    end,
    player_id_nearest = function() return getClosestPlayerId("simple") end,
    player_id_target = function()
        local target = select(2, getCharPlayerIsTargeting(playerHandle))
        if target then
            return select(2, sampGetPlayerIdByCharHandle(target))
        end
        return "{player_id_target}"
    end,
    player_nearest = function() return sampGetPlayerCount(true) - 1 end,
    car_nearest = function() return #getAllVehicles() end,
    my_car_speed = function()
        if isCharInAnyCar(playerPed) then return getCarSpeed(storeCarCharIsInNoSave(playerPed)) else return "{my_car_speed}" end
    end,
    my_car_model = function()
        if isCharInAnyCar(playerPed) then return getCarModel(storeCarCharIsInNoSave(playerPed)) else return "{my_car_model}" end
    end,
    my_car_color1 = function()
        if isCharInAnyCar(playerPed) then return getCarColours(storeCarCharIsInNoSave(playerPed)) else return "{my_car_color1}" end
    end,
    my_car_color2 = function()
        if isCharInAnyCar(playerPed) then return select(2, getCarColours(storeCarCharIsInNoSave(playerPed))) else return "{my_car_color2}" end
    end,
    my_car_hp = function()
        if isCharInAnyCar(playerPed) then return getCarHealth(storeCarCharIsInNoSave(playerPed)) else return "{my_car_hp}" end
    end,
    my_car_X = function()
        if isCharInAnyCar(playerPed) then return getCarCoordinates(storeCarCharIsInNoSave(playerPed)) else return "{my_car_X}" end
    end,
    my_car_Y = function()
        if isCharInAnyCar(playerPed) then return select(2, getCarCoordinates(storeCarCharIsInNoSave(playerPed))) else return "{my_car_Y}" end
    end,
    my_car_Z = function()
        if isCharInAnyCar(playerPed) then return select(3, getCarCoordinates(storeCarCharIsInNoSave(playerPed))) else return "{my_car_Z}" end
    end,
    my_car_name_model = function()
        if isCharInAnyCar(playerPed) then
            local model = getCarModel(storeCarCharIsInNoSave(playerPed))
            if model <= 611 then return getNameOfVehicleModel(model) end
        end
        return "{my_car_name_model}"
    end,
    my_car_id = function()
        if isCharInAnyCar(playerPed) then
            return select(2, sampGetVehicleIdByCarHandle(storeCarCharIsInNoSave(playerPed)))
        end
        return "{my_car_id}"
    end,
    square = function()
        local x, y = getCharCoordinates(playerPed)
        local sqX = math.floor((x + 3000) / 250) + 1
        local sqY = math.floor((y + 3000) / 250) + 1
        if sqX >= 1 and sqX <= 24 and sqY >= 1 and sqY <= 24 then
            return string.char(64 + sqX) .. "-" .. sqY
        end
        return "{square}"
    end,
    compass = function() return getCompassDirection() end
}

    local minDistSq = math.huge
        local carRaw, carHandle = sampGetCarHandleBySampVehicleId(i)
        local car = carHandle and carRaw and carHandle or carRaw
            local distSq = (xi-x)^2 + (yi-y)^2 + (zi-z)^2
            if distSq < minDistSq then
                minDistSq = distSq
    local minDistSq = math.huge
            local playerRaw, playerHandle = sampGetCharHandleBySampPlayerId(i)
            local handle = playerHandle and playerRaw and playerHandle or playerRaw
                    local distSq = (xi-x)^2 + (yi-y)^2 + (zi-z)^2
                    if distSq < minDistSq then
                        minDistSq = distSq
                        local distSq = (xi-x)^2 + (yi-y)^2 + (zi-z)^2
                        if distSq < minDistSq then
                            minDistSq = distSq
            end
        end
    end
    return closest
end

function getClosestPlayerId(mode, skin)
    local minDist = 9999
    local closest = -1
    local x, y, z = getCharCoordinates(playerPed)
    for i = 0, 1000 do
        if sampIsPlayerConnected(i) then
            local handle = sampGetCharHandleBySampPlayerId(i)
            if handle then
                if mode == "simple" then
                    local xi, yi, zi = getCharCoordinates(handle)
                    local dist = math.sqrt((xi-x)^2 + (yi-y)^2 + (zi-z)^2)
                    if dist < minDist then
                        minDist = dist
                        closest = i
                    end
                elseif mode == "skin" and skin then
                    if getCharModel(handle) == skin then
                        local xi, yi, zi = getCharCoordinates(handle)
                        local dist = math.sqrt((xi-x)^2 + (yi-y)^2 + (zi-z)^2)
                        if dist < minDist then
                            minDist = dist
                            closest = i
                        end
                    end
                end
            end
        end
    end
    return closest
end

function getCompassDirection()
    local angle = getCharHeading(playerPed)
    if angle >= 337.5 or angle < 22.5 then return "Ñ"
    elseif angle < 67.5 then return "ÑÂ"
    elseif angle < 112.5 then return "Â"
    elseif angle < 157.5 then return "ÞÂ"
    elseif angle < 202.5 then return "Þ"
    elseif angle < 247.5 then return "ÞÇ"
    elseif angle < 292.5 then return "Ç"
    elseif angle < 337.5 then return "ÑÇ"
    end
    return "?"
end

-- ==================== ÂÛÏÎËÍÅÍÈÅ ÁÈÍÄÀ (Ñ ÒÀÉÌÀÓÒÎÌ, ÊÝØÅÌ È ÎÑÒÀÍÎÂÊÎÉ) ====================
local MAX_BIND_DURATION = 30000 -- 30 ñåêóíä

function performBind(bind, args, targetId)
    if not bind or not bind.steps or #bind.steps == 0 then return end
    if activeBinder then
        sampAddChatMessage("[Snatch Helper] Áèíä óæå âûïîëíÿåòñÿ", 0xFF0000)
        return
    end
    activeBinder = true
    stopCurrentBind = false
    local delay = bind.delay or 1500
    local startTime = os.clock() * 1000

    local cache = {}
    local varNames = extractVariables(bind.steps)
    local subs = {}
    for i, var in ipairs(varNames) do
        if args and args[i] then
            subs[var] = args[i]
        elseif targetId and var == "targetid" then
            subs[var] = tostring(targetId)
        else
            subs[var] = "{" .. var .. "}"
        end
    end

    local function handleError(err)
        sampAddChatMessage("[Snatch Helper] Îøèáêà: " .. tostring(err), 0xFF0000)
        print("[Snatch Helper] Îøèáêà: " .. tostring(err))
        -- Ñáðàñûâàåì ôëàãè ïðè îøèáêå
        activeBinder = false
        stopCurrentBind = false
    end

    for _, step in ipairs(bind.steps) do
        if stopCurrentBind then
            break
        end
        if os.clock() * 1000 - startTime > MAX_BIND_DURATION then
            sampAddChatMessage("[Snatch Helper] Áèíä ïðåðâàí ïî òàéìàóòó", 0xFF0000)
            break
        end
        local pause = step:match("^%[(%d+)%]$")
        if pause then
            wait(tonumber(pause))
        else
            local processedStep = replaceVars(step, subs)
            processedStep = replaceFunctions(processedStep, cache)
            xpcall(function()
                sampSendChat(encoding.UTF8:decode(processedStep))
            end, handleError)
            wait(delay)
        end
    end
    activeBinder = false
    stopCurrentBind = false
end

function extractVariables(steps)
    local vars = {}
    local seen = {}
    for _, step in ipairs(steps) do
        for var in step:gmatch("%{([^}]+)%}") do
            if not seen[var] then
                seen[var] = true
                table.insert(vars, var)
            end
        end
    end
    return vars
end

function replaceVars(step, subs)
    local result = step
    for var, value in pairs(subs) do
        local escapedVar = var:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        result = result:gsub("{" .. escapedVar .. "}", tostring(value))
    end
    return result
end

function replaceFunctions(step, cache)
    local result = step
    -- çàìåíà ïðîñòûõ ïåðåìåííûõ {var}
    for varName, func in pairs(simpleVariables) do
        local pattern = "{" .. varName .. "}"
        if result:find(pattern) then
            local success, val = pcall(func)
            if success then
                result = result:gsub(pattern, tostring(val))
            else
                result = result:gsub(pattern, "{"..varName.."}")
            end
        end
    end
    return result
end
-- ==================== ÏÅÐÅÕÂÀÒ RPC (áîëüøå íå íóæåí äëÿ êîìàíä) ====================
function onSendRpc(id, bs)
    if id == 50 then
        local len = raknetBitStreamReadInt8(bs)
        local cmd = raknetBitStreamReadString(bs, len)
        local cmdLower = string.lower(cmd)
        if cmdLower == "/gw" or cmdLower == "/uk" then
            return true, id, bs
        end
    end
    return true, id, bs
end
addEventHandler("onSendRpc", onSendRpc)

-- ==================== ÑÈÑÒÅÌÀ ÑÅËÅÊÒÎÐÀ (PIE MENU) ====================
local menuContext = {
    c_iMaxPieMenuStack = 8,
    c_iMaxPieItemCount = 12,
    c_iRadiusEmpty = 30,
    c_iRadiusMin = 30,
    c_iMinItemCount = 3,
    c_iMinItemCountPerLevel = 3,
    m_oPieMenuStack = {},
    m_iCurrentIndex = -1,
    m_iLastFrame = 0,
    m_iMaxIndex = 0,
    m_oCenter = imgui.ImVec2(0, 0),
    m_iMouseButton = 0,
    m_bClose = false,
}
for i = 1, 8 do menuContext.m_oPieMenuStack[i] = { m_iCurrentIndex = 0, m_fMaxItemSqrDiameter = 0, m_iHoveredItem = 0, m_iLastHoveredItem = 0, m_iClickedItem = 0, m_oItemIsSubMenu = {}, m_oItemNames = {}, m_oItemSizes = {} } end

function BeginPiePopup(ctx, pName, iMouseButton)
    iMouseButton = iMouseButton or 0
    if imgui.IsPopupOpen(pName) then
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0,0,0,1))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0,0,0,1))
        imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 0.0)
        imgui.PushStyleVar(imgui.StyleVar.Alpha, 1.0)
        ctx.m_iMouseButton = iMouseButton
        ctx.m_bClose = false
        imgui.SetNextWindowPos(imgui.ImVec2(-100,-100), imgui.Cond.Appearing)
        imgui.SetNextWindowSize(imgui.ImVec2(0,0), imgui.Cond.Always)
        local bOpened = imgui.BeginPopupModal(pName, true, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove)
        if bOpened then
            local iCurrentFrame = imgui.GetFrameCount()
            if ctx.m_iLastFrame < (iCurrentFrame - 1) then
                ctx.m_oCenter = imgui.ImVec2(sizeX/2, sizeY/2)
            end
            ctx.m_iLastFrame = iCurrentFrame
            ctx.m_iMaxIndex = -1
            ctx.m_iCurrentIndex = ctx.m_iCurrentIndex + 1
            ctx.m_iMaxIndex = ctx.m_iMaxIndex + 1
            local oPieMenu = ctx.m_oPieMenuStack[ctx.m_iCurrentIndex]
            oPieMenu.m_iCurrentIndex = 0
            oPieMenu.m_fMaxItemSqrDiameter = 0
            if not imgui.IsMouseReleased(ctx.m_iMouseButton) then
                oPieMenu.m_iHoveredItem = -1
            end
            if ctx.m_iCurrentIndex > 0 then
                oPieMenu.m_fMaxItemSqrDiameter = ctx.m_oPieMenuStack[ctx.m_iCurrentIndex - 1].m_fMaxItemSqrDiameter
            end
            return true
        else
            imgui.EndPopup()
            imgui.PopStyleColor(2)
            imgui.PopStyleVar(2)
        end
    end
    return false
end

function PieMenuItem(ctx, pName)
    local oPieMenu = ctx.m_oPieMenuStack[ctx.m_iCurrentIndex]
    oPieMenu.m_oItemSizes[oPieMenu.m_iCurrentIndex] = imgui.CalcTextSize(pName, true)
    local fSqrDiameter = oPieMenu.m_oItemSizes[oPieMenu.m_iCurrentIndex].x^2 + oPieMenu.m_oItemSizes[oPieMenu.m_iCurrentIndex].y^2
    if fSqrDiameter > oPieMenu.m_fMaxItemSqrDiameter then
        oPieMenu.m_fMaxItemSqrDiameter = fSqrDiameter
    end
    oPieMenu.m_oItemIsSubMenu[oPieMenu.m_iCurrentIndex] = false
    oPieMenu.m_oItemNames[oPieMenu.m_iCurrentIndex] = pName
    local bActive = oPieMenu.m_iCurrentIndex == oPieMenu.m_iHoveredItem
    oPieMenu.m_iCurrentIndex = oPieMenu.m_iCurrentIndex + 1
    if bActive then ctx.m_bClose = true end
    return bActive
end

function EndPiePopup(ctx, title)
    local oPieMenu = ctx.m_oPieMenuStack[ctx.m_iCurrentIndex]
    ctx.m_iCurrentIndex = ctx.m_iCurrentIndex - 1
    local pDrawList = imgui.GetWindowDrawList()
    pDrawList:PushClipRectFullScreen()
    local oMousePos = imgui.GetIO().MousePos
    local oDragDelta = imgui.ImVec2(oMousePos.x - ctx.m_oCenter.x, oMousePos.y - ctx.m_oCenter.y)
    local fDragDistSqr = oDragDelta.x^2 + oDragDelta.y^2
    local fCurrentRadius = ctx.c_iRadiusEmpty
    local bItemHovered = false
    local c_fDefaultRotate = -math.pi / 2
    local fLastRotate = c_fDefaultRotate

    pDrawList:AddCircleFilled(imgui.ImVec2(ctx.m_oCenter.x, ctx.m_oCenter.y), 30, imgui.GetColorU32(imgui.ImVec4(0.2,0.2,0.2,0.9)), 25)
    pDrawList:AddText(imgui.ImVec2(ctx.m_oCenter.x - imgui.CalcTextSize(title).x/2, ctx.m_oCenter.y - 10), imgui.GetColorU32(imgui.ImVec4(1,1,1,1)), title)

    for iIndex = 0, ctx.m_iMaxIndex do
        local oPieMenu = ctx.m_oPieMenuStack[iIndex+1]
        local fMenuHeight = math.sqrt(oPieMenu.m_fMaxItemSqrDiameter)
        local fMaxRadius = fCurrentRadius + (fMenuHeight * oPieMenu.m_iCurrentIndex) / 2
        local item_arc_span = 2 * math.pi / math.max(ctx.c_iMinItemCount + ctx.c_iMinItemCountPerLevel * iIndex, oPieMenu.m_iCurrentIndex)
        local drag_angle = math.atan2(oDragDelta.y, oDragDelta.x)
        local fRotate = fLastRotate - item_arc_span * (oPieMenu.m_iCurrentIndex - 1) / 2
        local item_hovered = -1

        for item_n = 0, oPieMenu.m_iCurrentIndex - 1 do
            local item_label = oPieMenu.m_oItemNames[item_n+1]
            local inner_spacing = imgui.GetStyle().ItemInnerSpacing.x / fCurrentRadius / 2
            local fMinInnerSpacing = imgui.GetStyle().ItemInnerSpacing.x / (fCurrentRadius * 2)
            local fMaxInnerSpacing = imgui.GetStyle().ItemInnerSpacing.x / (fMaxRadius * 2)
            local item_inner_ang_min = item_arc_span * (item_n - 0.5 + fMinInnerSpacing) + fRotate
            local item_inner_ang_max = item_arc_span * (item_n + 0.5 - fMinInnerSpacing) + fRotate
            local item_outer_ang_min = item_arc_span * (item_n - 0.5 + fMaxInnerSpacing) + fRotate
            local item_outer_ang_max = item_arc_span * (item_n + 0.5 - fMaxInnerSpacing) + fRotate
            local hovered = false

            if fDragDistSqr >= fCurrentRadius^2 and fDragDistSqr < fMaxRadius^2 then
                while (drag_angle - item_inner_ang_min) < 0 do drag_angle = drag_angle + 2*math.pi end
                while (drag_angle - item_inner_ang_min) > 2*math.pi do drag_angle = drag_angle - 2*math.pi end
                if drag_angle >= item_inner_ang_min and drag_angle < item_inner_ang_max then
                    hovered = true
                    bItemHovered = not oPieMenu.m_oItemIsSubMenu[item_n+1]
                end
            end

            local iColor = imgui.GetColorU32(hovered and imgui.ImVec4(0.3,0.6,1,1) or imgui.ImVec4(0.2,0.2,0.2,0.8))
            local arc_segments = math.floor((32 * item_arc_span / (2*math.pi)) + 1)
            local fAngleStepInner = (item_inner_ang_max - item_inner_ang_min) / arc_segments
            local fAngleStepOuter = (item_outer_ang_max - item_outer_ang_min) / arc_segments

            pDrawList:PrimReserve(arc_segments * 6, (arc_segments + 1) * 2)
            for iSeg = 0, arc_segments do
                local fCosInner = math.cos(item_inner_ang_min + fAngleStepInner * iSeg)
                local fSinInner = math.sin(item_inner_ang_min + fAngleStepInner * iSeg)
                local fCosOuter = math.cos(item_outer_ang_min + fAngleStepOuter * iSeg)
                local fSinOuter = math.sin(item_outer_ang_min + fAngleStepOuter * iSeg)
                if iSeg < arc_segments then
                    local VtxCurrentIdx = pDrawList._VtxCurrentIdx
                    pDrawList:PrimWriteIdx(VtxCurrentIdx + 0)
                    pDrawList:PrimWriteIdx(VtxCurrentIdx + 2)
                    pDrawList:PrimWriteIdx(VtxCurrentIdx + 1)
                    pDrawList:PrimWriteIdx(VtxCurrentIdx + 3)
                    pDrawList:PrimWriteIdx(VtxCurrentIdx + 2)
                    pDrawList:PrimWriteIdx(VtxCurrentIdx + 1)
                end
                pDrawList:PrimWriteVtx(imgui.ImVec2(ctx.m_oCenter.x + fCosInner * (fCurrentRadius + imgui.GetStyle().ItemInnerSpacing.x), ctx.m_oCenter.y + fSinInner * (fCurrentRadius + imgui.GetStyle().ItemInnerSpacing.x)), imgui.ImVec2(0,0), iColor)
                pDrawList:PrimWriteVtx(imgui.ImVec2(ctx.m_oCenter.x + fCosOuter * (fMaxRadius - imgui.GetStyle().ItemInnerSpacing.x), ctx.m_oCenter.y + fSinOuter * (fMaxRadius - imgui.GetStyle().ItemInnerSpacing.x)), imgui.ImVec2(0,0), iColor)
            end

            local fRadCenter = (item_arc_span * item_n) + fRotate
            local oOuterCenter = imgui.ImVec2(ctx.m_oCenter.x + math.cos(fRadCenter) * fMaxRadius, ctx.m_oCenter.y + math.sin(fRadCenter) * fMaxRadius)
            pDrawList:AddText(imgui.ImVec2(ctx.m_oCenter.x + math.cos((item_inner_ang_min + item_inner_ang_max)*0.5) * (fCurrentRadius + fMaxRadius) * 0.5 - imgui.CalcTextSize(item_label).x * 0.5, ctx.m_oCenter.y + math.sin((item_inner_ang_min + item_inner_ang_max)*0.5) * (fCurrentRadius + fMaxRadius) * 0.5 - imgui.CalcTextSize(item_label).y * 0.5), imgui.GetColorU32(imgui.ImVec4(1,1,1,1)), item_label)

            if hovered then item_hovered = item_n end
        end

        oPieMenu.m_fLastMaxItemSqrDiameter = oPieMenu.m_fMaxItemSqrDiameter
        oPieMenu.m_iHoveredItem = item_hovered
        if fDragDistSqr >= fMaxRadius^2 then item_hovered = oPieMenu.m_iLastHoveredItem end
        oPieMenu.m_iLastHoveredItem = item_hovered
        fLastRotate = item_arc_span * oPieMenu.m_iLastHoveredItem + fRotate
        if item_hovered == -1 or not oPieMenu.m_oItemIsSubMenu[item_hovered+1] then break end
    end

    pDrawList:PopClipRect()
    if ctx.m_bClose or (not bItemHovered and imgui.IsMouseReleased(ctx.m_iMouseButton)) or not selectorActive then
        imgui.CloseCurrentPopup()
    end
    imgui.EndPopup()
    imgui.PopStyleColor(2)
    imgui.PopStyleVar(2)
end
-- ==================== ÑÒÈËÈ (ñ ó÷¸òîì òåìû) ====================
function setup_premium_style(themeName)
    local theme = colorThemes[themeName] or colorThemes.default
    local style = imgui.GetStyle()
    local colors = style.Colors

    style.WindowRounding = 12.0
    style.FrameRounding = 8.0
    style.GrabRounding = 8.0
    style.ScrollbarRounding = 10.0
    style.ChildRounding = 10.0
    style.PopupRounding = 10.0
    style.TabRounding = 8.0
    style.WindowPadding = imgui.ImVec2(18, 18)
    style.FramePadding = imgui.ImVec2(14, 10)
    style.ItemSpacing = imgui.ImVec2(10, 8)
    style.ItemInnerSpacing = imgui.ImVec2(6, 6)
    style.ScrollbarSize = 16
    style.GrabMinSize = 12
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.WindowBorderSize = 0.8
    style.ChildBorderSize = 0.8
    style.PopupBorderSize = 0.8
    style.FrameBorderSize = 0.5
    style.TabBorderSize = 0.5

    colors[imgui.Col.WindowBg] = theme.bg_dark
    colors[imgui.Col.ChildBg] = theme.bg_medium
    colors[imgui.Col.PopupBg] = imgui.ImVec4(0.09, 0.09, 0.09, 0.98)
    colors[imgui.Col.Border] = imgui.ImVec4(0.25, 0.25, 0.25, 0.50)
    colors[imgui.Col.BorderShadow] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[imgui.Col.TitleBg] = imgui.ImVec4(0.07, 0.07, 0.07, 1.00)
    colors[imgui.Col.TitleBgActive] = theme.accent_primary
    colors[imgui.Col.TitleBgCollapsed] = imgui.ImVec4(0.07, 0.07, 0.07, 0.75)
    colors[imgui.Col.Button] = imgui.ImVec4(0.20, 0.20, 0.20, 0.85)
    colors[imgui.Col.ButtonHovered] = theme.accent_gradient
    colors[imgui.Col.ButtonActive] = theme.accent_dark
    colors[imgui.Col.FrameBg] = imgui.ImVec4(0.15, 0.15, 0.15, 0.54)
    colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.22, 0.22, 0.22, 0.54)
    colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.28, 0.28, 0.28, 0.54)
    colors[imgui.Col.Text] = theme.text_primary
    colors[imgui.Col.TextDisabled] = theme.text_secondary
    colors[imgui.Col.Header] = imgui.ImVec4(0.25, 0.10, 0.10, 0.31)
    colors[imgui.Col.HeaderHovered] = imgui.ImVec4(0.35, 0.15, 0.15, 0.51)
    colors[imgui.Col.HeaderActive] = imgui.ImVec4(0.45, 0.20, 0.20, 0.71)
    colors[imgui.Col.Separator] = imgui.ImVec4(0.30, 0.30, 0.30, 0.50)
    colors[imgui.Col.SeparatorHovered] = theme.accent_secondary
    colors[imgui.Col.SeparatorActive] = theme.accent_primary
    colors[imgui.Col.ScrollbarBg] = imgui.ImVec4(0.05, 0.05, 0.05, 0.53)
    colors[imgui.Col.ScrollbarGrab] = imgui.ImVec4(0.30, 0.30, 0.30, 1.00)
    colors[imgui.Col.ScrollbarGrabHovered] = imgui.ImVec4(0.40, 0.40, 0.40, 1.00)
    colors[imgui.Col.ScrollbarGrabActive] = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[imgui.Col.Tab] = imgui.ImVec4(0.15, 0.15, 0.15, 0.86)
    colors[imgui.Col.TabHovered] = theme.accent_gradient
    colors[imgui.Col.TabActive] = theme.accent_primary
    colors[imgui.Col.TabUnfocused] = imgui.ImVec4(0.15, 0.15, 0.15, 0.97)
    colors[imgui.Col.TabUnfocusedActive] = imgui.ImVec4(0.25, 0.15, 0.15, 1.00)
    colors[imgui.Col.PlotLines] = theme.accent_secondary
    colors[imgui.Col.PlotLinesHovered] = theme.accent_primary
    colors[imgui.Col.PlotHistogram] = theme.accent_gradient
    colors[imgui.Col.PlotHistogramHovered] = theme.accent_primary
    colors[imgui.Col.TextSelectedBg] = imgui.ImVec4(0.85, 0.18, 0.18, 0.35)
    colors[imgui.Col.DragDropTarget] = imgui.ImVec4(0.95, 0.30, 0.30, 0.90)
    colors[imgui.Col.NavHighlight] = theme.accent_secondary
    colors[imgui.Col.NavWindowingHighlight] = imgui.ImVec4(0.95, 0.30, 0.30, 0.70)
    colors[imgui.Col.NavWindowingDimBg] = imgui.ImVec4(0.80, 0.80, 0.80, 0.20)
end

-- ==================== ÒÀÁËÈÖÀ ÈÌ¨Í ÊËÀÂÈØ ====================
local keyNames = {
    [0x01] = 'Left Mouse', [0x02] = 'Right Mouse', [0x04] = 'Middle Mouse',
    [0x08] = 'Backspace', [0x09] = 'Tab', [0x0D] = 'Enter', [0x10] = 'Shift',
    [0x11] = 'Ctrl', [0x12] = 'Alt', [0x1B] = 'Esc', [0x20] = 'Space',
    [0x21] = 'Page Up', [0x22] = 'Page Down', [0x23] = 'End', [0x24] = 'Home',
    [0x25] = 'Left', [0x26] = 'Up', [0x27] = 'Right', [0x28] = 'Down',
    [0x2D] = 'Insert', [0x2E] = 'Delete',
    [0x30] = '0', [0x31] = '1', [0x32] = '2', [0x33] = '3', [0x34] = '4',
    [0x35] = '5', [0x36] = '6', [0x37] = '7', [0x38] = '8', [0x39] = '9',
    [0x41] = 'A', [0x42] = 'B', [0x43] = 'C', [0x44] = 'D', [0x45] = 'E',
    [0x46] = 'F', [0x47] = 'G', [0x48] = 'H', [0x49] = 'I', [0x4A] = 'J',
    [0x4B] = 'K', [0x4C] = 'L', [0x4D] = 'M', [0x4E] = 'N', [0x4F] = 'O',
    [0x50] = 'P', [0x51] = 'Q', [0x52] = 'R', [0x53] = 'S', [0x54] = 'T',
    [0x55] = 'U', [0x56] = 'V', [0x57] = 'W', [0x58] = 'X', [0x59] = 'Y',
    [0x5A] = 'Z',
    [0x70] = 'F1', [0x71] = 'F2', [0x72] = 'F3', [0x73] = 'F4', [0x74] = 'F5',
    [0x75] = 'F6', [0x76] = 'F7', [0x77] = 'F8', [0x78] = 'F9', [0x79] = 'F10',
    [0x7A] = 'F11', [0x7B] = 'F12',
}

function getKeyName(key, mod)
-- ====================    ====================
    return modText .. (keyNames[key] or "["..key.."]")
end

-- ==================== ÎÊÍÎ ÂÛÁÎÐÀ ÊËÀÂÈØÈ ====================
local keyBindPopupActive = false
local tempKey = 0
local tempMod = 0
local waitingForKey = false

imgui.OnFrame(
    function() return keyBindPopupActive end,
    function()
        imgui.SetNextWindowSize(imgui.ImVec2(300, 120), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.Begin(u8("Âûáîð ãîðÿ÷åé êëàâèøè"), imgui.new.bool(true), imgui.WindowFlags.NoCollapse)

        if waitingForKey then
            imgui.Text(u8("Íàæìèòå ëþáóþ êîìáèíàöèþ êëàâèø...\n(ESC äëÿ îòìåíû)"))
            -- Ñíà÷àëà ïðîâåðÿåì ESC äëÿ îòìåíû
            if wasKeyPressed(0x1B) then
                waitingForKey = false
            else
                -- Ñïèñîê îáû÷íûõ êëàâèø (èñêëþ÷àåì ìîäèôèêàòîðû Ctrl, Shift, Alt)
                local keys = {
                    0x01,0x02,0x04,0x08,0x09,0x0D,0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x2D,0x2E,
                    0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x41,0x42,0x43,0x44,0x45,0x46,0x47,
                    0x48,0x49,0x4A,0x4B,0x4C,0x4D,0x4E,0x4F,0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,
                    0x59,0x5A,0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B
                }
                for _, vkey in ipairs(keys) do
                    if wasKeyPressed(vkey) then
                        -- îïðåäåëèì ìîäèôèêàòîðû íà ìîìåíò íàæàòèÿ (ïðèîðèòåò: Ctrl > Shift > Alt)
                        local mod = 0
                        if isKeyDown(0x11) then mod = 1
                        elseif isKeyDown(0x10) then mod = 2
                        elseif isKeyDown(0x12) then mod = 3 end
                        tempKey = vkey
                        tempMod = mod
                        waitingForKey = false
                        break
                    end
                end
            end
        else
            imgui.Text(u8("Òåêóùàÿ êîìáèíàöèÿ: " .. getKeyName(tempKey, tempMod)))
            imgui.Spacing()
            if imgui.Button(u8("Èçìåíèòü"), imgui.ImVec2(100,0)) then
                waitingForKey = true
            end
            imgui.SameLine()
            if imgui.Button(u8("Ñáðîñèòü"), imgui.ImVec2(100,0)) then
                tempKey = 0
                tempMod = 0
            end
        end

        imgui.Separator()
        if imgui.Button(u8("OK"), imgui.ImVec2(100,0)) then
            -- ñîõðàíÿåì â çàâèñèìîñòè îò êîíòåêñòà
            if keyBindContext == "bind" then
                editKeyBuf[0] = tempKey
                editKeyModBuf[0] = tempMod
            elseif keyBindContext == "stop" then
                settings.stopKey = tempKey
                settings.stopKeyMod = tempMod
                saveSettings()
            elseif keyBindContext == "selector" then
                settings.selectorKey = tempKey
                settings.selectorKeyMod = tempMod
                saveSettings()
            end
            keyBindPopupActive = false
            keyBindContext = nil
        end
        imgui.SameLine()
        if imgui.Button(u8("Îòìåíà"), imgui.ImVec2(100,0)) then
            keyBindPopupActive = false
            keyBindContext = nil
        end

        imgui.End()
    end
)

-- ==================== ÃËÀÂÍÎÅ ÌÅÍÞ ====================
local activeTab = new.int(0)
local showMenu = {}
local showEasterEgg = new.bool(false)
for i=1,12 do showMenu[i] = new.bool(false) end
local easterEggTexture = nil


imgui.OnFrame(
    function() return mainWindow.alpha > 0 end,
    function()
        if imgui.PushStyleVar then
            imgui.PushStyleVar(imgui.StyleVar.Alpha, mainWindow.alpha)
        elseif imgui.PushStyleVarFloat then
            imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, mainWindow.alpha)
        end

        imgui.SetNextWindowPos(imgui.ImVec2(sizeX / 2, sizeY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(900, 650), imgui.Cond.FirstUseEver)
        local flags = imgui.WindowFlags.NoCollapse
        if mainWindow.alpha < 1 then flags = flags + imgui.WindowFlags.NoInputs end
        imgui.Begin(u8("Snatch Helper"), mainWindowOpen, flags)

        -- ñèíõðîíèçàöèÿ çàêðûòèÿ ïî êðåñòèêó
        if not mainWindowOpen[0] and mainWindow.state then
            mainWindow.switch2()
        end

        if imgui.BeginTabBar("MainTabs", 0) then
            if imgui.BeginTabItem(u8("Ñïðàâî÷íèê")) then
                activeTab[0] = 0
                renderReferenceTab()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem(u8("Áèíäåð")) then
                activeTab[0] = 1
                renderBinderTab()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem(u8("Íàñòðîéêè")) then
                activeTab[0] = 2
                renderSettingsTab()
                imgui.EndTabItem()
            end
            imgui.EndTabBar()
        end
        imgui.End()

        if imgui.PopStyleVar then
            imgui.PopStyleVar()
        elseif imgui.PopStyleVar then
            imgui.PopStyleVar()
        end
    end
)

function renderReferenceTab()
    createStyledHeader("Ñïðàâî÷íèê ïðîöåññóàëüíûõ äåéñòâèé", "large")
    imgui.SameLine()
    imgui.SetCursorPosX(imgui.GetCursorPosX() + 10)
    imgui.TextColored(imgui.ImVec4(0.85, 0.65, 0.65, 1.00), u8("v5.2"))
    imgui.Spacing()
    createStyledSeparator()
    imgui.Spacing()
    imgui.TextColored(imgui.ImVec4(0.70, 0.70, 0.70, 1.00), u8("Âûáåðèòå ðàçäåë äëÿ èçó÷åíèÿ:"))
    imgui.Spacing()
    imgui.Spacing()
    local menuButtons = {
        {text = "Îñíîâàíèÿ çàäåðæàíèÿ"},
        {text = "Ïîðÿäîê çàäåðæàíèÿ"}, 
        {text = "Îñíîâàíèÿ àðåñòà"},
        {text = "Ïîðÿäîê àðåñòà"},
        {text = "Ïîðÿäîê àðåñòà ãîñ. ñîòðóäíèêà"},
        {text = "Îñíîâàíèÿ äîïðîñà"},
        {text = "Ïîðÿäîê ïðîâåäåíèÿ äîïðîñà"},
        {text = "Àäâîêàò íà äîïðîñå"},
        {text = "Îñíîâàíèÿ äëÿ îáûñêà"},
        {text = "Îñíîâàíèÿ äëÿ ðåéäîâ"},
        {text = "Îñíîâàíèÿ ïðàâèë áåçîïàñíîñòè"},
        {text = "Ïàñõàëêà"}
    }
    for i, buttonData in ipairs(menuButtons) do
        local buttonText = buttonData.text
        if createStyledButton(buttonText, -1, 42) then
            if i == 12 then
                showEasterEgg[0] = true
            else
                showMenu[i][0] = true
            end
        end
        imgui.Spacing()
    end
    imgui.Spacing()
    imgui.BeginChild("StatusBar", imgui.ImVec2(0, 40), false)
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.12, 0.12, 0.12, 0.9))
    imgui.SetCursorPosY(imgui.GetCursorPosY() + 10)
    imgui.TextColored(imgui.ImVec4(0.85, 0.65, 0.65, 1.00), u8("Ñòàòóñ:"))
    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.30, 0.95, 0.30, 1.00))
    imgui.Text(u8("Àêòèâåí"))
    imgui.PopStyleColor()
    imgui.SameLine()
    imgui.SetCursorPosX(imgui.GetWindowWidth() - 120)
    imgui.TextColored(imgui.ImVec4(0.60, 0.60, 0.60, 1.00), u8("Snatch Helper"))
    imgui.PopStyleColor()
    imgui.EndChild()
end

function renderBinderTab()
    -- Ïîëó÷àåì äîñòóïíîå ïðîñòðàíñòâî âíóòðè âêëàäêè
    local avail = imgui.GetContentRegionAvail()
    -- Ëåâàÿ ïàíåëü: ìèíèìóì 200 ïèêñåëåé, èíà÷å 30% îò øèðèíû
    local listWidth = math.max(avail.x * 0.3, 200)
    -- Ïðàâàÿ ïàíåëü: îñòàòîê ìèíóñ îòñòóï ìåæäó ïàíåëÿìè
    local editorWidth = avail.x - listWidth - imgui.GetStyle().ItemSpacing.x

    -- Ëåâàÿ ïàíåëü (ñïèñîê)
    imgui.BeginChild("BindsListPanel", imgui.ImVec2(listWidth, -1), true)
    

    
    imgui.Text(u8("Ïîèñê:"))
    imgui.InputText("##search", searchBuf, 64)
    imgui.Separator()
    imgui.Spacing()
    if createStyledButton("+ Íîâûé", -1, 30, true) then
        selectedBindIndex = nil
        ffi.copy(editNameBuf, "")
        ffi.copy(editCmdBuf, "")
        ffi.copy(editStepsBuf, "")
        editDelayBuf[0] = settings.defaultDelay
        editKeyBuf[0] = 0
        editKeyModBuf[0] = 0
    end
    imgui.Spacing()
    
    local searchText = ffi.string(searchBuf):lower()
    local filteredIndices = {}
    for i, bind in ipairs(binds) do
        if searchText == "" or 
           (bind.name and bind.name:lower():find(searchText, 1, true)) or
           (bind.cmd and bind.cmd:lower():find(searchText, 1, true)) then
            table.insert(filteredIndices, i)
        end
    end
    
    if #filteredIndices == 0 then
        imgui.TextColored(imgui.ImVec4(0.70, 0.70, 0.70, 1.00), u8("Íåò áèíäîâ"))
    else
        -- Âíóòðåííèé child äëÿ ïðîêðóòêè ñïèñêà
        imgui.BeginChild("ScrollingBinds", imgui.ImVec2(0, 0), false)
        for _, idx in ipairs(filteredIndices) do
            local bind = binds[idx]
            local isSelected = (selectedBindIndex == idx)
            if isSelected then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.85, 0.18, 0.18, 0.6))
            else
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.2, 0.2, 0.6))
            end
            if imgui.Button(bind.name or "Áåç íàçâàíèÿ", imgui.ImVec2(-1, 30)) then
                selectedBindIndex = idx
                ffi.copy(editNameBuf, bind.name or "")
                if bind.cmd and bind.cmd ~= "" then
                    ffi.copy(editCmdBuf, "/" .. bind.cmd)
                else
                    ffi.copy(editCmdBuf, "")
                end
                ffi.copy(editStepsBuf, joinSteps(bind.steps or {}))
                editDelayBuf[0] = bind.delay or settings.defaultDelay
                editKeyBuf[0] = bind.key or 0
                editKeyModBuf[0] = bind.key_mod or 0
            end
            imgui.PopStyleColor()
            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                imgui.Text(u8("Êîìàíäà: " .. (bind.cmd and "/"..bind.cmd or "íåò")))
                imgui.Text(u8("Øàãîâ: " .. #(bind.steps or {})))
                if bind.key and bind.key ~= 0 then
                    imgui.Text(u8("Êëàâèøà: " .. getKeyName(bind.key, bind.key_mod)))
                end
                imgui.EndTooltip()
            end
        end
        imgui.EndChild()
    end
    
    imgui.EndChild() -- çàêðûâàåì ëåâóþ ïàíåëü

    -- Ðàçìåùàåì ñëåäóþùóþ ïàíåëü ðÿäîì
    imgui.SameLine()

    -- Ïðàâàÿ ïàíåëü (ðåäàêòîð)
    imgui.BeginChild("BindEditorPanel", imgui.ImVec2(editorWidth, -1), true)
    
    if selectedBindIndex then
        imgui.Text(u8("Ðåäàêòèðîâàíèå áèíäà"))
    else
        imgui.Text(u8("Ñîçäàíèå íîâîãî áèíäà"))
    end
    imgui.Separator()
    imgui.Spacing()
    imgui.Text(u8("Íàçâàíèå:"))
    imgui.InputText("##editname", editNameBuf, 256)
    imgui.Spacing()
    imgui.Text(u8("Êîìàíäà (ñ /):"))
    imgui.InputText("##editcmd", editCmdBuf, 64)
    imgui.Spacing()
    imgui.Text(u8("Ãîðÿ÷àÿ êëàâèøà:"))
    local keyLabel = getKeyName(editKeyBuf[0], editKeyModBuf[0])
    if imgui.Button(u8(keyLabel), imgui.ImVec2(200, 0)) then
        tempKey = editKeyBuf[0]
        tempMod = editKeyModBuf[0]
        waitingForKey = true
        keyBindContext = "bind"
        keyBindPopupActive = true
    end
    imgui.Spacing()
    imgui.Text(u8("Çàäåðæêà ìåæäó øàãàìè (ìñ):"))
    imgui.InputInt("##editdelay", editDelayBuf, 100, 500)
    if editDelayBuf[0] < 100 then editDelayBuf[0] = 100 end
    imgui.Spacing()
    imgui.Text(u8("Øàãè (êàæäàÿ ñòðîêà - îòäåëüíîå äåéñòâèå):"))
    imgui.TextWrapped(u8("Èñïîëüçóéòå {èìÿ} äëÿ ïîäñòàíîâêè àðãóìåíòîâ, [÷èñëî] äëÿ ïàóçû."))
    imgui.InputTextMultiline("##editsteps", editStepsBuf, 4096, imgui.ImVec2(-1, 200), imgui.InputTextFlags.None)
    imgui.Spacing()
    if createStyledButton("Ñîõðàíèòü", 100, 32, true) then
        local name = ffi.string(editNameBuf):gsub("^%s*(.-)%s*$", "%1")
        local cmdRaw = ffi.string(editCmdBuf):gsub("^%s*(.-)%s*$", "%1")
        local cmd = cmdRaw:match("^/(%S+)") or cmdRaw:match("^(%S+)") or ""
        local stepsText = ffi.string(editStepsBuf)
        local delay = editDelayBuf[0]
        if name ~= "" and stepsText ~= "" then
            local newBind = {
                id = (selectedBindIndex and binds[selectedBindIndex].id) or generateId(),
                name = name,
                cmd = cmd,
                steps = splitSteps(stepsText),
                delay = delay,
                key = editKeyBuf[0],
                key_mod = editKeyModBuf[0]
            }
            if selectedBindIndex then
                binds[selectedBindIndex] = newBind
            else
                table.insert(binds, newBind)
                selectedBindIndex = #binds
            end
            saveBinds()
            sampAddChatMessage("[Snatch Helper] Áèíä ñîõðàíåí", 0x00FF00)
        else
            sampAddChatMessage("[Snatch Helper] Çàïîëíèòå íàçâàíèå è øàãè!", 0xFF0000)
        end
    end
    imgui.SameLine()
    if createStyledButton("Âûïîëíèòü", 100, 32) then
        local stepsText = ffi.string(editStepsBuf)
        if stepsText ~= "" then
            local testBind = {
                name = ffi.string(editNameBuf),
                cmd = ffi.string(editCmdBuf),
                steps = splitSteps(stepsText),
                delay = editDelayBuf[0],
                key = editKeyBuf[0],
                key_mod = editKeyModBuf[0]
            }
            lua_thread.create(function() performBind(testBind, {}) end)
        end
    end
    imgui.SameLine()
    if selectedBindIndex and createStyledButton("Óäàëèòü", 100, 32) then
        deleteConfirmation.active = true
        deleteConfirmation.index = selectedBindIndex
    end

    -- Îêíî ïîäòâåðæäåíèÿ óäàëåíèÿ
    if deleteConfirmation.active then
        imgui.OpenPopup(u8("Ïîäòâåðæäåíèå óäàëåíèÿ"))
    end
    if imgui.BeginPopupModal(u8("Ïîäòâåðæäåíèå óäàëåíèÿ"), nil, imgui.WindowFlags.AlwaysAutoResize) then
        imgui.Text(u8("Âû óâåðåíû, ÷òî õîòèòå óäàëèòü ýòîò áèíä?"))
        imgui.Separator()
        if imgui.Button(u8("Äà"), imgui.ImVec2(80,0)) then
            if deleteConfirmation.index then
                table.remove(binds, deleteConfirmation.index)
                if selectedBindIndex == deleteConfirmation.index then
                    selectedBindIndex = nil
                    ffi.copy(editNameBuf, "")
                    ffi.copy(editCmdBuf, "")
                    ffi.copy(editStepsBuf, "")
                    editDelayBuf[0] = settings.defaultDelay
                    editKeyBuf[0] = 0
                    editKeyModBuf[0] = 0
                end
                saveBinds()
                sampAddChatMessage("[Snatch Helper] Áèíä óäàëåí", 0x00FF00)
            end
            deleteConfirmation.active = false
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button(u8("Íåò"), imgui.ImVec2(80,0)) then
            deleteConfirmation.active = false
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end

    imgui.EndChild() -- çàêðûâàåì ïðàâóþ ïàíåëü
end

function renderSettingsTab()
    createStyledHeader("Íàñòðîéêè èíòåðôåéñà", "large")
    imgui.Spacing()
    createStyledSeparator()
    imgui.Spacing()
    local changed = false

    -- Çàäåðæêà ïî óìîë÷àíèþ
    imgui.Text(u8("Çàäåðæêà ïî óìîë÷àíèþ äëÿ íîâûõ áèíäîâ (ìñ):"))
    local defaultDelayVal = imgui.new.int(settings.defaultDelay)
    if imgui.InputInt("##defaultDelay", defaultDelayVal, 100, 500) then
        settings.defaultDelay = defaultDelayVal[0]
        if settings.defaultDelay < 100 then settings.defaultDelay = 100 end
        changed = true
    end
    imgui.Spacing()

    -- Öâåòîâàÿ òåìà
    imgui.Text(u8("Öâåòîâàÿ òåìà:"))
    local themeIndex = imgui.new.int(0)
    if settings.currentTheme == "dark" then themeIndex[0] = 1
    elseif settings.currentTheme == "light" then themeIndex[0] = 2
    elseif settings.currentTheme == "green" then themeIndex[0] = 3
    elseif settings.currentTheme == "blue" then themeIndex[0] = 4
    else themeIndex[0] = 0 end
    local themeNames = {u8"Ïî óìîë÷àíèþ", u8"Ò¸ìíàÿ", u8"Ñâåòëàÿ", u8"Çåë¸íàÿ", u8"Ñèíÿÿ"}
    local themeItems = ffi.new("const char*[?]", #themeNames)
    for i = 1, #themeNames do
        themeItems[i-1] = themeNames[i]
    end
    if imgui.Combo("##theme", themeIndex, themeItems, #themeNames) then
        if themeIndex[0] == 0 then settings.currentTheme = "default"
        elseif themeIndex[0] == 1 then settings.currentTheme = "dark"
        elseif themeIndex[0] == 2 then settings.currentTheme = "light"
        elseif themeIndex[0] == 3 then settings.currentTheme = "green"
        elseif themeIndex[0] == 4 then settings.currentTheme = "blue" end
        setup_premium_style(settings.currentTheme)
        changed = true
    end
    imgui.Spacing()

    -- Êëàâèøà îñòàíîâêè áèíäà
    imgui.Text(u8("Êëàâèøà îñòàíîâêè áèíäà (ïî óìîë÷àíèþ F12):"))
    local stopKeyLabel = getKeyName(settings.stopKey, settings.stopKeyMod)
    if imgui.Button(u8(stopKeyLabel), imgui.ImVec2(200, 0)) then
        tempKey = settings.stopKey
        tempMod = settings.stopKeyMod
        waitingForKey = true
        keyBindContext = "stop"
        keyBindPopupActive = true
    end
    imgui.Spacing()

    -- Êëàâèøà ñåëåêòîðà èãðîêà
    imgui.Text(u8("Êëàâèøà ñåëåêòîðà èãðîêà (ïî óìîë÷àíèþ Alt):"))
    local selKeyLabel = getKeyName(settings.selectorKey, settings.selectorKeyMod)
    if imgui.Button(u8(selKeyLabel), imgui.ImVec2(200, 0)) then
        tempKey = settings.selectorKey
        tempMod = settings.selectorKeyMod
        waitingForKey = true
        keyBindContext = "selector"
        keyBindPopupActive = true
    end
    imgui.Spacing()

    if changed then saveSettings() end
end


-- Îêíà ñïðàâî÷íèêà (ïðåæíèå)
local menuData = {
    [1] = { title = "Îñíîâàíèÿ çàäåðæàíèÿ", content = [[Êàê íàçûâàòü: Çàäåðæàíû íà îñíîâàíèè ïóíêòà X, ñòàòüè 1, ðàçäåëà 2, ÷àñòè 1 Ïðîöåññóàëüíîãî Êîäåêñà.\nËèáî ñëîâàìè, ïðèìåð: Çàäåðæàíû â ñâÿçè ñ íàðóøåíèåì óñòàâà ÌÞ.\n\nA. Ñîâåðøåíèå ãðàæäàíèíîì äîðîæíîãî èëè óãîëîâíîãî ïðîñòóïêà\nB. Íàõîæäåíèå ãðàæäàíèíà â ìàñêå, ñêðûâàþùåé ëèöî\nC. Ãðàæäàíèí âåä¸ò ñåáÿ ïîäîçðèòåëüíî, âûçûâàþùå, àãðåññèâíî\nD. Èìååòñÿ ïðåäïîëîæåíèå, ÷òî ëèöî íàõîäèòñÿ ïîä àëêîãîëåì èëè íàðêîòèêàìè\nE. Ïðîâåäåíèå ïðîâåðêè äîêóìåíòîâ ãðàæäàíèíà\nF. Ãðàæäàíèí ïåðåñåêàåò îðãàíèçîâàííûå áëîêïîñòû\nG. Ãðàæäàíèí íàõîäèòñÿ ïîáëèçîñòè îò ìåñòà ïðåñòóïëåíèÿ è ìîã áûòü ñâèäåòåëåì\nH. Íàðóøåíèå óñòàâà èëè ÔÏ îò ãîñíèêà\nI. Â ïåðèîä ââåäåíèÿ âîåííîãî ïîëîæåíèÿ]] },
    [2] = { title = "Ïîðÿäîê çàäåðæàíèÿ", content = [[1) Èäåíòèôèöèðîâàòü ñåáÿ, ïîêàçàòü êñèâó ïî òðåáîâàíèþ\n2) Ïðîâåñòè íåîáõîäèìûå äåéñòâèÿ â çàâèñèìîñòè îò ñèòóàöèè:\n   - Çàòðåáîâàòü äîêóìåíòû\n   - Ïðîâåñòè îïðîñ\n   - Îáûñê ïðè íàëè÷èè îñíîâàíèé\n   - Ïîòðåáîâàòü ïîêèíóòü ÒÑ\n   - Ïîòðåáîâàòü ïåðåìåñòèòüñÿ\n   - Íàäåòü íàðó÷íèêè, íî ïîñëå ñíÿòü\n   - Ïðîâåñòè àðåñò ïðè íàëè÷èè îñíîâàíèé]] },
    [3] = { title = "Îñíîâàíèÿ àðåñòà", content = [[Àðåñòîâàíû íà îñíîâàíèè ïóíêòà X, ñòàòüè 3, ðàçäåëà 2, ÷àñòè 1 Ïðîöåññóàëüíîãî Êîäåêñà.\n\nA. Ëèöî çàñòèãíóòî íà ìåñòå ñîâåðøåíèÿ äîðîæíîãî èëè óãîëîâíîãî ïðåñòóïëåíèÿ\nB. Â ñëó÷àå åñëè ïðåñòóïíèê ñêðûëñÿ - åãî ìîæíî àðåñòîâàòü â òå÷åíèè 12 ÷àñîâ áåç ÊÔ\nC. Ëèöî íàõîäèòñÿ â ôåäåðàëüíîì ðîçûñêå\nD. Íà àðåñòîâûâàåìîãî èìååòñÿ äåéñòâóþùèé îðäåð íà àðåñò\nE. Ïðîâåäåíèå ïðîâåðêè äîêóìåíòîâ ãðàæäàíèíà\nF. Èãíîðèðîâàíèå â òå÷åíèè 24 ÷àñîâ òðåáîâàíèÿ î ÿâêå íà äîïðîñ\nG. Òðàíñïîðòèðîâêà íà äîïðîñ]] },
    [4] = { title = "Ïîðÿäîê àðåñòà", content = [[1) Íàäåòü íàðó÷íèêè\n2) Èäåíòèôèöèðîâàòü ñåáÿ è ïîêàçàòü êñèâó ïðè çàïðîñå, åñëè ýòîãî íå ñäåëàëè ðàíüøå\n3) Ñîîáùèòü îñíîâàíèÿ äëÿ àðåñòà. ÂÀÆÍÎ: Ïðè àðåñòå ïî ÓÊ/ÄÊ - íàçâàòü ñòàòüþ (íîìåð èëè íàçâàíèå)\n4) Óçíàòü â ðàìêàõ ÐÏ ëè÷íîñòü àðåñòîâàííîãî, åñëè íå óçíàëè ðàíåå.\n5) Îáûñê\n6) Ìèðàíäà\n7) Âûäà÷à ðîçûñêà, åñëè íå âûäàëè ðàíåå\n8) Òðàíñïîðòèðîâêà â ÊÏÇ èëè äîïðîñíóþ\n9) Ïîñàäêà â ÊÏÇ ïðè íåîáõîäèìîñòè\n\nÈÑÊËÞ×ÅÍÈÅ: Â ñëó÷àå îïàñíîñòè, ìîæíî ñíà÷àëà ïåðåâåñòè è òîëüêî ïîòîì íà÷àòü ñ ïóíêòà 2.\nÈÑÊËÞ×ÅÍÈÅ: Ìèðàíäó è ðîçûñê ìîæíî âûäàòü âî âðåìÿ òðàíñïîðòèðîâêè.\nÈÑÊËÞ×ÅÍÈÅ: Ìèðàíäó ìîæíî çà÷èòàòü äî óñòàíîâëåíèÿ ëè÷íîñòè.]] },
    [5] = { title = "Ïîðÿäîê àðåñòà ãîñ. ñîòðóäíèêà", content = [[1) Ïî óñìîòðåíèþ âûäàòü ðîçûñê ñ ïðè÷èíîé 'ÑËÅÄÑÒÂÈÅ'\n2) Åñëè àðåñòîâàííîãî ïåðåäàëè êîïû - ïîëó÷åíèå îò íèõ äîêàçàòåëüñòâ\n3) Ìèðàíäà\n4) Îáûñê\n5) Âåç¸òå íà äîïðîñ ïî ñâîåìó óñìîòðåíèþ\n6) Ïî îêîí÷àíèþ ïðîöåññóàëüíûõ äåéñòâèé âûáèðàåòå ìåðó íàêàçàíèÿ\n7) Åñëè ïðèìåí¸í àðåñò â ÊÏÇ, â òå÷åíèè 24 ÷àñîâ ñîñòàâëÿåòå ÊÔ íà ôîðóì]] },
    [6] = { title = "Îñíîâàíèÿ äîïðîñà", content = [[Äîïðîñ ïðîâîäèòñÿ íà îñíîâàíèè ïóíêòà X, ñòàòüè 1, ðàçäåëà 2, ÷àñòè 2 ÏÊ.\n\nA. Äîïðîñ àðåñòîâàííîãî ëèöà\nB. Îðäåð íà ïðîâåäåíèå äîïðîñà\nC. Íàëè÷èå îñíîâàíèé ïîëàãàòü, ÷òî ó ëèöà åñòü èíôîðìàöèÿ\nD. Íà ëèöî îòêðûò ÊÔ. Ïî çàïðîñó ïðåäîñòàâèòü ìàòåðèàëû è îïóáëèêîâàòü ÊÔ íà ôîðóìå â òå÷åíèè 24 ÷àñîâ\nE. Ïîâåñòêà íà äîïðîñ, îïóáëèêîâàííàÿ íà ôîðóìå]] },
    [7] = { title = "Ïîðÿäîê ïðîâåäåíèÿ äîïðîñà", content = [[1) Óñàäèòü ÷åëîâåêà íà ñòóë, îäíó ðóêó ïðèêîâàòü ê ñòîëó, âòîðóþ îñòàâèòü ñâîáîäíîé\n2) Âêëþ÷èòü êàìåðó â äîïðîñíîé\n3) Íàçâàòü äàòó è âðåìÿ íà÷àëà äîïðîñà. Ïðèìåð: Äîïðîñ ïðîâîäèòñÿ 15 èþëÿ 2025 â 16:30\n4) Ñîîáùèòü êòî ïðîâîäèò äîïðîñ è íàçâàòü ïîçûâíîé. Ïðèìåð: Äîïðîñ ïðîâîäèò àãåíò Ñëîíÿðà\n5) Óêàçàòü êòî äîïðàøèâàåòñÿ è â êàêîì ñòàòóñå (ñâèäåòåëü/ïîäîçðåâàåìûé/ïîòåðïåâøèé). Ïðèìåð: Äîïðàøèâàåò Òîì Êðóç êàê ñâèäåòåëü.\n6) Ìèðàíäà\n7) Óòî÷íÿåì æåëàåò-ëè äîïðàøèâàåìûé ðåàëèçîâàòü ñâîè ïðàâà. Åñëè òðåáóåò àäâîêàòà - /advokatdopros\n8) Åñëè äîïðàøèâàåì ãîñíèêà - ïî ñâîåìó æåëàíèþ ìîæíî óâåäîìèòü åãî îðãàíèçàöèþ. Ëèäåð è çàì èìåþò ïðàâî ïðèñóòñòâîâàòü íà äîïðîñå.\n9) Óâåäîìëÿåì àäâîêàòà, äîïðàøèâàåìîãî è åãî ëèäåðà/çàìà îá îòâåòñòâåííîñòè çà ðàçãëàøåíèå ãîñ.òàéíû\nÎò àäâîêàòà è ëèäåðà/çàìà îáÿçàòåëüíî òðåáóåì ïîäïèñàòü óâåäîìëåíèå, ïðè îòêàçå - âûãîíÿåì ñ äîïðîñíîé.\n11) Çàäà¸ì âîïðîñû, êîòîðûå ñ÷èòàåì íóæíûì\n12) Â êîíöå äîïðîñà îïîâåùàåì î çàâåðøåíèè äîïðîñà è âûêëþ÷àåì êàìåðó.\n13) Âûâîäèì äîïðàøèâàåìîãî, åãî ëèäåðà/çàìà è àäâîêàòà ñ ìåøêîì íà ãîëîâå èç îôèñà. Ïðè íåîáõîäèìîñòè îòâîçèì â ÊÏÇ.]] },
    [8] = { title = "Àäâîêàò íà äîïðîñå", content = [[Ïðè ïîñòóïëåíèè òðåáîâàíèÿ - çàïðàøèâàåì àäâîêàòà â /d ó ïðàâèòåëüñòâà. Åñëè â òå÷åíèè 5 ìèíóò...\n...ñ ìîìåíòà ÏÅÐÂÎÃÎ çàïðîñà îòâåòà íå ïîñëåäîâàëî - ïðîäîëæàåì áåç àäâîêàòà. Àíàëîãè÷íî äåëàåì ïðè îòðèöàòåëüíîì îòâåòå.\nÅñëè àäâîêàò âûøåë íà ñâÿçü - æä¸ì ïîêà îí ïðèåäåò â òå÷åíèè 10 ìèíóò. Ïî èñòå÷åíèè ýòîãî âðåìåíè - ïðîäîëæàåì áåç àäâîêàòà.\nÏðè ïðèáûòèè àäâîêàòà ïðîâåðÿåì ó íåãî ïàñïîðò, íàëè÷èå ëèöåíçèè è 5+ ðàíãà â ïðàâèòåëüñòâå.\nÏåðåä çàâîäîì â îôèñ îáûñêèâàåì è îòáèðàåì ó àäâîêàòà òåëåôîí, êàìåðó, äèêòîôîí è ò.ï., íàäåâàåì ìåøîê.\nÅñëè ó àäâîêàòà íàøëè çàïðåù¸íêó - àðåñòîâûâàåì àäâîêàòà.\nÀäâîêàò èìååò ïðàâî íà ïðèâàòíûå áåñåäû. Îáùàÿ èõ ïðîäîëæèòåëüíîñòü - 20 ìèíóò.]] },
    [9] = { title = "Îñíîâàíèÿ äëÿ îáûñêà", content = [[Îáûñê íà îñíîâàíèè ïóíêòà X, ñòàòüè 1, ðàçäåëà 3, ÷àñòè 1 ÏÊ\n\nA. Îðäåð\nB. Àðåñò\nC. Ïðîâåäåíèå ðåéäà\nD. Êîíòðîëü íà áëîêïîñòàõ\nE. Âõîä â çîíó îöåïëåíèÿ\nF. Âõîä íà òåððèòîðèþ ðåæèìíîãî îáúåêòà\nG. Äîáðîâîëüíîå ñîãëàñèå íà îáûñê\nH. Çàäåðæàíèå â ñâÿçè ñ íîøåíèåì ãðàæäàíèíîì ìàñêè\nI. Çàäåðæàíèå ãîñíèêà â ñâÿçè ñ íàðóøåíèåì óñòàâà èëè ÔÏ\nK. Çàäåðæàíèå â ñëó÷àå, åñëè åñòü îñíîâàíèÿ ïðåäïîëàãàòü, ÷òî çàäåðæàííûé ñîâåðøèë ïðåñòóïëåíèå\nL. Çàäåðæàíèå â ñëó÷àå, åñëè çàäåðæàííûé óïîòðåáèë íàðêî èëè àëêîãîëü íà ãëàçàõ àãåíòà\nM. Ïðîâåäåíèå ïðîâåðêè ãîñ îðãàíèçàöèè\n\nÂÀÆÍÎ: Îáûñê äåëàåòñÿ Â ÏÅÐ×ÀÒÊÀÕ!]] },
    [10] = { title = "Îñíîâàíèÿ äëÿ ðåéäîâ", content = [[Ðåéä ÃÅÒÒÎ - Ñòàòüÿ 2, ðàçäåë 5, ÷àñòè 2 ÏÊ. [Íóæåí îðäåð]\nÐåéä ÏÐÈÒÎÍÀ - Ñòàòüÿ 3, ðàçäåë 5, ÷àñòè 2 ÏÊ\nÐåéä ÎÏÃ - Ñòàòüÿ 4, ðàçäåë 5, ÷àñòè 2 ÏÊ [Íóæåí îðäåð]\nÐåéä ÑÒÎ - Ñòàòüÿ 5, ðàçäåë 5, ÷àñòè 2 ÏÊ\nÐåéä ÃÐÓÇÎÏÅÐÅÂÎÇÎÊ - Ñòàòüÿ 6, ðàçäåë 5, ÷àñòè 2 ÏÊ [Íóæåí îðäåð]\nÐåéä ÏÀÒÐÓËÅÉ - Ñòàòüÿ 7, ðàçäåë 5, ÷àñòè 2 ÏÊ\nÐåéä ËÀÂÎÊ ÖÐ/ÖÃ - Ñòàòüÿ 8, ðàçäåë 5, ÷àñòè 2 ÏÊ\nÐåéä ÃÎÑ.ÎÐÃ - Ñòàòüÿ 9, ðàçäåë 5, ÷àñòè 2 ÏÊ [Íóæåí îðäåð]\nÐåéä ÍÀÐÊÎÒÐÀÔÈÊÀ - Ñòàòüÿ 10, ðàçäåë 5, ÷àñòè 2 ÏÊ]] },
    [11] = { title = "Îñíîâàíèÿ ïðàâèë áåçîïàñíîñòè", content = [[6 ìåòðîâ - ñòàòüÿ 1, ðàçäåë 5, ÷àñòè 1 ÏÊ\n3 ïîâîðîòà - ñòàòüÿ 1, ðàçäåë 5, ÷àñòè 1 ÏÊ]] }
}

for i = 1, 11 do
    imgui.OnFrame(
        function() return showMenu[i][0] end,
        function()
            imgui.SetNextWindowSize(imgui.ImVec2(520, 480), imgui.Cond.FirstUseEver)
            imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
            local title = menuData[i] and menuData[i].title or ("Èíôîðìàöèÿ " .. i)
            imgui.Begin(u8(title), showMenu[i], imgui.WindowFlags.NoCollapse)
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.11, 0.42, 0.87, 1.00))
            imgui.TextWrapped(u8(title))
            imgui.PopStyleColor()
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()
            imgui.BeginChild("ContentScroll", imgui.ImVec2(0, 0), true)
            if menuData[i] and menuData[i].content then
                imgui.PushTextWrapPos(0)
                imgui.TextWrapped(u8(menuData[i].content))
                imgui.PopTextWrapPos()
            end
            imgui.EndChild()
            imgui.Spacing()
            imgui.Separator()
            if createStyledButton("Çàêðûòü", 100, 32, true) then
                showMenu[i][0] = false
            end
            imgui.End()
        end
    )
end

-- Îêíî ïàñõàëêè
imgui.OnFrame(
    function() return showEasterEgg[0] end,
    function()
        imgui.SetNextWindowSize(imgui.ImVec2(520, 420), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.Begin(u8("Ïàñõàëêà"), showEasterEgg, imgui.WindowFlags.NoCollapse)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.95, 0.75, 0.35, 1.00))
        imgui.TextWrapped(u8(""))
        imgui.PopStyleColor()
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        if easterEggTexture ~= nil then
            local displayWidth = 460
            local displayHeight = 260
            imgui.SetCursorPosX((imgui.GetWindowWidth() - displayWidth) / 2)
            imgui.Image(easterEggTexture, imgui.ImVec2(displayWidth, displayHeight))
            imgui.Spacing()
            imgui.Spacing()
            imgui.TextColored(imgui.ImVec4(0.70, 0.70, 0.70, 1.00), u8(" "))
        else
            imgui.BeginChild("EasterEggText", imgui.ImVec2(0, 0), true)
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.90, 0.90, 0.90, 1.00))
            imgui.PushTextWrapPos(0)
            imgui.TextWrapped(u8("×òîáû äîáàâèòü êàðòèíêó, ïîìåñòèòå ôàéë 'image.png' â ïàïêó:"))
            imgui.TextColored(imgui.ImVec4(0.95, 0.75, 0.35, 1.00), u8("   " .. configDirectory))
            imgui.PopTextWrapPos()
            imgui.PopStyleColor()
            imgui.EndChild()
        end
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        imgui.SetCursorPosX((imgui.GetWindowWidth() - 100) / 2)
        if createStyledButton("Çàêðûòü", 100, 32, true) then
            showEasterEgg[0] = false
        end
        imgui.End()
    end
)

-- ==================== ÓÌÍÀß ÂÛÄÀ×À ÂÛÃÎÂÎÐÀ ====================
local path_gwarn_json = configDirectory .. "/gwarn.json"
local ustav_data = {}
local ustav_names = {}

function load_ustav_from_json()
    if doesFileExist(path_gwarn_json) then
        local file = io.open(path_gwarn_json, 'r')
        if file then
            local contents = file:read('*a')
            file:close()
            if contents and #contents > 0 then
                local success, data = pcall(decodeJson, contents)
                if success then
                    ustav_data = data
                    ustav_names = {}
                    for i, ustav in ipairs(ustav_data) do
                        if ustav.name then table.insert(ustav_names, ustav.name) end
                    end
                    print('[Snatch Helper] Çàãðóæåíî óñòàâîâ: ' .. #ustav_data)
                else
                    ustav_data = {}
                end
            else
                ustav_data = {}
            end
        else
            ustav_data = {}
        end
    else
        ustav_data = {}
    end
end
load_ustav_from_json()

local SumMenuWindow = imgui.new.bool(false)
local showUstavMenu = {}
for i = 1, 10 do showUstavMenu[i] = imgui.new.bool(false) end
local selectedPlayerId = 0
local selectedPlayerName = ""
local selectedUstavIndex = 0
local message_color = 0xFF0000

function getPlayerNameById(playerId)
    return sampGetPlayerNickname(playerId) or "ID_" .. playerId
end

function sendGwarnWithRoleplay(playerId, reason)
    if isActiveCommand then return false end
    isActiveCommand = true
    sampSendChat("/do ÊÏÊ íàõîäèòñÿ íà ïîÿñíîì äåðæàòåëå.")
    wait(1500)
    sampSendChat("/me áåð¸ò â ðóêè ñâîé ÊÏÊ è âêëþ÷àåò åãî")
    wait(1500)
    sampSendChat("/me çàõîäèò â áàçó äàííûõ è ïåðåõîäèò â ðàçäåë óïðàâëåíèå ñîòðóäíèêàìè äðóãèõ îðãàíèçàöèé")
    wait(1500)
    sampSendChat("/me îòêðûâàåò äåëî íóæíîãî ñîòðóäíèêà è âíîñèò â íåãî èçìåíåíèÿ")
    wait(1500)
    sampSendChat("/do Èçìåíåíèÿ óñïåøíî ñîõðàíåíû.")
    wait(1500)
    sampSendChat("/me âûõîäèò ñ áàçû äàííûõ è âûêëþ÷èâ ÊÏÊ óáèðàåò åãî íà ïîÿñíîé äåðæàòåëü")
    wait(1500)
    local command = string.format("/me %d %s", playerId, reason)
    print("[Snatch Helper] Îòïðàâëÿåòñÿ êîìàíäà: " .. command)
    print("[DEBUG] reason = '" .. tostring(reason) .. "'")
    sampSendChat(command)
    isActiveCommand = false
    return true
end

imgui.OnFrame(
    function() return SumMenuWindow[0] end,
    function()
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(520,480), imgui.Cond.FirstUseEver)
        imgui.Begin(u8("Âûáîð óñòàâà äëÿ âûãîâîðà"), SumMenuWindow, imgui.WindowFlags.NoCollapse)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.11,0.42,0.87,1))
        imgui.TextWrapped(u8("Âûäà÷à ñïåöèàëüíîãî âûãîâîðà"))
        imgui.PopStyleColor()
        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
        imgui.Text(u8("ID èãðîêà: " .. tostring(selectedPlayerId)))
        imgui.Text(u8("Èìÿ èãðîêà: " .. selectedPlayerName))
        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
        imgui.Text(u8("Âûáåðèòå óñòàâ:"))
        imgui.Spacing()
        if #ustav_data == 0 then
            imgui.TextColored(imgui.ImVec4(0.9,0.2,0.2,1), u8("Óñòàâû íå çàãðóæåíû!"))
        else
            for i, name in ipairs(ustav_names) do
                if createStyledButton(name, -1, 42) then
                    selectedUstavIndex = i
                    SumMenuWindow[0] = false
                    showUstavMenu[i][0] = true
                end
                imgui.Spacing()
            end
        end
        imgui.Spacing(); imgui.Separator()
        if createStyledButton("Îòìåíà", 100, 32) then SumMenuWindow[0] = false end
        imgui.End()
    end
)

for idx, ustav in ipairs(ustav_data) do
    imgui.OnFrame(
        function() return showUstavMenu[idx][0] end,
        function()
            imgui.SetNextWindowSize(imgui.ImVec2(1500,700), imgui.Cond.FirstUseEver)
            imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2,sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
            imgui.Begin(u8(ustav.name .. " - âûáîð ïóíêòà"), showUstavMenu[idx], imgui.WindowFlags.NoCollapse)
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.11,0.42,0.87,1))
            imgui.TextWrapped(u8(ustav.name .. " - âûáîð ïóíêòà"))
            imgui.PopStyleColor()
            if not ustav.item or #ustav.item == 0 then
                imgui.TextColored(imgui.ImVec4(0.9,0.2,0.2,1), u8("Ïóíêòû íå çàãðóæåíû!"))
            else
                imgui.BeginChild("UstavItems", imgui.ImVec2(0,0), true)
                for i, item in ipairs(ustav.item) do
                    local btnText = item.reason or "Ïóíêò "..i
                    if item.reason and item.text then
                        local text = item.text:len() > 300 and item.text:sub(1,300).."..." or item.text
                        btnText = item.reason .. " - " .. text
                    end
                    if createStyledButton(btnText, -1, 0) then
                        showUstavMenu[idx][0] = false
                        lua_thread.create(function() sendGwarnWithRoleplay(selectedPlayerId, item.reason) end)
                    end
                    if i < #ustav.item then imgui.Spacing(); imgui.Separator(); imgui.Spacing() end
                end
                imgui.EndChild()
            end
            imgui.Spacing(); imgui.Separator()
            if createStyledButton("Íàçàä", 100, 32) then
                showUstavMenu[idx][0] = false
                SumMenuWindow[0] = true
            end
            imgui.End()
        end
    )
end

-- ==================== ÓÌÍÀß ÂÛÄÀ×À ÐÎÇÛÑÊÀ ====================
local path_uk_json = configDirectory .. "/uk.json"
local uk_data = {}
local uk_names = {}

function load_uk_from_json()
    if doesFileExist(path_uk_json) then
        local file = io.open(path_uk_json, 'r')
        if file then
            local contents = file:read('*a')
            file:close()
            if contents and #contents > 0 then
                local success, data = pcall(decodeJson, contents)
                if success then
                    uk_data = data
                    uk_names = {}
                    for i, sec in ipairs(uk_data) do
                        if sec.name then table.insert(uk_names, sec.name) end
                    end
                    print('[Snatch Helper] Çàãðóæåíî ðàçäåëîâ ÓÊ: ' .. #uk_data)
                else
                    uk_data = {}
                end
            else
                uk_data = {}
            end
        else
            uk_data = {}
        end
    else
        uk_data = {}
    end
end
load_uk_from_json()

local WantedMenuWindow = imgui.new.bool(false)
local selectedWantedPlayerId = 0
local selectedWantedPlayerName = ""
local isActiveWantedCommand = false

function sendWantedWithRoleplay(playerId, reason)
    if isActiveWantedCommand then return false end
    isActiveWantedCommand = true
    sampSendChat("/do ÊÏÊ íàõîäèòñÿ íà ïîÿñíîì äåðæàòåëå.")
    wait(1500)
    sampSendChat("/me áåð¸ò â ðóêè ñâîé ÊÏÊ è âêëþ÷àåò åãî")
    wait(1500)
    sampSendChat("/me çàõîäèò â áàçó äàííûõ è ïåðåõîäèò â ðàçäåë ôåäåðàëüíîãî ðîçûñêà")
    wait(1500)
    sampSendChat("/me îòêðûâàåò ðîçûñêíîå äåëî è âíîñèò â íåãî èçìåíåíèÿ")
    wait(1500)
    sampSendChat("/do Èçìåíåíèÿ óñïåøíî ñîõðàíåíû.")
    wait(1500)
    sampSendChat("/me âûõîäèò ñ áàçû äàííûõ è âûêëþ÷èâ ÊÏÊ óáèðàåò åãî íà ïîÿñíîé äåðæàòåëü")
    wait(1500)
    local command = string.format("/su %d %s", playerId, reason)
    sampSendChat(encoding.UTF8:decode(command))
    isActiveWantedCommand = false
    return true
end

imgui.OnFrame(
    function() return WantedMenuWindow[0] end,
    function()
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(1000,600), imgui.Cond.FirstUseEver)
        imgui.Begin(u8("Óìíàÿ âûäà÷à ðîçûñêà"), WantedMenuWindow, imgui.WindowFlags.NoCollapse)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.87,0.11,0.11,1))
        imgui.TextWrapped(u8("Âûäà÷à ôåäåðàëüíîãî ðîçûñêà ïî ñòàòüÿì ÓÊ"))
        imgui.PopStyleColor()
        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
        imgui.Text(u8("ID èãðîêà: " .. tostring(selectedWantedPlayerId)))
        imgui.Text(u8("Èìÿ èãðîêà: " .. selectedWantedPlayerName))
        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
        imgui.Text(u8("Âûáåðèòå ðàçäåë Óãîëîâíîãî Êîäåêñà:"))
        imgui.Spacing()
        if #uk_data == 0 then
            imgui.TextColored(imgui.ImVec4(0.9,0.2,0.2,1), u8("Ðàçäåëû ÓÊ íå çàãðóæåíû!"))
        else
            for i, name in ipairs(uk_names) do
                if imgui.CollapsingHeader(u8(name)) then
                    imgui.Indent(20)
                    local section = uk_data[i]
                    if section and section.item then
                        for j, item in ipairs(section.item) do
                            local btnText = item.reason or "Ñòàòüÿ "..j
                            if item.reason and item.text then
                                local text = item.text:len() > 120 and item.text:sub(1,120).."..." or item.text
                                btnText = item.reason .. " - " .. text
                            end
                            if item.lvl then btnText = btnText .. " (Óð."..item.lvl..")" end
                            if createStyledButton(btnText, -1, 35) then
                                WantedMenuWindow[0] = false
                                lua_thread.create(function() sendWantedWithRoleplay(selectedWantedPlayerId, item.reason) end)
                            end
                            if j < #section.item then imgui.Spacing() end
                        end
                    end
                    imgui.Unindent(20)
                end
                if i < #uk_names then imgui.Spacing() end
            end
        end
        imgui.Spacing(); imgui.Separator()
        imgui.SetCursorPosX(imgui.GetWindowWidth()/2-50)
        if createStyledButton("Îòìåíà", 100, 32, true) then WantedMenuWindow[0] = false end
        imgui.End()
    end
)

-- ==================== ÇÀÃÐÓÇÊÀ ÒÅÊÑÒÓÐÛ ÏÀÑÕÀËÊÈ ====================
imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    setup_premium_style(settings.currentTheme)
    local imgPath = configDirectory .. "/image.png"
    if doesFileExist(imgPath) then
        local ok, tex = pcall(imgui.CreateTextureFromFile, imgPath)
        if ok and tex then easterEggTexture = tex end
    end
end)

-- ==================== ÎÑÍÎÂÍÎÉ ÖÈÊË ====================
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    sampRegisterChatCommand("gw", function(arg)
        if not isActiveCommand then
            local id = tonumber(arg)
            if id and id > 0 then
                selectedPlayerId = id
                selectedPlayerName = getPlayerNameById(selectedPlayerId)
                if selectedPlayerName == "ID_"..selectedPlayerId then
                    sampAddChatMessage('[Snatch Helper] Èãðîê íå íàéäåí!', message_color)
                    return
                end
                if #ustav_data == 0 then
                    sampAddChatMessage('[Snatch Helper] Óñòàâû íå çàãðóæåíû!', message_color)
                    return
                end
                SumMenuWindow[0] = true
            else
                sampAddChatMessage('[Snatch Helper] Èñïîëüçóéòå /gw [ID èãðîêà] (ID äîëæåí áûòü ïîëîæèòåëüíûì ÷èñëîì)', message_color)
            end
        else
            sampAddChatMessage('[Snatch Helper] Äîæäèòåñü çàâåðøåíèÿ îòûãðîâêè!', message_color)
        end
    end)

    sampRegisterChatCommand("uk", function(arg)
        if not isActiveWantedCommand then
            local id = tonumber(arg)
            if id and id > 0 then
                selectedWantedPlayerId = id
                selectedWantedPlayerName = getPlayerNameById(selectedWantedPlayerId)
                if selectedWantedPlayerName == "ID_"..selectedWantedPlayerId then
                    sampAddChatMessage('[Snatch Helper] Èãðîê íå íàéäåí!', message_color)
                    return
                end
                if #uk_data == 0 then
                    sampAddChatMessage('[Snatch Helper] Ðàçäåëû ÓÊ íå çàãðóæåíû!', message_color)
                    return
                end
                WantedMenuWindow[0] = true
            else
                sampAddChatMessage('[Snatch Helper] Èñïîëüçóéòå /uk [ID èãðîêà] (ID äîëæåí áûòü ïîëîæèòåëüíûì ÷èñëîì)', message_color)
            end
        else
            sampAddChatMessage('[Snatch Helper] Äîæäèòåñü çàâåðøåíèÿ îòûãðîâêè!', message_color)
        end
    end)

    sampAddChatMessage("{ff0000}[Snatch Helper] {ff4444}Ñêðèïò çàãðóæåí (v5.2)")
    sampAddChatMessage("{ff0000}[Snatch Helper] {ff4444}Óìíàÿ âûäà÷à âûãîâîðà: /gw")
    sampAddChatMessage("{ff0000}[Snatch Helper] {ff4444}Óìíàÿ âûäà÷à ðîçûñêà: /uk")
    sampAddChatMessage("{ff0000}[Snatch Helper] {ff4444}Ñïðàâî÷íèê è áèíäåð: F3")
    sampAddChatMessage("{ff0000}[Snatch Helper] {ff4444}Óäà÷íîé ñìåíû!")

    addEventHandler('onWindowMessage', function(msg, wparam)
        if msg == 256 or msg == 260 then
            if wparam == 0x72 then
                mainWindow.switch()
                mainWindowOpen[0] = mainWindow.state
            elseif wparam == 0x73 then
                mainWindow.state = true
                mainWindow.switch()
                mainWindowOpen[0] = mainWindow.state
                activeTab[0] = 1
            end
        end
    end)

    while true do
        wait(0)
        -- Ñòîï-êëàâèøà
        local stopPressed = false
        if settings.stopKeyMod == 0 then stopPressed = wasKeyPressed(settings.stopKey)
        elseif settings.stopKeyMod == 1 then stopPressed = isKeyDown(0x11) and wasKeyPressed(settings.stopKey)
        elseif settings.stopKeyMod == 2 then stopPressed = isKeyDown(0x10) and wasKeyPressed(settings.stopKey)
        elseif settings.stopKeyMod == 3 then stopPressed = isKeyDown(0x12) and wasKeyPressed(settings.stopKey) end
        if stopPressed and activeBinder then
            stopCurrentBind = true
            sampAddChatMessage("[Snatch Helper] Áèíä îñòàíîâëåí", 0xFF0000)
        end

        -- Ãîðÿ÷èå êëàâèøè áèíäîâ (íå ðàáîòàþò ïðè îòêðûòîì ÷àòå)
        if not sampIsChatInputActive() and not sampIsDialogActive() then
            for key, list in pairs(keyToBind) do
                for _, item in ipairs(list) do
                    local pressed = false
                    if item.mod == 0 then pressed = wasKeyPressed(key)
                    elseif item.mod == 1 then pressed = isKeyDown(0x11) and wasKeyPressed(key)
                    elseif item.mod == 2 then pressed = isKeyDown(0x10) and wasKeyPressed(key)
                    elseif item.mod == 3 then pressed = isKeyDown(0x12) and wasKeyPressed(key) end
                    if pressed then
                        lua_thread.create(function() performBind(item.bind, {}) end)
                    end
                end
            end
        end

        -- Ñåëåêòîð
        local selPressed = false
        if settings.selectorKeyMod == 0 then selPressed = isKeyDown(settings.selectorKey)
        elseif settings.selectorKeyMod == 1 then selPressed = isKeyDown(0x11) and isKeyDown(settings.selectorKey)
        elseif settings.selectorKeyMod == 2 then selPressed = isKeyDown(0x10) and isKeyDown(settings.selectorKey)
        elseif settings.selectorKeyMod == 3 then selPressed = isKeyDown(0x12) and isKeyDown(settings.selectorKey) end
        if selPressed and not selectorActive then
            local target = select(2, getCharPlayerIsTargeting(playerHandle))
            if target then
                selectorTargetId = select(2, sampGetPlayerIdByCharHandle(target))
                if selectorTargetId then selectorActive = true end
            end
        elseif not selPressed and selectorActive then
            selectorActive = false
        end
    end
end