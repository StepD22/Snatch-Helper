---@diagnostic disable: undefined-global, need-check-nil, lowercase-global, cast-local-type, unused-local

script_name("Snatch Helper")
script_description('Улучшенный помощник с биндером, горячими клавишами, селектором и темами')
script_author("StepD")
script_version("5.2") -- увеличил версию

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

-- ==================== ЛОКАЛЬНЫЕ ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ====================
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

-- ==================== АНИМАЦИЯ ОКНА ====================
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
local mainWindowOpen = imgui.new.bool(false)  -- для синхронизации с крестиком
local keyBindContext = nil -- "bind", "stop", "selector"

-- ==================== КОНФИГУРАЦИЯ ====================
local configDirectory = getWorkingDirectory():gsub('\\','/') .. "/Snatch Helper"
local settings = {
    defaultDelay = 1500,
    stopKey = 0x7B,        -- F12 по умолчанию
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
-- ==================== ЦВЕТОВЫЕ ТЕМЫ ====================
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

-- ==================== СТИЛЕВЫЕ ФУНКЦИИ ====================
function createStyledButton(label, width, height, isAccent)
    local colors = {
        primary = imgui.ImVec4(0.85, 0.18, 0.18, 1.00),
        primary_dark = imgui.ImVec4(0.65, 0.12, 0.12, 1.00),
        primary_light = imgui.ImVec4(0.95, 0.30, 0.30, 1.00),
        gradient = imgui.ImVec4(0.90, 0.22, 0.22, 0.90),
        secondary = imgui.ImVec4(0.25, 0.25, 0.25, 0.85),
        secondary_hover = imgui.ImVec4(0.35, 0.35, 0.35, 0.85),
        text = imgui.ImVec4(0.98, 0.98, 0.98, 1.00)
    }
    local buttonColor, hoverColor, activeColor
    if isAccent then
        buttonColor = colors.primary
        hoverColor = colors.primary_light
        activeColor = colors.primary_dark
    else
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

-- ==================== БИНДЕР ====================
local binds = {}
local bindsConfigFile = configDirectory .. "/binds.json"

-- Переменные интерфейса
local searchBuf = ffi.new("char[64]")
local selectedBindIndex = nil
local editNameBuf = ffi.new("char[256]")
local editCmdBuf = ffi.new("char[64]")
local editStepsBuf = ffi.new("char[4096]")
local editDelayBuf = ffi.new("int[1]", 1500)
local editKeyBuf = ffi.new("int[1]", 0)
local editKeyModBuf = ffi.new("int[1]", 0)

-- Для окна выбора клавиши
local keyBindPopupActive = false
local tempKey = 0
local tempMod = 0
local waitingForKey = false

-- Индекс для быстрого поиска по команде
local cmdToBind = {}
local keyToBind = {}  -- для горячих клавиш
local registeredCommands = {} -- список зарегистрированных команд

-- Подтверждение удаления
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
            local cmd = bind.cmd  -- уже без слеша
            local success = sampRegisterChatCommand(cmd, function(args)
                if activeBinder then
                    sampAddChatMessage("[Snatch Helper] Бинд уже выполняется", 0xFF0000)
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
                    print("[Snatch Helper] Загружено биндов: " .. #binds)
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
-- Таблица простых переменных {var}
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

-- Вспомогательные функции для поиска
function getClosestCarId()
    local minDist = 9999
    local closest = -1
    local x, y, z = getCharCoordinates(playerPed)
    for i = 0, 1800 do
        local car = sampGetCarHandleBySampVehicleId(i)
        if car then
            local xi, yi, zi = getCarCoordinates(car)
            local dist = math.sqrt((xi-x)^2 + (yi-y)^2 + (zi-z)^2)
            if dist < minDist then
                minDist = dist
                closest = i
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
    if angle >= 337.5 or angle < 22.5 then return "С"
    elseif angle < 67.5 then return "СВ"
    elseif angle < 112.5 then return "В"
    elseif angle < 157.5 then return "ЮВ"
    elseif angle < 202.5 then return "Ю"
    elseif angle < 247.5 then return "ЮЗ"
    elseif angle < 292.5 then return "З"
    elseif angle < 337.5 then return "СЗ"
    end
    return "?"
end

-- ==================== ВЫПОЛНЕНИЕ БИНДА (С ТАЙМАУТОМ, КЭШЕМ И ОСТАНОВКОЙ) ====================
local MAX_BIND_DURATION = 30000 -- 30 секунд

function performBind(bind, args, targetId)
    if not bind or not bind.steps or #bind.steps == 0 then return end
    if activeBinder then
        sampAddChatMessage("[Snatch Helper] Бинд уже выполняется", 0xFF0000)
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
        sampAddChatMessage("[Snatch Helper] Ошибка: " .. tostring(err), 0xFF0000)
        print("[Snatch Helper] Ошибка: " .. tostring(err))
        -- Сбрасываем флаги при ошибке
        activeBinder = false
        stopCurrentBind = false
    end

    for _, step in ipairs(bind.steps) do
        if stopCurrentBind then
            break
        end
        if os.clock() * 1000 - startTime > MAX_BIND_DURATION then
            sampAddChatMessage("[Snatch Helper] Бинд прерван по таймауту", 0xFF0000)
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
        result = result:gsub("{" .. var .. "}", value)
    end
    return result
end

function replaceFunctions(step, cache)
    local result = step
    -- замена простых переменных {var}
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
-- ==================== ПЕРЕХВАТ RPC (больше не нужен для команд) ====================
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

-- ==================== СИСТЕМА СЕЛЕКТОРА (PIE MENU) ====================
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
-- ==================== СТИЛИ (с учётом темы) ====================
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

-- ==================== ТАБЛИЦА ИМЁН КЛАВИШ ====================
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
    if key == 0 then return "Не назначена" end
    local modText = ""
    if mod == 1 then modText = "Ctrl+"
    elseif mod == 2 then modText = "Shift+"
    elseif mod == 3 then modText = "Alt+" end
    return modText .. (keyNames[key] or "["..key.."]")
end

-- ==================== ОКНО ВЫБОРА КЛАВИШИ ====================
local keyBindPopupActive = false
local tempKey = 0
local tempMod = 0
local waitingForKey = false

imgui.OnFrame(
    function() return keyBindPopupActive end,
    function()
        imgui.SetNextWindowSize(imgui.ImVec2(300, 120), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.Begin(u8("Выбор горячей клавиши"), imgui.new.bool(true), imgui.WindowFlags.NoCollapse)

        if waitingForKey then
            imgui.Text(u8("Нажмите любую комбинацию клавиш...\n(ESC для отмены)"))
            -- Сначала проверяем ESC для отмены
            if wasKeyPressed(0x1B) then
                waitingForKey = false
            else
                -- Список обычных клавиш (исключаем модификаторы Ctrl, Shift, Alt)
                local keys = {
                    0x01,0x02,0x04,0x08,0x09,0x0D,0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x2D,0x2E,
                    0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x41,0x42,0x43,0x44,0x45,0x46,0x47,
                    0x48,0x49,0x4A,0x4B,0x4C,0x4D,0x4E,0x4F,0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,
                    0x59,0x5A,0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B
                }
                for _, vkey in ipairs(keys) do
                    if wasKeyPressed(vkey) then
                        -- определим модификаторы на момент нажатия (приоритет: Ctrl > Shift > Alt)
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
            imgui.Text(u8("Текущая комбинация: " .. getKeyName(tempKey, tempMod)))
            imgui.Spacing()
            if imgui.Button(u8("Изменить"), imgui.ImVec2(100,0)) then
                waitingForKey = true
            end
            imgui.SameLine()
            if imgui.Button(u8("Сбросить"), imgui.ImVec2(100,0)) then
                tempKey = 0
                tempMod = 0
            end
        end

        imgui.Separator()
        if imgui.Button(u8("OK"), imgui.ImVec2(100,0)) then
            -- сохраняем в зависимости от контекста
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
        if imgui.Button(u8("Отмена"), imgui.ImVec2(100,0)) then
            keyBindPopupActive = false
            keyBindContext = nil
        end

        imgui.End()
    end
)

-- ==================== ГЛАВНОЕ МЕНЮ ====================
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

        -- синхронизация закрытия по крестику
        if not mainWindowOpen[0] and mainWindow.state then
            mainWindow.switch2()
        end

        if imgui.BeginTabBar("MainTabs", 0) then
            if imgui.BeginTabItem(u8("Справочник")) then
                activeTab[0] = 0
                renderReferenceTab()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem(u8("Биндер")) then
                activeTab[0] = 1
                renderBinderTab()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem(u8("Настройки")) then
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
    createStyledHeader("Справочник процессуальных действий", "large")
    imgui.SameLine()
    imgui.SetCursorPosX(imgui.GetCursorPosX() + 10)
    imgui.TextColored(imgui.ImVec4(0.85, 0.65, 0.65, 1.00), u8("v5.2"))
    imgui.Spacing()
    createStyledSeparator()
    imgui.Spacing()
    imgui.TextColored(imgui.ImVec4(0.70, 0.70, 0.70, 1.00), u8("Выберите раздел для изучения:"))
    imgui.Spacing()
    imgui.Spacing()
    local menuButtons = {
        {text = "Основания задержания"},
        {text = "Порядок задержания"}, 
        {text = "Основания ареста"},
        {text = "Порядок ареста"},
        {text = "Порядок ареста гос. сотрудника"},
        {text = "Основания допроса"},
        {text = "Порядок проведения допроса"},
        {text = "Адвокат на допросе"},
        {text = "Основания для обыска"},
        {text = "Основания для рейдов"},
        {text = "Основания правил безопасности"},
        {text = "Пасхалка"}
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
    imgui.TextColored(imgui.ImVec4(0.85, 0.65, 0.65, 1.00), u8("Статус:"))
    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.30, 0.95, 0.30, 1.00))
    imgui.Text(u8("Активен"))
    imgui.PopStyleColor()
    imgui.SameLine()
    imgui.SetCursorPosX(imgui.GetWindowWidth() - 120)
    imgui.TextColored(imgui.ImVec4(0.60, 0.60, 0.60, 1.00), u8("Snatch Helper"))
    imgui.PopStyleColor()
    imgui.EndChild()
end

function renderBinderTab()
    -- Получаем доступное пространство внутри вкладки
    local avail = imgui.GetContentRegionAvail()
    -- Левая панель: минимум 200 пикселей, иначе 30% от ширины
    local listWidth = math.max(avail.x * 0.3, 200)
    -- Правая панель: остаток минус отступ между панелями
    local editorWidth = avail.x - listWidth - imgui.GetStyle().ItemSpacing.x

    -- Левая панель (список)
    imgui.BeginChild("BindsListPanel", imgui.ImVec2(listWidth, -1), true)
    

    
    imgui.Text(u8("Поиск:"))
    imgui.InputText("##search", searchBuf, 64)
    imgui.Separator()
    imgui.Spacing()
    if createStyledButton("+ Новый", -1, 30, true) then
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
        imgui.TextColored(imgui.ImVec4(0.70, 0.70, 0.70, 1.00), u8("Нет биндов"))
    else
        -- Внутренний child для прокрутки списка
        imgui.BeginChild("ScrollingBinds", imgui.ImVec2(0, 0), false)
        for _, idx in ipairs(filteredIndices) do
            local bind = binds[idx]
            local isSelected = (selectedBindIndex == idx)
            if isSelected then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.85, 0.18, 0.18, 0.6))
            else
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.2, 0.2, 0.6))
            end
            if imgui.Button(bind.name or "Без названия", imgui.ImVec2(-1, 30)) then
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
                imgui.Text(u8("Команда: " .. (bind.cmd and "/"..bind.cmd or "нет")))
                imgui.Text(u8("Шагов: " .. #(bind.steps or {})))
                if bind.key and bind.key ~= 0 then
                    imgui.Text(u8("Клавиша: " .. getKeyName(bind.key, bind.key_mod)))
                end
                imgui.EndTooltip()
            end
        end
        imgui.EndChild()
    end
    
    imgui.EndChild() -- закрываем левую панель

    -- Размещаем следующую панель рядом
    imgui.SameLine()

    -- Правая панель (редактор)
    imgui.BeginChild("BindEditorPanel", imgui.ImVec2(editorWidth, -1), true)
    
    if selectedBindIndex then
        imgui.Text(u8("Редактирование бинда"))
    else
        imgui.Text(u8("Создание нового бинда"))
    end
    imgui.Separator()
    imgui.Spacing()
    imgui.Text(u8("Название:"))
    imgui.InputText("##editname", editNameBuf, 256)
    imgui.Spacing()
    imgui.Text(u8("Команда (с /):"))
    imgui.InputText("##editcmd", editCmdBuf, 64)
    imgui.Spacing()
    imgui.Text(u8("Горячая клавиша:"))
    local keyLabel = getKeyName(editKeyBuf[0], editKeyModBuf[0])
    if imgui.Button(u8(keyLabel), imgui.ImVec2(200, 0)) then
        tempKey = editKeyBuf[0]
        tempMod = editKeyModBuf[0]
        waitingForKey = true
        keyBindContext = "bind"
        keyBindPopupActive = true
    end
    imgui.Spacing()
    imgui.Text(u8("Задержка между шагами (мс):"))
    imgui.InputInt("##editdelay", editDelayBuf, 100, 500)
    if editDelayBuf[0] < 100 then editDelayBuf[0] = 100 end
    imgui.Spacing()
    imgui.Text(u8("Шаги (каждая строка - отдельное действие):"))
    imgui.TextWrapped(u8("Используйте {имя} для подстановки аргументов, [число] для паузы."))
    imgui.InputTextMultiline("##editsteps", editStepsBuf, 4096, imgui.ImVec2(-1, 200), imgui.InputTextFlags.None)
    imgui.Spacing()
    if createStyledButton("Сохранить", 100, 32, true) then
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
            sampAddChatMessage("[Snatch Helper] Бинд сохранен", 0x00FF00)
        else
            sampAddChatMessage("[Snatch Helper] Заполните название и шаги!", 0xFF0000)
        end
    end
    imgui.SameLine()
    if createStyledButton("Выполнить", 100, 32) then
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
    if selectedBindIndex and createStyledButton("Удалить", 100, 32) then
        deleteConfirmation.active = true
        deleteConfirmation.index = selectedBindIndex
    end

    -- Окно подтверждения удаления
    if deleteConfirmation.active then
        imgui.OpenPopup(u8("Подтверждение удаления"))
    end
    if imgui.BeginPopupModal(u8("Подтверждение удаления"), nil, imgui.WindowFlags.AlwaysAutoResize) then
        imgui.Text(u8("Вы уверены, что хотите удалить этот бинд?"))
        imgui.Separator()
        if imgui.Button(u8("Да"), imgui.ImVec2(80,0)) then
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
                sampAddChatMessage("[Snatch Helper] Бинд удален", 0x00FF00)
            end
            deleteConfirmation.active = false
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button(u8("Нет"), imgui.ImVec2(80,0)) then
            deleteConfirmation.active = false
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end

    imgui.EndChild() -- закрываем правую панель
end

function renderSettingsTab()
    createStyledHeader("Настройки интерфейса", "large")
    imgui.Spacing()
    createStyledSeparator()
    imgui.Spacing()
    local changed = false

    -- Задержка по умолчанию
    imgui.Text(u8("Задержка по умолчанию для новых биндов (мс):"))
    local defaultDelayVal = imgui.new.int(settings.defaultDelay)
    if imgui.InputInt("##defaultDelay", defaultDelayVal, 100, 500) then
        settings.defaultDelay = defaultDelayVal[0]
        if settings.defaultDelay < 100 then settings.defaultDelay = 100 end
        changed = true
    end
    imgui.Spacing()

    -- Цветовая тема
    imgui.Text(u8("Цветовая тема:"))
    local themeIndex = imgui.new.int(0)
    if settings.currentTheme == "dark" then themeIndex[0] = 1
    elseif settings.currentTheme == "light" then themeIndex[0] = 2
    elseif settings.currentTheme == "green" then themeIndex[0] = 3
    elseif settings.currentTheme == "blue" then themeIndex[0] = 4
    else themeIndex[0] = 0 end
    local themeNames = {u8"По умолчанию", u8"Тёмная", u8"Светлая", u8"Зелёная", u8"Синяя"}
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

    -- Клавиша остановки бинда
    imgui.Text(u8("Клавиша остановки бинда (по умолчанию F12):"))
    local stopKeyLabel = getKeyName(settings.stopKey, settings.stopKeyMod)
    if imgui.Button(u8(stopKeyLabel), imgui.ImVec2(200, 0)) then
        tempKey = settings.stopKey
        tempMod = settings.stopKeyMod
        waitingForKey = true
        keyBindContext = "stop"
        keyBindPopupActive = true
    end
    imgui.Spacing()

    -- Клавиша селектора игрока
    imgui.Text(u8("Клавиша селектора игрока (по умолчанию Alt):"))
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


-- Окна справочника (прежние)
local menuData = {
    [1] = { title = "Основания задержания", content = [[Как называть: Задержаны на основании пункта X, статьи 1, раздела 2, части 1 Процессуального Кодекса.\nЛибо словами, пример: Задержаны в связи с нарушением устава МЮ.\n\nA. Совершение гражданином дорожного или уголовного проступка\nB. Нахождение гражданина в маске, скрывающей лицо\nC. Гражданин ведёт себя подозрительно, вызывающе, агрессивно\nD. Имеется предположение, что лицо находится под алкоголем или наркотиками\nE. Проведение проверки документов гражданина\nF. Гражданин пересекает организованные блокпосты\nG. Гражданин находится поблизости от места преступления и мог быть свидетелем\nH. Нарушение устава или ФП от госника\nI. В период введения военного положения]] },
    [2] = { title = "Порядок задержания", content = [[1) Идентифицировать себя, показать ксиву по требованию\n2) Провести необходимые действия в зависимости от ситуации:\n   - Затребовать документы\n   - Провести опрос\n   - Обыск при наличии оснований\n   - Потребовать покинуть ТС\n   - Потребовать переместиться\n   - Надеть наручники, но после снять\n   - Провести арест при наличии оснований]] },
    [3] = { title = "Основания ареста", content = [[Арестованы на основании пункта X, статьи 3, раздела 2, части 1 Процессуального Кодекса.\n\nA. Лицо застигнуто на месте совершения дорожного или уголовного преступления\nB. В случае если преступник скрылся - его можно арестовать в течении 12 часов без КФ\nC. Лицо находится в федеральном розыске\nD. На арестовываемого имеется действующий ордер на арест\nE. Проведение проверки документов гражданина\nF. Игнорирование в течении 24 часов требования о явке на допрос\nG. Транспортировка на допрос]] },
    [4] = { title = "Порядок ареста", content = [[1) Надеть наручники\n2) Идентифицировать себя и показать ксиву при запросе, если этого не сделали раньше\n3) Сообщить основания для ареста. ВАЖНО: При аресте по УК/ДК - назвать статью (номер или название)\n4) Узнать в рамках РП личность арестованного, если не узнали ранее.\n5) Обыск\n6) Миранда\n7) Выдача розыска, если не выдали ранее\n8) Транспортировка в КПЗ или допросную\n9) Посадка в КПЗ при необходимости\n\nИСКЛЮЧЕНИЕ: В случае опасности, можно сначала перевести и только потом начать с пункта 2.\nИСКЛЮЧЕНИЕ: Миранду и розыск можно выдать во время транспортировки.\nИСКЛЮЧЕНИЕ: Миранду можно зачитать до установления личности.]] },
    [5] = { title = "Порядок ареста гос. сотрудника", content = [[1) По усмотрению выдать розыск с причиной 'СЛЕДСТВИЕ'\n2) Если арестованного передали копы - получение от них доказательств\n3) Миранда\n4) Обыск\n5) Везёте на допрос по своему усмотрению\n6) По окончанию процессуальных действий выбираете меру наказания\n7) Если применён арест в КПЗ, в течении 24 часов составляете КФ на форум]] },
    [6] = { title = "Основания допроса", content = [[Допрос проводится на основании пункта X, статьи 1, раздела 2, части 2 ПК.\n\nA. Допрос арестованного лица\nB. Ордер на проведение допроса\nC. Наличие оснований полагать, что у лица есть информация\nD. На лицо открыт КФ. По запросу предоставить материалы и опубликовать КФ на форуме в течении 24 часов\nE. Повестка на допрос, опубликованная на форуме]] },
    [7] = { title = "Порядок проведения допроса", content = [[1) Усадить человека на стул, одну руку приковать к столу, вторую оставить свободной\n2) Включить камеру в допросной\n3) Назвать дату и время начала допроса. Пример: Допрос проводится 15 июля 2025 в 16:30\n4) Сообщить кто проводит допрос и назвать позывной. Пример: Допрос проводит агент Слоняра\n5) Указать кто допрашивается и в каком статусе (свидетель/подозреваемый/потерпевший). Пример: Допрашивает Том Круз как свидетель.\n6) Миранда\n7) Уточняем желает-ли допрашиваемый реализовать свои права. Если требует адвоката - /advokatdopros\n8) Если допрашиваем госника - по своему желанию можно уведомить его организацию. Лидер и зам имеют право присутствовать на допросе.\n9) Уведомляем адвоката, допрашиваемого и его лидера/зама об ответственности за разглашение гос.тайны\nОт адвоката и лидера/зама обязательно требуем подписать уведомление, при отказе - выгоняем с допросной.\n11) Задаём вопросы, которые считаем нужным\n12) В конце допроса оповещаем о завершении допроса и выключаем камеру.\n13) Выводим допрашиваемого, его лидера/зама и адвоката с мешком на голове из офиса. При необходимости отвозим в КПЗ.]] },
    [8] = { title = "Адвокат на допросе", content = [[При поступлении требования - запрашиваем адвоката в /d у правительства. Если в течении 5 минут...\n...с момента ПЕРВОГО запроса ответа не последовало - продолжаем без адвоката. Аналогично делаем при отрицательном ответе.\nЕсли адвокат вышел на связь - ждём пока он приедет в течении 10 минут. По истечении этого времени - продолжаем без адвоката.\nПри прибытии адвоката проверяем у него паспорт, наличие лицензии и 5+ ранга в правительстве.\nПеред заводом в офис обыскиваем и отбираем у адвоката телефон, камеру, диктофон и т.п., надеваем мешок.\nЕсли у адвоката нашли запрещёнку - арестовываем адвоката.\nАдвокат имеет право на приватные беседы. Общая их продолжительность - 20 минут.]] },
    [9] = { title = "Основания для обыска", content = [[Обыск на основании пункта X, статьи 1, раздела 3, части 1 ПК\n\nA. Ордер\nB. Арест\nC. Проведение рейда\nD. Контроль на блокпостах\nE. Вход в зону оцепления\nF. Вход на территорию режимного объекта\nG. Добровольное согласие на обыск\nH. Задержание в связи с ношением гражданином маски\nI. Задержание госника в связи с нарушением устава или ФП\nK. Задержание в случае, если есть основания предполагать, что задержанный совершил преступление\nL. Задержание в случае, если задержанный употребил нарко или алкоголь на глазах агента\nM. Проведение проверки гос организации\n\nВАЖНО: Обыск делается В ПЕРЧАТКАХ!]] },
    [10] = { title = "Основания для рейдов", content = [[Рейд ГЕТТО - Статья 2, раздел 5, части 2 ПК. [Нужен ордер]\nРейд ПРИТОНА - Статья 3, раздел 5, части 2 ПК\nРейд ОПГ - Статья 4, раздел 5, части 2 ПК [Нужен ордер]\nРейд СТО - Статья 5, раздел 5, части 2 ПК\nРейд ГРУЗОПЕРЕВОЗОК - Статья 6, раздел 5, части 2 ПК [Нужен ордер]\nРейд ПАТРУЛЕЙ - Статья 7, раздел 5, части 2 ПК\nРейд ЛАВОК ЦР/ЦГ - Статья 8, раздел 5, части 2 ПК\nРейд ГОС.ОРГ - Статья 9, раздел 5, части 2 ПК [Нужен ордер]\nРейд НАРКОТРАФИКА - Статья 10, раздел 5, части 2 ПК]] },
    [11] = { title = "Основания правил безопасности", content = [[6 метров - статья 1, раздел 5, части 1 ПК\n3 поворота - статья 1, раздел 5, части 1 ПК]] }
}

for i = 1, 11 do
    imgui.OnFrame(
        function() return showMenu[i][0] end,
        function()
            imgui.SetNextWindowSize(imgui.ImVec2(520, 480), imgui.Cond.FirstUseEver)
            imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
            local title = menuData[i] and menuData[i].title or ("Информация " .. i)
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
            if createStyledButton("Закрыть", 100, 32, true) then
                showMenu[i][0] = false
            end
            imgui.End()
        end
    )
end

-- Окно пасхалки
imgui.OnFrame(
    function() return showEasterEgg[0] end,
    function()
        imgui.SetNextWindowSize(imgui.ImVec2(520, 420), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.Begin(u8("Пасхалка"), showEasterEgg, imgui.WindowFlags.NoCollapse)
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
            imgui.TextWrapped(u8("Чтобы добавить картинку, поместите файл 'image.png' в папку:"))
            imgui.TextColored(imgui.ImVec4(0.95, 0.75, 0.35, 1.00), u8("   " .. configDirectory))
            imgui.PopTextWrapPos()
            imgui.PopStyleColor()
            imgui.EndChild()
        end
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        imgui.SetCursorPosX((imgui.GetWindowWidth() - 100) / 2)
        if createStyledButton("Закрыть", 100, 32, true) then
            showEasterEgg[0] = false
        end
        imgui.End()
    end
)

-- ==================== УМНАЯ ВЫДАЧА ВЫГОВОРА ====================
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
                    print('[Snatch Helper] Загружено уставов: ' .. #ustav_data)
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
    sampSendChat("/do КПК находится на поясном держателе.")
    wait(1500)
    sampSendChat("/me берёт в руки свой КПК и включает его")
    wait(1500)
    sampSendChat("/me заходит в базу данных и переходит в раздел управление сотрудниками других организаций")
    wait(1500)
    sampSendChat("/me открывает дело нужного сотрудника и вносит в него изменения")
    wait(1500)
    sampSendChat("/do Изменения успешно сохранены.")
    wait(1500)
    sampSendChat("/me выходит с базы данных и выключив КПК убирает его на поясной держатель")
    wait(1500)
    local command = string.format("/me %d %s", playerId, reason)
    print("[Snatch Helper] Отправляется команда: " .. command)
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
        imgui.Begin(u8("Выбор устава для выговора"), SumMenuWindow, imgui.WindowFlags.NoCollapse)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.11,0.42,0.87,1))
        imgui.TextWrapped(u8("Выдача специального выговора"))
        imgui.PopStyleColor()
        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
        imgui.Text(u8("ID игрока: " .. tostring(selectedPlayerId)))
        imgui.Text(u8("Имя игрока: " .. selectedPlayerName))
        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
        imgui.Text(u8("Выберите устав:"))
        imgui.Spacing()
        if #ustav_data == 0 then
            imgui.TextColored(imgui.ImVec4(0.9,0.2,0.2,1), u8("Уставы не загружены!"))
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
        if createStyledButton("Отмена", 100, 32) then SumMenuWindow[0] = false end
        imgui.End()
    end
)

for idx, ustav in ipairs(ustav_data) do
    imgui.OnFrame(
        function() return showUstavMenu[idx][0] end,
        function()
            imgui.SetNextWindowSize(imgui.ImVec2(1500,700), imgui.Cond.FirstUseEver)
            imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2,sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
            imgui.Begin(u8(ustav.name .. " - выбор пункта"), showUstavMenu[idx], imgui.WindowFlags.NoCollapse)
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.11,0.42,0.87,1))
            imgui.TextWrapped(u8(ustav.name .. " - выбор пункта"))
            imgui.PopStyleColor()
            if not ustav.item or #ustav.item == 0 then
                imgui.TextColored(imgui.ImVec4(0.9,0.2,0.2,1), u8("Пункты не загружены!"))
            else
                imgui.BeginChild("UstavItems", imgui.ImVec2(0,0), true)
                for i, item in ipairs(ustav.item) do
                    local btnText = item.reason or "Пункт "..i
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
            if createStyledButton("Назад", 100, 32) then
                showUstavMenu[idx][0] = false
                SumMenuWindow[0] = true
            end
            imgui.End()
        end
    )
end

-- ==================== УМНАЯ ВЫДАЧА РОЗЫСКА ====================
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
                    print('[Snatch Helper] Загружено разделов УК: ' .. #uk_data)
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
    sampSendChat("/do КПК находится на поясном держателе.")
    wait(1500)
    sampSendChat("/me берёт в руки свой КПК и включает его")
    wait(1500)
    sampSendChat("/me заходит в базу данных и переходит в раздел федерального розыска")
    wait(1500)
    sampSendChat("/me открывает розыскное дело и вносит в него изменения")
    wait(1500)
    sampSendChat("/do Изменения успешно сохранены.")
    wait(1500)
    sampSendChat("/me выходит с базы данных и выключив КПК убирает его на поясной держатель")
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
        imgui.Begin(u8("Умная выдача розыска"), WantedMenuWindow, imgui.WindowFlags.NoCollapse)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.87,0.11,0.11,1))
        imgui.TextWrapped(u8("Выдача федерального розыска по статьям УК"))
        imgui.PopStyleColor()
        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
        imgui.Text(u8("ID игрока: " .. tostring(selectedWantedPlayerId)))
        imgui.Text(u8("Имя игрока: " .. selectedWantedPlayerName))
        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
        imgui.Text(u8("Выберите раздел Уголовного Кодекса:"))
        imgui.Spacing()
        if #uk_data == 0 then
            imgui.TextColored(imgui.ImVec4(0.9,0.2,0.2,1), u8("Разделы УК не загружены!"))
        else
            for i, name in ipairs(uk_names) do
                if imgui.CollapsingHeader(u8(name)) then
                    imgui.Indent(20)
                    local section = uk_data[i]
                    if section and section.item then
                        for j, item in ipairs(section.item) do
                            local btnText = item.reason or "Статья "..j
                            if item.reason and item.text then
                                local text = item.text:len() > 120 and item.text:sub(1,120).."..." or item.text
                                btnText = item.reason .. " - " .. text
                            end
                            if item.lvl then btnText = btnText .. " (Ур."..item.lvl..")" end
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
        if createStyledButton("Отмена", 100, 32, true) then WantedMenuWindow[0] = false end
        imgui.End()
    end
)

-- ==================== ЗАГРУЗКА ТЕКСТУРЫ ПАСХАЛКИ ====================
imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    setup_premium_style(settings.currentTheme)
    local imgPath = configDirectory .. "/image.png"
    if doesFileExist(imgPath) then
        local ok, tex = pcall(imgui.CreateTextureFromFile, imgPath)
        if ok and tex then easterEggTexture = tex end
    end
end)

-- ==================== ОСНОВНОЙ ЦИКЛ ====================
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
                    sampAddChatMessage('[Snatch Helper] Игрок не найден!', message_color)
                    return
                end
                if #ustav_data == 0 then
                    sampAddChatMessage('[Snatch Helper] Уставы не загружены!', message_color)
                    return
                end
                SumMenuWindow[0] = true
            else
                sampAddChatMessage('[Snatch Helper] Используйте /gw [ID игрока] (ID должен быть положительным числом)', message_color)
            end
        else
            sampAddChatMessage('[Snatch Helper] Дождитесь завершения отыгровки!', message_color)
        end
    end)

    sampRegisterChatCommand("uk", function(arg)
        if not isActiveWantedCommand then
            local id = tonumber(arg)
            if id and id > 0 then
                selectedWantedPlayerId = id
                selectedWantedPlayerName = getPlayerNameById(selectedWantedPlayerId)
                if selectedWantedPlayerName == "ID_"..selectedWantedPlayerId then
                    sampAddChatMessage('[Snatch Helper] Игрок не найден!', message_color)
                    return
                end
                if #uk_data == 0 then
                    sampAddChatMessage('[Snatch Helper] Разделы УК не загружены!', message_color)
                    return
                end
                WantedMenuWindow[0] = true
            else
                sampAddChatMessage('[Snatch Helper] Используйте /uk [ID игрока] (ID должен быть положительным числом)', message_color)
            end
        else
            sampAddChatMessage('[Snatch Helper] Дождитесь завершения отыгровки!', message_color)
        end
    end)

    sampAddChatMessage("{ff0000}[Snatch Helper] {ff4444}Скрипт загружен (v5.2)")
    sampAddChatMessage("{ff0000}[Snatch Helper] {ff4444}Умная выдача выговора: /gw")
    sampAddChatMessage("{ff0000}[Snatch Helper] {ff4444}Умная выдача розыска: /uk")
    sampAddChatMessage("{ff0000}[Snatch Helper] {ff4444}Справочник и биндер: F3")
    sampAddChatMessage("{ff0000}[Snatch Helper] {ff4444}Удачной смены!")

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
        -- Стоп-клавиша
        local stopPressed = false
        if settings.stopKeyMod == 0 then stopPressed = wasKeyPressed(settings.stopKey)
        elseif settings.stopKeyMod == 1 then stopPressed = isKeyDown(0x11) and wasKeyPressed(settings.stopKey)
        elseif settings.stopKeyMod == 2 then stopPressed = isKeyDown(0x10) and wasKeyPressed(settings.stopKey)
        elseif settings.stopKeyMod == 3 then stopPressed = isKeyDown(0x12) and wasKeyPressed(settings.stopKey) end
        if stopPressed and activeBinder then
            stopCurrentBind = true
            sampAddChatMessage("[Snatch Helper] Бинд остановлен", 0xFF0000)
        end

        -- Горячие клавиши биндов (не работают при открытом чате)
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

        -- Селектор
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