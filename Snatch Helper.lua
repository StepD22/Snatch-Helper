---@diagnostic disable: undefined-global, need-check-nil, lowercase-global, cast-local-type, unused-local
script_name("Snatch Helper")
script_description('')
script_author("StepD")
script_version("1.1")

require('lib.moonloader')

-- =========================================================================
-- CRASH HANDLER — создаём перехватчик ошибок
-- =========================================================================
pcall(function()
    local _chDir = getWorkingDirectory():gsub('\\','/')
    local _chPath = _chDir .. '/.SH_ErrorHandler.lua'
    if not doesFileExist(_chPath) then
        local f = io.open(_chPath,'w')
        if f then
            f:write([[
function onSystemMessage(msg, type, script)
    if script and script.name=='Snatch Helper' and msg then
        if msg:find('stack traceback') or (type==3 and not msg:find('warning')) then
            sampShowDialog(49321,'{FF4A58}Snatch Helper — Ошибка',
                '{ffffff}Скрипт упал из-за непредвиденной ошибки.\n\n'..
                '{ff9944}Детали:\n{ff6666}'..msg,
                '{FF4A58}Закрыть','',0)
        end
    end
end
]])
            f:close()
            os.execute('attrib +h "'..(_chPath:gsub('/','\\'))..'" 2>nul')
        end
    end
end)
local encoding = require('encoding')
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local ffi = require('ffi')
local imgui = require('mimgui')
local memory = require('memory')
local sampev = require('lib.samp.events')
local hasRequests, requests = pcall(require, 'requests')
local str = ffi.string
local sizeX, sizeY = getScreenResolution()

-- =========================================================================
-- КОНСТАНТЫ (в таблице для экономии locals)
-- =========================================================================
local C = {
    SCRIPT_VERSION       = "1.1",
    NOTIFICATION_DURATION = 4.5,
    NOTIFICATION_FADE    = 0.6,
    MAX_NOTIFICATIONS    = 6,
    MAX_ACTIVITY         = 50,
    MIN_DELAY            = 50,
    MAX_DELAY            = 60000,
    MIN_BIND_DURATION    = 5000,
    MAX_BIND_DURATION    = 600000,
    AUTO_BACKUP_INTERVAL = 300,
    MAX_HISTORY          = 100,
    MAX_PARTICLES        = 15,
    NOTIFY_INFO          = 1,
    NOTIFY_SUCCESS       = 2,
    NOTIFY_WARNING       = 3,
    NOTIFY_ERROR         = 4,
    NOTIFY_SYSTEM        = 5,
    NAV_DASHBOARD        = 0,
    NAV_BINDER           = 1,
    NAV_REFERENCE        = 2,
    NAV_SETTINGS         = 3,
    NAV_JOURNAL        = 4,
    NAV_NOTES          = 5,
    STATS_UPDATE_INTERVAL = 0.3,
    BIND_STATS_INTERVAL  = 1.0,
    ANIM_CLEANUP_INTERVAL = 30,
    ANIM_MAX_ENTRIES     = 400,
    MAX_BACKUP_FILES     = 20,
    CLOSEST_PLAYER_CACHE_TIME = 0.5,
    -- Клавиши
    KEY_F1  = 0x70, KEY_F2  = 0x71, KEY_F3  = 0x72, KEY_F4  = 0x73,
    KEY_F5  = 0x74, KEY_F6  = 0x75, KEY_F7  = 0x76, KEY_F8  = 0x77,
    KEY_F9  = 0x78, KEY_F10 = 0x79, KEY_F11 = 0x7A, KEY_F12 = 0x7B,
    KEY_ESC   = 0x1B, KEY_SHIFT = 0x10, KEY_CTRL  = 0x11, KEY_ALT   = 0x12,
    KEY_WM_KEYDOWN = 0x100, KEY_WM_SYSKEYDOWN = 0x104,
}

-- =========================================================================
-- СОСТОЯНИЕ (сгруппировано в таблицы)
-- =========================================================================
local S = {
    selectedDemoutePlayerId = 0,
    selectedDemoutePlayerName = "",
    selectedDismissPlayerId = 0,
    selectedDismissPlayerName = "",
    activeBinder = false,
    stopCurrentBind = false,
    registeredCommands = {},
    keyBindContext = nil,
    keyBindPopupActive = false,
    tempKey = 0,
    tempMod = 0,
    waitingForKey = false,
    deleteConfirmation = { active = false, index = nil },
    sessionStartTime = os.clock(),
    lastBindName = "",
    lastBindTime = 0,
    currentBindProgress = 0,
    currentBindTotal = 0,
    currentBindName = "",
    currentBindStartTime = 0,
    totalSessionBinds = 0,
    prevNav = 0,
    navTransition = 1.0,
    sidebarWidth = 160,
    sidebarExpandedWidth = 160,
    headerHeight = 56,
    contentPadding = 30,
    lastAutoBackup = os.clock(),
    contextMenuData = nil,
    dragBindIdx = nil,
    dragTargetIdx = nil,
    currentProfile = "default",
    profiles = { "default" },
    selectedBindIndex = nil,
    selectedUstavIdx = 0,
    selectedPlayerId = 0,
    selectedPlayerName = "",
    selectedWantedPlayerId = 0,
    selectedWantedPlayerName = "",
    membersOverlayVisible = false,
    animCleanupTimer = 0,
    lastFpsUpdate = 0,
    lastStatsUpdate = 0,
    lastBindStatsUpdate = 0,
    journalFilter = "all",
    lastSavedState = nil,
    hasUnsavedChanges = false,
    showUnsavedConfirm = false,
    unsavedAction = nil, -- {type="select"|"create"|"close", idx=N}
    lastChangeCheck = 0,
    overlayDebounceSave = 0,
    isCreatingNew = false,
    stopSentTime = 0,  -- время нажатия стоп клавиши, для принудительного сброса
    -- Индексы вкладок окон действий (перенесены из chunk-locals)
    gwarnTabIdx   = 0,
    demouteTabIdx = 0,
    dismissTabIdx = 0,
    -- Таймер повтора Members если список пуст
    membersRetryAt = 0,
    -- Состояние фокуса поля шагов биндера
    _stepsFieldActive = false,
    -- Флаг нажатой кнопки мыши для текущего кадра (для checkKeyCombo)
    _mouseJustPressed = 0,
    -- Таймер автосохранения бинда (debounce)
    autoSaveTimer = 0,
}

-- B = Buffers
local B = {
    editNameBuf      = ffi.new("char[256]"),
    editCmdBuf       = ffi.new("char[64]"),
    editStepsBuf     = ffi.new("char[32768]"),
    editDelayBuf     = ffi.new("int[1]", 1500),
    editKeyBuf       = ffi.new("int[1]", 0),
    editKeyModBuf    = ffi.new("int[1]", 0),
    editCooldownBuf  = ffi.new("int[1]", 0),
    editEnabledBuf   = imgui.new.bool(true),
    editCategoryBuf  = imgui.new.int(0),
    editFavoriteBuf  = imgui.new.bool(false),
    editDescBuf      = ffi.new("char[512]"),
    notesBuf         = ffi.new("char[65536]"),
    notesLoaded      = false,
    -- Буферы QA-редактора бинда
    qaNameBuf        = ffi.new("char[256]"),
    qaStepsBuf       = ffi.new("char[32768]"),
    qaDelayBuf       = ffi.new("int[1]", 1500),
    _qaEditorLoaded  = false,
    -- Кэш-буферы для настроек (ФИКС 9: не пересоздаём каждый кадр)
    setDefaultDelay  = ffi.new("int[1]", 1500),
    setMaxDuration   = ffi.new("int[1]", 60000),
    setAfInterval    = ffi.new("int[1]", 2000),
    setAfDist        = ffi.new("int[1]", 50),
    setMariInterval  = ffi.new("int[1]", 60000),
    uiScaleBuf       = ffi.new("float[1]", 1.0),
    rpWeaponDelayBuf = ffi.new("int[1]", 600), -- legacy, не используется
    _settingsBufsSync = false,
    -- Буферы поиска для окон действий (перенесены из chunk-locals)
    gwarnSearch  = ffi.new("char[128]"),
    wantedSearch = ffi.new("char[128]"),
    demSearch    = ffi.new("char[128]"),
    disSearch    = ffi.new("char[128]"),
}

local currentNav = imgui.new.int(0)
local U = {}

-- Members Overlay
local membersOverlay = {
    list = {},
    fraction = "",
    isChecking = false,
    showWindow = false,
    lastUpdate = 0,
    cachedW = 200,
    dragActive = false,
    tempList = {},
    _parseFailCount = 0,   -- счётчик подряд неудачных парсов
    _checkStartTime = nil,
}

-- Доп. данные для дашборда
local dashData = {
    fpsHistory = {},
    pingHistory = {},
    cachedStats = nil,
    cachedBindStats = nil,
    _ringMaxFPS = 30,
    _ringIdxFPS = 0,
    _ringSizeFPS = 0,
}
-- Хелпер: возвращает ring-буфер в хронологическом порядке (для sparkline)
local function getRingBuffer(buf, head, size)
    local out = {}
    if size == 0 then return out end
    local cap = #buf
    for i = 0, size - 1 do
        local idx = ((head - size + i) % cap) + 1
        out[i + 1] = buf[idx] or 0
    end
    return out
end

local textures = { logo = nil, avatar = nil }

-- =========================================================================
-- PADDING ФУНКЦИИ
-- =========================================================================
local function setWindowPadding(x, y)
    imgui.GetStyle().WindowPadding = imgui.ImVec2(x, y)
end

local function pushWindowPadding(x, y)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(x, y))
end

local forceWindowPadding = pushWindowPadding

local function pushPadding(x, y)
    local s = imgui.GetStyle()
    local prev = imgui.ImVec2(s.WindowPadding.x, s.WindowPadding.y)
    pushWindowPadding(x, y)
    return prev
end

-- =========================================================================
-- СИСТЕМА АНИМАЦИЙ
-- =========================================================================
local anims = {}
local anims_count = 0
local function anim(id, target, speed)
    speed = speed or 0.10
    if anims[id] == nil then anims[id] = target; anims_count = anims_count + 1 end
    anims[id] = anims[id] + (target - anims[id]) * speed
    if math.abs(anims[id] - target) < 0.001 then anims[id] = target end
    return anims[id]
end

local function animBool(id, condition, speed)
    return anim(id, condition and 1 or 0, speed or 0.12)
end

local _colorAnimTargets = {}
local function animColor(id, target, speed)
    speed = speed or 0.10
    _colorAnimTargets[id] = { r = target.x, g = target.y, b = target.z, a = target.w }
    return imgui.ImVec4(
        anim(id.."_r", target.x, speed),
        anim(id.."_g", target.y, speed),
        anim(id.."_b", target.z, speed),
        anim(id.."_a", target.w, speed)
    )
end

local function animSpring(id, target, stiffness, damping)
    stiffness = stiffness or 0.15
    damping = damping or 0.75
    local key_v = id .. "_vel"
    local key_p = id .. "_pos"
    if anims[key_p] == nil then anims[key_p] = target; anims[key_v] = 0; anims_count = anims_count + 2 end
    local force = (target - anims[key_p]) * stiffness
    anims[key_v] = (anims[key_v] + force) * damping
    anims[key_p] = anims[key_p] + anims[key_v]
    if math.abs(anims[key_p] - target) < 0.001 and math.abs(anims[key_v]) < 0.001 then
        anims[key_p] = target; anims[key_v] = 0
    end
    return anims[key_p]
end

-- Очистка анимаций (УЛУЧШЕНИЕ #6)
local function cleanupAnims()
    if anims_count <= C.ANIM_MAX_ENTRIES then return end
    local toRemove = {}
    for k, v in pairs(anims) do
        if type(k) == "string" then
            if k:sub(-4) == "_vel" and math.abs(v) < 0.001 then
                local posKey = k:sub(1, -5) .. "_pos"
                table.insert(toRemove, k)
                table.insert(toRemove, posKey)
            end
        end
    end
    -- Чистка записей цветовых анимаций (_r/_g/_b/_a)
    for baseId, tgt in pairs(_colorAnimTargets) do
        local kr = anims[baseId.."_r"]
        local kg = anims[baseId.."_g"]
        local kb = anims[baseId.."_b"]
        local ka = anims[baseId.."_a"]
        if kr ~= nil
        and math.abs(kr - tgt.r) < 0.001
        and math.abs(kg - tgt.g) < 0.001
        and math.abs(kb - tgt.b) < 0.001
        and math.abs(ka - tgt.a) < 0.001 then
            anims[baseId.."_r"] = nil; anims[baseId.."_g"] = nil
            anims[baseId.."_b"] = nil; anims[baseId.."_a"] = nil
            _colorAnimTargets[baseId] = nil
            anims_count = math.max(0, anims_count - 4)
        end
    end
    for _, k in ipairs(toRemove) do
        if anims[k] ~= nil then anims[k] = nil; anims_count = math.max(0, anims_count - 1) end
    end
    if anims_count > C.ANIM_MAX_ENTRIES * 1.5 then anims = {}; anims_count = 0; _colorAnimTargets = {} end
end

-- =========================================================================
-- УТИЛИТЫ
-- =========================================================================
local function trim(s) return s and s:gsub("^[%s%c]*", ""):gsub("[%s%c]*$", "") or "" end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function doesFileExistSafe(p)
    if not p or p == "" then return false end
    local ok, r = pcall(doesFileExist, p); return ok and r
end

local function ensureDirectory(p)
    if not p or p == "" then return false end
    local ok, _ = pcall(function() if not doesDirectoryExist(p) then createDirectory(p) end end)
    return ok
end

local _idSeq = 0
local function generateId()
    _idSeq = _idSeq + 1
    return string.format("%x%x%x%x", os.time(), _idSeq, math.random(0, 0xFFFF), math.random(0, 0xFF))
end

local function deepCopy(t, _seen)
    if type(t) ~= "table" then return t end
    _seen = _seen or {}; if _seen[t] then return _seen[t] end
    local c = {}; _seen[t] = c
    for k, v in pairs(t) do c[deepCopy(k, _seen)] = deepCopy(v, _seen) end
    return setmetatable(c, getmetatable(t))
end

local function lerp(a, b, t) return a + (b - a) * clamp(t, 0, 1) end

local function lerpColor(c1, c2, t)
    t = clamp(t, 0, 1)
    return imgui.ImVec4(lerp(c1.x,c2.x,t), lerp(c1.y,c2.y,t), lerp(c1.z,c2.z,t), lerp(c1.w,c2.w,t))
end

local function ImVec4toU32(c, a)
    a = a or c.w
    return clamp(math.floor(a*255),0,255)*16777216
        + clamp(math.floor(c.z*255),0,255)*65536
        + clamp(math.floor(c.y*255),0,255)*256
        + clamp(math.floor(c.x*255),0,255)
end

local function formatTime(s)
    local h = math.floor(s/3600); local m = math.floor((s%3600)/60); local sec = math.floor(s%60)
    if h > 0 then return string.format("%dч %dм %dс", h, m, sec) end
    if m > 0 then return string.format("%dм %dс", m, sec) end
    return string.format("%dс", sec)
end

local function formatTimeShort(s)
    local m = math.floor(s/60); local sec = math.floor(s%60)
    return string.format("%d:%02d", m, sec)
end

local function safeFormat(fmt, ...)
    local ok, r = pcall(string.format, fmt, ...); return ok and r or tostring(fmt)
end

local function safeSendChat(text)
    if not text or text == "" then return false end
    local ok, _ = pcall(sampSendChat, text); return ok
end

-- Easing (в таблице — УЛУЧШЕНИЕ)
local ease = {
    outCubic = function(t) return 1 - (1 - clamp(t,0,1))^3 end,
    inOutCubic = function(t) t = clamp(t,0,1); if t < 0.5 then return 4*t*t*t end; return 1 - (-2*t+2)^3/2 end,
    outBack = function(t) t = clamp(t,0,1); local c1 = 1.70158; local c3 = c1+1; return 1+c3*(t-1)^3+c1*(t-1)^2 end,
    outQuart = function(t) return 1 - (1 - clamp(t,0,1))^4 end,
}

local function getPlayerStats()
    local s = { hp = 0, armor = 0, weapon = 0, fps = 0, online = 0, myId = -1, ping = 0, score = 0, nick = "Player" }
    pcall(function()
        if not playerPed then return end
        local _, id = sampGetPlayerIdByCharHandle(playerPed)
        if id then
            s.myId = id
            s.hp = sampGetPlayerHealth(id) or 0
            s.armor = sampGetPlayerArmor(id) or 0
            s.ping = sampGetPlayerPing(id) or 0
            s.score = sampGetPlayerScore(id) or 0
            s.nick = sampGetPlayerNickname(id) or "Player"
        end
        s.weapon = getCurrentCharWeapon(playerPed) or 0
        local fp = memory.getfloat(0xB7CB50, true)
        s.fps = fp and math.floor(fp) or 0
        s.online = sampGetPlayerCount(false) or 0
    end)
    return s
end

local function getCachedPlayerStats()
    local now = os.clock()
    if not dashData.cachedStats or (now - S.lastStatsUpdate) > C.STATS_UPDATE_INTERVAL then
        dashData.cachedStats = getPlayerStats()
        S.lastStatsUpdate = now
    end
    return dashData.cachedStats
end

-- =========================================================================
-- УВЕДОМЛЕНИЯ
-- =========================================================================
local notifications = {}
local notifyColors = {
    [C.NOTIFY_INFO]    = imgui.ImVec4(0.35, 0.70, 1, 1),
    [C.NOTIFY_SUCCESS] = imgui.ImVec4(0.25, 0.92, 0.50, 1),
    [C.NOTIFY_WARNING] = imgui.ImVec4(1, 0.82, 0.25, 1),
    [C.NOTIFY_ERROR]   = imgui.ImVec4(1, 0.30, 0.30, 1),
    [C.NOTIFY_SYSTEM]  = imgui.ImVec4(0.72, 0.52, 1, 1),
}
-- SVG-иконки для уведомлений, рисуются через DrawList
-- каждая функция принимает (dl, cx, cy, r, col, alpha)
U.notifyIconDrawers = {
    [C.NOTIFY_INFO] = function(dl, cx, cy, r, col, a)
        -- Круг с точкой и палочкой (i)
        dl:AddCircle(imgui.ImVec2(cx,cy), r, ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a*0.5)), 16, 1.2)
        dl:AddCircleFilled(imgui.ImVec2(cx, cy-r*0.35), r*0.18, ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a)), 8)
        dl:AddRectFilled(imgui.ImVec2(cx-r*0.14, cy-r*0.10), imgui.ImVec2(cx+r*0.14, cy+r*0.42), ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a)), 1)
    end,
    [C.NOTIFY_SUCCESS] = function(dl, cx, cy, r, col, a)
        -- Галочка
        dl:AddCircleFilled(imgui.ImVec2(cx,cy), r, ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a*0.15)), 16)
        local c = ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a))
        dl:AddLine(imgui.ImVec2(cx-r*0.45, cy+r*0.05), imgui.ImVec2(cx-r*0.05, cy+r*0.42), c, 1.8)
        dl:AddLine(imgui.ImVec2(cx-r*0.05, cy+r*0.42), imgui.ImVec2(cx+r*0.45, cy-r*0.30), c, 1.8)
    end,
    [C.NOTIFY_WARNING] = function(dl, cx, cy, r, col, a)
        -- Треугольник с восклицательным
        local c = ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a))
        local cf = ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a*0.12))
        dl:AddTriangleFilled(imgui.ImVec2(cx, cy-r*0.52), imgui.ImVec2(cx-r*0.52, cy+r*0.40), imgui.ImVec2(cx+r*0.52, cy+r*0.40), cf)
        dl:AddTriangle(imgui.ImVec2(cx, cy-r*0.52), imgui.ImVec2(cx-r*0.52, cy+r*0.40), imgui.ImVec2(cx+r*0.52, cy+r*0.40), c, 1.2)
        dl:AddRectFilled(imgui.ImVec2(cx-r*0.12, cy-r*0.18), imgui.ImVec2(cx+r*0.12, cy+r*0.18), c, 1)
        dl:AddCircleFilled(imgui.ImVec2(cx, cy+r*0.30), r*0.13, c, 6)
    end,
    [C.NOTIFY_ERROR] = function(dl, cx, cy, r, col, a)
        -- Крест в круге
        dl:AddCircleFilled(imgui.ImVec2(cx,cy), r, ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a*0.15)), 16)
        local c = ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a))
        local s = r * 0.32
        dl:AddLine(imgui.ImVec2(cx-s, cy-s), imgui.ImVec2(cx+s, cy+s), c, 1.8)
        dl:AddLine(imgui.ImVec2(cx+s, cy-s), imgui.ImVec2(cx-s, cy+s), c, 1.8)
    end,
    [C.NOTIFY_SYSTEM] = function(dl, cx, cy, r, col, a)
        -- Звёздочка/шестерёнка (6 лучей)
        local c = ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a))
        dl:AddCircle(imgui.ImVec2(cx,cy), r*0.28, c, 12, 1.2)
        for k = 0, 5 do
            local angle = (k/6)*math.pi*2
            local x1 = cx + math.cos(angle)*r*0.28*1.3
            local y1 = cy + math.sin(angle)*r*0.28*1.3
            local x2 = cx + math.cos(angle)*r*0.52
            local y2 = cy + math.sin(angle)*r*0.52
            dl:AddLine(imgui.ImVec2(x1,y1), imgui.ImVec2(x2,y2), c, 1.8)
        end
    end,
}

local function addNotification(text, ntype, duration)
    ntype = ntype or C.NOTIFY_INFO
    duration = duration or C.NOTIFICATION_DURATION
    -- ring-insert: new at end, remove oldest from front
    notifications[#notifications + 1] = { text = text, ntype = ntype, time = os.clock(), duration = duration }
    if #notifications > C.MAX_NOTIFICATIONS then
        for i = 1, #notifications - 1 do notifications[i] = notifications[i + 1] end
        notifications[#notifications] = nil
    end
end

-- =========================================================================
-- Утилита: копирование в буфер обмена (с PowerShell-фолбэком)
-- =========================================================================
-- Копирует CP1251 строку в буфер обмена как CF_UNICODETEXT через WinAPI
-- CP_ACP (0) = системная кодировка (CP1251 на русской Windows) ? UTF-16LE напрямую
local function setClipboardUnicode(cp1251str)
    local wlen = ffi.C.MultiByteToWideChar(0, 0, cp1251str, -1, nil, 0)
    if wlen == 0 then return false end
    local hmem = ffi.C.GlobalAlloc(0x0042, wlen * 2) -- GMEM_MOVEABLE | GMEM_ZEROINIT
    if hmem == nil then return false end
    local ptr = ffi.C.GlobalLock(hmem)
    if ptr == nil then
        ffi.C.GlobalFree(hmem)
        return false
    end
    ffi.C.MultiByteToWideChar(0, 0, cp1251str, -1, ffi.cast("wchar_t*", ptr), wlen)
    ffi.C.GlobalUnlock(hmem)
    if ffi.C.OpenClipboard(nil) == 0 then return false end
    ffi.C.EmptyClipboard()
    ffi.C.SetClipboardData(13, hmem) -- CF_UNICODETEXT = 13
    ffi.C.CloseClipboard()
    return true
end

local function copyToClipboard(text, successMsg)
    -- text в CP1251; MultiByteToWideChar с CP_ACP сам конвертирует корректно
    local pcallOk, result = pcall(setClipboardUnicode, text)
    local ok = pcallOk and (result == true)  -- учитываем false от WinAPI
    if not ok then
        ok = pcall(setClipboardText, text) -- SAMPFUNCS фолбэк
    end
    if ok then
        addNotification(successMsg or "Скопировано!", C.NOTIFY_SUCCESS)
    else
        addNotification("Ошибка копирования!", C.NOTIFY_ERROR)
    end
end

-- =========================================================================
-- РИСОВАНИЕ: ЭФФЕКТЫ
-- =========================================================================
local function drawShadow(dl, x1, y1, x2, y2, r, layers, intensity)
    layers = layers or 3
    intensity = intensity or 0.6
    for i = 1, layers do
        local off = i * 4
        local a = 0.04 * intensity * (1 - i/(layers+1))
        dl:AddRectFilled(imgui.ImVec2(x1-off*0.3, y1+off*0.6),
            imgui.ImVec2(x2+off*0.3, y2+off),
            ImVec4toU32(imgui.ImVec4(0,0,0,a)), r+i)
    end
end

local function drawGlow(dl, x, y, radius, color, intensity)
    intensity = intensity or 1
    for i = 1, 2 do
        local r = radius + i * 6
        local a = 0.12 * intensity * (1 - i/3)
        dl:AddCircleFilled(imgui.ImVec2(x,y), r,
            ImVec4toU32(imgui.ImVec4(color.x,color.y,color.z,a)), 16)
    end
end

local function drawGlowRect(dl, x1, y1, x2, y2, color, intensity, r)
    intensity = intensity or 0.5; r = r or 0
    for i = 1, 2 do
        local off = i * 4
        local a = 0.08 * intensity * (1 - i/3)
        dl:AddRectFilled(imgui.ImVec2(x1-off, y1-off),
            imgui.ImVec2(x2+off, y2+off),
            ImVec4toU32(imgui.ImVec4(color.x,color.y,color.z,a)), r+i*2)
    end
end

local function drawGrad(dl, x, y, w, h, c1, c2)
    dl:AddRectFilledMultiColor(imgui.ImVec2(x,y), imgui.ImVec2(x+w,y+h),
        ImVec4toU32(c1), ImVec4toU32(c2), ImVec4toU32(c2), ImVec4toU32(c1))
end

local function drawGradRounded(dl, x, y, w, h, c1, c2, radius)
    radius = radius or 0
    if radius < 1 or h < 1 then
        dl:AddRectFilledMultiColor(
            imgui.ImVec2(x, y), imgui.ImVec2(x + w, y + h),
            ImVec4toU32(c1), ImVec4toU32(c2), ImVec4toU32(c2), ImVec4toU32(c1))
        return
    end

    local r = math.min(radius, w / 2)
    local segments = 12
    local thickness = h

    -- Левая дуга (top-left)
    for i = 0, segments - 1 do
        local a1 = math.pi + (math.pi / 2) * (i / segments)
        local a2 = math.pi + (math.pi / 2) * ((i + 1) / segments)
        local px1 = x + r + math.cos(a1) * r
        local py1 = y + r + math.sin(a1) * r
        local px2 = x + r + math.cos(a2) * r
        local py2 = y + r + math.sin(a2) * r
        local t1 = clamp((px1 - x) / w, 0, 1)
        local col = lerpColor(c1, c2, t1)
        dl:AddLine(imgui.ImVec2(px1, py1), imgui.ImVec2(px2, py2),
            ImVec4toU32(col), thickness)
    end

    -- Прямая часть сверху
    local steps = 20
    for i = 0, steps - 1 do
        local t1 = i / steps
        local t2 = (i + 1) / steps
        local px1 = x + r + (w - 2 * r) * t1
        local px2 = x + r + (w - 2 * r) * t2
        local col = lerpColor(c1, c2, (px1 - x) / w)
        dl:AddLine(imgui.ImVec2(px1, y), imgui.ImVec2(px2, y),
            ImVec4toU32(col), thickness)
    end

    -- Правая дуга (top-right)
    for i = 0, segments - 1 do
        local a1 = -math.pi / 2 + (math.pi / 2) * (i / segments)
        local a2 = -math.pi / 2 + (math.pi / 2) * ((i + 1) / segments)
        local px1 = x + w - r + math.cos(a1) * r
        local py1 = y + r + math.sin(a1) * r
        local px2 = x + w - r + math.cos(a2) * r
        local py2 = y + r + math.sin(a2) * r
        local t1 = clamp((px1 - x) / w, 0, 1)
        local col = lerpColor(c1, c2, t1)
        dl:AddLine(imgui.ImVec2(px1, py1), imgui.ImVec2(px2, py2),
            ImVec4toU32(col), thickness)
    end
end

local function drawGradV(dl, x, y, w, h, c1, c2)
    dl:AddRectFilledMultiColor(imgui.ImVec2(x,y), imgui.ImVec2(x+w,y+h),
        ImVec4toU32(c1), ImVec4toU32(c1), ImVec4toU32(c2), ImVec4toU32(c2))
end

local function pulsingDot(dl, x, y, r, col, speed)
    speed = speed or 4
    local p = (math.sin(os.clock()*speed)+1)*0.5
    local a = lerp(0.4,1,p)
    local rr = lerp(r*0.8,r,p)
    dl:AddCircleFilled(imgui.ImVec2(x,y), rr,
        ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,a)), 16)
end

local function drawGlassBg(dl, x1, y1, x2, y2, r, tint, borderAlpha)
    tint = tint or imgui.ImVec4(0.1,0.1,0.15,0.75)
    borderAlpha = borderAlpha or 0.12
    dl:AddRectFilled(imgui.ImVec2(x1,y1), imgui.ImVec2(x2,y2), ImVec4toU32(tint), r)
    dl:AddRect(imgui.ImVec2(x1,y1), imgui.ImVec2(x2,y2),
        ImVec4toU32(imgui.ImVec4(1,1,1,borderAlpha)), r, 15, 1)
end

local _spPts = { x = {}, y = {} }   -- sparkline point cache (was two separate locals)
local function drawSparkline(dl, x, y, w, h, data, color, filled)
    if not data or #data < 2 then return end
    local n = #data
    local maxV = 0
    for i = 1, n do if data[i] > maxV then maxV = data[i] end end
    if maxV == 0 then maxV = 1 end
    local step = w / (n - 1)
    local colU32 = ImVec4toU32(color)
    for i = 1, n do
        _spPts.x[i] = x + (i - 1) * step
        _spPts.y[i] = y + h - (data[i] / maxV) * h
    end
    if filled then
        local ca = ImVec4toU32(imgui.ImVec4(color.x, color.y, color.z, 0.15))
        local cb = ImVec4toU32(imgui.ImVec4(color.x, color.y, color.z, 0.02))
        for i = 1, n - 1 do
            dl:AddRectFilledMultiColor(
                imgui.ImVec2(_spPts.x[i],   _spPts.y[i]),
                imgui.ImVec2(_spPts.x[i+1], y + h),
                ca, ca, cb, cb)
        end
    end
    for i = 1, n - 1 do
        dl:AddLine(
            imgui.ImVec2(_spPts.x[i],   _spPts.y[i]),
            imgui.ImVec2(_spPts.x[i+1], _spPts.y[i+1]),
            colU32, 2)
    end
    local lx = _spPts.x[n]
    local ly = _spPts.y[n]
    dl:AddCircleFilled(imgui.ImVec2(lx, ly), 3, colU32, 12)
    drawGlow(dl, lx, ly, 3, color, 0.4)
end

local function drawCircularProgress(dl, cx, cy, radius, progress, thickness, color, bgColor, startAngle)
    startAngle = startAngle or (-math.pi / 2)
    thickness = thickness or 4
    progress = clamp(progress, 0, 1)
    if bgColor then
        local segments = 20
        for i = 0, segments - 1 do
            local a1 = (i / segments) * math.pi * 2
            local a2 = ((i + 1) / segments) * math.pi * 2
            dl:AddLine(
                imgui.ImVec2(cx + math.cos(a1) * radius, cy + math.sin(a1) * radius),
                imgui.ImVec2(cx + math.cos(a2) * radius, cy + math.sin(a2) * radius),
                ImVec4toU32(bgColor), thickness)
        end
    end
    if progress > 0.001 then
        local segments = math.max(6, math.floor(20 * progress))
        for i = 0, segments - 1 do
            local t1 = i / segments
            local t2 = (i + 1) / segments
            local a1 = startAngle + t1 * progress * math.pi * 2
            local a2 = startAngle + t2 * progress * math.pi * 2
            dl:AddLine(
                imgui.ImVec2(cx + math.cos(a1) * radius, cy + math.sin(a1) * radius),
                imgui.ImVec2(cx + math.cos(a2) * radius, cy + math.sin(a2) * radius),
                ImVec4toU32(color), thickness)
        end
    end
end

local function drawMiniBarChart(dl, x, y, w, h, data, color, maxVal)
    if not data or #data == 0 then return end
    maxVal = maxVal or 0
    for _, v in ipairs(data) do if v > maxVal then maxVal = v end end
    if maxVal == 0 then maxVal = 1 end
    local barW = math.max(2, (w / #data) - 1)
    local gap = 1
    for i, v in ipairs(data) do
        local bx = x + (i - 1) * (barW + gap)
        local bh = (v / maxVal) * h
        local a = 0.3 + (v / maxVal) * 0.7
        dl:AddRectFilled(imgui.ImVec2(bx, y + h - bh), imgui.ImVec2(bx + barW, y + h),
            ImVec4toU32(imgui.ImVec4(color.x, color.y, color.z, a)), 2)
    end
end

local function drawTrendArrow(dl, x, y, up, color)
    local col = ImVec4toU32(color)
    if up then
        dl:AddTriangleFilled(imgui.ImVec2(x, y + 8), imgui.ImVec2(x + 5, y), imgui.ImVec2(x + 10, y + 8), col)
    else
        dl:AddTriangleFilled(imgui.ImVec2(x, y), imgui.ImVec2(x + 5, y + 8), imgui.ImVec2(x + 10, y), col)
    end
end

local function animatedCounter(id, targetVal, speed)
    speed = speed or 0.06
    return math.floor(anim(id, targetVal, speed) + 0.5)
end

local function drawBoldText(dl, x, y, color, text, scale)
    local col = ImVec4toU32(color)
    if scale and scale > 1 then
        dl:AddText(imgui.ImVec2(x, y), col, text)
        dl:AddText(imgui.ImVec2(x + 1, y), col, text)
        dl:AddText(imgui.ImVec2(x + 0.5, y + 0.5), col, text)
    else
        dl:AddText(imgui.ImVec2(x, y), col, text)
        dl:AddText(imgui.ImVec2(x + 1, y), col, text)
    end
end

-- =========================================================================
-- КАСТОМНЫЕ ИКОНКИ (анонимные — УЛУЧШЕНИЕ)
-- =========================================================================
local iconDrawers = {
    function(dl, cx, cy, s, color)
        local col = ImVec4toU32(color)
        local sz = s * 0.26; local gap = s * 0.08
        for r = -1, 0 do for c2 = -1, 0 do
            local ox = cx + c2*(sz+gap*2) + gap
            local oy = cy + r*(sz+gap*2) + gap
            dl:AddRectFilled(imgui.ImVec2(ox, oy), imgui.ImVec2(ox+sz, oy+sz), col, 3)
        end end
    end,
    function(dl, cx, cy, s, color)
        local col = ImVec4toU32(color)
        local w = s * 0.55; local h = 2; local gap = s * 0.22
        for i = -1, 1 do
            local y = cy + i * gap
            local lw = (i == 0) and w or (w * 0.72)
            dl:AddRectFilled(imgui.ImVec2(cx-lw/2, y-h/2), imgui.ImVec2(cx+lw/2, y+h/2), col, 1)
            dl:AddCircleFilled(imgui.ImVec2(cx-w/2-5, y), 2.5, col, 8)
        end
    end,
    function(dl, cx, cy, s, color)
        local col = ImVec4toU32(color)
        local w, h = s*0.48, s*0.55
        dl:AddRect(imgui.ImVec2(cx-w/2, cy-h/2), imgui.ImVec2(cx+w/2, cy+h/2), col, 3, 15, 1.8)
        dl:AddLine(imgui.ImVec2(cx, cy-h/2+3), imgui.ImVec2(cx, cy+h/2-3), col, 1.5)
        for i = -1, 1, 2 do
            dl:AddLine(imgui.ImVec2(cx+i*3, cy-h/4), imgui.ImVec2(cx+i*(w/2-4), cy-h/4), col, 1)
        end
    end,
    function(dl, cx, cy, s, color)
        local col = ImVec4toU32(color)
        local r2 = s * 0.14; local r1 = s * 0.28
        dl:AddCircle(imgui.ImVec2(cx,cy), r2, col, 12, 2)
        for i = 0, 5 do
            local angle = (i / 6) * math.pi * 2 + os.clock() * 0.3
            local x1 = cx + math.cos(angle) * r2 * 1.3
            local y1 = cy + math.sin(angle) * r2 * 1.3
            local x2 = cx + math.cos(angle) * r1
            local y2 = cy + math.sin(angle) * r1
            dl:AddLine(imgui.ImVec2(x1,y1), imgui.ImVec2(x2,y2), col, 2.5)
        end
    end,
    function(dl, cx, cy, s, color)
        local col = ImVec4toU32(color)
        dl:AddCircle(imgui.ImVec2(cx,cy), s*0.32, col, 24, 1.8)
        dl:AddCircleFilled(imgui.ImVec2(cx, cy-s*0.10), 2.2, col, 8)
        dl:AddRectFilled(imgui.ImVec2(cx-1.5, cy+1), imgui.ImVec2(cx+1.5, cy+s*0.16), col, 1)
    end,
        -- [6] Журнал (часы/лог)
    function(dl, cx, cy, s, color)
        local col = ImVec4toU32(color)
        local r = s * 0.28
        dl:AddCircle(imgui.ImVec2(cx, cy), r, col, 16, 1.8)
        -- Стрелки часов
        dl:AddLine(imgui.ImVec2(cx, cy), imgui.ImVec2(cx, cy - r * 0.6), col, 1.8)
        dl:AddLine(imgui.ImVec2(cx, cy), imgui.ImVec2(cx + r * 0.4, cy + r * 0.2), col, 1.8)
        -- Точка центра
        dl:AddCircleFilled(imgui.ImVec2(cx, cy), 1.5, col, 8)
    end,
    -- [7] Заметки (блокнот)
    function(dl, cx, cy, s, color)
        local col = ImVec4toU32(color)
        local w, h = s * 0.4, s * 0.5
        dl:AddRect(imgui.ImVec2(cx - w/2, cy - h/2), imgui.ImVec2(cx + w/2, cy + h/2), col, 2, 15, 1.8)
        -- Линии текста
        for i = -1, 1 do
            local ly = cy + i * (h * 0.25)
            dl:AddLine(imgui.ImVec2(cx - w/2 + 4, ly), imgui.ImVec2(cx + w/2 - 4, ly), col, 1)
        end
    end,
}

-- =========================================================================
-- КОНФИГУРАЦИЯ
-- =========================================================================
local configDirectory = getWorkingDirectory():gsub('\\','/') .. "/config/Snatch Helper"
ensureDirectory(configDirectory)
ensureDirectory(configDirectory .. "/backups")
ensureDirectory(configDirectory .. "/profiles")

-- Пути к файлам конфигурации (централизовано)
U.bindsConfigFile   = configDirectory .. "/binds.json"
U.activityLogFile   = configDirectory .. "/activity_log.json"

-- =========================================================================
-- AUTO FIND
-- =========================================================================
local autoFind = {
    active = false, targetId = -1, targetNick = "",
    lastId = -1, lastNick = "", waitInta = false,
    interval = 2000, lastFindTime = 0, suppressMessages = true,
    -- Оповещение о близости
    proximityAlert = true,
    proximityDistance = 50,
    soundAlert = false,
    proximityAlerted = false,
}
-- =========================================================================
-- ПОДСВЕТКА СОЗДАТЕЛЯ
-- =========================================================================
local creatorNick = "Smoant_Despasito"
local creatorBadge = "[SH Dev]"
local creatorMode = 3  -- 1=цвет, 2=бейдж+цвет, 3=бейдж+градиент
local creatorColors = {
    badge    = "00FFB3",
    solid    = "FF00FF",   -- для mode 1 и 2
    nickFrom = "00FFB3",   -- начало градиента (mode 3)
    nickTo   = "CC44FF",   -- конец градиента (mode 3)
    id       = "CC44FF",
}

local function gradientNick(text, hex1, hex2)
    local r1, g1, b1 = tonumber(hex1:sub(1,2), 16), tonumber(hex1:sub(3,4), 16), tonumber(hex1:sub(5,6), 16)
    local r2, g2, b2 = tonumber(hex2:sub(1,2), 16), tonumber(hex2:sub(3,4), 16), tonumber(hex2:sub(5,6), 16)
    local len = #text
    local parts = {}
    for i = 1, len do
        local t = (i - 1) / math.max(len - 1, 1)
        local r = math.floor(r1 + (r2 - r1) * t)
        local g = math.floor(g1 + (g2 - g1) * t)
        local b = math.floor(b1 + (b2 - b1) * t)
        parts[i] = string.format("{%02X%02X%02X}%s", r, g, b, text:sub(i, i))
    end
    return table.concat(parts)
end

local function buildCreatorNick(restoreHex, bracket)
    local nickPart = ""
    local badgePart = ""

    -- Бейдж (mode 2 и 3)
    if creatorMode == 2 or creatorMode == 3 then
        badgePart = "{" .. creatorColors.badge .. "}" .. creatorBadge .. " "
    end

    -- Ник
    if creatorMode == 1 then
        nickPart = "{" .. creatorColors.solid .. "}" .. creatorNick
    elseif creatorMode == 2 then
        nickPart = "{" .. creatorColors.solid .. "}" .. creatorNick
    elseif creatorMode == 3 then
        nickPart = gradientNick(creatorNick, creatorColors.nickFrom, creatorColors.nickTo)
    elseif creatorMode == 4 then
        nickPart = gradientNick(creatorNick, creatorColors.nickFrom, creatorColors.nickTo)
    end

    -- ID
    local idPart = ""
    if bracket then
        idPart = "{" .. creatorColors.id .. "}" .. bracket
    end

    -- Восстановление цвета
    local restorePart = "{" .. restoreHex .. "}"

    return badgePart .. nickPart .. idPart .. restorePart
end
-- =========================================================================
-- СИСТЕМА ОБНОВЛЕНИЙ
-- =========================================================================
local updater = {
    github_user = "StepD22",        -- GitHub юзернейм
    github_repo = "Snatch-Helper",            -- название репозитория
    github_branch = "main",               -- ветка 

    -- Состояние
    checking = false,
    downloading = false,
    updateAvailable = false,
    newVersion = "",
    changelog = "",
    remoteFiles = {},
    checkError = nil,
    downloadProgress = { current = 0, total = 0, currentFile = "" },
    lastCheck = 0,
    autoCheckInterval = 3600, -- проверка раз в час (секунды)
    pendingReload = false,

    -- Пути
    tempDir = configDirectory .. "/update_temp",
}

function updater.getRawUrl(filePath)
    return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s",
        updater.github_user, updater.github_repo, updater.github_branch, filePath)
end

function updater.getVersionUrl()
    return updater.getRawUrl("version.json") .. "?t=" .. os.time()
end

function updater.parseVersion(verStr)
    local parts = {}
    for p in tostring(verStr):gmatch("(%d+)") do
        table.insert(parts, tonumber(p))
    end
    return parts
end

function updater.isNewer(remote, current)
    local r = updater.parseVersion(remote)
    local c = updater.parseVersion(current)
    local maxLen = math.max(#r, #c)
    for i = 1, maxLen do
        local rv = r[i] or 0
        local cv = c[i] or 0
        if rv > cv then return true end
        if rv < cv then return false end
    end
    return false
end

function updater.checkForUpdates(silent)
    if updater.checking then return end
    updater.checking = true
    updater.checkError = nil
    updater.updateAvailable = false

    local versionUrl = updater.getVersionUrl()
    local tempFile = updater.tempDir .. "/version_check.json"

    ensureDirectory(updater.tempDir)

    if not silent then
        addNotification("Проверка обновлений...", C.NOTIFY_INFO)
    end

    downloadUrlToFile(versionUrl, tempFile, function(id, status, p1, p2)
        if status == 58 then -- DOWNLOAD_STATUS_ENDDOWNLOADDATA
            lua_thread.create(function()
                wait(100)
                if doesFileExistSafe(tempFile) then
                    local f = io.open(tempFile, 'r')
                    if f then
                        local content = f:read('*a')
                        f:close()
                        os.remove(tempFile)

                        local ok, data = pcall(decodeJson, content)
                        if ok and type(data) == "table" and data.version then
                            updater.newVersion = data.version
                            updater.changelog = data.changelog or ""
                            updater.remoteFiles = data.files or {}
                            updater.lastCheck = os.clock()

                            if updater.isNewer(data.version, C.SCRIPT_VERSION) then
                                updater.updateAvailable = true
                                addNotification(
                                    "Доступно обновление: v" .. data.version,
                                    C.NOTIFY_SUCCESS, 8)
                            else
                                if not silent then
                                    addNotification("У вас последняя версия!", C.NOTIFY_INFO)
                                end
                            end
                        else
                            updater.checkError = "Ошибка разбора version.json"
                            if not silent then
                                addNotification("Ошибка проверки обновлений", C.NOTIFY_ERROR)
                            end
                        end
                    end
                else
                    updater.checkError = "Не удалось скачать version.json"
                    if not silent then
                        addNotification("Нет связи с GitHub", C.NOTIFY_ERROR)
                    end
                end
                updater.checking = false
            end)

        elseif status == 68 then -- DOWNLOAD_STATUS_ERROR
            updater.checking = false
            updater.checkError = "Ошибка загрузки"
            if not silent then
                addNotification("Ошибка подключения к GitHub", C.NOTIFY_ERROR)
            end
        end
    end)
end

function updater.getFileDest(fileInfo)
    if fileInfo.type == "script" then
        return thisScript().path
    elseif fileInfo.type == "config" then
        return configDirectory .. "/" .. fileInfo.name
    elseif fileInfo.type == "font" then
        return configDirectory .. "/fonts/" .. fileInfo.name
    end
    return nil
end

function updater.getFileRemotePath(fileInfo)
    if fileInfo.type == "script" then
        return fileInfo.name
    elseif fileInfo.type == "config" then
        return "config/" .. fileInfo.name
    elseif fileInfo.type == "font" then
        return "fonts/" .. fileInfo.name
    end
    return fileInfo.name
end

function updater.downloadUpdate(filesFilter)
    if updater.downloading then return end
    updater.downloading = true

    local filesToDownload = {}
    for _, fileInfo in ipairs(updater.remoteFiles) do
        if filesFilter == "all" or filesFilter == fileInfo.type then
            if fileInfo.type == "config" and not fileInfo.required then
                -- Конфиг-файлы (не обязательные) — скачивать только если их нет
                local dest = updater.getFileDest(fileInfo)
                if dest and not doesFileExistSafe(dest) then
                    table.insert(filesToDownload, fileInfo)
                end
            else
                table.insert(filesToDownload, fileInfo)
            end
        end
    end

    if #filesToDownload == 0 then
        addNotification("Нечего обновлять", C.NOTIFY_INFO)
        updater.downloading = false
        return
    end

    updater.downloadProgress.total = #filesToDownload
    updater.downloadProgress.current = 0

    ensureDirectory(updater.tempDir)
    addNotification("Загрузка обновления: " .. #filesToDownload .. " файлов...", C.NOTIFY_INFO)

    lua_thread.create(function()
        local allOk = true
        local scriptUpdated = false

        for i, fileInfo in ipairs(filesToDownload) do
            updater.downloadProgress.current = i
            updater.downloadProgress.currentFile = fileInfo.name

            local remotePath = updater.getFileRemotePath(fileInfo)
            local url = updater.getRawUrl(remotePath)
            local tempPath = updater.tempDir .. "/" .. fileInfo.name:gsub("[/\\]", "_")
            local destPath = updater.getFileDest(fileInfo)

            if not destPath then
                addNotification("Неизвестный тип: " .. fileInfo.name, C.NOTIFY_WARNING)
            else
                local downloadDone = false
                local downloadOk = false

                downloadUrlToFile(url, tempPath, function(id, status, p1, p2)
                    if status == 58 then
                        downloadOk = true
                        downloadDone = true
                    elseif status == 68 then
                        downloadOk = false
                        downloadDone = true
                    end
                end)

                -- Ждём завершения загрузки
                local timeout = os.clock() + 30
                while not downloadDone and os.clock() < timeout do
                    wait(100)
                end

                if downloadOk and doesFileExistSafe(tempPath) then
                    -- Бэкап старого файла
                    if doesFileExistSafe(destPath) then
                        local backupPath = destPath .. ".backup"
                        os.remove(backupPath)
                        os.rename(destPath, backupPath)
                    end

                    -- Создать директорию если нужно
                    local destDir = destPath:match("(.+)[/\\]")
                    if destDir then ensureDirectory(destDir) end

                    -- Переместить новый файл
                    local copyOk = os.rename(tempPath, destPath)
                    if not copyOk then
                        -- os.rename не работает между дисками, копируем
                        local src = io.open(tempPath, 'rb')
                        local dst = io.open(destPath, 'wb')
                        if src and dst then
                            dst:write(src:read('*a'))
                            src:close()
                            dst:close()
                            os.remove(tempPath)
                            copyOk = true
                        end
                    end

                    if copyOk then
                        addNotification("Обновлён: " .. fileInfo.name, C.NOTIFY_SUCCESS)
                        if fileInfo.type == "script" then
                            scriptUpdated = true
                        end
                    else
                        addNotification("Ошибка копирования: " .. fileInfo.name, C.NOTIFY_ERROR)
                        allOk = false
                        -- Восстановить бэкап
                        local backupPath = destPath .. ".backup"
                        if doesFileExistSafe(backupPath) then
                            os.rename(backupPath, destPath)
                        end
                    end
                else
                    addNotification("Ошибка загрузки: " .. fileInfo.name, C.NOTIFY_ERROR)
                    allOk = false
                end
            end

            wait(200)
        end

        -- Очистка temp
        pcall(function()
            local tempFiles = updater.tempDir
            if doesDirectoryExist(tempFiles) then
                os.execute('rd /s /q "' .. tempFiles:gsub("/", "\\") .. '" 2>nul')
            end
        end)

        updater.downloading = false
        updater.downloadProgress.current = 0
        updater.downloadProgress.total = 0
        updater.downloadProgress.currentFile = ""

        if allOk then
            updater.updateAvailable = false
            addNotification("Обновление завершено!", C.NOTIFY_SUCCESS, 6)

            if scriptUpdated then
                updater.pendingReload = true
                addNotification("Перезагрузите скрипт для применения (Ctrl+R)", C.NOTIFY_WARNING, 10)
            end
        else
            addNotification("Обновление завершено с ошибками", C.NOTIFY_WARNING)
        end
    end)
end

function updater.downloadFullUpdate()
    updater.downloadUpdate("all")
end

function updater.downloadScriptOnly()
    updater.downloadUpdate("script")
end
local settings = {
defaultDelay = 1500, stopKey = 0x7B, stopKeyMod = 0,
currentTheme = "midnight", showNotifications = true, maxBindDuration = 60000,
enableGwarn = true, enableUk = true, enableDemoute = true, enableDismiss = true,
showOverlay = true, confirmDelete = true,
openKey = 0x71, binderKey = 0x73,
compactMode = false, showParticles = true,
autoBackup = true, sidebarAutoHide = false, showFavorites = true,
overlayPosition = 0, showStepNumbers = true, enableSounds = false,
fontSize = 0, animationSpeed = 1.0, showMiniStats = true,
showMembersOverlay = true,
membersAutoRefresh = true,
membersAutoRefreshInterval = 60000,
membersOverlayRightX = -1,
membersOverlayPosY = -1,
uiScale = 1.0,          -- DPI / масштаб интерфейса
-- РП отыгрыш оружия
rpWeaponEnabled   = true,
rpWeaponFemale    = false, -- true=женский род
-- Webhook
webhookEnabled = true,
webhookDiscordUrl = "",
webhookTelegramToken = "",
webhookTelegramChatId = "",
webhookMode = 0,
webhookCooldown = 3000,
webhookIncludePlayerNames = true,
webhookEvents = {
    bind_gwarn = true,
    bind_wanted = true,
    bind_demoute = true,
    bind_dismiss = true,
},
}

local settingsFile = configDirectory .. "/settings.json"

local function mergeSettings(dst, src)
    for k, v in pairs(src) do
        if dst[k] ~= nil then
            if type(dst[k]) == "table" and type(v) == "table" then
                mergeSettings(dst[k], v)
            elseif type(dst[k]) == type(v) then
                dst[k] = v
            end
        end
    end
end

local function loadSettings()
    if not doesFileExistSafe(settingsFile) then return end
    local f = io.open(settingsFile, 'r'); if not f then return end
    local c = f:read('*a'); f:close()
    if not c or #c < 2 then return end
    local ok, data = pcall(decodeJson, c)
    if ok and type(data) == "table" then
        mergeSettings(settings, data)
    end
end

local function saveSettings()
    if not ensureDirectory(configDirectory) then return end
    local f = io.open(settingsFile, 'w'); if not f then return end
    local ok, j = pcall(encodeJson, settings)
    if ok and j then f:write(j) end; f:close()
end

-- =========================================================================
-- АНИМАЦИЯ ОКНА
-- =========================================================================
local ui_meta = {
    __index = function(self, v)
        if v == "switch" then
            return function()
                if self.process and self.process:status() ~= "dead" then return false end
                self.timer = os.clock(); self.state = not self.state
                self.process = lua_thread.create(function()
                    local st = self.timer
                    while true do wait(0)
                        local t2 = clamp((os.clock()-st)/self.duration, 0, 1)
                        self.alpha = self.state and ease.outCubic(t2) or (1-ease.outCubic(t2))
                        if t2 >= 1 then break end
                    end
                end)
                return true
            end
        end
        if v == "alpha" then return self.state and 1.0 or 0.0 end
        if v == "switch2" then return function() self.state = not self.state; self.alpha = self.state and 1 or 0 end end
    end
}

local mainWindow = setmetatable({ state = false, duration = 0.35 }, ui_meta)
local mainWindowOpen = imgui.new.bool(false)
-- =========================================================================
-- WEBHOOK СИСТЕМА
-- =========================================================================



-- Конвертация CP1251 -> UTF-8 (pure Lua)
local _cp1251u = {
    [0x80]=0x0402,[0x81]=0x0403,[0x82]=0x201A,[0x83]=0x0453,[0x84]=0x201E,[0x85]=0x2026,
    [0x86]=0x2020,[0x87]=0x2021,[0x88]=0x20AC,[0x89]=0x2030,[0x8A]=0x0409,[0x8B]=0x2039,
    [0x8C]=0x040A,[0x8D]=0x040C,[0x8E]=0x040B,[0x8F]=0x040F,[0x90]=0x0452,[0x91]=0x2018,
    [0x92]=0x2019,[0x93]=0x201C,[0x94]=0x201D,[0x95]=0x2022,[0x96]=0x2013,[0x97]=0x2014,
    [0x99]=0x2122,[0x9A]=0x0459,[0x9B]=0x203A,[0x9C]=0x045A,[0x9D]=0x045C,[0x9E]=0x045B,
    [0x9F]=0x045F,[0xA0]=0x00A0,[0xA1]=0x040E,[0xA2]=0x045E,[0xA3]=0x0408,[0xA4]=0x00A4,
    [0xA5]=0x0490,[0xA6]=0x00A6,[0xA7]=0x00A7,[0xA8]=0x0401,[0xA9]=0x00A9,[0xAA]=0x0404,
    [0xAB]=0x00AB,[0xAC]=0x00AC,[0xAD]=0x00AD,[0xAE]=0x00AE,[0xAF]=0x0407,[0xB0]=0x00B0,
    [0xB1]=0x00B1,[0xB2]=0x0406,[0xB3]=0x0456,[0xB4]=0x0491,[0xB5]=0x00B5,[0xB6]=0x00B6,
    [0xB7]=0x00B7,[0xB8]=0x0451,[0xB9]=0x2116,[0xBA]=0x0454,[0xBB]=0x00BB,[0xBC]=0x0458,
    [0xBD]=0x0405,[0xBE]=0x0455,[0xBF]=0x0457,
}
for i=0,63 do _cp1251u[0xC0+i]=0x0410+i end

local function cp1251ToUtf8(s)
    if not s then return "" end
    local t = {}
    for i=1,#s do
        local b = s:byte(i)
        if b < 0x80 then
            t[#t+1] = string.char(b)
        else
            local u = _cp1251u[b] or 0x3F
            if u < 0x800 then
                t[#t+1] = string.char(0xC0+math.floor(u/64), 0x80+(u%64))
            else
                t[#t+1] = string.char(0xE0+math.floor(u/4096),
                    0x80+math.floor((u%4096)/64), 0x80+(u%64))
            end
        end
    end
    return table.concat(t)
end

local function jsonEscapeStr(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\r", "\\r")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\t", "\\t")
    s = s:gsub("[%z\x01-\x1F]", "")
    return s
end

local function buildWebhookEmbed(ev, targetName, targetId, reason, actorName, actorId, timeStr)
    local title  = jsonEscapeStr(ev.emoji .. "  " .. ev.name)
    local fields = ""
        .. '{"name":"' .. jsonEscapeStr("Target") .. '","value":"'        .. jsonEscapeStr(targetName .. " [" .. targetId .. "]")
        .. '","inline":true},'
        .. '{"name":"' .. jsonEscapeStr("Reason") .. '","value":"'        .. jsonEscapeStr(reason)
        .. '","inline":false},'
        .. '{"name":"' .. jsonEscapeStr("Agent") .. '","value":"'        .. jsonEscapeStr(actorName .. " [" .. actorId .. "]")
        .. '","inline":true},'
        .. '{"name":"' .. jsonEscapeStr("Time") .. '","value":"'        .. jsonEscapeStr(timeStr)
        .. '","inline":true}'
    return '{"username":"Snatch Helper",'
        .. '"avatar_url":"https://i.imgur.com/4M34hi2.png",'
        .. '"embeds":[{'
        .. '"title":"' .. title .. '",'
        .. '"color":' .. ev.color .. ','
        .. '"fields":[' .. fields .. ']'
        .. '}]}'
end
pcall(function()
    ffi.cdef[[
        typedef void* HANDLE;
        typedef struct {
            unsigned long  cb;
            char*          lpReserved;
            char*          lpDesktop;
            char*          lpTitle;
            unsigned long  dwX, dwY, dwXSize, dwYSize;
            unsigned long  dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            unsigned short wShowWindow, cbReserved2;
            unsigned char* lpReserved2;
            HANDLE hStdInput, hStdOutput, hStdError;
        } STARTUPINFOA_WH;
        typedef struct {
            HANDLE hProcess, hThread;
            unsigned long dwProcessId, dwThreadId;
        } PROCESS_INFORMATION_WH;
        int CreateProcessA(const char*, char*, void*, void*, int,
            unsigned long, void*, const char*, STARTUPINFOA_WH*, PROCESS_INFORMATION_WH*);
        int CloseHandle(HANDLE);
        int    MultiByteToWideChar(unsigned int, unsigned long, const char*, int, wchar_t*, int);
        void*  GlobalAlloc(unsigned int, size_t);
        void*  GlobalLock(void*);
        void*  GlobalFree(void*);
        int    GlobalUnlock(void*);
        int    OpenClipboard(void*);
        int    EmptyClipboard(void);
        void*  SetClipboardData(unsigned int, void*);
        int    CloseClipboard(void);
    ]]
end)

local function webhookPostAsync(url, utf8JsonStr)
    local tmp = (os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp"):gsub("/","\\")
    local rnd = tostring(math.random(100000,999999))
    local jsonPath = tmp .. "\\sh_" .. rnd .. ".json"
    local ps1Path  = tmp .. "\\sh_" .. rnd .. ".ps1"

    -- Пишем JSON как бинарный UTF-8 (без BOM, без escaping)
    local fj = io.open(jsonPath, "wb")
    if not fj then return false end
    fj:write(utf8JsonStr)
    fj:close()

    -- PS1 содержит только ASCII — никаких проблем с кодировкой
    local fp = io.open(ps1Path, "w")
    if not fp then os.remove(jsonPath); return false end
    -- Используем одинарные кавычки для пути — безопасно
    local safeJson = jsonPath:gsub("\\","/")
    local safeUrl  = url:gsub("'","")
    fp:write("$u='" .. safeUrl  .. "'\n")
    fp:write("$f='" .. safeJson .. "'\n")
    fp:write("$b=[System.IO.File]::ReadAllText($f,[System.Text.Encoding]::UTF8)\n")
    fp:write("try{Invoke-RestMethod -Uri $u -Method Post -ContentType 'application/json; charset=utf-8' -Body $b}catch{}\n")
    fp:write("Remove-Item $f -Force -EA 0\n")
    fp:write("Remove-Item $MyInvocation.MyCommand.Path -Force -EA 0\n")
    fp:close()

    -- CreateProcessA с CREATE_NO_WINDOW — нет cmd.exe, нет консоли
    local ok, si, pi = pcall(function()
        local si = ffi.new("STARTUPINFOA_WH")
        si.cb = ffi.sizeof("STARTUPINFOA_WH")
        si.dwFlags = 0x1; si.wShowWindow = 0
        local pi = ffi.new("PROCESS_INFORMATION_WH")
        local cmd = ffi.new("char[2048]",
            "powershell -NoProfile -NonInteractive -WindowStyle Hidden"
            .. " -ExecutionPolicy Bypass -File \"" .. ps1Path .. "\"")
        local r = ffi.C.CreateProcessA(nil,cmd,nil,nil,0,0x08000000,nil,nil,si,pi)
        if r~=0 then ffi.C.CloseHandle(pi.hProcess); ffi.C.CloseHandle(pi.hThread) end
        return r
    end)
    if not ok then
        os.remove(jsonPath); os.remove(ps1Path)
        return false
    end
    return true
end

local webhookEventDefs = {
    bind_gwarn   = { name = "Vygovor",  emoji = "[!]", color = 16312092 },
    bind_wanted  = { name = "Rozysk",   emoji = "[W]", color = 15548997 },
    bind_demoute = { name = "DEMOUTE",  emoji = "[D]", color = 16098851 },
    bind_dismiss = { name = "DISMISS",  emoji = "[X]", color = 10070709 },
}

local function urlEncode(s)
    return (tostring(s):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function webhookSend(eventType, data)
    if not settings.webhookEnabled then return end
    local mode = settings.webhookMode or 0
    if not settings.webhookEvents or not settings.webhookEvents[eventType] then return end
    local ev = webhookEventDefs[eventType]
    if not ev then return end
    local ps = getCachedPlayerStats()
    local targetName = cp1251ToUtf8(data.targetName or "?")
    local reason     = cp1251ToUtf8(data.reason or "-")
    local actorName  = cp1251ToUtf8(ps.nick or "?")
    local timeStr    = os.date("!%d.%m.%Y %H:%M", os.time() + 10800) .. " MSK"
    local targetId   = tostring(tonumber(data.targetId or 0))
    local actorId    = tostring(tonumber(ps.myId or -1))
    local tName = settings.webhookIncludePlayerNames and targetName or "hidden"
    local aName = settings.webhookIncludePlayerNames and actorName or "hidden"
    -- Discord (mode 0 or 2)
    if (mode == 0 or mode == 2) and settings.webhookDiscordUrl and settings.webhookDiscordUrl ~= "" then
        local payloadJson = buildWebhookEmbed(ev, tName, targetId, reason, aName, actorId, timeStr)
        webhookPostAsync(settings.webhookDiscordUrl, payloadJson)
    end
    -- Telegram (mode 1 or 2)
    if (mode == 1 or mode == 2)
    and settings.webhookTelegramToken and settings.webhookTelegramToken ~= ""
    and settings.webhookTelegramChatId and settings.webhookTelegramChatId ~= "" then
        local text = ev.emoji .. " " .. ev.name .. "\n"
            .. "Target: " .. tName .. " [" .. targetId .. "]\n"
            .. "Reason: " .. reason .. "\n"
            .. "Agent: " .. aName .. " [" .. actorId .. "]\n"
            .. "Time: " .. timeStr
        local escaped = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        local tgUrl = "https://api.telegram.org/bot" .. settings.webhookTelegramToken
            .. "/sendMessage?chat_id=" .. urlEncode(settings.webhookTelegramChatId)
            .. "&parse_mode=HTML&text=" .. urlEncode(escaped)
        if hasRequests and type(requests) == "table" then
            pcall(requests.get, tgUrl)
        end
    end
end


local colorThemes = {
    midnight = {
        name = "Midnight", icon = "*",
        sidebar        = imgui.ImVec4(0.020, 0.022, 0.050, 1),
        sidebar_active = imgui.ImVec4(0.040, 0.048, 0.105, 1),
        bg             = imgui.ImVec4(0.030, 0.035, 0.072, 0.99),
        header         = imgui.ImVec4(0.025, 0.028, 0.062, 1),
        card           = imgui.ImVec4(0.045, 0.052, 0.108, 0.92),
        card_hover     = imgui.ImVec4(0.058, 0.068, 0.142, 0.95),
        input          = imgui.ImVec4(0.032, 0.038, 0.082, 0.90),
        accent         = imgui.ImVec4(0.22, 0.52, 1.00, 1),
        accent2        = imgui.ImVec4(0.45, 0.72, 1.00, 1),
        accent_dim     = imgui.ImVec4(0.15, 0.35, 0.80, 1),
        text           = imgui.ImVec4(0.90, 0.92, 0.98, 1),
        text2          = imgui.ImVec4(0.50, 0.55, 0.72, 1),
        text3          = imgui.ImVec4(0.30, 0.34, 0.48, 1),
        green          = imgui.ImVec4(0.20, 0.90, 0.55, 1),
        yellow         = imgui.ImVec4(1.00, 0.82, 0.30, 1),
        red            = imgui.ImVec4(1.00, 0.32, 0.38, 1),
        blue           = imgui.ImVec4(0.30, 0.65, 1.00, 1),
        grad1          = imgui.ImVec4(0.15, 0.40, 1.00, 1),
        grad2          = imgui.ImVec4(0.50, 0.20, 1.00, 1),
        glass          = imgui.ImVec4(0.03, 0.04, 0.09, 0.70),
    },
    ember = {
        name = "Ember", icon = "~",
        sidebar        = imgui.ImVec4(0.045, 0.030, 0.020, 1),
        sidebar_active = imgui.ImVec4(0.090, 0.058, 0.035, 1),
        bg             = imgui.ImVec4(0.058, 0.038, 0.025, 0.99),
        header         = imgui.ImVec4(0.048, 0.032, 0.022, 1),
        card           = imgui.ImVec4(0.085, 0.058, 0.038, 0.92),
        card_hover     = imgui.ImVec4(0.115, 0.078, 0.048, 0.95),
        input          = imgui.ImVec4(0.058, 0.038, 0.028, 0.90),
        accent         = imgui.ImVec4(1.00, 0.55, 0.10, 1),
        accent2        = imgui.ImVec4(1.00, 0.72, 0.35, 1),
        accent_dim     = imgui.ImVec4(0.82, 0.40, 0.05, 1),
        text           = imgui.ImVec4(1.00, 0.95, 0.90, 1),
        text2          = imgui.ImVec4(0.72, 0.58, 0.48, 1),
        text3          = imgui.ImVec4(0.50, 0.40, 0.32, 1),
        green          = imgui.ImVec4(0.45, 0.90, 0.40, 1),
        yellow         = imgui.ImVec4(1.00, 0.88, 0.25, 1),
        red            = imgui.ImVec4(1.00, 0.30, 0.25, 1),
        blue           = imgui.ImVec4(0.40, 0.70, 1.00, 1),
        grad1          = imgui.ImVec4(1.00, 0.45, 0.00, 1),
        grad2          = imgui.ImVec4(1.00, 0.20, 0.05, 1),
        glass          = imgui.ImVec4(0.08, 0.05, 0.03, 0.70),
    },
    neon = {
        name = "Neon", icon = "#",
        sidebar        = imgui.ImVec4(0.018, 0.018, 0.028, 1),
        sidebar_active = imgui.ImVec4(0.035, 0.035, 0.065, 1),
        bg             = imgui.ImVec4(0.025, 0.025, 0.042, 0.99),
        header         = imgui.ImVec4(0.020, 0.020, 0.038, 1),
        card           = imgui.ImVec4(0.040, 0.040, 0.072, 0.92),
        card_hover     = imgui.ImVec4(0.055, 0.055, 0.098, 0.95),
        input          = imgui.ImVec4(0.028, 0.028, 0.052, 0.90),
        accent         = imgui.ImVec4(0.00, 1.00, 0.85, 1),
        accent2        = imgui.ImVec4(0.40, 1.00, 0.92, 1),
        accent_dim     = imgui.ImVec4(0.00, 0.72, 0.60, 1),
        text           = imgui.ImVec4(0.92, 0.95, 0.95, 1),
        text2          = imgui.ImVec4(0.52, 0.58, 0.60, 1),
        text3          = imgui.ImVec4(0.32, 0.36, 0.40, 1),
        green          = imgui.ImVec4(0.00, 1.00, 0.50, 1),
        yellow         = imgui.ImVec4(1.00, 0.95, 0.00, 1),
        red            = imgui.ImVec4(1.00, 0.10, 0.40, 1),
        blue           = imgui.ImVec4(0.00, 0.60, 1.00, 1),
        grad1          = imgui.ImVec4(0.00, 1.00, 0.85, 1),
        grad2          = imgui.ImVec4(1.00, 0.00, 0.60, 1),
        glass          = imgui.ImVec4(0.02, 0.02, 0.05, 0.70),
    },
    -- Carnival: карнавал — глубокий индиго + кислотный лайм + неоновая роза
    carnival = {
        name = "Carnival", icon = "C",
        sidebar        = imgui.ImVec4(0.022, 0.015, 0.055, 1),
        sidebar_active = imgui.ImVec4(0.045, 0.028, 0.110, 1),
        bg             = imgui.ImVec4(0.028, 0.018, 0.068, 0.99),
        header         = imgui.ImVec4(0.020, 0.014, 0.052, 1),
        card           = imgui.ImVec4(0.045, 0.030, 0.100, 0.92),
        card_hover     = imgui.ImVec4(0.060, 0.040, 0.135, 0.95),
        input          = imgui.ImVec4(0.030, 0.020, 0.072, 0.90),
        accent         = imgui.ImVec4(0.72, 1.00, 0.00, 1),
        accent2        = imgui.ImVec4(1.00, 0.30, 0.72, 1),
        accent_dim     = imgui.ImVec4(0.50, 0.72, 0.00, 1),
        text           = imgui.ImVec4(0.96, 0.94, 1.00, 1),
        text2          = imgui.ImVec4(0.62, 0.52, 0.85, 1),
        text3          = imgui.ImVec4(0.38, 0.30, 0.55, 1),
        green          = imgui.ImVec4(0.60, 1.00, 0.00, 1),
        yellow         = imgui.ImVec4(1.00, 0.90, 0.00, 1),
        red            = imgui.ImVec4(1.00, 0.22, 0.55, 1),
        blue           = imgui.ImVec4(0.35, 0.75, 1.00, 1),
        grad1          = imgui.ImVec4(0.68, 1.00, 0.00, 1),
        grad2          = imgui.ImVec4(1.00, 0.25, 0.70, 1),
        glass          = imgui.ImVec4(0.04, 0.03, 0.10, 0.75),
    },
    aurora = {
        name = "Aurora", icon = "@",
        sidebar        = imgui.ImVec4(0.015, 0.035, 0.032, 1),
        sidebar_active = imgui.ImVec4(0.028, 0.072, 0.062, 1),
        bg             = imgui.ImVec4(0.022, 0.048, 0.042, 0.99),
        header         = imgui.ImVec4(0.018, 0.040, 0.035, 1),
        card           = imgui.ImVec4(0.035, 0.075, 0.065, 0.92),
        card_hover     = imgui.ImVec4(0.045, 0.100, 0.085, 0.95),
        input          = imgui.ImVec4(0.025, 0.052, 0.045, 0.90),
        accent         = imgui.ImVec4(0.00, 0.92, 0.70, 1),
        accent2        = imgui.ImVec4(0.35, 1.00, 0.85, 1),
        accent_dim     = imgui.ImVec4(0.00, 0.65, 0.48, 1),
        text           = imgui.ImVec4(0.88, 0.96, 0.94, 1),
        text2          = imgui.ImVec4(0.48, 0.65, 0.60, 1),
        text3          = imgui.ImVec4(0.30, 0.45, 0.40, 1),
        green          = imgui.ImVec4(0.20, 1.00, 0.60, 1),
        yellow         = imgui.ImVec4(0.90, 1.00, 0.30, 1),
        red            = imgui.ImVec4(1.00, 0.35, 0.45, 1),
        blue           = imgui.ImVec4(0.30, 0.72, 1.00, 1),
        grad1          = imgui.ImVec4(0.00, 0.90, 0.65, 1),
        grad2          = imgui.ImVec4(0.45, 0.30, 1.00, 1),
        glass          = imgui.ImVec4(0.02, 0.06, 0.05, 0.70),
    },
    -- Lagoon: лагуна — тёмный океан + тропическая бирюза + коралловое золото
    lagoon = {
        name = "Lagoon", icon = "L",
        sidebar        = imgui.ImVec4(0.010, 0.025, 0.045, 1),
        sidebar_active = imgui.ImVec4(0.018, 0.050, 0.088, 1),
        bg             = imgui.ImVec4(0.014, 0.032, 0.058, 0.99),
        header         = imgui.ImVec4(0.010, 0.025, 0.048, 1),
        card           = imgui.ImVec4(0.022, 0.050, 0.088, 0.92),
        card_hover     = imgui.ImVec4(0.030, 0.065, 0.115, 0.95),
        input          = imgui.ImVec4(0.015, 0.035, 0.065, 0.90),
        accent         = imgui.ImVec4(0.00, 0.88, 0.80, 1),
        accent2        = imgui.ImVec4(1.00, 0.80, 0.25, 1),
        accent_dim     = imgui.ImVec4(0.00, 0.60, 0.55, 1),
        text           = imgui.ImVec4(0.88, 0.97, 0.99, 1),
        text2          = imgui.ImVec4(0.45, 0.68, 0.78, 1),
        text3          = imgui.ImVec4(0.25, 0.42, 0.52, 1),
        green          = imgui.ImVec4(0.00, 1.00, 0.72, 1),
        yellow         = imgui.ImVec4(1.00, 0.82, 0.15, 1),
        red            = imgui.ImVec4(1.00, 0.35, 0.40, 1),
        blue           = imgui.ImVec4(0.30, 0.70, 1.00, 1),
        grad1          = imgui.ImVec4(0.00, 0.85, 0.78, 1),
        grad2          = imgui.ImVec4(1.00, 0.75, 0.18, 1),
        glass          = imgui.ImVec4(0.02, 0.05, 0.09, 0.75),
    },
    crimson = {
        name = "Crimson", icon = "%",
        sidebar        = imgui.ImVec4(0.042, 0.018, 0.018, 1),
        sidebar_active = imgui.ImVec4(0.090, 0.032, 0.032, 1),
        bg             = imgui.ImVec4(0.055, 0.022, 0.022, 0.99),
        header         = imgui.ImVec4(0.045, 0.018, 0.018, 1),
        card           = imgui.ImVec4(0.080, 0.035, 0.035, 0.92),
        card_hover     = imgui.ImVec4(0.110, 0.048, 0.048, 0.95),
        input          = imgui.ImVec4(0.055, 0.025, 0.025, 0.90),
        accent         = imgui.ImVec4(1.00, 0.20, 0.28, 1),
        accent2        = imgui.ImVec4(1.00, 0.45, 0.52, 1),
        accent_dim     = imgui.ImVec4(0.82, 0.12, 0.18, 1),
        text           = imgui.ImVec4(1.00, 0.94, 0.94, 1),
        text2          = imgui.ImVec4(0.75, 0.55, 0.55, 1),
        text3          = imgui.ImVec4(0.52, 0.36, 0.36, 1),
        green          = imgui.ImVec4(0.30, 0.92, 0.55, 1),
        yellow         = imgui.ImVec4(1.00, 0.85, 0.30, 1),
        red            = imgui.ImVec4(1.00, 0.25, 0.30, 1),
        blue           = imgui.ImVec4(0.45, 0.68, 1.00, 1),
        grad1          = imgui.ImVec4(1.00, 0.18, 0.25, 1),
        grad2          = imgui.ImVec4(0.85, 0.05, 0.40, 1),
        glass          = imgui.ImVec4(0.08, 0.03, 0.03, 0.70),
    },
    sakura = {
        name = "Sakura", icon = "^",
        sidebar        = imgui.ImVec4(0.042, 0.028, 0.038, 1),
        sidebar_active = imgui.ImVec4(0.085, 0.052, 0.072, 1),
        bg             = imgui.ImVec4(0.052, 0.035, 0.048, 0.99),
        header         = imgui.ImVec4(0.045, 0.030, 0.040, 1),
        card           = imgui.ImVec4(0.078, 0.052, 0.068, 0.92),
        card_hover     = imgui.ImVec4(0.105, 0.070, 0.092, 0.95),
        input          = imgui.ImVec4(0.052, 0.035, 0.048, 0.90),
        accent         = imgui.ImVec4(1.00, 0.58, 0.72, 1),
        accent2        = imgui.ImVec4(1.00, 0.75, 0.85, 1),
        accent_dim     = imgui.ImVec4(0.82, 0.40, 0.55, 1),
        text           = imgui.ImVec4(1.00, 0.96, 0.98, 1),
        text2          = imgui.ImVec4(0.72, 0.58, 0.65, 1),
        text3          = imgui.ImVec4(0.50, 0.38, 0.44, 1),
        green          = imgui.ImVec4(0.40, 0.90, 0.60, 1),
        yellow         = imgui.ImVec4(1.00, 0.88, 0.40, 1),
        red            = imgui.ImVec4(1.00, 0.32, 0.42, 1),
        blue           = imgui.ImVec4(0.52, 0.70, 1.00, 1),
        grad1          = imgui.ImVec4(1.00, 0.50, 0.68, 1),
        grad2          = imgui.ImVec4(0.85, 0.40, 0.90, 1),
        glass          = imgui.ImVec4(0.07, 0.04, 0.06, 0.70),
    },
    -- ??? НОВЫЕ ТЕМЫ ??????????????????????????????????????????????????????????
    -- Void: глубокий космос — почти чёрный с электрически-фиолетовым акцентом
    -- Bloodmoon: кровавая луна — глубокий бургундский с тёплым янтарным свечением
    bloodmoon = {
        name = "Bloodmoon", icon = "B",
        sidebar        = imgui.ImVec4(0.030, 0.010, 0.006, 1),
        sidebar_active = imgui.ImVec4(0.062, 0.018, 0.010, 1),
        bg             = imgui.ImVec4(0.040, 0.013, 0.008, 0.99),
        header         = imgui.ImVec4(0.030, 0.010, 0.006, 1),
        card           = imgui.ImVec4(0.062, 0.022, 0.012, 0.92),
        card_hover     = imgui.ImVec4(0.085, 0.030, 0.016, 0.95),
        input          = imgui.ImVec4(0.042, 0.015, 0.008, 0.90),
        accent         = imgui.ImVec4(0.95, 0.68, 0.12, 1),
        accent2        = imgui.ImVec4(1.00, 0.85, 0.35, 1),
        accent_dim     = imgui.ImVec4(0.78, 0.48, 0.06, 1),
        text           = imgui.ImVec4(1.00, 0.96, 0.86, 1),
        text2          = imgui.ImVec4(0.78, 0.52, 0.35, 1),
        text3          = imgui.ImVec4(0.50, 0.30, 0.18, 1),
        green          = imgui.ImVec4(0.45, 0.92, 0.40, 1),
        yellow         = imgui.ImVec4(1.00, 0.88, 0.10, 1),
        red            = imgui.ImVec4(1.00, 0.20, 0.15, 1),
        blue           = imgui.ImVec4(0.40, 0.68, 1.00, 1),
        grad1          = imgui.ImVec4(0.98, 0.65, 0.08, 1),
        grad2          = imgui.ImVec4(0.88, 0.28, 0.05, 1),
        glass          = imgui.ImVec4(0.06, 0.02, 0.01, 0.75),
    },
    -- Cyber: киберпанк — абсолютный чёрный + электрический жёлтый (единственная жёлтая тема)
    cyber = {
        name = "Cyber", icon = "Y",
        sidebar        = imgui.ImVec4(0.010, 0.012, 0.006, 1),
        sidebar_active = imgui.ImVec4(0.024, 0.028, 0.012, 1),
        bg             = imgui.ImVec4(0.014, 0.016, 0.008, 0.99),
        header         = imgui.ImVec4(0.010, 0.012, 0.006, 1),
        card           = imgui.ImVec4(0.025, 0.030, 0.014, 0.92),
        card_hover     = imgui.ImVec4(0.035, 0.042, 0.018, 0.95),
        input          = imgui.ImVec4(0.016, 0.020, 0.009, 0.90),
        accent         = imgui.ImVec4(0.95, 0.95, 0.00, 1),
        accent2        = imgui.ImVec4(1.00, 1.00, 0.30, 1),
        accent_dim     = imgui.ImVec4(0.68, 0.68, 0.00, 1),
        text           = imgui.ImVec4(0.96, 0.98, 0.90, 1),
        text2          = imgui.ImVec4(0.60, 0.65, 0.38, 1),
        text3          = imgui.ImVec4(0.36, 0.40, 0.22, 1),
        green          = imgui.ImVec4(0.25, 1.00, 0.35, 1),
        yellow         = imgui.ImVec4(1.00, 1.00, 0.10, 1),
        red            = imgui.ImVec4(1.00, 0.22, 0.22, 1),
        blue           = imgui.ImVec4(0.30, 0.75, 1.00, 1),
        grad1          = imgui.ImVec4(0.95, 0.95, 0.00, 1),
        grad2          = imgui.ImVec4(1.00, 0.52, 0.00, 1),
        glass          = imgui.ImVec4(0.02, 0.03, 0.01, 0.78),
    },
    -- Nebula: туманность — чёрный космос с горячим розово-оранжевым свечением (как NGC-фото)
    nebula = {
        name = "Nebula", icon = "N",
        sidebar        = imgui.ImVec4(0.016, 0.008, 0.022, 1),
        sidebar_active = imgui.ImVec4(0.035, 0.015, 0.048, 1),
        bg             = imgui.ImVec4(0.022, 0.010, 0.030, 0.99),
        header         = imgui.ImVec4(0.016, 0.008, 0.022, 1),
        card           = imgui.ImVec4(0.038, 0.018, 0.052, 0.92),
        card_hover     = imgui.ImVec4(0.052, 0.025, 0.072, 0.95),
        input          = imgui.ImVec4(0.024, 0.012, 0.034, 0.90),
        accent         = imgui.ImVec4(0.98, 0.28, 0.62, 1),
        accent2        = imgui.ImVec4(1.00, 0.52, 0.75, 1),
        accent_dim     = imgui.ImVec4(0.75, 0.15, 0.42, 1),
        text           = imgui.ImVec4(0.98, 0.92, 0.98, 1),
        text2          = imgui.ImVec4(0.68, 0.45, 0.65, 1),
        text3          = imgui.ImVec4(0.42, 0.26, 0.42, 1),
        green          = imgui.ImVec4(0.28, 0.98, 0.65, 1),
        yellow         = imgui.ImVec4(1.00, 0.85, 0.25, 1),
        red            = imgui.ImVec4(1.00, 0.22, 0.30, 1),
        blue           = imgui.ImVec4(0.38, 0.68, 1.00, 1),
        grad1          = imgui.ImVec4(0.98, 0.25, 0.58, 1),
        grad2          = imgui.ImVec4(1.00, 0.55, 0.15, 1),
        glass          = imgui.ImVec4(0.04, 0.02, 0.06, 0.78),
    },
    -- Forest: густой лес — тёмно-зелёная база с ярко-изумрудным акцентом
    forest = {
        name = "Forest", icon = "F",
        sidebar        = imgui.ImVec4(0.012, 0.028, 0.018, 1),
        sidebar_active = imgui.ImVec4(0.022, 0.055, 0.032, 1),
        bg             = imgui.ImVec4(0.018, 0.038, 0.025, 0.99),
        header         = imgui.ImVec4(0.014, 0.030, 0.020, 1),
        card           = imgui.ImVec4(0.028, 0.060, 0.038, 0.92),
        card_hover     = imgui.ImVec4(0.038, 0.080, 0.050, 0.95),
        input          = imgui.ImVec4(0.020, 0.042, 0.028, 0.90),
        accent         = imgui.ImVec4(0.25, 0.95, 0.45, 1),
        accent2        = imgui.ImVec4(0.55, 1.00, 0.68, 1),
        accent_dim     = imgui.ImVec4(0.15, 0.68, 0.30, 1),
        text           = imgui.ImVec4(0.88, 0.96, 0.90, 1),
        text2          = imgui.ImVec4(0.48, 0.68, 0.55, 1),
        text3          = imgui.ImVec4(0.28, 0.42, 0.34, 1),
        green          = imgui.ImVec4(0.25, 1.00, 0.55, 1),
        yellow         = imgui.ImVec4(0.88, 1.00, 0.25, 1),
        red            = imgui.ImVec4(1.00, 0.35, 0.40, 1),
        blue           = imgui.ImVec4(0.35, 0.72, 1.00, 1),
        grad1          = imgui.ImVec4(0.20, 0.92, 0.42, 1),
        grad2          = imgui.ImVec4(0.00, 0.70, 0.58, 1),
        glass          = imgui.ImVec4(0.02, 0.06, 0.04, 0.70),
    },
    -- Dusk: сумерки — тёмно-лиловая база с закатно-оранжевым акцентом
    dusk = {
        name = "Dusk", icon = "D",
        sidebar        = imgui.ImVec4(0.032, 0.020, 0.048, 1),
        sidebar_active = imgui.ImVec4(0.065, 0.038, 0.095, 1),
        bg             = imgui.ImVec4(0.040, 0.025, 0.060, 0.99),
        header         = imgui.ImVec4(0.032, 0.020, 0.050, 1),
        card           = imgui.ImVec4(0.062, 0.040, 0.092, 0.92),
        card_hover     = imgui.ImVec4(0.085, 0.055, 0.125, 0.95),
        input          = imgui.ImVec4(0.042, 0.028, 0.065, 0.90),
        accent         = imgui.ImVec4(1.00, 0.55, 0.18, 1),
        accent2        = imgui.ImVec4(1.00, 0.72, 0.40, 1),
        accent_dim     = imgui.ImVec4(0.85, 0.38, 0.08, 1),
        text           = imgui.ImVec4(1.00, 0.95, 0.92, 1),
        text2          = imgui.ImVec4(0.72, 0.55, 0.65, 1),
        text3          = imgui.ImVec4(0.48, 0.35, 0.48, 1),
        green          = imgui.ImVec4(0.40, 0.92, 0.55, 1),
        yellow         = imgui.ImVec4(1.00, 0.88, 0.30, 1),
        red            = imgui.ImVec4(1.00, 0.28, 0.38, 1),
        blue           = imgui.ImVec4(0.50, 0.65, 1.00, 1),
        grad1          = imgui.ImVec4(1.00, 0.48, 0.12, 1),
        grad2          = imgui.ImVec4(0.70, 0.15, 0.85, 1),
        glass          = imgui.ImVec4(0.06, 0.04, 0.09, 0.70),
    },
    -- Slate: стальной профессионал — холодный тёмно-серый с небесно-голубым
    -- Phoenix: феникс — угольный + алый + золото (два горячих акцента)
    phoenix = {
        name = "Phoenix", icon = "P",
        sidebar        = imgui.ImVec4(0.018, 0.015, 0.012, 1),
        sidebar_active = imgui.ImVec4(0.040, 0.028, 0.018, 1),
        bg             = imgui.ImVec4(0.025, 0.018, 0.014, 0.99),
        header         = imgui.ImVec4(0.018, 0.014, 0.010, 1),
        card           = imgui.ImVec4(0.042, 0.030, 0.020, 0.92),
        card_hover     = imgui.ImVec4(0.058, 0.042, 0.028, 0.95),
        input          = imgui.ImVec4(0.028, 0.020, 0.015, 0.90),
        accent         = imgui.ImVec4(1.00, 0.20, 0.12, 1),
        accent2        = imgui.ImVec4(1.00, 0.78, 0.00, 1),
        accent_dim     = imgui.ImVec4(0.78, 0.12, 0.06, 1),
        text           = imgui.ImVec4(1.00, 0.96, 0.88, 1),
        text2          = imgui.ImVec4(0.75, 0.55, 0.38, 1),
        text3          = imgui.ImVec4(0.48, 0.34, 0.22, 1),
        green          = imgui.ImVec4(0.40, 0.95, 0.38, 1),
        yellow         = imgui.ImVec4(1.00, 0.88, 0.00, 1),
        red            = imgui.ImVec4(1.00, 0.15, 0.08, 1),
        blue           = imgui.ImVec4(0.42, 0.70, 1.00, 1),
        grad1          = imgui.ImVec4(1.00, 0.18, 0.10, 1),
        grad2          = imgui.ImVec4(1.00, 0.78, 0.00, 1),
        glass          = imgui.ImVec4(0.04, 0.03, 0.02, 0.78),
    },

    -- ??? ПРЕМИУМ ТЕМЫ ?????????????????????????????????????????????????????????

    -- Abyss: бездна — абсолютно чёрная база с биолюминесцентным морским свечением
    abyss = {
        name = "Abyss", icon = "A",
        sidebar        = imgui.ImVec4(0.008, 0.010, 0.015, 1),
        sidebar_active = imgui.ImVec4(0.015, 0.032, 0.042, 1),
        bg             = imgui.ImVec4(0.012, 0.015, 0.022, 0.99),
        header         = imgui.ImVec4(0.008, 0.012, 0.018, 1),
        card           = imgui.ImVec4(0.020, 0.030, 0.042, 0.92),
        card_hover     = imgui.ImVec4(0.028, 0.045, 0.062, 0.95),
        input          = imgui.ImVec4(0.014, 0.020, 0.030, 0.90),
        accent         = imgui.ImVec4(0.00, 0.88, 0.78, 1),
        accent2        = imgui.ImVec4(0.25, 1.00, 0.90, 1),
        accent_dim     = imgui.ImVec4(0.00, 0.58, 0.52, 1),
        text           = imgui.ImVec4(0.85, 0.96, 0.98, 1),
        text2          = imgui.ImVec4(0.40, 0.60, 0.65, 1),
        text3          = imgui.ImVec4(0.22, 0.35, 0.40, 1),
        green          = imgui.ImVec4(0.00, 1.00, 0.55, 1),
        yellow         = imgui.ImVec4(0.95, 0.90, 0.25, 1),
        red            = imgui.ImVec4(1.00, 0.25, 0.42, 1),
        blue           = imgui.ImVec4(0.10, 0.60, 1.00, 1),
        grad1          = imgui.ImVec4(0.00, 0.82, 0.75, 1),
        grad2          = imgui.ImVec4(0.00, 0.42, 0.98, 1),
        glass          = imgui.ImVec4(0.01, 0.02, 0.04, 0.75),
    },

    -- Inferno: вулкан — угольно-чёрная база с раскалённой лавой
    inferno = {
        name = "Inferno", icon = "I",
        sidebar        = imgui.ImVec4(0.025, 0.010, 0.008, 1),
        sidebar_active = imgui.ImVec4(0.058, 0.020, 0.012, 1),
        bg             = imgui.ImVec4(0.032, 0.012, 0.008, 0.99),
        header         = imgui.ImVec4(0.022, 0.010, 0.006, 1),
        card           = imgui.ImVec4(0.052, 0.022, 0.014, 0.92),
        card_hover     = imgui.ImVec4(0.072, 0.030, 0.018, 0.95),
        input          = imgui.ImVec4(0.035, 0.015, 0.010, 0.90),
        accent         = imgui.ImVec4(1.00, 0.38, 0.00, 1),
        accent2        = imgui.ImVec4(1.00, 0.62, 0.12, 1),
        accent_dim     = imgui.ImVec4(0.85, 0.22, 0.00, 1),
        text           = imgui.ImVec4(1.00, 0.95, 0.88, 1),
        text2          = imgui.ImVec4(0.78, 0.52, 0.38, 1),
        text3          = imgui.ImVec4(0.50, 0.30, 0.20, 1),
        green          = imgui.ImVec4(0.50, 0.95, 0.35, 1),
        yellow         = imgui.ImVec4(1.00, 0.88, 0.00, 1),
        red            = imgui.ImVec4(1.00, 0.15, 0.10, 1),
        blue           = imgui.ImVec4(0.40, 0.65, 1.00, 1),
        grad1          = imgui.ImVec4(1.00, 0.35, 0.00, 1),
        grad2          = imgui.ImVec4(1.00, 0.85, 0.00, 1),
        glass          = imgui.ImVec4(0.05, 0.02, 0.01, 0.75),
    },

    -- Prism: призма — почти чёрный с переливающимся pink?cyan градиентом
    prism = {
        name = "Prism", icon = "P",
        sidebar        = imgui.ImVec4(0.015, 0.015, 0.022, 1),
        sidebar_active = imgui.ImVec4(0.032, 0.025, 0.055, 1),
        bg             = imgui.ImVec4(0.020, 0.018, 0.032, 0.99),
        header         = imgui.ImVec4(0.015, 0.014, 0.025, 1),
        card           = imgui.ImVec4(0.035, 0.028, 0.058, 0.92),
        card_hover     = imgui.ImVec4(0.048, 0.038, 0.080, 0.95),
        input          = imgui.ImVec4(0.022, 0.020, 0.038, 0.90),
        accent         = imgui.ImVec4(0.88, 0.25, 0.88, 1),
        accent2        = imgui.ImVec4(1.00, 0.55, 1.00, 1),
        accent_dim     = imgui.ImVec4(0.65, 0.12, 0.68, 1),
        text           = imgui.ImVec4(0.96, 0.92, 1.00, 1),
        text2          = imgui.ImVec4(0.62, 0.52, 0.78, 1),
        text3          = imgui.ImVec4(0.38, 0.30, 0.52, 1),
        green          = imgui.ImVec4(0.30, 1.00, 0.72, 1),
        yellow         = imgui.ImVec4(1.00, 0.88, 0.28, 1),
        red            = imgui.ImVec4(1.00, 0.28, 0.52, 1),
        blue           = imgui.ImVec4(0.35, 0.70, 1.00, 1),
        grad1          = imgui.ImVec4(1.00, 0.20, 0.80, 1),
        grad2          = imgui.ImVec4(0.00, 0.88, 1.00, 1),
        glass          = imgui.ImVec4(0.03, 0.02, 0.05, 0.75),
    },

    -- Toxic: токсик — смоляной чёрный с ядовито-зелёным кислотным свечением
    toxic = {
        name = "Toxic", icon = "T",
        sidebar        = imgui.ImVec4(0.010, 0.018, 0.010, 1),
        sidebar_active = imgui.ImVec4(0.018, 0.042, 0.018, 1),
        bg             = imgui.ImVec4(0.014, 0.022, 0.012, 0.99),
        header         = imgui.ImVec4(0.010, 0.018, 0.010, 1),
        card           = imgui.ImVec4(0.022, 0.040, 0.020, 0.92),
        card_hover     = imgui.ImVec4(0.030, 0.055, 0.028, 0.95),
        input          = imgui.ImVec4(0.015, 0.028, 0.014, 0.90),
        accent         = imgui.ImVec4(0.42, 1.00, 0.00, 1),
        accent2        = imgui.ImVec4(0.68, 1.00, 0.25, 1),
        accent_dim     = imgui.ImVec4(0.28, 0.72, 0.00, 1),
        text           = imgui.ImVec4(0.88, 0.98, 0.85, 1),
        text2          = imgui.ImVec4(0.48, 0.68, 0.42, 1),
        text3          = imgui.ImVec4(0.28, 0.42, 0.25, 1),
        green          = imgui.ImVec4(0.35, 1.00, 0.15, 1),
        yellow         = imgui.ImVec4(0.95, 1.00, 0.00, 1),
        red            = imgui.ImVec4(1.00, 0.28, 0.30, 1),
        blue           = imgui.ImVec4(0.30, 0.80, 1.00, 1),
        grad1          = imgui.ImVec4(0.38, 1.00, 0.00, 1),
        grad2          = imgui.ImVec4(0.00, 0.85, 0.45, 1),
        glass          = imgui.ImVec4(0.02, 0.04, 0.02, 0.75),
    },

    -- RoseGold: розовое золото — тёмная слива с металлическим розово-золотым
    rosegold = {
        name = "Rose Gold", icon = "R",
        sidebar        = imgui.ImVec4(0.038, 0.020, 0.028, 1),
        sidebar_active = imgui.ImVec4(0.075, 0.038, 0.052, 1),
        bg             = imgui.ImVec4(0.048, 0.026, 0.036, 0.99),
        header         = imgui.ImVec4(0.038, 0.020, 0.028, 1),
        card           = imgui.ImVec4(0.072, 0.042, 0.058, 0.92),
        card_hover     = imgui.ImVec4(0.095, 0.058, 0.078, 0.95),
        input          = imgui.ImVec4(0.050, 0.028, 0.040, 0.90),
        accent         = imgui.ImVec4(0.95, 0.62, 0.58, 1),
        accent2        = imgui.ImVec4(1.00, 0.80, 0.72, 1),
        accent_dim     = imgui.ImVec4(0.78, 0.42, 0.38, 1),
        text           = imgui.ImVec4(1.00, 0.96, 0.94, 1),
        text2          = imgui.ImVec4(0.78, 0.58, 0.65, 1),
        text3          = imgui.ImVec4(0.52, 0.36, 0.42, 1),
        green          = imgui.ImVec4(0.38, 0.92, 0.58, 1),
        yellow         = imgui.ImVec4(1.00, 0.85, 0.42, 1),
        red            = imgui.ImVec4(1.00, 0.28, 0.38, 1),
        blue           = imgui.ImVec4(0.52, 0.72, 1.00, 1),
        grad1          = imgui.ImVec4(0.98, 0.62, 0.55, 1),
        grad2          = imgui.ImVec4(0.95, 0.78, 0.38, 1),
        glass          = imgui.ImVec4(0.08, 0.04, 0.06, 0.75),
    },

    -- Storm: шторм — грозовой тёмно-синий + электрический белый + молния-пурпур
    storm = {
        name = "Storm", icon = "~",
        sidebar        = imgui.ImVec4(0.015, 0.018, 0.038, 1),
        sidebar_active = imgui.ImVec4(0.030, 0.035, 0.075, 1),
        bg             = imgui.ImVec4(0.020, 0.024, 0.050, 0.99),
        header         = imgui.ImVec4(0.015, 0.018, 0.040, 1),
        card           = imgui.ImVec4(0.032, 0.040, 0.080, 0.92),
        card_hover     = imgui.ImVec4(0.044, 0.055, 0.108, 0.95),
        input          = imgui.ImVec4(0.022, 0.028, 0.058, 0.90),
        accent         = imgui.ImVec4(0.88, 0.94, 1.00, 1),
        accent2        = imgui.ImVec4(0.72, 0.30, 1.00, 1),
        accent_dim     = imgui.ImVec4(0.55, 0.65, 0.80, 1),
        text           = imgui.ImVec4(0.92, 0.95, 1.00, 1),
        text2          = imgui.ImVec4(0.52, 0.60, 0.80, 1),
        text3          = imgui.ImVec4(0.30, 0.36, 0.55, 1),
        green          = imgui.ImVec4(0.25, 1.00, 0.60, 1),
        yellow         = imgui.ImVec4(1.00, 0.90, 0.20, 1),
        red            = imgui.ImVec4(1.00, 0.28, 0.35, 1),
        blue           = imgui.ImVec4(0.42, 0.78, 1.00, 1),
        grad1          = imgui.ImVec4(0.85, 0.95, 1.00, 1),
        grad2          = imgui.ImVec4(0.65, 0.25, 0.98, 1),
        glass          = imgui.ImVec4(0.03, 0.04, 0.08, 0.78),
    },

    -- Opal: опал — антрацит + тёплый персик + холодный ментол (переливающийся)
    opal = {
        name = "Opal", icon = "O",
        sidebar        = imgui.ImVec4(0.018, 0.020, 0.025, 1),
        sidebar_active = imgui.ImVec4(0.036, 0.040, 0.052, 1),
        bg             = imgui.ImVec4(0.024, 0.026, 0.032, 0.99),
        header         = imgui.ImVec4(0.018, 0.020, 0.025, 1),
        card           = imgui.ImVec4(0.040, 0.044, 0.058, 0.92),
        card_hover     = imgui.ImVec4(0.054, 0.060, 0.078, 0.95),
        input          = imgui.ImVec4(0.026, 0.030, 0.038, 0.90),
        accent         = imgui.ImVec4(1.00, 0.68, 0.52, 1),
        accent2        = imgui.ImVec4(0.52, 1.00, 0.88, 1),
        accent_dim     = imgui.ImVec4(0.78, 0.45, 0.32, 1),
        text           = imgui.ImVec4(0.96, 0.96, 0.98, 1),
        text2          = imgui.ImVec4(0.62, 0.65, 0.72, 1),
        text3          = imgui.ImVec4(0.38, 0.40, 0.46, 1),
        green          = imgui.ImVec4(0.35, 0.98, 0.72, 1),
        yellow         = imgui.ImVec4(1.00, 0.88, 0.40, 1),
        red            = imgui.ImVec4(1.00, 0.35, 0.42, 1),
        blue           = imgui.ImVec4(0.40, 0.75, 1.00, 1),
        grad1          = imgui.ImVec4(1.00, 0.65, 0.48, 1),
        grad2          = imgui.ImVec4(0.48, 0.98, 0.85, 1),
        glass          = imgui.ImVec4(0.04, 0.04, 0.05, 0.78),
    },

    -- Jungle: джунгли — тёмный с ядовито-жёлтым + коралловым + сочной зеленью
    jungle = {
        name = "Jungle", icon = "J",
        sidebar        = imgui.ImVec4(0.010, 0.020, 0.012, 1),
        sidebar_active = imgui.ImVec4(0.018, 0.042, 0.022, 1),
        bg             = imgui.ImVec4(0.014, 0.026, 0.016, 0.99),
        header         = imgui.ImVec4(0.010, 0.020, 0.012, 1),
        card           = imgui.ImVec4(0.022, 0.045, 0.026, 0.92),
        card_hover     = imgui.ImVec4(0.030, 0.062, 0.035, 0.95),
        input          = imgui.ImVec4(0.015, 0.030, 0.018, 0.90),
        accent         = imgui.ImVec4(0.82, 1.00, 0.00, 1),
        accent2        = imgui.ImVec4(1.00, 0.42, 0.22, 1),
        accent_dim     = imgui.ImVec4(0.58, 0.72, 0.00, 1),
        text           = imgui.ImVec4(0.90, 0.98, 0.88, 1),
        text2          = imgui.ImVec4(0.50, 0.70, 0.48, 1),
        text3          = imgui.ImVec4(0.28, 0.44, 0.28, 1),
        green          = imgui.ImVec4(0.28, 1.00, 0.28, 1),
        yellow         = imgui.ImVec4(0.90, 1.00, 0.00, 1),
        red            = imgui.ImVec4(1.00, 0.30, 0.25, 1),
        blue           = imgui.ImVec4(0.28, 0.78, 1.00, 1),
        grad1          = imgui.ImVec4(0.78, 1.00, 0.00, 1),
        grad2          = imgui.ImVec4(1.00, 0.40, 0.18, 1),
        glass          = imgui.ImVec4(0.02, 0.05, 0.02, 0.78),
    },
}

local themeOrder = {
    -- Ряд 1: тёмные холодные + переливы
    "midnight",  "abyss",    "neon",     "prism",
    "storm",     "opal",     "carnival",

    -- Ряд 2: горячие и огненные
    "inferno",   "ember",    "crimson",  "bloodmoon",
    "dusk",      "nebula",   "phoenix",

    -- Ряд 3: природные и органические
    "aurora",    "forest",   "toxic",    "rosegold",
    "sakura",    "lagoon",   "jungle",

    -- Ряд 4:
    "cyber",
}
local function T() return colorThemes[settings.currentTheme] or colorThemes.midnight end
local T_u32 = {}  -- Кэш ImVec4toU32 для цветов темы
local function applyTheme(tn)
    local t = colorThemes[tn] or colorThemes.midnight
    local s = imgui.GetStyle(); local c = s.Colors
    s.WindowRounding = 20; s.FrameRounding = 14; s.GrabRounding = 14
    s.ScrollbarRounding = 14; s.ChildRounding = 18; s.PopupRounding = 18
    s.TabRounding = 14; s.WindowPadding = imgui.ImVec2(0,0)
    s.FramePadding = imgui.ImVec2(14,10); s.ItemSpacing = imgui.ImVec2(8,6)
    s.ScrollbarSize = 6; s.GrabMinSize = 14
    s.WindowTitleAlign = imgui.ImVec2(0.5,0.5)
    s.WindowBorderSize = 0; s.ChildBorderSize = 0
    s.FrameBorderSize = 0; s.TabBorderSize = 0
    c[imgui.Col.WindowBg] = t.bg
    c[imgui.Col.ChildBg] = imgui.ImVec4(0,0,0,0)
    c[imgui.Col.PopupBg] = imgui.ImVec4(t.bg.x,t.bg.y,t.bg.z,0.98)
    c[imgui.Col.Border] = imgui.ImVec4(0.25,0.25,0.30,0.10)
    c[imgui.Col.TitleBg] = t.header; c[imgui.Col.TitleBgActive] = t.header
    c[imgui.Col.Button] = imgui.ImVec4(t.card.x,t.card.y,t.card.z,0.65)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.25)
    c[imgui.Col.ButtonActive] = imgui.ImVec4(t.accent_dim.x,t.accent_dim.y,t.accent_dim.z,0.50)
    c[imgui.Col.FrameBg] = t.input
    c[imgui.Col.FrameBgHovered] = imgui.ImVec4(t.input.x+0.04,t.input.y+0.04,t.input.z+0.04,0.95)
    c[imgui.Col.Text] = t.text; c[imgui.Col.TextDisabled] = t.text3
    c[imgui.Col.Header] = imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.10)
    c[imgui.Col.HeaderHovered] = imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.20)
    c[imgui.Col.Separator] = imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.12)
    c[imgui.Col.ScrollbarBg] = imgui.ImVec4(0,0,0,0.02)
    c[imgui.Col.ScrollbarGrab] = imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.25)
    c[imgui.Col.ScrollbarGrabActive] = t.accent
    c[imgui.Col.CheckMark] = t.accent2
    c[imgui.Col.TextSelectedBg] = imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.20)
    -- Строим кэш U32 для цветов темы
    T_u32 = {}
    for k, v in pairs(t) do
        if type(v) == "userdata" then T_u32[k] = ImVec4toU32(v) end
    end
end

loadSettings()
if not colorThemes[settings.currentTheme] then settings.currentTheme = "midnight" end

-- Forward declarations (используются до определения)
local addActivity
local recentActivity = {}

-- =========================================================================
-- РП ОТЫГРЫШ ОРУЖИЯ (система идентична Arizona Helper)
-- =========================================================================
local rpGuns = {
    configFile = configDirectory .. "/rpguns.json",
    data = {
        -- Список оружий: id, name (в винительном падеже), enable, rpTake (1=спина,2=карман,3=пояс,4=кобура)
        rp_guns = {
            {id=0,  name="кулаки",                    enable=true,  rpTake=2},
            {id=1,  name="кастеты",                   enable=false, rpTake=2},
            {id=2,  name="клюшку для гольфа",         enable=false, rpTake=1},
            {id=3,  name="дубинку",                   enable=true,  rpTake=3},
            {id=4,  name="острый нож",                enable=false, rpTake=3},
            {id=5,  name="биту",                      enable=false, rpTake=1},
            {id=6,  name="лопату",                    enable=true,  rpTake=1},
            {id=7,  name="кий",                       enable=false, rpTake=1},
            {id=8,  name="катану",                    enable=false, rpTake=1},
            {id=9,  name="бензопилу",                 enable=false, rpTake=1},
            {id=10, name="игрушку",                   enable=false, rpTake=2},
            {id=11, name="большую игрушку",           enable=false, rpTake=2},
            {id=12, name="моторную игрушку",          enable=false, rpTake=2},
            {id=13, name="большую игрушку",           enable=false, rpTake=2},
            {id=14, name="букет цветов",              enable=true,  rpTake=1},
            {id=15, name="трость",                    enable=false, rpTake=1},
            {id=16, name="осколочную гранату",        enable=false, rpTake=3},
            {id=17, name="дымовую гранату",           enable=true,  rpTake=3},
            {id=18, name="коктейль Молотова",         enable=true,  rpTake=3},
            {id=22, name="пистолет Colt45",           enable=false, rpTake=4},
            {id=23, name="электрошокер Taser X26P",   enable=true,  rpTake=4},
            {id=24, name="пистолет Desert Eagle",     enable=true,  rpTake=4},
            {id=25, name="дробовик",                  enable=true,  rpTake=1},
            {id=26, name="обрез",                     enable=true,  rpTake=4},
            {id=27, name="улучшенный обрез",          enable=false, rpTake=1},
            {id=28, name="ПП Micro Uzi",              enable=true,  rpTake=3},
            {id=29, name="ПП MP5",                    enable=true,  rpTake=4},
            {id=30, name="автомат AK47",              enable=true,  rpTake=1},
            {id=31, name="автомат M4",                enable=true,  rpTake=1},
            {id=32, name="ПП Tec9",                   enable=true,  rpTake=4},
            {id=33, name="винтовку Rifle",            enable=true,  rpTake=1},
            {id=34, name="снайперскую винтовку",      enable=true,  rpTake=1},
            {id=35, name="РПГ",                       enable=false, rpTake=1},
            {id=36, name="ПТУР",                      enable=false, rpTake=1},
            {id=37, name="огнемёт",                   enable=false, rpTake=1},
            {id=38, name="миниган",                   enable=false, rpTake=1},
            {id=39, name="динамит",                   enable=false, rpTake=3},
            {id=40, name="детонатор",                 enable=false, rpTake=3},
            {id=41, name="перцовый балончик",         enable=true,  rpTake=2},
            {id=42, name="огнетушитель",              enable=true,  rpTake=1},
            {id=43, name="фотоаппарат",               enable=true,  rpTake=2},
            {id=44, name="ПНВ",                       enable=false, rpTake=3},
            {id=45, name="тепловизор",                enable=false, rpTake=3},
            {id=46, name="парашут",                   enable=true,  rpTake=1},
            {id=49, name="т/с",                       enable=false, rpTake=1},
            {id=71, name="пистолет Desert Eagle Steel",  enable=true, rpTake=4},
            {id=72, name="пистолет Desert Eagle Gold",   enable=true, rpTake=4},
            {id=73, name="пистолет Glock Gradient",      enable=true, rpTake=4},
            {id=74, name="пистолет Desert Eagle Flame",  enable=true, rpTake=4},
            {id=75, name="пистолет Python Royal",        enable=true, rpTake=4},
            {id=76, name="пистолет Python Silver",       enable=true, rpTake=4},
            {id=77, name="автомат AK-47 Roses",          enable=true, rpTake=1},
            {id=78, name="автомат AK-47 Gold",           enable=true, rpTake=1},
            {id=79, name="пулемёт M249 Graffiti",        enable=true, rpTake=1},
            {id=80, name="золотую Сайгу",                enable=true, rpTake=1},
            {id=81, name="ПП Standart",                  enable=true, rpTake=4},
            {id=82, name="пулемёт M249",                 enable=true, rpTake=1},
            {id=83, name="ПП Skorp",                     enable=true, rpTake=4},
            {id=84, name="автомат AKS74 камуфляжный",    enable=true, rpTake=1},
            {id=85, name="автомат AK47 камуфляжный",     enable=true, rpTake=1},
            {id=86, name="дробовик Rebecca",             enable=true, rpTake=1},
            {id=87, name="Doomgun",                      enable=true, rpTake=1},
            {id=88, name="ледяной меч",                  enable=true, rpTake=1},
            {id=89, name="портальную пушку",             enable=true, rpTake=4},
            {id=90, name="оглушающую гранату",           enable=true, rpTake=3},
            {id=91, name="ослепляющую гранату",          enable=true, rpTake=3},
            {id=92, name="снайперскую винтовку TAC50",   enable=true, rpTake=1},
            {id=93, name="оглушающий пистолет",          enable=true, rpTake=4},
            {id=94, name="снежную пушку",                enable=true, rpTake=1},
            {id=95, name="пиксельный бластер",           enable=true, rpTake=3},
            {id=96, name="автомат M4 Gold",              enable=true, rpTake=1},
            {id=97, name="бандитский дробовик",          enable=true, rpTake=1},
            {id=98, name="ПП Uzi Graffiti",              enable=true, rpTake=4},
            {id=99, name="золотую монтировку",           enable=true, rpTake=1},
            {id=100,name="биту Compton",                 enable=true, rpTake=1},
            {id=101,name="пистолет SciFi Deagle",        enable=true, rpTake=4},
            {id=102,name="автомат SciFi AK47",           enable=true, rpTake=1},
            {id=103,name="дробовик SciFi",               enable=true, rpTake=1},
            {id=104,name="нож SciFi",                    enable=true, rpTake=3},
            {id=105,name="сканер",                       enable=false,rpTake=4},
            {id=106,name="золотой нож",                  enable=true, rpTake=3},
            {id=107,name="катану Нир",                   enable=true, rpTake=1},
        },
        -- Расположение: {partOn (откуда берёт), partOff (куда кладёт)}
        rpTakeNames = {
            {"из-за спины", "за спину"},
            {"из кармана",  "в карман"},
            {"из пояса",    "на пояс"},
            {"из кобуры",   "в кобуру"},
        },
        gunActions = { on={}, off={}, partOn={}, partOff={} },
        byId = {},
        oldGun = nil,
        nowGun = 0,
    },
}

-- Инициализация lookup-таблиц (аналог initialize_guns)
function rpGuns.initialize()
    local d       = rpGuns.data
    local female  = settings.rpWeaponFemale
    d.byId        = {}
    d.gunActions  = { on={}, off={}, partOn={}, partOff={} }
    for _, weapon in pairs(d.rp_guns) do
        local id      = weapon.id
        local takeType = d.rpTakeNames[weapon.rpTake] or d.rpTakeNames[1]
        d.byId[id]              = weapon
        d.gunActions.partOn[id]  = takeType[1]
        d.gunActions.partOff[id] = takeType[2]
        -- Глагол "достать": нож(3), гранаты(16-18), флеш(90,91) ? "снял/а"
        if id == 3 or (id > 15 and id < 19) or id == 90 or id == 91 then
            d.gunActions.on[id]  = female and "сняла" or "снял"
        else
            d.gunActions.on[id]  = female and "достала" or "достал"
        end
        -- Глагол "убрать": нож(3), гранаты(16-18), динамит/детонатор(39-40), флеш(90,91) ? "повесил/а"
        if id == 3 or (id > 15 and id < 19) or (id > 38 and id < 41) or id == 90 or id == 91 then
            d.gunActions.off[id] = female and "повесила" or "повесил"
        else
            d.gunActions.off[id] = female and "убрала" or "убрал"
        end
    end
end

function rpGuns.getName(id)
    if rpGuns.data.byId[id] then return rpGuns.data.byId[id].name end
    return "оружие"
end

function rpGuns.isExists(id)
    return rpGuns.data.byId[id] ~= nil
end

function rpGuns.isEnabled(id)
    local w = rpGuns.data.byId[id]
    return w and w.enable or false
end

function rpGuns.handleNew(weaponId)
    addNotification("Новое оружие ID "..weaponId..": добавлено как «оружие»", C.NOTIFY_INFO)
    table.insert(rpGuns.data.rp_guns, {id=weaponId, name="оружие", enable=true, rpTake=1})
    rpGuns.saveConfig()
    rpGuns.initialize()
end

-- Основная логика смены оружия (аналог processWeaponChange)
function rpGuns.process(oldGun, nowGun)
    if not settings.rpWeaponEnabled then return end
    local chatOk,chatA = pcall(sampIsChatInputActive)
    local dlgOk,dlgA   = pcall(sampIsDialogActive)
    if (chatOk and chatA) or (dlgOk and dlgA) then return end
    if not rpGuns.isExists(oldGun) then rpGuns.handleNew(oldGun) end
    if not rpGuns.isExists(nowGun) then rpGuns.handleNew(nowGun) end
    local act = rpGuns.data.gunActions
    if not act.off[oldGun] or not act.on[nowGun] then
        rpGuns.initialize(); return
    end
    local msg
    if oldGun == 0 and nowGun == 0 then
        return
    elseif oldGun == 0 and not rpGuns.isEnabled(nowGun) then
        return
    elseif nowGun == 0 and not rpGuns.isEnabled(oldGun) then
        return
    elseif not rpGuns.isEnabled(oldGun) and rpGuns.isEnabled(nowGun) then
        -- было выключено, стало включено
        msg = string.format("/me %s %s %s",
            act.on[nowGun], rpGuns.getName(nowGun), act.partOn[nowGun])
    elseif rpGuns.isEnabled(oldGun) and not rpGuns.isEnabled(nowGun) then
        -- было включено, стало выключено
        msg = string.format("/me %s %s %s",
            act.off[oldGun], rpGuns.getName(oldGun), act.partOff[oldGun])
    elseif oldGun == 0 then
        msg = string.format("/me %s %s %s",
            act.on[nowGun], rpGuns.getName(nowGun), act.partOn[nowGun])
    elseif nowGun == 0 then
        msg = string.format("/me %s %s %s",
            act.off[oldGun], rpGuns.getName(oldGun), act.partOff[oldGun])
    elseif rpGuns.isEnabled(oldGun) and rpGuns.isEnabled(nowGun) then
        -- смена одного оружия на другое — единое /me
        msg = string.format("/me %s %s %s, после чего %s %s %s",
            act.off[oldGun], rpGuns.getName(oldGun), act.partOff[oldGun],
            act.on[nowGun],  rpGuns.getName(nowGun),  act.partOn[nowGun])
    end
    if msg then
        safeSendChat(msg)
    end
end

function rpGuns.saveConfig()
    local f = io.open(rpGuns.configFile, 'w')
    if not f then return end
    local ok, j = pcall(encodeJson, rpGuns.data.rp_guns)
    if ok and j then f:write(j) end
    f:close()
end

function rpGuns.loadConfig()
    if not doesFileExistSafe(rpGuns.configFile) then return end
    local f = io.open(rpGuns.configFile, 'r')
    if not f then return end
    local raw = f:read('*a'); f:close()
    local ok, data = pcall(decodeJson, raw)
    if ok and type(data) == "table" then
        rpGuns.data.rp_guns = data
    end
end

rpGuns.loadConfig()
rpGuns.initialize()

-- =========================================================================
-- AUTO FIND: ФУНКЦИИ
-- =========================================================================
local function afCheckOnline(id)
    id = tonumber(id)
    if id and sampIsPlayerConnected(id) then return sampGetPlayerNickname(id) end
    return false
end

local function afReset()
    autoFind.active = false; autoFind.targetId = -1; autoFind.targetNick = ""
    autoFind.lastId = -1; autoFind.lastNick = ""; autoFind.waitInta = false
    autoFind.proximityAlerted = false; autoFind.lastDist = nil
end

local function afDoFind()
    if autoFind.lastId == -1 then return end
    if not afCheckOnline(autoFind.lastId) then
        addNotification("AutoFind: " .. autoFind.lastNick .. "[" .. autoFind.lastId .. "] вышел!", C.NOTIFY_WARNING)
        afReset(); return
    end
    -- Проверка близости цели
    if autoFind.proximityAlert then
        local ok2, targetHandle = pcall(sampGetCharHandleBySampPlayerId, autoFind.lastId)
        if ok2 and targetHandle then
            local ok3, tx, ty, tz = pcall(getCharCoordinates, targetHandle)
            local ok4, mx, my, mz = pcall(getCharCoordinates, playerPed)
            if ok3 and ok4 then
                local dx, dy, dz = tx - mx, ty - my, tz - mz
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                autoFind.lastDist = math.floor(dist)
                if dist <= autoFind.proximityDistance then
                    if not autoFind.proximityAlerted then
                        autoFind.proximityAlerted = true
                        addNotification(
                            "AutoFind: " .. autoFind.lastNick .. " рядом! (" .. math.floor(dist) .. "м)",
                            C.NOTIFY_SUCCESS, 8)
                        if autoFind.soundAlert then
                            pcall(function() playSound(1056, mx, my, mz) end)
                        end
                    end
                    return -- не шлём /find если уже рядом
                else
                    autoFind.proximityAlerted = false
                end
            end
        end
    end
    safeSendChat("/find " .. autoFind.lastId)
end

local function afCommand(arg)
    local id = arg:match('(%d+)')
    if id then
        id = tonumber(id)
        local nick = afCheckOnline(id)
        if not nick then addNotification("AutoFind: ID " .. id .. " не в сети!", C.NOTIFY_ERROR); afReset(); return end
        if id == autoFind.lastId then addNotification("AutoFind: поиск " .. autoFind.lastNick .. " завершён", C.NOTIFY_INFO); afReset(); return end
        autoFind.active = true; autoFind.lastId = id; autoFind.lastNick = nick
        addNotification("AutoFind: поиск " .. nick .. "[" .. id .. "] начат!", C.NOTIFY_SUCCESS)
    else
        if autoFind.lastId ~= -1 then addNotification("AutoFind: поиск " .. autoFind.lastNick .. " завершён", C.NOTIFY_INFO) end
        afReset()
    end
end

-- =========================================================================
-- БЫСТРЫЕ ДЕЙСТВИЯ (QUICK ACTIONS)
-- =========================================================================
local QA = {
    active=false, mode="foot",
    targetPid=-1, targetVeh=-1, targetSid=-1, targetNick="",
    tx=0, ty=0, tz=0,
    execTargetId=nil, execTargetNick=nil,
    foot={}, vehicle={},
    footCol={1.0,0.82,0.20,1.0}, vehCol={0.13,0.83,0.78,1.0},
    maxDist=30.0, markerSz=14.0,
    editTab=0, _held=false, _lastFind=0, _editSlot=nil,
    subTab=0,
    -- Редактор бинда внутри QA
    editingSlot     = nil,   -- ссылка на слот чей бинд редактируем
    editingBind     = nil,   -- ссылка на bind объект
    editingBindIdx  = nil,   -- индекс в binds[]
    _stepsActive    = false, -- поле шагов в фокусе
    FIND_RATE=0.05,
    holdKey=0x12,   -- default Alt (0x12)
    holdKeyMod=0,
    configFile = configDirectory .. "/quick_actions.json",
}

function QA:save()
    local f = io.open(self.configFile,"w"); if not f then return end
    local ok,j = pcall(encodeJson,{foot=self.foot,vehicle=self.vehicle,
        maxDist=self.maxDist,footCol=self.footCol,vehCol=self.vehCol,
        markerSz=self.markerSz,holdKey=self.holdKey,holdKeyMod=self.holdKeyMod})
    if ok and j then f:write(j) end; f:close()
end

function QA:load()
    if not doesFileExistSafe(self.configFile) then return end
    local f = io.open(self.configFile,"r"); if not f then return end
    local raw = f:read("*a"); f:close()
    local ok,d = pcall(decodeJson,raw)
    if not ok or type(d)~="table" then return end
    if type(d.foot)       =="table"  then self.foot       = d.foot       end
    if type(d.vehicle)    =="table"  then self.vehicle    = d.vehicle    end
    if type(d.maxDist)    =="number" then self.maxDist    = d.maxDist    end
    if type(d.footCol)    =="table"  then self.footCol    = d.footCol    end
    if type(d.vehCol)     =="table"  then self.vehCol     = d.vehCol    end
    if type(d.markerSz)   =="number" then self.markerSz   = d.markerSz  end
    if type(d.holdKey)    =="number" then self.holdKey    = d.holdKey    end
    if type(d.holdKeyMod) =="number" then self.holdKeyMod = d.holdKeyMod end
    -- Гарантируем что слоты всегда таблицы
    if type(self.foot)    ~= "table" then self.foot    = {} end
    if type(self.vehicle) ~= "table" then self.vehicle = {} end
end

function QA:col()
    local c = self.mode=="foot" and self.footCol or self.vehCol
    return imgui.ImVec4(c[1],c[2],c[3],c[4])
end

function QA:findPlayer()
    local cx,cy,cz = getActiveCameraCoordinates()
    local lx,ly,lz = getActiveCameraPointAt()
    local dx,dy,dz = lx-cx, ly-cy, lz-cz
    local len = math.sqrt(dx*dx+dy*dy+dz*dz)
    if len < 0.001 then return end
    dx,dy,dz = dx/len, dy/len, dz/len
    local _,myId = sampGetPlayerIdByCharHandle(playerPed)
    local bestPid=-1; local bestDot=0.75; local bestNick=""
    local bx,by,bz = 0,0,0
    -- getAllChars() возвращает только загруженные модели — правильный способ в MoonLoader
    for _,ped in pairs(getAllChars()) do
        local result, id = sampGetPlayerIdByCharHandle(ped)
        if result and id and id ~= (myId or -1) and id ~= -1 then
            local px,py,pz = getCharCoordinates(ped)
            local ex,ey,ez = px-cx, py-cy, pz-cz
            local el = math.sqrt(ex*ex+ey*ey+ez*ez)
            if el > 0.5 and el < self.maxDist then
                local dot = (ex*dx + ey*dy + ez*dz) / el
                if dot > bestDot then
                    bestDot=dot; bestPid=id
                    bestNick = sampGetPlayerNickname(id) or ("ID_"..id)
                    bx,by,bz = px,py,pz+1.05
                end
            end
        end
    end
    self.targetPid=bestPid; self.targetSid=bestPid; self.targetNick=bestNick
    self.tx,self.ty,self.tz = bx,by,bz
end

function QA:findVehicle()
    local cx,cy,cz = getActiveCameraCoordinates()
    local lx,ly,lz = getActiveCameraPointAt()
    local dx,dy,dz = lx-cx, ly-cy, lz-cz
    local len = math.sqrt(dx*dx+dy*dy+dz*dz)
    if len < 0.001 then return end
    dx,dy,dz = dx/len, dy/len, dz/len
    local _,myId = sampGetPlayerIdByCharHandle(playerPed)
    local bestVeh=-1; local bestDot=0.75; local bestNick=""; local bestSid=-1
    local bx,by,bz = 0,0,0
    for _,ped in pairs(getAllChars()) do
        local result, id = sampGetPlayerIdByCharHandle(ped)
        if result and id and id ~= (myId or -1) and id ~= -1 then
            if isCharInAnyCar(ped) then
                local veh = storeCarCharIsInNoSave(ped)
                if veh then
                    local px,py,pz = getCarCoordinates(veh)
                    local ex,ey,ez = px-cx, py-cy, pz-cz
                    local el = math.sqrt(ex*ex+ey*ey+ez*ez)
                    if el > 1 and el < self.maxDist then
                        local dot = (ex*dx + ey*dy + ez*dz) / el
                        if dot > bestDot then
                            bestDot=dot; bestVeh=veh
                            bestNick = sampGetPlayerNickname(id) or ("ID_"..id)
                            bx,by,bz = px,py,pz+1.2
                            local svOk,sv = pcall(sampGetVehicleIdByHandle, veh)
                            bestSid = svOk and sv or -1
                        end
                    end
                end
            end
        end
    end
    self.targetVeh=bestVeh
    self.targetSid = bestSid~=-1 and bestSid or (bestVeh~=-1 and bestVeh or -1)
    self.targetNick = bestVeh~=-1 and ("ТС/"..bestNick) or ""
    self.tx,self.ty,self.tz = bx,by,bz
end

function QA:update()
    -- Для мышиных кнопок _held устанавливается в onWindowMessage
    -- Для клавиатурных — через isKeyDown
    if self.holdKey == 0 then
        self._held = false
    else
        local held = isKeyDown(self.holdKey)
        if held and self.holdKeyMod == 1 then held = isKeyDown(C.KEY_CTRL)  end
        if held and self.holdKeyMod == 2 then held = isKeyDown(C.KEY_SHIFT) end
        if held and self.holdKeyMod == 3 then held = isKeyDown(C.KEY_ALT)   end
        self._held = held
    end
    local chatOk,chatA = pcall(sampIsChatInputActive)
    local dlgOk,dlgA   = pcall(sampIsDialogActive)
    local canAct = self._held and not isAnyCursorWindowOpen()
        and not (chatOk and chatA) and not (dlgOk and dlgA)
        and not S.activeBinder
    if not canAct then
        if self.active then
            self.active=false; self.targetPid=-1; self.targetVeh=-1
            self.targetSid=-1; self.targetNick=""
        end
        return
    end
    self.active = true
    local icOk,ic = pcall(isCharInAnyCar, playerPed)
    self.mode = (icOk and ic) and "vehicle" or "foot"
    local now = os.clock()
    if now - self._lastFind >= self.FIND_RATE then
        self._lastFind = now
        local ok, err
        if self.mode == "foot" then
            ok, err = pcall(function() self:findPlayer() end)
        else
            ok, err = pcall(function() self:findVehicle() end)
        end
        if not ok then
            self.targetPid=-1; self.targetVeh=-1; self.targetSid=-1; self.targetNick=""
        end
    end
end

-- QA:execute минимален — addActivity/performBind/binds объявлены ПОСЛЕ этой функции.
-- Вся тяжёлая логика в qa_thread внутри main() где всё доступно.
function QA:execute(slot, bind, snapSid, snapNick)
    if S.activeBinder then addNotification("Биндер занят!", C.NOTIFY_WARNING); return false end
    if not bind       then addNotification("QA: бинд не найден!", C.NOTIFY_ERROR); return false end
    if bind.enabled == false then addNotification("Бинд выключен!", C.NOTIFY_WARNING); return false end
    if snapSid == -1  then addNotification("QA: цель не выбрана!", C.NOTIFY_WARNING); return false end
    self.execTargetId   = snapSid
    self.execTargetNick = snapNick
    addNotification("QA: "..(slot.label or "?").." ? "..snapNick, C.NOTIFY_SUCCESS, 2.5)
    return true
end

-- =========================================================================
-- КЛАВИШИ
-- =========================================================================
local keyNames = {
    -- Управление
    [0x08]='Bksp',  [0x09]='Tab',    [0x0D]='Enter',  [0x1B]='Esc',
    [0x20]='Space', [0x2C]='PrtScr', [0x13]='Pause',  [0xC0]='`',
    -- Модификаторы
    [0x10]='Shift', [0x11]='Ctrl',   [0x12]='Alt',
    [0x14]='Caps',  [0x90]='NumLk',  [0x91]='ScrLk',
    -- Навигация
    [0x21]='PgUp',  [0x22]='PgDn',   [0x23]='End',    [0x24]='Home',
    [0x25]='Left',  [0x26]='Up',     [0x27]='Right',  [0x28]='Down',
    [0x2D]='Ins',   [0x2E]='Del',
    -- Цифры
    [0x30]='0',[0x31]='1',[0x32]='2',[0x33]='3',[0x34]='4',
    [0x35]='5',[0x36]='6',[0x37]='7',[0x38]='8',[0x39]='9',
    -- Буквы
    [0x41]='A',[0x42]='B',[0x43]='C',[0x44]='D',[0x45]='E',
    [0x46]='F',[0x47]='G',[0x48]='H',[0x49]='I',[0x4A]='J',
    [0x4B]='K',[0x4C]='L',[0x4D]='M',[0x4E]='N',[0x4F]='O',
    [0x50]='P',[0x51]='Q',[0x52]='R',[0x53]='S',[0x54]='T',
    [0x55]='U',[0x56]='V',[0x57]='W',[0x58]='X',[0x59]='Y',[0x5A]='Z',
    -- F-клавиши
    [0x70]='F1',[0x71]='F2',[0x72]='F3',[0x73]='F4',
    [0x74]='F5',[0x75]='F6',[0x76]='F7',[0x77]='F8',
    [0x78]='F9',[0x79]='F10',[0x7A]='F11',[0x7B]='F12',
    -- Нумпад цифры
    [0x60]='Num0',[0x61]='Num1',[0x62]='Num2',[0x63]='Num3',
    [0x64]='Num4',[0x65]='Num5',[0x66]='Num6',[0x67]='Num7',
    [0x68]='Num8',[0x69]='Num9',
    -- Нумпад операторы
    [0x6A]='Num*', [0x6B]='Num+', [0x6D]='Num-',
    [0x6E]='Num.', [0x6F]='Num/',
    -- Знаки
    [0xBB]='=',  [0xBD]='-',  [0xDB]='[',  [0xDD]=']',
    [0xDC]='\\', [0xBA]=';',  [0xDE]="'",  [0xBC]=',',
    [0xBE]='.',  [0xBF]='/',
    -- Кнопки мыши (WM_xBUTTONDOWN wparam-коды используем как VK)
    [0x01]='Mouse1', [0x02]='Mouse2', [0x04]='Mouse3',
    [0x05]='Mouse4', [0x06]='Mouse5',
}

local function getKeyName(k, m)
    if not k or k == 0 then return "---" end
    local p = ""
    if m == 1 then p = "Ctrl+" elseif m == 2 then p = "Shift+" elseif m == 3 then p = "Alt+" end
    return p .. (keyNames[k] or safeFormat("0x%X", k))
end

-- drawKeyChip: рисует красивый chip с модификатором и клавишей через DrawList
-- Возвращает ширину нарисованного chip
local function drawKeyChip(dl, x, y, k, m, t, alpha)
    alpha = alpha or 1.0
    local h = 18
    local r = 5
    local px, py = 5, 3
    local gap = 3
    local keyStr = k and k ~= 0 and (keyNames[k] or safeFormat("0x%X", k)) or nil
    if not keyStr then
        -- "не задан" chip
        local noTxt = u8("—")
        local sz = imgui.CalcTextSize(noTxt)
        local w = sz.x + px*2
        dl:AddRectFilled(imgui.ImVec2(x, y), imgui.ImVec2(x+w, y+h),
            ImVec4toU32(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z, 0.08*alpha)), r)
        dl:AddRect(imgui.ImVec2(x, y), imgui.ImVec2(x+w, y+h),
            ImVec4toU32(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z, 0.18*alpha)), r, 15, 0.5)
        dl:AddText(imgui.ImVec2(x+px, y+py), ImVec4toU32(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z, 0.45*alpha)), noTxt)
        return w
    end
    local modStr = nil
    if m == 1 then modStr = "Ctrl"
    elseif m == 2 then modStr = "Shift"
    elseif m == 3 then modStr = "Alt" end
    local totalW = 0
    if modStr then
        local ms = imgui.CalcTextSize(u8(modStr))
        local mw = ms.x + px*2
        dl:AddRectFilled(imgui.ImVec2(x, y), imgui.ImVec2(x+mw, y+h),
            ImVec4toU32(imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z, 0.10*alpha)), r)
        dl:AddRect(imgui.ImVec2(x, y), imgui.ImVec2(x+mw, y+h),
            ImVec4toU32(imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z, 0.30*alpha)), r, 15, 0.5)
        dl:AddText(imgui.ImVec2(x+px, y+py), ImVec4toU32(imgui.ImVec4(t.accent2.x,t.accent2.y,t.accent2.z, 0.80*alpha)), u8(modStr))
        totalW = mw
        -- маленький "+" между частями
        dl:AddText(imgui.ImVec2(x+mw+1, y+py), ImVec4toU32(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z, 0.40*alpha)), u8("+"))
        totalW = totalW + gap + 7
        x = x + totalW
    end
    local ks = imgui.CalcTextSize(u8(keyStr))
    local kw = ks.x + px*2
    dl:AddRectFilled(imgui.ImVec2(x, y), imgui.ImVec2(x+kw, y+h),
        ImVec4toU32(imgui.ImVec4(t.yellow.x,t.yellow.y,t.yellow.z, 0.10*alpha)), r)
    dl:AddRect(imgui.ImVec2(x, y), imgui.ImVec2(x+kw, y+h),
        ImVec4toU32(imgui.ImVec4(t.yellow.x,t.yellow.y,t.yellow.z, 0.35*alpha)), r, 15, 0.5)
    dl:AddText(imgui.ImVec2(x+px, y+py), ImVec4toU32(imgui.ImVec4(t.yellow.x,t.yellow.y,t.yellow.z, 0.90*alpha)), u8(keyStr))
    return totalW + kw
end

local function checkModifier(m)
    if m==0 then return true end
    if m==1 then return isKeyDown(C.KEY_CTRL) end
    if m==2 then return isKeyDown(C.KEY_SHIFT) end
    if m==3 then return isKeyDown(C.KEY_ALT) end
    return false
end

local function checkKeyCombo(k, m)
    if k == 0 then return false end
    -- Кнопки мыши (VK 0x01-0x06) — проверяем через isKeyDown
    -- wasKeyPressed не работает для мыши, но isKeyDown работает
    local pressed = false
    if k <= 0x06 then
        pressed = S._mouseJustPressed == k
    else
        pressed = wasKeyPressed(k)
    end
    if not pressed then return false end
    return checkModifier(m)
end

-- =========================================================================
-- ПЕРЕМЕННЫЕ
-- =========================================================================
local simpleVariables = {}
local function initVariables()
    simpleVariables = {
        my_id        = { desc = "Ваш ID",        cat = "Игрок",   func = function()
            local _, id = sampGetPlayerIdByCharHandle(playerPed); return id or -1
        end },
        my_nick      = { desc = "Ваш ник",       cat = "Игрок",   func = function()
            local _, id = sampGetPlayerIdByCharHandle(playerPed)
            if not id then return "Unknown" end
            return sampGetPlayerNickname(id) or "Unknown"
        end },
        my_rpnick    = { desc = "РП-ник",         cat = "Игрок",   func = function()
            local _, id = sampGetPlayerIdByCharHandle(playerPed)
            if not id then return "Unknown" end
            local nick = sampGetPlayerNickname(id)
            if not nick then return "Unknown" end
            return nick:gsub("_", " ")
        end },
        my_name      = { desc = "Имя",            cat = "Игрок",   func = function()
            local _, id = sampGetPlayerIdByCharHandle(playerPed)
            if not id then return "?" end
            local n = sampGetPlayerNickname(id)
            if not n then return "?" end
            return n:match("^(.-)_") or n
        end },
        my_surname   = { desc = "Фамилия",        cat = "Игрок",   func = function()
            local _, id = sampGetPlayerIdByCharHandle(playerPed)
            if not id then return "?" end
            local n = sampGetPlayerNickname(id)
            if not n then return "?" end
            return n:match("_(.+)$") or n
        end },
        my_hp        = { desc = "HP",             cat = "Статы",   func = function()
            local _, id = sampGetPlayerIdByCharHandle(playerPed)
            return (id and sampGetPlayerHealth(id)) or 0
        end },
        my_armor     = { desc = "Броня",          cat = "Статы",   func = function()
            local _, id = sampGetPlayerIdByCharHandle(playerPed)
            return (id and sampGetPlayerArmor(id)) or 0
        end },
        my_ping      = { desc = "Пинг",           cat = "Статы",   func = function()
            local _, id = sampGetPlayerIdByCharHandle(playerPed)
            return (id and sampGetPlayerPing(id)) or 0
        end },
        my_score     = { desc = "Уровень",        cat = "Статы",   func = function()
            local _, id = sampGetPlayerIdByCharHandle(playerPed)
            return (id and sampGetPlayerScore(id)) or 0
        end },
        my_weapon    = { desc = "ID оружия",      cat = "Статы",   func = function()
            return getCurrentCharWeapon(playerPed) or 0
        end },
        my_x         = { desc = "X",              cat = "Мир",     func = function()
            local x = getCharCoordinates(playerPed); return math.floor(x or 0)
        end },
        my_y         = { desc = "Y",              cat = "Мир",     func = function()
            local _, y = getCharCoordinates(playerPed); return math.floor(y or 0)
        end },
        my_z         = { desc = "Z",              cat = "Мир",     func = function()
            local _, _, z = getCharCoordinates(playerPed); return math.floor(z or 0)
        end },
        time         = { desc = "HH:MM:SS",       cat = "Время",   func = function() return os.date("%H:%M:%S") end },
        time_short   = { desc = "HH:MM",          cat = "Время",   func = function() return os.date("%H:%M") end },
        date         = { desc = "DD.MM.YYYY",     cat = "Время",   func = function() return os.date("%d.%m.%Y") end },
        day          = { desc = "День недели",    cat = "Время",   func = function()
            local days = {"Вс","Пн","Вт","Ср","Чт","Пт","Сб"}
            return days[tonumber(os.date("%w")) + 1] or "?"
        end },
        player_count = { desc = "Онлайн",         cat = "Сервер",  func = function() return sampGetPlayerCount(true) or 0 end },
        nearest_id   = { desc = "Ближайший ID",   cat = "Другие",  func = function() return getClosestPlayerId() end },
        random_100   = { desc = "Рандом 1-100",   cat = "Утилиты", func = function() return math.random(1, 100) end },
        session_time = { desc = "Время сессии",   cat = "Утилиты", func = function() return formatTimeShort(os.clock() - S.sessionStartTime) end },
        bind_count   = { desc = "Кол-во биндов",  cat = "Утилиты", func = function() return #binds end },
        target_id    = { desc = "ID цели (QA)",   cat = "QA",      func = function() return QA.execTargetId or QA.targetSid end },
        target_nick  = { desc = "Ник цели (QA)",  cat = "QA",      func = function() return QA.execTargetNick or QA.targetNick end },
    }
end

-- УЛУЧШЕНИЕ #8 — кэширование
local cachedClosestPlayer = { id = -1, time = 0 }
function getClosestPlayerId()
    local now = os.clock()
    if (now - cachedClosestPlayer.time) < C.CLOSEST_PLAYER_CACHE_TIME then return cachedClosestPlayer.id end
    local minD, closest = 999999, -1
    local ok, myId = pcall(function() return select(2, sampGetPlayerIdByCharHandle(playerPed)) end)
    if not ok or not myId then cachedClosestPlayer.id = -1; cachedClosestPlayer.time = now; return -1 end
    local ok2, mx, my, mz = pcall(getCharCoordinates, playerPed)
    if not ok2 then cachedClosestPlayer.id = -1; cachedClosestPlayer.time = now; return -1 end
    for i = 0, 999 do
        if i ~= myId and sampIsPlayerConnected(i) then
            local h = sampGetCharHandleBySampPlayerId(i)
            if h then
                local ok3, px, py, pz = pcall(getCharCoordinates, h)
                if ok3 then
                    local dx, dy, dz = px-mx, py-my, pz-mz
                    local d = dx*dx + dy*dy + dz*dz
                    if d < minD then minD = d; closest = i end
                end
            end
        end
    end
    cachedClosestPlayer.id = closest; cachedClosestPlayer.time = now
    return closest
end

local _noCacheVars = { random_100 = true }

local function resolveVariable(vn, cache)
    cache = cache or {}
    if not _noCacheVars[vn] and cache[vn] then return cache[vn] end
    local entry = simpleVariables[vn]
    if entry and entry.func then
        local ok, val = pcall(entry.func)
        if ok and val ~= nil then
            local result = tostring(val)
            if not _noCacheVars[vn] then cache[vn] = result end
            return result
        end
    end
    return nil
end

-- =========================================================================
-- ИСТОРИЯ И АКТИВНОСТЬ
-- =========================================================================
local bindHistory = {}
local function addHistory(bindName, duration, steps, success)
    table.insert(bindHistory, 1, {
        name = bindName, time = os.time(), clock = os.clock(),
        duration = duration, steps = steps, success = success
    })
    while #bindHistory > C.MAX_HISTORY do table.remove(bindHistory) end
end

addActivity = function(text, atype)
    table.insert(recentActivity, 1, {
        text = text, time = os.clock(), atype = atype or "bind",
        timestamp = os.date("%H:%M:%S"), date = os.date("%d.%m.%Y")
    })
    while #recentActivity > C.MAX_ACTIVITY do table.remove(recentActivity) end
end

local hourlyStats = {}
local function updateHourlyStats()
    local hour = tonumber(os.date("%H"))
    if not hourlyStats[hour] then hourlyStats[hour] = 0 end
    hourlyStats[hour] = hourlyStats[hour] + 1
end

-- =========================================================================
-- БИНДЕР: ДАННЫЕ
-- =========================================================================
local binds = {}
local keyBindMap = {}  -- [key*10+mod] = bind, быстрый индекс хоткеев
local function rebuildKeyBindMap()
    keyBindMap = {}
    for _, bind in ipairs(binds) do
        if bind.enabled ~= false and bind.key and bind.key ~= 0 then
            local combo = bind.key * 10 + (bind.key_mod or 0)
            if not keyBindMap[combo] then
                keyBindMap[combo] = bind
            end
        end
    end
end

local function saveActivityLog()
    if not ensureDirectory(configDirectory) then return end
    local f = io.open(U.activityLogFile, 'w'); if not f then return end
    local sv = {}
    for i = 1, math.min(#recentActivity, C.MAX_ACTIVITY) do
        table.insert(sv, {
            text = recentActivity[i].text, atype = recentActivity[i].atype,
            timestamp = recentActivity[i].timestamp, date = recentActivity[i].date,
            time_saved = recentActivity[i].time
        })
    end
    local ok, j = pcall(encodeJson, sv)
    if ok and j then f:write(j) end; f:close()
end

local function loadActivityLog()
    if not doesFileExistSafe(U.activityLogFile) then return end
    local f = io.open(U.activityLogFile, 'r')
    if not f then return end
    local c = f:read('*a'); f:close()
    if not c or #c < 2 then return end
    local ok, data = pcall(decodeJson, c)
    if ok and type(data) == "table" then
        for _, item in ipairs(data) do
            table.insert(recentActivity, {
                text = item.text or "", atype = item.atype or "system",
                timestamp = item.timestamp or "", date = item.date or "",
                time = os.clock() - 9999
            })
        end
        while #recentActivity > C.MAX_ACTIVITY do table.remove(recentActivity) end
    end
end

local function splitSteps(text)
    local steps = {}; if not text or text == "" then return steps end
    for line in text:gmatch("([^\r\n]+)") do
        local tr = trim(line)
        if tr ~= "" and not tr:match("^//") and not tr:match("^#") then table.insert(steps, tr) end
    end; return steps
end

local function joinSteps(steps)
    if not steps or #steps == 0 then return "" end
    return table.concat(steps, "\n")
end


-- =========================================================================
-- ОТСЛЕЖИВАНИЕ НЕСОХРАНЁННЫХ ИЗМЕНЕНИЙ (6.5, 6.6)
-- =========================================================================
local function getEditorSnapshot()
    if not S.selectedBindIndex then return nil end
    return {
        name     = ffi.string(B.editNameBuf),
        cmd      = ffi.string(B.editCmdBuf),
        steps    = ffi.string(B.editStepsBuf),
        delay    = B.editDelayBuf[0],
        key      = B.editKeyBuf[0],
        keyMod   = B.editKeyModBuf[0],
        cooldown = B.editCooldownBuf[0],
        enabled  = B.editEnabledBuf[0],
        favorite = B.editFavoriteBuf[0],
        category = B.editCategoryBuf[0],
    }
end

local function checkUnsavedChanges()
    if not S.selectedBindIndex or not S.lastSavedState then
        S.hasUnsavedChanges = false
        return false
    end
    local c = getEditorSnapshot()
    if not c then S.hasUnsavedChanges = false; return false end
    S.hasUnsavedChanges = (
        c.name     ~= S.lastSavedState.name or
        c.cmd      ~= S.lastSavedState.cmd or
        c.steps    ~= S.lastSavedState.steps or
        c.delay    ~= S.lastSavedState.delay or
        c.key      ~= S.lastSavedState.key or
        c.keyMod   ~= S.lastSavedState.keyMod or
        c.cooldown ~= S.lastSavedState.cooldown or
        c.enabled  ~= S.lastSavedState.enabled or
        c.favorite ~= S.lastSavedState.favorite or
        c.category ~= S.lastSavedState.category
    )
    return S.hasUnsavedChanges
end

local function markEditorClean()
    S.lastSavedState = getEditorSnapshot()
    S.hasUnsavedChanges = false
    S.autoSaveTimer = 0
end

local function discardAndSelect(idx)
    S.hasUnsavedChanges = false
    S.lastSavedState = nil
    S._stepsFieldActive = false
    S.autoSaveTimer = 0
    B._qaEditorLoaded = false   -- принудительно перезагружать буферы при следующем открытии QA редактора
    if idx then
        S.selectedBindIndex = idx
        local b = binds[idx]
        ffi.copy(B.editNameBuf, u8(b.name or ""))
        ffi.copy(B.editCmdBuf, (b.cmd and b.cmd ~= "") and ("/" .. b.cmd) or "")
        ffi.copy(B.editStepsBuf, u8(joinSteps(b.steps or {})))
        ffi.copy(B.editDescBuf, u8(b.desc or ""))
        B.editDelayBuf[0] = b.delay or settings.defaultDelay
        B.editKeyBuf[0] = b.key or 0
        B.editKeyModBuf[0] = b.key_mod or 0
        B.editCooldownBuf[0] = b.cooldown or 0
        B.editEnabledBuf[0] = b.enabled ~= false
        B.editFavoriteBuf[0] = b.favorite or false
        B.editCategoryBuf[0] = b.category or 0
        markEditorClean()
    else
        S.selectedBindIndex = nil
        ffi.copy(B.editNameBuf, ""); ffi.copy(B.editCmdBuf, "")
        ffi.copy(B.editStepsBuf, ""); ffi.copy(B.editDescBuf, "")
        B.editDelayBuf[0] = settings.defaultDelay
        B.editKeyBuf[0] = 0; B.editKeyModBuf[0] = 0
        B.editCooldownBuf[0] = 0
        B.editEnabledBuf[0] = true; B.editFavoriteBuf[0] = false
        B.editCategoryBuf[0] = 0
        S.lastSavedState = nil
    end
end

local function requestBindAction(actionType, idx)
    if S.hasUnsavedChanges then
        S.showUnsavedConfirm = true
        S.unsavedAction = { type = actionType, idx = idx }
        return false
    end
    return true
end


local function unregisterBindCommands()
    for _, cmd in ipairs(S.registeredCommands) do pcall(sampUnregisterChatCommand, cmd) end
    S.registeredCommands = {}
end

-- forward declaration
local performBind
local saveCurrentBind

-- УЛУЧШЕНИЕ #17 — валидация дубликатов
local function registerBindCommands()
    unregisterBindCommands()
    local cmdSet = {}
    for i, b in ipairs(binds) do
        if b.cmd and b.cmd ~= "" and b.enabled ~= false then
            local cmd = b.cmd:match("^(%S+)") or ""
            if cmd ~= "" then
                if cmdSet[cmd] then
                    addNotification("Дубликат команды /" .. cmd .. ": '" .. (b.name or "?") .. "' и '" .. (cmdSet[cmd].name or "?") .. "'", C.NOTIFY_WARNING)
                else
                    cmdSet[cmd] = b
                end
            end
        end
    end
    for _, b in ipairs(binds) do
        if b.cmd and b.cmd ~= "" and b.enabled ~= false then
            local fullCmd = b.cmd
            local cmd = fullCmd:match("^(%S+)") or ""
            if cmd ~= "" then
                local ref = b
                local expectedArgs = {}
                for argName in fullCmd:gmatch("{([^}]+)}") do table.insert(expectedArgs, argName) end
                local ok = pcall(sampRegisterChatCommand, cmd, function(args)
                    if S.activeBinder then addNotification("Биндер занят!", C.NOTIFY_WARNING); return end
                    if ref.cooldown and ref.cooldown > 0 and ref.lastUseTime then
                        local el = (os.clock() - ref.lastUseTime) * 1000
                        if el < ref.cooldown then addNotification("Кулдаун: " .. math.ceil((ref.cooldown - el) / 1000) .. "с", C.NOTIFY_WARNING); return end
                    end
                    local al = {}
                    if args and args ~= "" then for w in args:gmatch("%S+") do table.insert(al, w) end end
                    if #expectedArgs > 0 and #al < #expectedArgs then
                        local usage = "/" .. cmd
                        for _, aname in ipairs(expectedArgs) do usage = usage .. " [" .. aname .. "]" end
                        local missing = {}
                        for i2 = #al + 1, #expectedArgs do table.insert(missing, "{" .. expectedArgs[i2] .. "}") end
                        sampAddChatMessage("{FF6600}[Snatch Helper]{FFFFFF} Использование: " .. usage, -1)
                        sampAddChatMessage("{FF6600}[Snatch Helper]{FFFFFF} Не указано: " .. table.concat(missing, ", "), -1)
                        addNotification("Не хватает аргументов: " .. table.concat(missing, ", "), C.NOTIFY_WARNING)
                        return
                    end
                    lua_thread.create(function() performBind(ref, al) end)
                end)
                if ok then table.insert(S.registeredCommands, cmd) end
            end
        end
    end
    rebuildKeyBindMap()
end

local function validateBind(b)
    if not b.id then b.id = generateId() end
    if not b.delay or type(b.delay) ~= "number" then b.delay = settings.defaultDelay end
    if not b.key or type(b.key) ~= "number" then b.key = 0 end
    if not b.key_mod or type(b.key_mod) ~= "number" then b.key_mod = 0 end
    if not b.uses or type(b.uses) ~= "number" then b.uses = 0 end
    if not b.steps or type(b.steps) ~= "table" then b.steps = {} end
    if not b.name then b.name = "" end
    if not b.cmd then b.cmd = "" end
    if not b.desc then b.desc = "" end
    if not b.category or type(b.category) ~= "number" then b.category = 0 end
    if b.enabled == nil then b.enabled = true end
    if b.favorite == nil then b.favorite = false end
    if not b.cooldown or type(b.cooldown) ~= "number" then b.cooldown = 0 end
    if not b.created then b.created = os.time() end
    b.delay = clamp(b.delay, C.MIN_DELAY, C.MAX_DELAY)
    b.cooldown = clamp(b.cooldown, 0, C.MAX_DELAY)
end

local function loadBinds()
    binds = {}
    if not doesFileExistSafe(U.bindsConfigFile) then return end
    local f = io.open(U.bindsConfigFile, 'r')
    if not f then return end
    local c = f:read('*a'); f:close()
    if not c or #c < 2 then return end
    local ok, data = pcall(decodeJson, c)
    if ok and type(data) == "table" then
        binds = data
        for _, b in ipairs(binds) do validateBind(b) end
    end
end

local function saveBinds()
    if not ensureDirectory(configDirectory) then return end
    local f = io.open(U.bindsConfigFile, 'w'); if not f then return end
    local sv = {}
    for _, b in ipairs(binds) do local cp = deepCopy(b); cp.lastUseTime = nil; table.insert(sv, cp) end
    local ok, j = pcall(encodeJson, sv)
    if ok and j then f:write(j) end; f:close()
    registerBindCommands()
end

-- УЛУЧШЕНИЕ #19 — очистка старых бэкапов
local function cleanOldBackups()
    local backupDir = configDirectory .. "/backups"
    if not doesDirectoryExist(backupDir) then return end
    local files = {}
    local ok2, handle = pcall(io.popen, 'dir /b /o-d "' .. backupDir:gsub("/", "\\") .. '\\*.json" 2>nul')
    if ok2 and handle then
        for line in handle:lines() do if line and line ~= "" then table.insert(files, backupDir .. "/" .. line) end end
        handle:close()
    end
    for i = C.MAX_BACKUP_FILES + 1, #files do pcall(os.remove, files[i]) end
end

local function autoBackup()
    if not settings.autoBackup then return end
    local backupDir = configDirectory .. "/backups"
    ensureDirectory(backupDir)
    local backupFile = backupDir .. "/binds_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    local f = io.open(backupFile, 'w'); if not f then return end
    local sv = {}
    for _, b in ipairs(binds) do local cp = deepCopy(b); cp.lastUseTime = nil; table.insert(sv, cp) end
    local ok, j = pcall(encodeJson, sv)
    if ok and j then f:write(j) end; f:close()
    cleanOldBackups()
end

local function exportBinds(path)
    local f = io.open(path, 'w'); if not f then addNotification("Ошибка экспорта!", C.NOTIFY_ERROR); return end
    local sv = {}
    for _, b in ipairs(binds) do local cp = deepCopy(b); cp.lastUseTime = nil; table.insert(sv, cp) end
    local ok, j = pcall(encodeJson, sv)
    if ok and j then f:write(j); f:close(); addNotification("Экспорт: " .. #binds .. " биндов", C.NOTIFY_SUCCESS)
    else f:close(); addNotification("Ошибка!", C.NOTIFY_ERROR) end
end

local function importBinds(path)
    if not doesFileExistSafe(path) then addNotification("Файл не найден!", C.NOTIFY_ERROR); return end
    local f = io.open(path, 'r'); if not f then addNotification("Ошибка чтения!", C.NOTIFY_ERROR); return end
    local c = f:read('*a'); f:close()
    local ok, data = pcall(decodeJson, c)
    if not ok or type(data) ~= "table" then addNotification("Неверный формат!", C.NOTIFY_ERROR); return end
    local n = 0
    for _, b in ipairs(data) do
        b.id = generateId(); b.uses = 0; b.lastUseTime = nil
        validateBind(b); table.insert(binds, b); n = n + 1
    end
    saveBinds(); addNotification("Импортировано: " .. n .. " биндов", C.NOTIFY_SUCCESS)
end

loadBinds()

-- =========================================================================
-- ВЫПОЛНЕНИЕ БИНДА
-- =========================================================================
local function extractCustomVars(steps)
    local vars, seen = {}, {}
    for _, s in ipairs(steps) do
        for v in s:gmatch("{([^}]+)}") do
            -- Пропускаем SAMP цвет-коды вида {RRGGBB} (ровно 6 hex-символов)
            if not v:match("^%x%x%x%x%x%x$") then
                if not seen[v] and not simpleVariables[v] then
                    seen[v] = true
                    table.insert(vars, v)
                end
            end
        end
    end
    return vars
end

-- Ескейпит магические символы Lua-паттерна в имени переменной (фикс BUG B)
local function escapePattern(s)
    return (s:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1"))
end

local function processStep(step, subs, cache)
    -- Единственный gsub-проход: для каждого {vn} в строке ищем значение.
    -- Приоритет: пользовательские аргументы (subs) > simpleVariables.
    -- SAMP цвет-коды {RRGGBB} (ровно 6 hex-символов) оставляем нетронутыми.
    return (step:gsub("{([^}]+)}", function(vn)
        -- Пропускаем SAMP цвета
        if #vn == 6 and vn:match("^%x+$") then
            return "{" .. vn .. "}"
        end
        -- Пользовательский аргумент?
        if subs and subs[vn] ~= nil then
            return tostring(subs[vn])
        end
        -- Встроенная переменная?
        local val = resolveVariable(vn, cache)
        if val ~= nil then return tostring(val) end
        -- Неизвестно — оставляем как есть
        return "{" .. vn .. "}"
    end))
end
-- =========================================================================
-- АНАЛИЗ ДЛИНЫ СТРОК (6.4)
-- =========================================================================
local function analyzeStepLines(stepsText)
    local lines = {}
    local decoded = u8:decode(stepsText)
    if not decoded or decoded == "" then return lines end
    local lineNum = 0
    for line in (decoded .. "\n"):gmatch("([^\n]*)\r?\n") do
        lineNum = lineNum + 1
        local tr = trim(line)
        local isComment = tr:match("^//") or tr:match("^#")
        local isEmpty = tr == ""
        local processed = ""
        local processedLen = 0
        local hasCustomArgs = false
        if not isComment and not isEmpty then
            processed = processStep(tr, {}, {})
            processedLen = #processed
            -- FIX D: обнаруживаем неразрешённые пользовательские аргументы (пропускаем SAMP цвета)
            for remVar in processed:gmatch("{([^}]+)}") do
                if not remVar:match("^%x%x%x%x%x%x$") and not simpleVariables[remVar] then
                    hasCustomArgs = true; break
                end
            end
        end
        table.insert(lines, {
            num = lineNum,
            raw = line,
            len = #tr,
            processedLen = processedLen,
            isComment = isComment,
            isEmpty = isEmpty,
            isLong = processedLen > 144,
            isWarning = processedLen > 120 and processedLen <= 144,
            hasCustomArgs = hasCustomArgs,
        })
    end
    return lines
end
performBind = function(bind, args)
    if not bind or not bind.steps or #bind.steps == 0 then return end
    if S.activeBinder then addNotification("Биндер занят!", C.NOTIFY_WARNING); return end
    if bind.enabled == false then addNotification("Бинд выключен!", C.NOTIFY_WARNING); return end
    S.activeBinder = true; S.stopCurrentBind = false
    local delay = bind.delay or settings.defaultDelay
    local startMs = os.clock() * 1000
    S.currentBindStartTime = os.clock()
    S.currentBindTotal = #bind.steps; S.currentBindProgress = 0
    S.currentBindName = (bind.name and bind.name ~= "") and bind.name or "Бинд"
    local cvars = {}
    if bind.cmd and bind.cmd ~= "" then
        for argName in bind.cmd:gmatch("{([^}]+)}") do table.insert(cvars, argName) end
    end
    if #cvars == 0 then cvars = extractCustomVars(bind.steps) end
    local subs = {}
    for i, v in ipairs(cvars) do if args and args[i] then subs[v] = args[i] end end
    S.lastBindTime = os.clock(); S.lastBindName = S.currentBindName
    updateHourlyStats()
    local cache = {}
    local success = true
    for si, step in ipairs(bind.steps) do
        S.currentBindProgress = si
        if S.stopCurrentBind then
            addNotification("Остановлен: " .. S.currentBindName, C.NOTIFY_WARNING)
            success = false; break
        end
        if (os.clock()*1000 - startMs) > settings.maxBindDuration then
            addNotification("Таймаут: " .. S.currentBindName, C.NOTIFY_ERROR)
            success = false; break
        end
        local pauseMs = step:match("^%[(%d+)%]$")
        local mn2, mx2 = step:match("^%[wait_random:(%d+),(%d+)%]$")
        local hp_op, hp_val, hp_cmd = step:match("^%[if:hp(%D)(%d+)%](.+)$")
        local rep_count, rep_cmd = step:match("^%[repeat:(%d+)%](.+)$")
        if pauseMs then wait(tonumber(pauseMs))
        elseif mn2 then
            wait(math.random(tonumber(mn2), tonumber(mx2)))
        elseif hp_op then
            local op, val, cmd = hp_op, tonumber(hp_val) or 0, hp_cmd
            local _,id = sampGetPlayerIdByCharHandle(playerPed)
            local hp = id and (sampGetPlayerHealth(id) or 0) or 0
            local cond = false
            if op == ">" then cond = hp > val elseif op == "<" then cond = hp < val elseif op == "=" then cond = hp == val end
            if cond then
                safeSendChat(processStep(trim(cmd), subs, cache))
                wait(delay)
            end
        elseif rep_count then
            local count, cmd = tonumber(rep_count) or 1, rep_cmd
            if count > 10 then
                addNotification("repeat: максимум 10 (запрошено " .. count .. ")", C.NOTIFY_WARNING)
                count = 10
            end
            for _ = 1, count do
                if S.stopCurrentBind then break end
                safeSendChat(processStep(trim(cmd), subs, cache))
                wait(delay)
            end
        else
            safeSendChat(processStep(step, subs, cache))
            wait(delay)
        end
    end
    local duration = os.clock() - S.currentBindStartTime
    if bind.uses then bind.uses = bind.uses + 1 end
    bind.lastUseTime = os.clock(); S.totalSessionBinds = S.totalSessionBinds + 1
    addHistory(S.currentBindName, duration, S.currentBindTotal, success)
    S.currentBindProgress = 0; S.currentBindTotal = 0; S.currentBindName = ""
    S.activeBinder = false; S.stopCurrentBind = false
end

-- =========================================================================
-- UI: КОМПОНЕНТЫ
-- =========================================================================
local function cardBegin(id, sz, noShadow, topPad, gradColors)
    local t = T()
    local hov = anim("card_h_"..id, 0, 0.12)
    local bgCol = lerpColor(t.card, t.card_hover, hov)
    imgui.PushStyleColor(imgui.Col.ChildBg, bgCol)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 18)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildBorderSize, 0)
    imgui.BeginChild(id, sz or imgui.ImVec2(0,0), true)
    local isHov = imgui.IsWindowHovered(imgui.HoveredFlags.ChildWindows)
    anim("card_h_"..id, isHov and 1 or 0, 0.12)
    if not noShadow then
        local dl = imgui.GetWindowDrawList()
        local wp = imgui.GetWindowPos(); local ws = imgui.GetWindowSize()
        drawShadow(dl, wp.x, wp.y, wp.x+ws.x, wp.y+ws.y, 18, 4, 0.35 + hov*0.25)
        dl:AddRect(imgui.ImVec2(wp.x, wp.y), imgui.ImVec2(wp.x+ws.x, wp.y+ws.y),
            ImVec4toU32(imgui.ImVec4(1,1,1,0.04+hov*0.04)), 18)
    end
    imgui.Dummy(imgui.ImVec2(0, topPad or 14))
    imgui.Indent(18)
end

local function cardEnd()
    imgui.Unindent(18); imgui.EndChild()
    imgui.PopStyleVar(2); imgui.PopStyleColor()
end

local function btn(label, w, h, variant)
    local t = T(); variant = variant or "default"
    local id = "btn_" .. label .. (w or 0) .. (h or 0)
    local hov = anim(id, 0, 0.15)
    local bc, hc, ac, tc
    if variant == "accent" then
        bc = imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z, 0.78 + hov*0.15)
        hc = imgui.ImVec4(t.accent2.x,t.accent2.y,t.accent2.z,0.88)
        ac = imgui.ImVec4(t.accent_dim.x,t.accent_dim.y,t.accent_dim.z,0.92)
        tc = imgui.ImVec4(1,1,1,1)
    elseif variant == "danger" then
        bc = imgui.ImVec4(t.red.x,t.red.y,t.red.z, 0.38 + hov*0.25)
        hc = imgui.ImVec4(t.red.x,t.red.y,t.red.z,0.68)
        ac = imgui.ImVec4(t.red.x,t.red.y,t.red.z,0.85)
        tc = t.text
    elseif variant == "success" then
        bc = imgui.ImVec4(t.green.x,t.green.y,t.green.z, 0.48 + hov*0.25)
        hc = imgui.ImVec4(t.green.x,t.green.y,t.green.z,0.72)
        ac = imgui.ImVec4(t.green.x,t.green.y,t.green.z,0.88)
        tc = imgui.ImVec4(0,0,0,1)
    elseif variant == "ghost" then
        bc = imgui.ImVec4(t.card.x,t.card.y,t.card.z, 0.30 + hov*0.35)
        hc = imgui.ImVec4(t.card_hover.x,t.card_hover.y,t.card_hover.z,0.75)
        ac = imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.28)
        tc = lerpColor(t.text2, t.text, hov)
    elseif variant == "outline" then
        bc = imgui.ImVec4(0,0,0, hov*0.06)
        hc = imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.12)
        ac = imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.28)
        tc = lerpColor(t.accent, t.accent2, hov)
    else
        bc = imgui.ImVec4(t.card.x,t.card.y,t.card.z, 0.60 + hov*0.20)
        hc = imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.20)
        ac = imgui.ImVec4(t.accent_dim.x,t.accent_dim.y,t.accent_dim.z,0.42)
        tc = t.text
    end
    imgui.PushStyleColor(imgui.Col.Button, bc)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, hc)
    imgui.PushStyleColor(imgui.Col.ButtonActive, ac)
    imgui.PushStyleColor(imgui.Col.Text, tc)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    local r
    if w and w ~= 0 and h and h ~= 0 then r = imgui.Button(u8(label), imgui.ImVec2(w,h))
    else r = imgui.Button(u8(label)) end
    if imgui.IsItemHovered() then anim(id, 1, 0.15) else anim(id, 0, 0.10) end
    imgui.PopStyleVar(); imgui.PopStyleColor(4)
    if variant == "outline" then
        local dl = imgui.GetWindowDrawList()
        local borderA = lerp(0.30, 0.65, hov)
        dl:AddRect(imgui.GetItemRectMin(), imgui.GetItemRectMax(),
            ImVec4toU32(imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,borderA)), 14, 15, 1.5)
    end
    if variant == "accent" and hov > 0.3 then
        local dl = imgui.GetWindowDrawList()
        local mi, ma = imgui.GetItemRectMin(), imgui.GetItemRectMax()
        drawGlowRect(dl, mi.x, mi.y, ma.x, ma.y, t.accent, hov*0.15, 14)
    end
    return r
end

local function badge(text, color)
    local t = T(); color = color or t.accent
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(color.x,color.y,color.z,0.10))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(color.x,color.y,color.z,0.16))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(color.x,color.y,color.z,0.16))
    imgui.PushStyleColor(imgui.Col.Text, color)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 20)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(8,3))
    if U.fontSemibold then imgui.PushFont(U.fontSemibold) end
imgui.SmallButton(u8(text))
if U.fontSemibold then imgui.PopFont() end
    imgui.PopStyleVar(2); imgui.PopStyleColor(4)
end

local function progressBar(label, val, maxV, color, showText)
    local t = T(); color = color or t.accent
    local prog = clamp(val / math.max(maxV, 1), 0, 1)
    local sp = imgui.GetCursorScreenPos()
    local w = imgui.GetContentRegionAvail().x; local h = 5
    local dl = imgui.GetWindowDrawList()
    dl:AddRectFilled(imgui.ImVec2(sp.x,sp.y), imgui.ImVec2(sp.x+w,sp.y+h),
        ImVec4toU32(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.10)), h/2)
    local animProg = anim("prog_"..label..tostring(color.x), prog, 0.05)
    if animProg > 0.001 then
        local fillW = w * animProg
        dl:AddRectFilled(imgui.ImVec2(sp.x,sp.y), imgui.ImVec2(sp.x+fillW,sp.y+h), ImVec4toU32(color, 0.82), h/2)
        drawGlow(dl, sp.x + fillW, sp.y+h/2, 3, color, 0.35)
    end
    imgui.Dummy(imgui.ImVec2(w, h + 2))
end

local function thinSep()
    local t = T()
    imgui.Dummy(imgui.ImVec2(0,5))
    local sp = imgui.GetCursorScreenPos(); local w = imgui.GetContentRegionAvail().x
    local dl = imgui.GetWindowDrawList()
    local inset = 8; local drawW = w - inset * 2
    drawGrad(dl, sp.x + inset, sp.y, drawW/2, 1,
        imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.02), imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.12))
    drawGrad(dl, sp.x + inset + drawW/2, sp.y, drawW/2, 1,
        imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.12), imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.02))
    imgui.Dummy(imgui.ImVec2(w,6))
end

local function secTitle(text)
    local t   = T()
    imgui.Dummy(imgui.ImVec2(0, 7))
    local sp  = imgui.GetCursorScreenPos()
    local dl  = imgui.GetWindowDrawList()
    local avW = imgui.GetContentRegionAvail().x
    local lh  = 16
    local cy  = sp.y + lh / 2

    local cL  = sp.x
    local cR  = sp.x + avW
    local cCx = (cL + cR) * 0.5

    -- Измеряем и рисуем одним шрифтом
    local label   = u8(text:upper())
    local labelSz = imgui.CalcTextSize(label)

    local pillPadX, pillH = 10, 18
    local pillW = labelSz.x + pillPadX * 2
    local pillX = cCx - pillW * 0.5
    local pillY = cy - pillH * 0.5

    local lineInset = 6
    drawGrad(dl,
        cL + lineInset, cy,
        pillX - cL - lineInset - 4, 1,
        imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.02),
        imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.22))
    drawGrad(dl,
        pillX + pillW + 4, cy,
        cR - (pillX + pillW + 4) - lineInset, 1,
        imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.22),
        imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.02))

    dl:AddRectFilled(
        imgui.ImVec2(pillX, pillY),
        imgui.ImVec2(pillX + pillW, pillY + pillH),
        ImVec4toU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.10)),
        pillH * 0.5)
    dl:AddRect(
        imgui.ImVec2(pillX, pillY),
        imgui.ImVec2(pillX + pillW, pillY + pillH),
        ImVec4toU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.30)),
        pillH * 0.5, 15, 0.5)

    dl:AddText(
        imgui.ImVec2(pillX + pillPadX, pillY + (pillH - labelSz.y) * 0.5),
        ImVec4toU32(t.accent, 0.90), label)

    imgui.Dummy(imgui.ImVec2(avW, lh + 6))
end

local function toggleSwitch(label, boolPtr)
    local t = T()
    local val = boolPtr[0]
    local id = "tgl_" .. label
    local animVal = anim(id, val and 1 or 0, 0.10)
    local dl = imgui.GetWindowDrawList()
    local sp = imgui.GetCursorScreenPos()
    local w, h = 44, 24; local r = h / 2
    local bgCol = lerpColor(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.22),
        imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.60), animVal)
    dl:AddRectFilled(imgui.ImVec2(sp.x,sp.y), imgui.ImVec2(sp.x+w,sp.y+h), ImVec4toU32(bgCol), r)
    local circleX = lerp(sp.x + r, sp.x + w - r, animVal)
    dl:AddCircleFilled(imgui.ImVec2(circleX, sp.y + r), r - 3.5, ImVec4toU32(imgui.ImVec4(1,1,1,0.95)), 24)
    if animVal > 0.5 then drawGlow(dl, circleX, sp.y+r, r-2, t.accent, (animVal-0.5)*0.5) end
    imgui.InvisibleButton("##toggle_" .. label, imgui.ImVec2(w, h))
    if imgui.IsItemClicked() then boolPtr[0] = not boolPtr[0] end
    imgui.SameLine(0, 14)
    imgui.PushStyleColor(imgui.Col.Text, lerpColor(t.text3, t.text2, animVal))
    imgui.SetCursorPosY(imgui.GetCursorPosY() + 3)
    imgui.Text(u8(label)); imgui.PopStyleColor()
    return boolPtr[0] ~= val
end

-- =========================================================================
-- ПОПАП КЛАВИШИ
-- =========================================================================
imgui.OnFrame(
    function() return S.keyBindPopupActive end,
    function(self)

        local t = T()
        imgui.SetNextWindowSize(imgui.ImVec2(380, 210), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2,sizeY/2), imgui.Cond.Always, imgui.ImVec2(0.5,0.5))
        pushWindowPadding(24,20)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 20)
        local op = imgui.new.bool(true)
        imgui.Begin(u8(" Назначение клавиши"), op, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
        if not op[0] then S.keyBindPopupActive = false; S.keyBindContext = nil; S.waitingForKey = false end
        if S.waitingForKey then
            imgui.Spacing()
            local p = (math.sin(os.clock()*3)+1)*0.5
            imgui.PushStyleColor(imgui.Col.Text, lerpColor(t.yellow, t.accent2, p))
            imgui.Text(u8(" Нажмите нужную клавишу...")); imgui.PopStyleColor()
            imgui.Spacing()
            imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.Text(u8(" ESC — отмена")); imgui.PopStyleColor()
        else
            imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.Text(u8("Текущая:")); imgui.PopStyleColor()
            imgui.SameLine(); badge(getKeyName(S.tempKey, S.tempMod), t.green)
            imgui.Spacing(); imgui.Spacing()
            if btn(" Переназначить ", 140, 34, "accent") then S.waitingForKey = true end
            imgui.SameLine()
            if btn(" Сбросить ", 110, 34, "ghost") then S.tempKey = 0; S.tempMod = 0 end
            imgui.Spacing(); thinSep()
            if btn(" Применить ", 100, 32, "success") then
                if S.keyBindContext == "bind" then B.editKeyBuf[0] = S.tempKey; B.editKeyModBuf[0] = S.tempMod
                elseif S.keyBindContext == "stop" then settings.stopKey = S.tempKey; settings.stopKeyMod = S.tempMod; saveSettings()
                elseif S.keyBindContext == "open" then settings.openKey = S.tempKey; saveSettings()
                elseif S.keyBindContext == "qa_slot" and QA._editSlot then
                    QA._editSlot.key = S.tempKey; QA._editSlot.keyMod = S.tempMod
                    QA._editSlot = nil; QA:save()
                elseif S.keyBindContext == "qa_hold" then
                    QA.holdKey = S.tempKey; QA.holdKeyMod = S.tempMod; QA:save() end
                S.keyBindPopupActive = false; S.keyBindContext = nil
            end
            imgui.SameLine()
            if btn(" Отмена ", 100, 32, "ghost") then S.keyBindPopupActive = false; S.keyBindContext = nil end
        end
        imgui.End(); imgui.PopStyleVar(2)
    end
)

-- =========================================================================
-- СПРАВОЧНИК (данные)
-- =========================================================================
local menuData = {
    [1] = { t = "Основания задержания", c = [[Как называть: Задержаны на основании пункта X, статьи 1, раздела 2, части 1 Процессуального Кодекса.
Либо словами, пример: Задержаны в связи с нарушением устава МЮ.
A. Совершение гражданином дорожного или уголовного проступка
B. Нахождение гражданина в маске, скрывающей лицо
C. Гражданин ведёт себя подозрительно, вызывающе, агрессивно
D. Имеется предположение, что лицо находится под алкоголем или наркотиками
E. Проведение проверки документов гражданина
F. Гражданин пересекает организованные блокпосты
G. Гражданин находится поблизости от места преступления и мог быть свидетелем
H. Нарушение устава или ФП от госника
I. В период введения военного положения]] },
    [2] = { t = "Порядок задержания", c = [[1) Идентифицировать себя, показать ксиву по требованию
2) Провести необходимые действия в зависимости от ситуации:
 - Затребовать документы
 - Провести опрос
 - Обыск при наличии оснований
 - Потребовать покинуть ТС
 - Потребовать переместиться
 - Надеть наручники, но после снять
 - Провести арест при наличии оснований]] },
    [3] = { t = "Основания ареста", c = [[Арестованы на основании пункта X, статьи 3, раздела 2, части 1 Процессуального Кодекса.
A. Лицо застигнуто на месте совершения дорожного или уголовного преступления
B. В случае если преступник скрылся - его можно арестовать в течении 12 часов без КФ
C. Лицо находится в федеральном розыске
D. На арестовываемого имеется действующий ордер на арест
E. Проведение проверки документов гражданина
F. Игнорирование в течении 24 часов требования о явке на допрос
G. Транспортировка на допрос]] },
    [4] = { t = "Порядок ареста", c = [[1) Надеть наручники
2) Идентифицировать себя и показать ксиву при запросе
3) Сообщить основания для ареста. ВАЖНО: При аресте по УК/ДК - назвать статью
4) Узнать в рамках РП личность арестованного
5) Обыск
6) Миранда
7) Выдача розыска
8) Транспортировка в КПЗ или допросную
9) Посадка в КПЗ при необходимости]] },
    [5] = { t = "Порядок ареста гос. сотрудника", c = [[1) По усмотрению выдать розыск с причиной 'СЛЕДСТВИЕ'
2) Если арестованного передали копы - получение от них доказательств
3) Миранда
4) Обыск
5) Везёте на допрос по своему усмотрению
6) По окончанию процессуальных действий выбираете меру наказания
7) Если применён арест в КПЗ, в течении 24 часов составляете КФ на форум]] },
    [6] = { t = "Основания допроса", c = [[Допрос проводится на основании пункта X, статьи 1, раздела 2, части 2 ПК.
A. Допрос арестованного лица
B. Ордер на проведение допроса
C. Наличие оснований полагать, что у лица есть информация
D. На лицо открыт КФ
E. Повестка на допрос]] },
    [7] = { t = "Порядок проведения допроса", c = [[1) Усадить человека на стул
2) Включить камеру в допросной
3) Назвать дату и время начала допроса
4) Сообщить кто проводит допрос и назвать позывной
5) Указать кто допрашивается и в каком статусе
6) Миранда
7) Уточняем желает-ли допрашиваемый реализовать свои права
8) Если допрашиваем госника - можно уведомить его организацию
9) Уведомляем об ответственности за разглашение гос.тайны
10) Задаём вопросы
11) Оповещаем о завершении допроса и выключаем камеру
12) Выводим допрашиваемого с мешком на голове из офиса]] },
    [8] = { t = "Адвокат на допросе", c = [[При поступлении требования - запрашиваем адвоката в /d у правительства.
Если в течении 5 минут ответа не последовало - продолжаем без адвоката.
Если адвокат вышел на связь - ждём 10 минут.
При прибытии проверяем паспорт, наличие лицензии и 5+ ранга.
Обыскиваем адвоката, надеваем мешок.
Адвокат имеет право на приватные беседы (20 минут).]] },
    [9] = { t = "Основания для обыска", c = [[Обыск на основании пункта X, статьи 1, раздела 3, части 1 ПК
A. Ордер
B. Арест
C. Проведение рейда
D. Контроль на блокпостах
E. Вход в зону оцепления
F. Вход на территорию режимного объекта
G. Добровольное согласие на обыск
H-M. Различные основания задержания
ВАЖНО: Обыск делается В ПЕРЧАТКАХ!]] },
    [10] = { t = "Основания для рейдов", c = [[Рейд ГЕТТО - Статья 2, раздел 5, части 2 ПК [Нужен ордер]
Рейд ПРИТОНА - Статья 3, раздел 5, части 2 ПК
Рейд ОПГ - Статья 4, раздел 5, части 2 ПК [Нужен ордер]
Рейд СТО - Статья 5, раздел 5, части 2 ПК
Рейд ГРУЗОПЕРЕВОЗОК - Статья 6 [Нужен ордер]
Рейд ПАТРУЛЕЙ - Статья 7
Рейд ЛАВОК - Статья 8
Рейд ГОС.ОРГ - Статья 9 [Нужен ордер]
Рейд НАРКОТРАФИКА - Статья 10]] },
    [11] = { t = "Основания правил безопасности", c = [[6 метров - статья 1, раздел 5, части 1 ПК
3 поворота - статья 1, раздел 5, части 1 ПК]] },
}

-- =========================================================================
-- ОВЕРЛЕЙ АКТИВНОГО БИНДА
-- =========================================================================
imgui.OnFrame(
    function() return S.activeBinder and settings.showOverlay and S.currentBindTotal > 0 end,
    function(self)
        self.HideCursor = not mainWindow.state
        local t = T()
        -- Высота зависит от наличия шага
        local oW = 320
        local oH = 64
        local posY = settings.overlayPosition == 0 and 12 or (sizeY - oH - 8)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, posY), imgui.Cond.Always, imgui.ImVec2(0.5,0))
        imgui.SetNextWindowSize(imgui.ImVec2(oW, oH), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 16)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
        pushWindowPadding(14, 10)
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(t.sidebar.x,t.sidebar.y,t.sidebar.z,0.96))
        local fl = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoInputs + imgui.WindowFlags.NoFocusOnAppearing
        imgui.Begin("##overlay", nil, fl)
        local dl = imgui.GetWindowDrawList()
        local wp = imgui.GetWindowPos(); local ws = imgui.GetWindowSize()

        drawShadow(dl, wp.x, wp.y, wp.x+ws.x, wp.y+ws.y, 16, 6, 0.65)
        -- Тонкая рамка
        dl:AddRect(imgui.ImVec2(wp.x, wp.y), imgui.ImVec2(wp.x+ws.x, wp.y+ws.y),
            ImVec4toU32(imgui.ImVec4(1,1,1,0.05)), 16)

        -- Строка 1: пульс + имя бинда + счётчик
        pulsingDot(dl, wp.x + 14, wp.y + 18, 4, t.yellow, 5)
        local nm = #S.currentBindName > 22 and S.currentBindName:sub(1,20)..".." or S.currentBindName
        dl:AddText(imgui.ImVec2(wp.x + 26, wp.y + 11),
            ImVec4toU32(t.yellow, 0.95), u8(nm))
        local cntStr = u8(safeFormat("%d/%d", S.currentBindProgress, S.currentBindTotal))
        local cntSz = imgui.CalcTextSize(cntStr)
        dl:AddText(imgui.ImVec2(wp.x + ws.x - cntSz.x - 12, wp.y + 11),
            ImVec4toU32(t.text3, 0.55), cntStr)

        -- Строка 2: точки-сегменты
        local maxDots = math.min(S.currentBindTotal, 18)
        local dotSpacing = math.min(14, (oW - 30) / math.max(maxDots, 1))
        local dotsW = dotSpacing * maxDots - (dotSpacing - 8)
        local dotStartX = wp.x + (ws.x - dotsW) * 0.5
        local dotY = wp.y + 40
        local step = S.currentBindProgress

        for di = 1, maxDots do
            local dx = dotStartX + (di - 1) * dotSpacing
            if di < step then
                -- пройден
                dl:AddCircleFilled(imgui.ImVec2(dx, dotY), 3.5,
                    ImVec4toU32(t.green, 0.75), 10)
            elseif di == step then
                -- текущий: пульс + свечение
                local pulse = (math.sin(os.clock() * 8) + 1) * 0.5
                dl:AddCircleFilled(imgui.ImVec2(dx, dotY), 4 + pulse * 1.5,
                    ImVec4toU32(t.yellow, 0.25), 12)
                dl:AddCircleFilled(imgui.ImVec2(dx, dotY), 4,
                    ImVec4toU32(t.yellow, 1.0), 12)
            else
                -- предстоящий
                dl:AddCircleFilled(imgui.ImVec2(dx, dotY), 2.5,
                    ImVec4toU32(t.text3, 0.20), 10)
            end
            -- Соединительная линия
            if di < maxDots then
                local lineCol = di < step and t.green or t.text3
                local lineA = di < step and 0.25 or 0.10
                dl:AddLine(imgui.ImVec2(dx + 4.5, dotY),
                    imgui.ImVec2(dx + dotSpacing - 4.5, dotY),
                    ImVec4toU32(lineCol, lineA), 1)
            end
        end

        -- Текущий шаг (если есть bind с шагами)
        if S.currentBindProgress > 0 and S.currentBindProgress <= S.currentBindTotal then
            -- текст ниже не помещается в oH=64, выводим в строке 1 через tooltip-like
        end

        imgui.Dummy(imgui.ImVec2(oW - 28, oH - 20))
        imgui.End(); imgui.PopStyleColor(); imgui.PopStyleVar(3)
    end
)

-- =========================================================================
-- QA: ОВЕРЛЕЙ МИРА (ромб + панель хоткеев)
-- =========================================================================
imgui.OnFrame(
    function() return QA.active end,
    function(self)
        self.HideCursor = true
        local col  = QA:col()
        local colU = ImVec4toU32(col)
        local now  = os.clock()
        local t    = T()

        -- Полноэкранное прозрачное окно
        imgui.SetNextWindowPos(imgui.ImVec2(0,0), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(sizeX,sizeY), imgui.Cond.Always)
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0,0,0,0))
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize,0)
        setWindowPadding(0,0)
        imgui.Begin("##qa_wrl", nil,
            imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+
            imgui.WindowFlags.NoMove+imgui.WindowFlags.NoScrollbar+
            imgui.WindowFlags.NoInputs+imgui.WindowFlags.NoBringToFrontOnFocus+
            imgui.WindowFlags.NoFocusOnAppearing+imgui.WindowFlags.NoSavedSettings)
        local dl = imgui.GetWindowDrawList()

        -- Ромб над целью
        if QA.targetSid~=-1 and (QA.tx~=0 or QA.ty~=0 or QA.tz~=0) then
            local scrOk,sx,sy = pcall(convert3DCoordsToScreen, QA.tx, QA.ty, QA.tz)
            local fx, fy
            if type(scrOk)=="boolean" then
                if scrOk then fx,fy = sx,sy end
            else
                fx,fy = scrOk,sx
            end
            if fx and fy and fx>10 and fx<sizeX-10 and fy>10 and fy<sizeY-60 then
                local ms  = QA.markerSz
                local rot = now * 1.2
                -- Ripple
                for rk=1,2 do
                    local rp = ((now*0.9+rk*0.5)%1)
                    dl:AddCircle(imgui.ImVec2(fx,fy), ms*(1+rp*1.6),
                        ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,(1-rp)*0.5)), 24, 1.5)
                end
                -- Ромб (4 точки по кругу с шагом 90°)
                local p = {}
                for k=0,3 do
                    local a = rot + k*(math.pi/2)
                    p[k+1] = imgui.ImVec2(fx+math.cos(a)*ms, fy+math.sin(a)*ms)
                end
                dl:AddQuadFilled(p[1],p[2],p[3],p[4], ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.18)))
                dl:AddQuad(p[1],p[2],p[3],p[4], colU, 2.2)
                -- Внутренний ромбик
                local ms2=ms*0.42; local p2={}
                for k=0,3 do
                    local a=rot+k*(math.pi/2)
                    p2[k+1]=imgui.ImVec2(fx+math.cos(a)*ms2,fy+math.sin(a)*ms2)
                end
                dl:AddQuad(p2[1],p2[2],p2[3],p2[4], ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.35)),1)
                -- Нить вниз
                dl:AddLine(imgui.ImVec2(fx,fy+ms+2),imgui.ImVec2(fx,fy+ms+12),
                    ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.55)),1.2)
                -- Плашка имени
                local ns = u8(QA.targetNick.."  ["..QA.targetSid.."]")
                local nsz = imgui.CalcTextSize(ns)
                local lx2 = fx-nsz.x*0.5; local ly2 = fy+ms+14
                dl:AddRectFilled(imgui.ImVec2(lx2-8,ly2-3),imgui.ImVec2(lx2+nsz.x+8,ly2+nsz.y+3),
                    ImVec4toU32(imgui.ImVec4(0.04,0.04,0.12,0.85)),5)
                dl:AddRect(imgui.ImVec2(lx2-8,ly2-3),imgui.ImVec2(lx2+nsz.x+8,ly2+nsz.y+3),
                    ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.50)),5,15,0.8)
                dl:AddText(imgui.ImVec2(lx2,ly2), ImVec4toU32(col,0.95), ns)
            end
        end

        -- Индикатор режима (верхний центр)
        local modeStr = QA.mode=="foot" and "пешком" or "транспорт"
        local hasT    = QA.targetSid~=-1
        local ms2 = u8("  Быстрые действия · "..modeStr.." · "..(hasT and "цель найдена" or "ищем...").. "  ")
        local msz2 = imgui.CalcTextSize(ms2)
        local imx = math.floor((sizeX-msz2.x)*0.5); local imy = 12
        dl:AddRectFilled(imgui.ImVec2(imx,imy-5),imgui.ImVec2(imx+msz2.x,imy+msz2.y+5),
            ImVec4toU32(imgui.ImVec4(0.04,0.04,0.12,0.78)),14)
        dl:AddRect(imgui.ImVec2(imx,imy-5),imgui.ImVec2(imx+msz2.x,imy+msz2.y+5),
            ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.35)),14,15,0.7)
        local pp = (math.sin(now*4)+1)*0.5
        local dotC = hasT and col or imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.5)
        dl:AddCircleFilled(imgui.ImVec2(imx+10,imy+msz2.y*0.5), 3.5+pp*0.8,
            ImVec4toU32(imgui.ImVec4(dotC.x,dotC.y,dotC.z,0.6+pp*0.35)),12)
        dl:AddText(imgui.ImVec2(imx+20,imy), ImVec4toU32(t.text,0.78), ms2)

        imgui.End(); imgui.PopStyleVar(); imgui.PopStyleColor()

        -- Панель хоткеев (снизу слева) — отдельное окно чтобы не зависеть от прозрачного
        local slots = QA.mode=="foot" and QA.foot or QA.vehicle
        if #slots==0 then return end
        local slideA = anim("qa_slide", hasT and 1 or 0, 0.16)
        if slideA<0.01 then return end
        local rowH=32; local panelW=220
        local panelH = #slots*rowH+30
        local offY = (1-ease.outCubic(slideA))*14
        imgui.SetNextWindowPos(imgui.ImVec2(14, sizeY-panelH-14+offY), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(panelW, panelH+4), imgui.Cond.Always)
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.04,0.04,0.12,0.90*slideA))
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding,12)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize,0)
        setWindowPadding(10,8)
        imgui.Begin("##qa_hk", nil,
            imgui.WindowFlags.NoTitleBar+imgui.WindowFlags.NoResize+
            imgui.WindowFlags.NoMove+imgui.WindowFlags.NoScrollbar+
            imgui.WindowFlags.NoInputs+imgui.WindowFlags.NoBringToFrontOnFocus+
            imgui.WindowFlags.NoFocusOnAppearing)
        local pdl = imgui.GetWindowDrawList()
        local pwp = imgui.GetWindowPos(); local pws = imgui.GetWindowSize()
        pdl:AddRect(imgui.ImVec2(pwp.x,pwp.y),imgui.ImVec2(pwp.x+pws.x,pwp.y+pws.y),
            ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.22*slideA)),12,15,0.8)
        pdl:AddRectFilled(imgui.ImVec2(pwp.x+10,pwp.y),imgui.ImVec2(pwp.x+pws.x-10,pwp.y+2),
            ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.6*slideA)),1)
        -- Имя цели
        local nd = QA.targetNick; if #nd>18 then nd=nd:sub(1,16)..".." end
        pdl:AddCircleFilled(imgui.ImVec2(pwp.x+12,pwp.y+15),3.5,
            ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.7*slideA)),12)
        pdl:AddText(imgui.ImVec2(pwp.x+20,pwp.y+8),
            ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.75*slideA)), u8(nd))
        imgui.Dummy(imgui.ImVec2(0,24))
        -- Слоты
        for si,slot in ipairs(slots) do
            local kn   = u8(getKeyName(slot.key or 0, slot.keyMod or 0))
            local knsz = imgui.CalcTextSize(kn)
            local ln   = u8(slot.label or "?")
            local lnsz = imgui.CalcTextSize(ln)
            local ry   = pwp.y+28+(si-1)*rowH; local rx=pwp.x+10
            local cw   = knsz.x+14
            pdl:AddRectFilled(imgui.ImVec2(rx,ry+3),imgui.ImVec2(rx+cw,ry+rowH-3),
                ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.13*slideA)),5)
            pdl:AddRect(imgui.ImVec2(rx,ry+3),imgui.ImVec2(rx+cw,ry+rowH-3),
                ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.45*slideA)),5,15,0.9)
            pdl:AddText(imgui.ImVec2(rx+7,ry+(rowH-knsz.y)*0.5),
                ImVec4toU32(imgui.ImVec4(col.x,col.y,col.z,0.95*slideA)), kn)
            pdl:AddText(imgui.ImVec2(rx+cw+10,ry+(rowH-lnsz.y)*0.5),
                ImVec4toU32(imgui.ImVec4(0.90,0.92,1.0,0.85*slideA)), ln)
            imgui.Dummy(imgui.ImVec2(panelW-20,rowH))
        end
        imgui.End(); imgui.PopStyleVar(2); imgui.PopStyleColor()
    end
)

-- =========================================================================
-- УТИЛИТНАЯ ТАБЛИЦА U
-- =========================================================================
U.imgui = imgui
U.u8 = u8
U.ffi = ffi
U.str = str
U.ImVec4toU32 = ImVec4toU32
U.lerpColor = lerpColor
U.lerp = lerp
U.clamp = clamp
U.drawShadow = drawShadow
U.drawGlow = drawGlow
U.drawGlowRect = drawGlowRect
U.drawGrad = drawGrad
U.drawGradRounded = drawGradRounded
U.drawGradV = drawGradV
U.drawSparkline = drawSparkline
U.drawCircularProgress = drawCircularProgress
U.drawGlassBg = drawGlassBg
U.pulsingDot = pulsingDot
U.anim = anim
U.animBool = animBool
U.animatedCounter = animatedCounter
U.secTitle = secTitle
U.thinSep = thinSep
U.cardBegin = cardBegin
U.cardEnd = cardEnd
U.btn = btn
U.badge = badge
U.toggleSwitch = toggleSwitch
U.progressBar = progressBar
U.safeFormat = safeFormat
U.formatTime = formatTime
U.formatTimeShort = formatTimeShort
U.forceWindowPadding = forceWindowPadding
U.pushPadding = pushPadding
U.trim = trim
U.deepCopy = deepCopy
U.generateId = generateId
U.getKeyName = getKeyName
U.splitSteps = splitSteps
U.joinSteps = joinSteps
U.saveBinds = saveBinds
U.addNotification = addNotification
U.addActivity = addActivity
U.easeOutCubic = ease.outCubic
U.MIN_DELAY = C.MIN_DELAY
U.MAX_DELAY = C.MAX_DELAY
U.NOTIFY_INFO = C.NOTIFY_INFO
U.NOTIFY_SUCCESS = C.NOTIFY_SUCCESS
U.NOTIFY_WARNING = C.NOTIFY_WARNING
U.NOTIFY_ERROR = C.NOTIFY_ERROR
U.bindCatNames = {u8("Свои бинды"), u8("Системные"), u8("ФБР"), u8("Экспертизы")}
U.bindCatNamesPtr = ffi.new('const char*[4]', U.bindCatNames)
U.categories = { "Все", "Свои бинды", "Системные", "ФБР", "Экспертизы" }
U.catNames = {u8("Все"), u8("Свои бинды"), u8("Системные"), u8("ФБР"), u8("Экспертизы")}
U.catNamesPtr = ffi.new('const char*[5]', U.catNames)
U.searchBuf = ffi.new("char[256]")
U.showVarRef = imgui.new.bool(false)
U.filterCategory = ffi.new("int[1]", 0)
U.refSearchBuf = ffi.new("char[128]")
U.refDetailIdx = 0
U.refDetailOpen = imgui.new.bool(false)
-- U.bindsConfigFile and U.activityLogFile defined early after configDirectory

-- =========================================================================
-- УВЕДОМЛЕНИЯ (Рендер)
-- =========================================================================
imgui.OnFrame(
    function() return #notifications > 0 end,
    function(self)
        self.HideCursor = not mainWindow.state
        local now = os.clock()
        local toRm = {}
        for i, n in ipairs(notifications) do
            local dur = n.duration or C.NOTIFICATION_DURATION
            if now - n.time > dur + C.NOTIFICATION_FADE then table.insert(toRm, i) end
        end
        for i = #toRm, 1, -1 do table.remove(notifications, toRm[i]) end
        if #notifications == 0 then return end
        local nW = 360; local yOff = 24
        for i, n in ipairs(notifications) do
            local dur = n.duration or C.NOTIFICATION_DURATION
            local el = now - n.time
            local alpha
            if el > dur then alpha = 1 - (el - dur) / C.NOTIFICATION_FADE
            elseif el < 0.4 then alpha = ease.outCubic(el / 0.4)
            else alpha = 1 end
            alpha = clamp(alpha, 0, 1)
            local slideX = el < 0.4 and (1 - ease.outCubic(el / 0.4)) * (nW + 30) or 0
            if el > dur then slideX = (el - dur) / C.NOTIFICATION_FADE * 60 end
            local col = notifyColors[n.ntype] or notifyColors[C.NOTIFY_INFO]
            imgui.SetNextWindowPos(imgui.ImVec2(sizeX - nW - 24 + slideX, yOff), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(nW, 0), imgui.Cond.Always)
            imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, alpha)
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 18)
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
            setWindowPadding(0, 0)
            imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.06, 0.06, 0.10, 0.96))
            local fl = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar
                + imgui.WindowFlags.NoInputs + imgui.WindowFlags.NoFocusOnAppearing
                + imgui.WindowFlags.AlwaysAutoResize
            imgui.Begin("##ntf_" .. i, nil, fl)
            local dl = imgui.GetWindowDrawList()
            local wp = imgui.GetWindowPos(); local ws = imgui.GetWindowSize()
            drawShadow(dl, wp.x, wp.y, wp.x+ws.x, wp.y+ws.y, 18, 5, alpha*0.7)
            drawGlassBg(dl, wp.x, wp.y, wp.x+ws.x, wp.y+ws.y, 18, imgui.ImVec4(0.06,0.06,0.10,0.0), 0.08*alpha)
            imgui.Dummy(imgui.ImVec2(0, 12))
            imgui.Dummy(imgui.ImVec2(14, 0)); imgui.SameLine()
            -- SVG-иконка через DrawList
            ;(U.notifyIconDrawers[n.ntype] or U.notifyIconDrawers[C.NOTIFY_INFO])(dl, imgui.GetCursorScreenPos().x+9, imgui.GetCursorScreenPos().y+9, 9, col, alpha)
            imgui.Dummy(imgui.ImVec2(22, 18)); imgui.SameLine(0, 6)
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.94,0.94,0.98,alpha))
            imgui.PushTextWrapPos(nW - 28)
            imgui.TextWrapped(u8(n.text)); imgui.PopTextWrapPos(); imgui.PopStyleColor()
            imgui.Dummy(imgui.ImVec2(0, 10))
            local prog2 = clamp(1 - el / dur, 0, 1)
            local barW2 = (ws.x - 40) * prog2
            drawGrad(dl, wp.x+20, wp.y+ws.y-3.5, barW2, 2.5,
                imgui.ImVec4(col.x,col.y,col.z,alpha*0.75), imgui.ImVec4(col.x,col.y,col.z,alpha*0.1))
            yOff = yOff + ws.y + 10
            imgui.End(); imgui.PopStyleColor()
            imgui.PopStyleVar(3)
        end
    end
)
-- =========================================================================
-- ДАШБОРД: ПОДФУНКЦИИ
-- =========================================================================
local function drawDashBanner(dl, contentW, t, ps, now)
    local bannerH = 110
    local bannerPos = imgui.GetCursorScreenPos()
    local bx, by = bannerPos.x, bannerPos.y
    local bw = contentW
    dl:AddRectFilled(imgui.ImVec2(bx, by), imgui.ImVec2(bx+bw, by+bannerH),
        ImVec4toU32(imgui.ImVec4(t.card.x, t.card.y, t.card.z, 0.6)), 18)
    local gradPhase = (math.sin(now * 0.8) + 1) * 0.5
    local gc1 = lerpColor(t.grad1, t.accent, gradPhase * 0.3)
    local gc2 = lerpColor(t.grad2, t.accent2, (1 - gradPhase) * 0.3)
    drawGradRounded(dl, bx, by, bw, 4, gc1, gc2, 18)
    drawGradV(dl, bx, by+4, bw, 25, imgui.ImVec4(1,1,1,0.03), imgui.ImVec4(1,1,1,0))
    dl:AddRect(imgui.ImVec2(bx, by), imgui.ImVec2(bx+bw, by+bannerH),
        ImVec4toU32(imgui.ImVec4(1,1,1,0.06)), 18)
    if settings.showParticles then
        for i = 1, 3 do
            local px = bx + ((now * 15 + i * 97) % bw)
            local py = by + ((math.sin(now * 0.7 + i * 1.3) + 1) * 0.5) * bannerH
            local pa = (math.sin(now * 2 + i) + 1) * 0.03
            dl:AddCircleFilled(imgui.ImVec2(px, py), 1.5,
                ImVec4toU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, pa)), 6)
        end
    end
    local avatarCx = bx + 50
    local avatarCy = by + bannerH / 2
    local avatarR = 30
    if textures.avatar ~= nil then
        local imgR = avatarR + 3
        dl:AddImageRounded(textures.avatar,
            imgui.ImVec2(avatarCx - imgR, avatarCy - imgR),
            imgui.ImVec2(avatarCx + imgR, avatarCy + imgR),
            imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), 0xFFFFFFFF, imgR)
    else
        local initials = ps.nick:sub(1, 2):upper()
        local initSize = imgui.CalcTextSize(u8(initials))
        dl:AddText(imgui.ImVec2(avatarCx - initSize.x/2, avatarCy - initSize.y/2),
            ImVec4toU32(t.accent2), u8(initials))
    end
    drawCircularProgress(dl, avatarCx, avatarCy, avatarR + 4,
        clamp(ps.hp / 100, 0, 1), 3,
        ps.hp > 50 and t.green or (ps.hp > 25 and t.yellow or t.red),
        imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.1))
    local greetHour = tonumber(os.date("%H"))
    local greeting = "Доброй ночи"
    if greetHour >= 5 and greetHour < 12 then greeting = "Доброе утро"
    elseif greetHour >= 12 and greetHour < 17 then greeting = "Добрый день"
    elseif greetHour >= 17 and greetHour < 22 then greeting = "Добрый вечер" end
    local nameDisplay = ps.nick:gsub("_", " ")
    local textX = bx + 102
    local textBaseY = avatarCy - 24
-- Имя: имитация крупного шрифта через SetWindowFontScale
dl:AddText(imgui.ImVec2(textX, textBaseY), ImVec4toU32(t.text), u8(greeting .. ","))
dl:AddText(imgui.ImVec2(textX, textBaseY + 18), ImVec4toU32(t.accent2), u8(nameDisplay))
dl:AddText(imgui.ImVec2(textX + 0.7, textBaseY + 18), ImVec4toU32(t.accent2, 0.5), u8(nameDisplay))
    local rightX = bx + bw - 16
    local clockText = u8(os.date("%H:%M"))
    local clockSize = imgui.CalcTextSize(clockText)
    dl:AddText(imgui.ImVec2(rightX - clockSize.x, by + 18), ImVec4toU32(t.text, 0.9), clockText)
    local dateText = u8(os.date("%d.%m.%Y, %A"))
    local dateSize = imgui.CalcTextSize(dateText)
    dl:AddText(imgui.ImVec2(rightX - dateSize.x, by + 38), ImVec4toU32(t.text3, 0.7), dateText)
    local sessionTime = now - S.sessionStartTime
    local sessText = u8("Сессия: " .. formatTime(sessionTime))
    local sessSize = imgui.CalcTextSize(sessText)
    dl:AddText(imgui.ImVec2(rightX - sessSize.x, by + 56), ImVec4toU32(t.text3, 0.5), sessText)
    local idText = u8(safeFormat("ID: %d  |  LVL: %d", ps.myId, ps.score))
    dl:AddText(imgui.ImVec2(textX, textBaseY + 38), ImVec4toU32(t.text3, 0.6), idText)
    if S.activeBinder then
        local statusY = textBaseY + 56
        pulsingDot(dl, textX + 4, statusY + 5, 4, t.yellow, 5)
        dl:AddText(imgui.ImVec2(textX + 16, statusY - 2),
            ImVec4toU32(t.yellow, 0.9), u8("Бинд: " .. S.currentBindName))
    end
    imgui.Dummy(imgui.ImVec2(bw, bannerH + 6))
end

local function drawDashMetrics(dl, contentW, t, ps)
    secTitle("Обзор")
    local cardGap = 10
    local cardsPerRow = 3
    local cardW = math.floor((contentW - cardGap * (cardsPerRow - 1)) / cardsPerRow)
    local cardH = 88
    local metrics = {
        { icon = "@", val = ps.online, label = "Онлайн", color = t.blue },
        { icon = "~", val = ps.fps,    label = "FPS",
            color = ps.fps > 30 and t.green or (ps.fps > 15 and t.yellow or t.red) },
        { icon = "!", val = ps.ping,   label = "Ping",
            color = ps.ping < 80 and t.green or (ps.ping < 150 and t.yellow or t.red) },
    }
    for mi, m in ipairs(metrics) do
        local mid = "dm_" .. mi
        local mhov = anim(mid .. "_h", 0, 0.12)
        local mbg = lerpColor(t.card, t.card_hover, mhov)
        imgui.PushStyleColor(imgui.Col.ChildBg, mbg)
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 16)
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildBorderSize, 0)
        local prevPadM = pushPadding(20, 16)
        imgui.BeginChild("##mc_" .. mi, imgui.ImVec2(cardW, cardH), true)
        imgui.GetStyle().WindowPadding = prevPadM
        local isH = imgui.IsWindowHovered(imgui.HoveredFlags.ChildWindows)
        anim(mid .. "_h", isH and 1 or 0, 0.12)
        local cdl = imgui.GetWindowDrawList()
        local cwp = imgui.GetWindowPos()
        drawShadow(cdl, cwp.x, cwp.y, cwp.x + cardW, cwp.y + cardH, 16, 3, 0.2 + mhov * 0.15)
        cdl:AddRect(imgui.ImVec2(cwp.x, cwp.y), imgui.ImVec2(cwp.x + cardW, cwp.y + cardH),
            ImVec4toU32(imgui.ImVec4(1, 1, 1, 0.04 + mhov * 0.03)), 16)
        drawGradRounded(cdl, cwp.x, cwp.y, cardW, 3,
            imgui.ImVec4(m.color.x, m.color.y, m.color.z, 0.6 + mhov * 0.3),
            imgui.ImVec4(m.color.x, m.color.y, m.color.z, 0.05), 16)
        drawGlow(cdl, cwp.x + cardW - 12, cwp.y + 12, 5, m.color, 0.08 + mhov * 0.1)
        imgui.PushStyleColor(imgui.Col.Text, m.color)
        imgui.SetCursorPos(imgui.ImVec2(18, 16))
        imgui.Text(u8(m.icon)); imgui.PopStyleColor()
        local numVal = tonumber(m.val)
        local displayVal = numVal and tostring(animatedCounter(mid .. "_v", numVal)) or tostring(m.val)
        imgui.SetCursorPos(imgui.ImVec2(18, 36))
if U.fontMedium then imgui.PushFont(U.fontMedium) end
imgui.PushStyleColor(imgui.Col.Text, t.text)
imgui.Text(u8(displayVal)); imgui.PopStyleColor()
if U.fontMedium then imgui.PopFont() end
        imgui.SetCursorPos(imgui.ImVec2(18, 58))
        imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8(m.label)); imgui.PopStyleColor()
        imgui.EndChild()
        imgui.PopStyleVar(3); imgui.PopStyleColor()
        if mi % cardsPerRow ~= 0 and mi < #metrics then imgui.SameLine(0, cardGap) end
        if mi % cardsPerRow == 0 and mi < #metrics then imgui.Spacing() end
    end
    imgui.Spacing(); thinSep()
end

local function drawDashStatus(dl, contentW, t, ps, now, stats)
    local cardGap = 10
    local leftColW = math.floor(contentW * 0.55)
    local rightColW = contentW - leftColW - cardGap
    secTitle("Статус и здоровье")
    cardBegin("##status_main", imgui.ImVec2(leftColW, S.activeBinder and 130 or 100), false, 6)
    local sdl = imgui.GetWindowDrawList()
    local sPos = imgui.GetCursorScreenPos()
    if S.activeBinder then
        pulsingDot(sdl, sPos.x + 14, sPos.y + 8, 6, t.yellow, 5)
        imgui.Dummy(imgui.ImVec2(30, 16)); imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Text, t.yellow); imgui.Text(u8("ВЫПОЛНЯЕТСЯ")); imgui.PopStyleColor()
        imgui.SameLine(0, 10)
        imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.Text(u8(S.currentBindName)); imgui.PopStyleColor()
        imgui.Spacing()
        local bindProg = clamp(S.currentBindProgress / math.max(S.currentBindTotal, 1), 0, 1)
        local progSp = imgui.GetCursorScreenPos()
        local progW = imgui.GetContentRegionAvail().x; local progH = 8
        local animProg = anim("bind_prog_main", bindProg, 0.08)
        sdl:AddRectFilled(imgui.ImVec2(progSp.x, progSp.y), imgui.ImVec2(progSp.x + progW, progSp.y + progH),
            ImVec4toU32(imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.12)), progH / 2)
        if animProg > 0.001 then
            local fillW = progW * animProg
            drawGrad(sdl, progSp.x, progSp.y, fillW, progH, t.yellow, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.8))
            drawGlow(sdl, progSp.x + fillW, progSp.y + progH/2, 4, t.yellow, 0.5)
        end
        imgui.Dummy(imgui.ImVec2(progW, progH + 4))
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8(safeFormat("Шаг %d / %d • %s • %d%%",
            S.currentBindProgress, S.currentBindTotal,
            formatTimeShort(now - S.currentBindStartTime), math.floor(bindProg * 100))))
        imgui.PopStyleColor(); imgui.Spacing()
        if btn(" СТОП ", 100, 28, "danger") then S.stopCurrentBind = true end
    else
        pulsingDot(sdl, sPos.x + 14, sPos.y + 8, 5, t.green, 2)
        imgui.Dummy(imgui.ImVec2(30, 16)); imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Text, t.green); imgui.Text(u8("ГОТОВ К РАБОТЕ")); imgui.PopStyleColor()
        if S.lastBindName ~= "" then
            imgui.Spacing(); imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.Text(u8("Последний: " .. S.lastBindName .. " (" .. formatTime(now - S.lastBindTime) .. " назад)"))
            imgui.PopStyleColor()
        end
        imgui.Spacing(); imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8(safeFormat("Биндов/час: %d • Всего шагов: %d • Команд: %d • Хоткеев: %d",
            stats.bindsPerHour, stats.totalSteps, stats.bCmds, stats.bKeys)))
        imgui.PopStyleColor()
    end
    cardEnd()
    imgui.SameLine(0, cardGap)
    cardBegin("##vitals_card", imgui.ImVec2(rightColW, S.activeBinder and 130 or 100), false, 6)
    local vdl = imgui.GetWindowDrawList()
    local vPos = imgui.GetCursorScreenPos()
    local hpR = 24; local hpCx = vPos.x + 36; local hpCy = vPos.y + 30
    local hpProg = clamp(ps.hp / 100, 0, 1)
    local hpColor = ps.hp > 50 and t.green or (ps.hp > 25 and t.yellow or t.red)
    drawCircularProgress(vdl, hpCx, hpCy, hpR, anim("hp_circ", hpProg, 0.05), 4, hpColor,
        imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.1))
    local hpText = u8(tostring(animatedCounter("hp_val", ps.hp)))
    local hpTSize = imgui.CalcTextSize(hpText)
    vdl:AddText(imgui.ImVec2(hpCx - hpTSize.x/2, hpCy - hpTSize.y/2), ImVec4toU32(hpColor), hpText)
    local hpLabel = u8("HP"); local hpLabelSize = imgui.CalcTextSize(hpLabel)
    vdl:AddText(imgui.ImVec2(hpCx - hpLabelSize.x/2, hpCy + hpR + 6), ImVec4toU32(t.text3, 0.6), hpLabel)
    local armCx = vPos.x + 100; local armCy = vPos.y + 30
    local armProg = clamp(ps.armor / 100, 0, 1)
    drawCircularProgress(vdl, armCx, armCy, hpR, anim("arm_circ", armProg, 0.05), 4, t.blue,
        imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.1))
    local armText = u8(tostring(animatedCounter("arm_val", ps.armor)))
    local armTSize = imgui.CalcTextSize(armText)
    vdl:AddText(imgui.ImVec2(armCx - armTSize.x/2, armCy - armTSize.y/2), ImVec4toU32(t.blue), armText)
    local armLabel = u8("ARM"); local armLabelSize = imgui.CalcTextSize(armLabel)
    vdl:AddText(imgui.ImVec2(armCx - armLabelSize.x/2, armCy + hpR + 6), ImVec4toU32(t.text3, 0.6), armLabel)
    local infoX = vPos.x + 150; local infoBaseY = hpCy - hpR
    vdl:AddText(imgui.ImVec2(infoX, infoBaseY), ImVec4toU32(t.text3, 0.6), u8("Оружие"))
    vdl:AddText(imgui.ImVec2(infoX, infoBaseY + 14), ImVec4toU32(t.text, 0.8), u8("ID: " .. ps.weapon))
    vdl:AddText(imgui.ImVec2(infoX, infoBaseY + 34), ImVec4toU32(t.text3, 0.6), u8("Избранных"))
    vdl:AddText(imgui.ImVec2(infoX, infoBaseY + 48), ImVec4toU32(t.yellow, 0.8), u8(tostring(stats.bFav)))
    imgui.Dummy(imgui.ImVec2(rightColW - 32, 70))
    cardEnd()
    imgui.Spacing(); thinSep()
end

local function drawDashFavorites(contentW, t)
    if not settings.showFavorites then return end
end

local function drawDashActivityLog(t, now)
    secTitle("Журнал активности")
    cardBegin("##activity_log", imgui.ImVec2(-1, 200))
    if #recentActivity == 0 then
        imgui.Spacing(); imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8(" Активность пока не зафиксирована")); imgui.PopStyleColor()
    else
        local adl = imgui.GetWindowDrawList()
        for i = 1, math.min(#recentActivity, 8) do
            local act = recentActivity[i]
            local el = now - act.time
            local col = act.atype == "bind" and t.accent2
                or act.atype == "gwarn" and t.yellow
                or act.atype == "uk" and t.red
                or act.atype == "system" and t.blue or t.text2
            local linePos = imgui.GetCursorScreenPos()
            if i < math.min(#recentActivity, 8) then
                adl:AddLine(imgui.ImVec2(linePos.x + 8, linePos.y + 14),
                    imgui.ImVec2(linePos.x + 8, linePos.y + 28),
                    ImVec4toU32(imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.10)), 1)
            end
            local dotSize = (i == 1) and 5 or 3.5
            adl:AddCircleFilled(imgui.ImVec2(linePos.x + 8, linePos.y + 8), dotSize, ImVec4toU32(col, 0.8), 12)
            if i == 1 then drawGlow(adl, linePos.x + 8, linePos.y + 8, 4, col, 0.3) end
            imgui.Dummy(imgui.ImVec2(22, 0)); imgui.SameLine()
            imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.Text(u8(act.timestamp or "")); imgui.PopStyleColor()
            imgui.SameLine(0, 14)
            imgui.PushStyleColor(imgui.Col.Text, i == 1 and col or lerpColor(col, t.text3, 0.3))
            imgui.Text(u8(act.text)); imgui.PopStyleColor()
            if el < 60 then
                imgui.SameLine(imgui.GetContentRegionAvail().x - 30)
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.4))
                imgui.Text(u8(safeFormat("%dс", math.floor(el)))); imgui.PopStyleColor()
            end
        end
    end
    cardEnd()
end

local function drawDashAutoFind(contentW, t)
    cardBegin("##dash_afind", imgui.ImVec2(contentW, 160))
    imgui.PushStyleColor(imgui.Col.Text, t.accent2); imgui.Text(u8("AutoFind")); imgui.PopStyleColor()
    imgui.Spacing()
    local afdl = imgui.GetWindowDrawList(); local afsp = imgui.GetCursorScreenPos()
    if autoFind.active and autoFind.lastId ~= -1 then
        pulsingDot(afdl, afsp.x + 8, afsp.y + 8, 5, t.yellow, 4)
        imgui.Dummy(imgui.ImVec2(22, 12)); imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Text, t.yellow); imgui.Text(u8("ПОИСК АКТИВЕН")); imgui.PopStyleColor()
        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.Text(u8("Цель: " .. autoFind.lastNick)); imgui.PopStyleColor()
        imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8("ID: " .. autoFind.lastId)); imgui.PopStyleColor()
        if autoFind.lastDist then
            local distCol = autoFind.proximityAlerted and t.green or t.text3
            imgui.PushStyleColor(imgui.Col.Text, distCol)
            imgui.Text(u8("Дистанция: " .. autoFind.lastDist .. "м")); imgui.PopStyleColor()
        end
        if autoFind.proximityAlerted then
            imgui.PushStyleColor(imgui.Col.Text, t.green); imgui.Text(u8("< ЦЕЛЬ РЯДОМ! >")); imgui.PopStyleColor()
        end
        if autoFind.waitInta then imgui.PushStyleColor(imgui.Col.Text, t.red); imgui.Text(u8("В интерьере!")); imgui.PopStyleColor() end
        imgui.Spacing()
        if btn("Остановить##af_stop", -1, 26, "danger") then addNotification("AutoFind: поиск завершён", C.NOTIFY_INFO); afReset() end
    else
        afdl:AddCircleFilled(imgui.ImVec2(afsp.x + 8, afsp.y + 8), 4,
            ImVec4toU32(imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.3)), 12)
        imgui.Dummy(imgui.ImVec2(22, 12)); imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8("Используйте /afind [ID]")); imgui.Text(u8("для отслеживания игрока")); imgui.PopStyleColor()
    end
    cardEnd(); imgui.Spacing(); thinSep()
end

-- УЛУЧШЕНИЕ #7 — кэш статистики
local function getCachedBindStats()
    local now = os.clock()
    if dashData.cachedBindStats and (now - S.lastBindStatsUpdate) < C.BIND_STATS_INTERVAL then
        return dashData.cachedBindStats
    end
    local stats = { totalUses=0, bKeys=0, bCmds=0, bEnabled=0, bFav=0, bDisabled=0, totalSteps=0, bindsPerHour=0 }
    for _, b in ipairs(binds) do
        stats.totalUses = stats.totalUses + (b.uses or 0)
        if b.key and b.key ~= 0 then stats.bKeys = stats.bKeys + 1 end
        if b.cmd and b.cmd ~= "" then stats.bCmds = stats.bCmds + 1 end
        if b.enabled ~= false then stats.bEnabled = stats.bEnabled + 1 else stats.bDisabled = stats.bDisabled + 1 end
        if b.favorite then stats.bFav = stats.bFav + 1 end
        stats.totalSteps = stats.totalSteps + #(b.steps or {})
    end
    local sessionTime = now - S.sessionStartTime
    stats.bindsPerHour = sessionTime > 0 and math.floor(S.totalSessionBinds / (sessionTime / 3600) + 0.5) or 0
    dashData.cachedBindStats = stats; S.lastBindStatsUpdate = now
    return stats
end

-- =========================================================================
-- ДАШБОРД: ГЛАВНАЯ
-- =========================================================================
local function drawDashboard()
    local t = T(); local now = os.clock()
    local ps = getCachedPlayerStats()
    if now - S.lastFpsUpdate > 0.5 then
        S.lastFpsUpdate = now
        local cap = dashData._ringMaxFPS
        dashData._ringIdxFPS = (dashData._ringIdxFPS % cap) + 1
        dashData.fpsHistory[dashData._ringIdxFPS] = ps.fps
        dashData.pingHistory[dashData._ringIdxFPS] = ps.ping
        if dashData._ringSizeFPS < cap then dashData._ringSizeFPS = dashData._ringSizeFPS + 1 end
    end
    local stats = getCachedBindStats()
    setWindowPadding(S.contentPadding, S.contentPadding)
    imgui.BeginChild("##dash", imgui.ImVec2(0,0), false)
    local dl = imgui.GetWindowDrawList()
    local contentW = imgui.GetContentRegionAvail().x
    drawDashBanner(dl, contentW, t, ps, now)
    drawDashMetrics(dl, contentW, t, ps)
    drawDashStatus(dl, contentW, t, ps, now, stats)
    drawDashFavorites(contentW, t)
    drawDashActivityLog(t, now)
    drawDashAutoFind(contentW, t)
    imgui.Spacing(); imgui.EndChild()
end

-- =========================================================================
-- ПОДСВЕТКА СИНТАКСИСА ШАГОВ
-- =========================================================================
-- Рисует цветной оверлей поверх InputTextMultiline через DrawList
-- Вызывать ПОСЛЕ imgui.InputTextMultiline
local function drawStepsSyntaxHighlight(stepsRaw, frameMin, frameMax)
    local t = T()
    local dl = imgui.GetWindowDrawList()
    local decoded = u8:decode(stepsRaw or "")
    if not decoded or decoded == "" then return end
    -- Читаем реальный FramePadding и высоту строки из стиля imgui
    local fp  = imgui.GetStyle().FramePadding
    local lh  = imgui.GetTextLineHeightWithSpacing()
    local px  = fp.x
    local py  = fp.y
    local lineY = frameMin.y + py
    local visibleBottom = frameMax.y
    dl:PushClipRect(frameMin, frameMax, true)
    for line in (decoded .. "\n"):gmatch("([^\n]*)\n") do
        if lineY > visibleBottom then break end
        if lineY + lh >= frameMin.y then
            -- Сохраняем оригинальную строку (с пробелами) для корректного X
            local tr = trim(line)
            if tr ~= "" then
                -- Смещение X с учётом ведущих пробелов оригинальной строки
                local leadSpaces = line:match("^(%s*)")
                local indentW = leadSpaces and imgui.CalcTextSize(u8(leadSpaces)).x or 0
                local lineX = frameMin.x + px + indentW

                if tr:sub(1,2) == "//" or tr:sub(1,1) == "#" then
                    -- Комментарий — серый
                    dl:AddText(imgui.ImVec2(lineX, lineY),
                        ImVec4toU32(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z, 0.5)), u8(tr))

                elseif tr:match("^%[%d+%]$") or tr:match("^%[wait_random:")
                    or tr:match("^%[repeat:") or tr:match("^%[if:") then
                    -- Спецкоманды — пурпурные
                    dl:AddText(imgui.ImVec2(lineX, lineY),
                        ImVec4toU32(imgui.ImVec4(0.72, 0.52, 1, 0.9)), u8(tr))

                else
                    local cmdPart = tr:match("^(/[^%s]+)")
                    if cmdPart then
                        -- Команда — акцентный синий
                        dl:AddText(imgui.ImVec2(lineX, lineY),
                            ImVec4toU32(t.accent, 0.9), u8(cmdPart))
                        local rest  = tr:sub(#cmdPart + 1)
                        local restX = lineX + imgui.CalcTextSize(u8(cmdPart)).x
                        local pos   = 1
                        while pos <= #rest do
                            local s1, e1, vn = rest:find("{([^}]+)}", pos)
                            if not s1 then
                                -- Обычный текст до конца
                                dl:AddText(imgui.ImVec2(restX, lineY),
                                    ImVec4toU32(t.text, 0.75), u8(rest:sub(pos)))
                                break
                            end
                            if s1 > pos then
                                local plain = rest:sub(pos, s1-1)
                                dl:AddText(imgui.ImVec2(restX, lineY),
                                    ImVec4toU32(t.text, 0.75), u8(plain))
                                restX = restX + imgui.CalcTextSize(u8(plain)).x
                            end
                            -- Переменная: системная ? зелёная, кастомная ? жёлтая
                            local varTxt = "{" .. vn .. "}"
                            local isSys  = (not vn:match("^%x%x%x%x%x%x$")) and (simpleVariables[vn] ~= nil)
                            local varCol = isSys
                                and imgui.ImVec4(t.green.x,  t.green.y,  t.green.z,  0.95)
                                or  imgui.ImVec4(t.yellow.x, t.yellow.y, t.yellow.z, 0.95)
                            dl:AddText(imgui.ImVec2(restX, lineY), ImVec4toU32(varCol), u8(varTxt))
                            restX = restX + imgui.CalcTextSize(u8(varTxt)).x
                            pos = e1 + 1
                        end
                    else
                        -- Текст без команды — приглушённый белый
                        dl:AddText(imgui.ImVec2(lineX, lineY),
                            ImVec4toU32(t.text, 0.65), u8(tr))
                    end
                end
            end
        end
        lineY = lineY + lh
    end
    dl:PopClipRect()
end

-- =========================================================================
-- СОХРАНЕНИЕ ТЕКУЩЕГО БИНДА (используется кнопкой и автосохранением)
-- =========================================================================
saveCurrentBind = function(silent)
    local name = u8:decode(trim(ffi.string(B.editNameBuf)))
    local cmdR = trim(ffi.string(B.editCmdBuf))
    local cmd  = trim(cmdR:match("^/?(.+)") or "")
    local stR  = u8:decode(ffi.string(B.editStepsBuf))
    local desc = u8:decode(trim(ffi.string(B.editDescBuf)))
    if name == "" or stR == "" then
        if not silent then addNotification("Заполните название и шаги!", C.NOTIFY_ERROR) end
        return false
    end
    local nb = {
        id = (S.selectedBindIndex and binds[S.selectedBindIndex]
            and binds[S.selectedBindIndex].id) or generateId(),
        name = name, cmd = cmd, desc = desc,
        steps = splitSteps(stR), delay = B.editDelayBuf[0],
        key = B.editKeyBuf[0], key_mod = B.editKeyModBuf[0],
        cooldown = B.editCooldownBuf[0],
        enabled = B.editEnabledBuf[0], favorite = B.editFavoriteBuf[0],
        category = B.editCategoryBuf[0],
        uses = (S.selectedBindIndex and binds[S.selectedBindIndex]
            and binds[S.selectedBindIndex].uses) or 0,
        created = (S.selectedBindIndex and binds[S.selectedBindIndex]
            and binds[S.selectedBindIndex].created) or os.time(),
    }
    if S.selectedBindIndex and binds[S.selectedBindIndex] then
        binds[S.selectedBindIndex] = nb
    else
        table.insert(binds, nb); S.selectedBindIndex = #binds
        S.isCreatingNew = false
    end
    saveBinds()
    markEditorClean()
    dashData.cachedBindStats = nil
    if not silent then addNotification("Сохранено!", C.NOTIFY_SUCCESS) end
    return true
end

-- =========================================================================
-- БИНДЕР: ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (вынесены для лимита 200 locals)
-- =========================================================================
-- Цвета категорий — определяем один раз вне цикла (upvalue, не top-level local)
local function getBindCatColor(category)
    local t2 = T()
    local colors = { t2.accent, t2.green, t2.blue, t2.red, t2.yellow }
    return colors[(category or 0) + 1] or t2.accent
end

-- Рендер hover-превью шагов бинда (вынесен из drawBinder для экономии locals)
local function drawBindHoverPreview(b, btnMin, btnMax, stripeCol)
    if not imgui.IsItemHovered() then return end
    if not b.steps or #b.steps == 0 then return end
    local t = T()
    local previewW = 220
    local previewX = btnMax.x + 6
    if previewX + previewW > sizeX - 10 then
        previewX = btnMin.x - previewW - 6
    end
    local maxSteps = math.min(#b.steps, 5)
    local previewH = 36 + maxSteps * 16 + 10
    local previewY = clamp(btnMin.y, 10, sizeY - previewH - 10)
    local pdl = imgui.GetForegroundDrawList()
    -- Тень
    for pi = 1, 3 do
        pdl:AddRectFilled(
            imgui.ImVec2(previewX - 1 + pi*3, previewY - 1 + pi*3),
            imgui.ImVec2(previewX + previewW + 1 + pi*3, previewY + previewH + 1 + pi*3),
            ImVec4toU32(imgui.ImVec4(0, 0, 0, 0.06 * (1 - pi/4))), 12)
    end
    -- Фон + рамка
    pdl:AddRectFilled(imgui.ImVec2(previewX, previewY),
        imgui.ImVec2(previewX + previewW, previewY + previewH),
        ImVec4toU32(imgui.ImVec4(t.card.x, t.card.y, t.card.z, 0.98)), 12)
    pdl:AddRect(imgui.ImVec2(previewX, previewY),
        imgui.ImVec2(previewX + previewW, previewY + previewH),
        ImVec4toU32(imgui.ImVec4(stripeCol.x, stripeCol.y, stripeCol.z, 0.40)), 12, 15, 0.5)
    -- Акцентная полоска сверху
    pdl:AddRectFilled(imgui.ImVec2(previewX + 8, previewY),
        imgui.ImVec2(previewX + previewW - 8, previewY + 2),
        ImVec4toU32(stripeCol, 0.7), 1)
    -- Заголовок
    pdl:AddText(imgui.ImVec2(previewX + 10, previewY + 8),
        ImVec4toU32(t.text, 0.95), u8((b.name ~= "" and b.name) or "Бинд"))
    -- Мета
    local pmeta = safeFormat("%d шагов · %dмс", #b.steps, b.delay or settings.defaultDelay)
    if b.cmd and b.cmd ~= "" then
        pmeta = "/" .. (b.cmd:match("^(%S+)") or b.cmd) .. " · " .. pmeta
    end
    pdl:AddText(imgui.ImVec2(previewX + 10, previewY + 22),
        ImVec4toU32(t.text3, 0.55), u8(pmeta))
    -- Шаги
    local stepY = previewY + 36
    for si = 1, maxSteps do
        local step = b.steps[si]
        local stepStr = #step > 28 and (step:sub(1, 26) .. "..") or step
        local stepCol
        if step:match("^%[") then
            stepCol = imgui.ImVec4(0.72, 0.52, 1, 0.85)
        elseif step:match("^/") then
            stepCol = imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.85)
        else
            stepCol = imgui.ImVec4(t.text2.x, t.text2.y, t.text2.z, 0.6)
        end
        pdl:AddCircleFilled(imgui.ImVec2(previewX + 14, stepY + 6), 2, ImVec4toU32(stepCol, 0.7), 8)
        pdl:AddText(imgui.ImVec2(previewX + 22, stepY), ImVec4toU32(stepCol), u8(stepStr))
        stepY = stepY + 16
    end
    if #b.steps > maxSteps then
        pdl:AddText(imgui.ImVec2(previewX + 22, stepY), ImVec4toU32(t.text3, 0.40),
            u8(safeFormat("+ %d шагов...", #b.steps - maxSteps)))
    end
end

-- Пассивный просмотр шагов (вынесен из drawBinder для снижения кол-ва locals)
local function drawStepsPassiveViewer(stH)
    local t2 = T()
    local fsp = imgui.GetCursorScreenPos()
    local fsw = imgui.GetContentRegionAvail().x
    local fdl = imgui.GetWindowDrawList()
    fdl:AddRectFilled(imgui.ImVec2(fsp.x, fsp.y), imgui.ImVec2(fsp.x+fsw, fsp.y+stH),
        ImVec4toU32(imgui.ImVec4(t2.input.x+0.05, t2.input.y+0.05, t2.input.z+0.05, 0.95)), 14)
    fdl:AddRect(imgui.ImVec2(fsp.x, fsp.y), imgui.ImVec2(fsp.x+fsw, fsp.y+stH),
        ImVec4toU32(imgui.ImVec4(t2.text3.x, t2.text3.y, t2.text3.z, 0.18)), 14, 15, 0.5)
    if ffi.string(B.editStepsBuf) == "" then
        fdl:AddText(imgui.ImVec2(fsp.x+12, fsp.y+8),
            ImVec4toU32(imgui.ImVec4(t2.text3.x,t2.text3.y,t2.text3.z,0.3)), u8("Нажмите для редактирования"))
    end
    imgui.InvisibleButton("##eStepsView", imgui.ImVec2(fsw, stH))
    if imgui.IsItemClicked() then S._stepsFieldActive = true end
    fdl:PushClipRect(imgui.ImVec2(fsp.x+2, fsp.y+2), imgui.ImVec2(fsp.x+fsw-2, fsp.y+stH-2), true)
    local lh    = imgui.GetTextLineHeightWithSpacing()
    local lineY = fsp.y + 8
    local lineX = fsp.x + 12
    local dec2  = u8:decode(ffi.string(B.editStepsBuf))
    for line in (dec2 .. "\n"):gmatch("([^\n]*)\n") do
        if lineY + lh > fsp.y + stH then break end
        local tr2 = trim(line)
        if tr2 ~= "" then
            if tr2:sub(1,2) == "//" or tr2:sub(1,1) == "#" then
                fdl:AddText(imgui.ImVec2(lineX, lineY), ImVec4toU32(t2.text3, 0.5), u8(tr2))
            elseif tr2:match("^%[") then
                fdl:AddText(imgui.ImVec2(lineX, lineY), ImVec4toU32(imgui.ImVec4(0.72,0.52,1,0.9)), u8(tr2))
            elseif tr2:match("^/") then
                local cmd2 = tr2:match("^(/[^%s]+)") or ""
                fdl:AddText(imgui.ImVec2(lineX, lineY), ImVec4toU32(t2.accent, 0.9), u8(cmd2))
                local rx    = lineX + imgui.CalcTextSize(u8(cmd2)).x
                local rest2 = tr2:sub(#cmd2+1)
                local p2    = 1
                while p2 <= #rest2 do
                    local s2, e2, vn2 = rest2:find("{([^}]+)}", p2)
                    if not s2 then
                        fdl:AddText(imgui.ImVec2(rx, lineY), ImVec4toU32(t2.text, 0.8), u8(rest2:sub(p2))); break
                    end
                    if s2 > p2 then
                        local pl = rest2:sub(p2, s2-1)
                        fdl:AddText(imgui.ImVec2(rx, lineY), ImVec4toU32(t2.text, 0.8), u8(pl))
                        rx = rx + imgui.CalcTextSize(u8(pl)).x
                    end
                    local vt = "{" .. vn2 .. "}"
                    local vc = (not vn2:match("^%x%x%x%x%x%x$") and simpleVariables[vn2])
                        and imgui.ImVec4(t2.green.x,  t2.green.y,  t2.green.z,  0.95)
                        or  imgui.ImVec4(t2.yellow.x, t2.yellow.y, t2.yellow.z, 0.95)
                    fdl:AddText(imgui.ImVec2(rx, lineY), ImVec4toU32(vc), u8(vt))
                    rx = rx + imgui.CalcTextSize(u8(vt)).x
                    p2 = e2 + 1
                end
            else
                fdl:AddText(imgui.ImVec2(lineX, lineY), ImVec4toU32(t2.text, 0.7), u8(tr2))
            end
        end
        lineY = lineY + lh
    end
    fdl:PopClipRect()
end


-- =========================================================================
-- БЫСТРЫЕ ДЕЙСТВИЯ: ВКЛАДКА НАСТРОЕК
-- =========================================================================
local function drawQuickActionsTab()
    local t = T()
    setWindowPadding(0, 0)
    local av = imgui.GetContentRegionAvail()
    local listW = math.max(av.x * 0.25, 240)
    local editW = av.x - listW - 12

    -- ===== ЛЕВАЯ ПАНЕЛЬ (зеркало биндера) ===================================
    imgui.PushStyleColor(imgui.Col.ChildBg, t.sidebar)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 18)
    pushWindowPadding(16, 14)
    imgui.BeginChild("##qa_left", imgui.ImVec2(listW, -1), true)

    -- Поиск (идентично биндеру)
    if not B.qaSearchBuf then B.qaSearchBuf = ffi.new("char[128]") end
    imgui.PushItemWidth(-1)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 22)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(14, 9))
    imgui.InputTextWithHint("##qasearch", u8(" Поиск..."), B.qaSearchBuf, 128)
    imgui.PopStyleVar(2); imgui.PopItemWidth()
    imgui.Spacing()

    -- Вкладки режима (стиль категорий биндера, 2 в ряд)
    do
        local modes     = { "Пешком", "В транспорте" }
        local modeColors= { t.accent, imgui.ImVec4(0.13, 0.83, 0.78, 1) }
        local totalW2   = imgui.GetContentRegionAvail().x
        local tabH2     = 26; local tabGap2 = 4
        local tabW2     = math.floor((totalW2 - tabGap2) / 2)
        for mi, mname in ipairs(modes) do
            local ci = mi - 1; local mc = modeColors[mi]
            local isActive = QA.editTab == ci
            local hov2 = anim("qa_mtab_"..ci, 0, 0.15)
            local bgA2 = isActive and 0.65 or (hov2 * 0.12)
            local bg2  = isActive
                and imgui.ImVec4(mc.x, mc.y, mc.z, bgA2)
                or  imgui.ImVec4(t.card.x, t.card.y, t.card.z, 0.3 + hov2 * 0.15)
            imgui.PushStyleColor(imgui.Col.Button,        bg2)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(mc.x,mc.y,mc.z,0.25))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(mc.x,mc.y,mc.z,0.4))
            imgui.PushStyleColor(imgui.Col.Text,
                isActive and imgui.ImVec4(1,1,1,1) or lerpColor(t.text3, t.text2, hov2))
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8)
            imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(0, 4))
            if imgui.Button(u8(mname).."##qamt"..ci, imgui.ImVec2(tabW2, tabH2)) then
                if QA.editTab ~= ci then
                    QA.editTab = ci
                    QA.editingSlot=nil; QA.editingBind=nil; QA.editingBindIdx=nil
                    B._qaEditorLoaded = false
                end
            end
            if isActive then
                local mi2b = imgui.GetItemRectMin(); local ma2b = imgui.GetItemRectMax()
                local dl2b = imgui.GetWindowDrawList()
                dl2b:AddRectFilled(imgui.ImVec2(mi2b.x+8, ma2b.y-3),
                    imgui.ImVec2(ma2b.x-8, ma2b.y), ImVec4toU32(mc, 0.8), 2)
            end
            if imgui.IsItemHovered() then anim("qa_mtab_"..ci, 1, 0.15)
            else anim("qa_mtab_"..ci, 0, 0.08) end
            imgui.PopStyleVar(2); imgui.PopStyleColor(4)
            if mi == 1 then imgui.SameLine(0, tabGap2) end
        end
    end
    imgui.Spacing()

    -- Кнопка "+ Создать слот" (зеркало "+ Создать")
    local modeKey = QA.editTab==0 and "foot" or "vehicle"
    local slots   = QA.editTab==0 and QA.foot or QA.vehicle
    local qaCol   = QA.editTab==0 and t.accent or imgui.ImVec4(0.13, 0.83, 0.78, 1)

    if #slots < 8 then
        if btn("+ Создать слот##qadd_"..modeKey, -1, 36, "accent") then
            local newSlot = { key=0, keyMod=0, label="Действие", bindId="" }
            table.insert(slots, newSlot); QA:save()
            QA.editingSlot=newSlot; QA.editingBind=nil; QA.editingBindIdx=nil
            B._qaEditorLoaded = false
        end
    end
    imgui.Spacing()

    -- Фильтрация по поиску
    local qaSearchStr = ffi.string(B.qaSearchBuf):lower()
    local qaFilt = {}
    for qi, slot in ipairs(slots) do
        local nm = (slot.label or ""):lower(); local bn = ""
        if slot.bindId and slot.bindId ~= "" then
            for _, b in ipairs(binds) do
                if b.id == slot.bindId then bn = (b.name or ""):lower(); break end
            end
        end
        if qaSearchStr == "" or nm:find(qaSearchStr,1,true) or bn:find(qaSearchStr,1,true) then
            table.insert(qaFilt, qi)
        end
    end

    -- Счётчик (зеркало биндера)
    local qaFilterActive = qaSearchStr ~= ""
    if qaFilterActive then
        imgui.PushStyleColor(imgui.Col.Text, t.accent2)
        imgui.Text(u8(safeFormat("Найдено: %d из %d", #qaFilt, #slots)))
        imgui.PopStyleColor()
    else
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8(safeFormat("Слотов: %d", #slots)))
        imgui.PopStyleColor()
    end
    imgui.Spacing()

    -- ===== СПИСОК СЛОТОВ (зеркало списка биндов) ============================
    imgui.BeginChild("##qa_slots_scroll", imgui.ImVec2(0, 0), false)

    if #qaFilt == 0 then
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8(#slots == 0 and "Нет слотов" or "Нет совпадений"))
        imgui.PopStyleColor()
    else
        if not S.dragQAIdx then S.dragQAIdx = nil; S.dragQATarget = nil end

        for _, qi in ipairs(qaFilt) do
            local slot    = slots[qi]
            local isEdit  = (QA.editingSlot == slot)
            local bindObj = nil
            if slot.bindId and slot.bindId ~= "" then
                for _, b in ipairs(binds) do
                    if b.id == slot.bindId then bindObj = b; break end
                end
            end

            local lid2  = "qa_sl_"..modeKey..qi
            local hov2  = anim(lid2.."_h", 0, 0.15)
            local bgCol2
            if isEdit then
                bgCol2 = imgui.ImVec4(qaCol.x, qaCol.y, qaCol.z, 0.16 + hov2*0.08)
            elseif S.dragQATarget == qi then
                bgCol2 = imgui.ImVec4(qaCol.x, qaCol.y, qaCol.z, 0.25)
            else
                bgCol2 = imgui.ImVec4(t.card.x, t.card.y, t.card.z, hov2 * 0.45)
            end

            imgui.PushStyleColor(imgui.Col.Button,        bgCol2)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(qaCol.x, qaCol.y, qaCol.z, 0.12))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(qaCol.x, qaCol.y, qaCol.z, 0.22))
            imgui.PushStyleColor(imgui.Col.Text, t.text)
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)

            -- Тот же 46px высотой элемент что и в биндере
            local buttonH2 = 46
            if imgui.Button("##qaslb_"..modeKey..qi, imgui.ImVec2(-1, buttonH2)) then
                if not isEdit then
                    QA.editingSlot = slot; QA.editingBind = bindObj; QA.editingBindIdx = nil
                    if bindObj then
                        for bi2, b in ipairs(binds) do
                            if b.id == slot.bindId then QA.editingBindIdx = bi2; break end
                        end
                    end
                    B._qaEditorLoaded = false
                else
                    QA.editingSlot=nil; QA.editingBind=nil; QA.editingBindIdx=nil
                    B._qaEditorLoaded = false
                end
            end

            local bMin2 = imgui.GetItemRectMin(); local bMax2 = imgui.GetItemRectMax()
            local bDl2  = imgui.GetWindowDrawList()

            -- Акцентная полоска выбранного (зеркало биндера)
            if isEdit then
                bDl2:AddRectFilled(imgui.ImVec2(bMin2.x, bMin2.y+3),
                    imgui.ImVec2(bMin2.x+3, bMax2.y-3), ImVec4toU32(qaCol), 2)
                drawGlow(bDl2, bMin2.x+1, (bMin2.y+bMax2.y)/2, 4, qaCol, 0.3)
            end

            -- Строка 1: название слота (+ disabled-тильда если бинд выключен)
            local hasBind  = bindObj ~= nil
            local enabled  = not hasBind or (bindObj.enabled ~= false)
            local dispName = (not enabled and "~ " or "") .. (slot.label or "Слот")
            bDl2:AddText(imgui.ImVec2(bMin2.x+10, bMin2.y+6),
                ImVec4toU32(enabled and t.text or t.text3, 0.92), u8(dispName))

            -- Строка 2: мета (команда, кол-во шагов, использований)
            local meta2 = {}
            if bindObj then
                if bindObj.cmd and bindObj.cmd ~= "" then
                    table.insert(meta2, "/"..(bindObj.cmd:match("^(%S+)") or bindObj.cmd))
                end
                table.insert(meta2, #(bindObj.steps or {}).." шагов")
                if (bindObj.uses or 0) > 0 then table.insert(meta2, bindObj.uses.." исп.") end
            else
                table.insert(meta2, "бинд не задан")
            end
            bDl2:AddText(imgui.ImVec2(bMin2.x+12, bMin2.y+24),
                ImVec4toU32(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.6)), u8(table.concat(meta2," · ")))

            -- Хоткей chip справа (зеркало биндера)
            if (slot.key or 0) ~= 0 then
                local chipW2 = drawKeyChip(bDl2, 0, 0, slot.key, slot.keyMod or 0, t, 0)
                local chipX2 = bMax2.x - chipW2 - 6
                drawKeyChip(bDl2, chipX2, bMin2.y+(buttonH2-18)/2, slot.key, slot.keyMod or 0, t, 0.85)
            end

            -- Цветная точка статуса справа (зеркало биндера catDot)
            local dotOffX = 18
            bDl2:AddCircleFilled(imgui.ImVec2(bMax2.x-dotOffX, bMin2.y+buttonH2/2),
                3.5, ImVec4toU32(qaCol, hasBind and (enabled and 0.65 or 0.25) or 0.18), 10)

            -- Hover-превью шагов
            if bindObj then drawBindHoverPreview(bindObj, bMin2, bMax2, qaCol) end

            -- Drag-and-drop
            if imgui.IsItemActive() and imgui.IsMouseDragging(0, 3.0) then S.dragQAIdx = qi end
            if S.dragQAIdx and S.dragQAIdx ~= qi then
                local iMin = imgui.GetItemRectMin(); local iMax = imgui.GetItemRectMax()
                local mY   = imgui.GetMousePos().y
                if mY >= iMin.y and mY <= iMax.y then
                    S.dragQATarget = qi
                    local lY = mY < (iMin.y+iMax.y)/2 and iMin.y or iMax.y
                    bDl2:AddLine(imgui.ImVec2(iMin.x+4,lY), imgui.ImVec2(iMax.x-4,lY), ImVec4toU32(qaCol,0.8), 2)
                end
            end

            if imgui.IsItemHovered() then anim(lid2.."_h",1,0.15) else anim(lid2.."_h",0,0.08) end
            imgui.PopStyleVar(); imgui.PopStyleColor(4)

            -- ПКМ = удалить
            if imgui.IsItemHovered() and imgui.IsMouseClicked(1) then
                if QA.editingSlot == slot then
                    QA.editingSlot=nil; QA.editingBind=nil; QA.editingBindIdx=nil
                end
                table.remove(slots, qi); QA:save()
            end
        end

        -- Завершение drag-and-drop
        if S.dragQAIdx and not imgui.IsMouseDown(0) then
            if S.dragQATarget and S.dragQATarget ~= S.dragQAIdx then
                local moved = table.remove(slots, S.dragQAIdx)
                local ins   = S.dragQATarget
                if S.dragQAIdx < ins then ins = ins - 1 end
                table.insert(slots, math.max(1, math.min(ins, #slots+1)), moved)
                QA:save(); addNotification("Слот перемещён", C.NOTIFY_INFO)
            end
            S.dragQAIdx = nil; S.dragQATarget = nil
        end
    end

    imgui.EndChild()  -- qa_slots_scroll
    imgui.EndChild(); imgui.PopStyleVar(2); imgui.PopStyleColor()

    -- ===== ПРАВАЯ ПАНЕЛЬ =====================================================
    imgui.SameLine(0, 12)
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0,0,0,0))
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 0)
    setWindowPadding(S.contentPadding, S.contentPadding)
    imgui.BeginChild("##qa_right", imgui.ImVec2(editW, -1), false)

    local slot = QA.editingSlot

    -- ===== ПУСТОЕ СОСТОЯНИЕ (зеркало биндера) ================================
    if not slot then
        imgui.Spacing(); imgui.Spacing(); imgui.Spacing()
        local emptyDl  = imgui.GetWindowDrawList()
        local emptyPos = imgui.GetCursorScreenPos()
        local emptyW   = imgui.GetContentRegionAvail().x
        local cx = math.floor(emptyPos.x + emptyW / 2)
        local cy = math.floor(emptyPos.y + 80)
        local emptyPulse = (math.sin(os.clock()*1.8)+1)*0.5
        local outerR = 38 + emptyPulse * 4
        emptyDl:AddCircle(imgui.ImVec2(cx,cy), outerR,
            ImVec4toU32(imgui.ImVec4(qaCol.x,qaCol.y,qaCol.z, 0.06+emptyPulse*0.06)), 28, 1.5)
        drawGlow(emptyDl, cx, cy, 30+emptyPulse*5, qaCol, 0.06+emptyPulse*0.05)
        emptyDl:AddCircle(imgui.ImVec2(cx,cy), 34,
            ImVec4toU32(imgui.ImVec4(qaCol.x,qaCol.y,qaCol.z, 0.12+emptyPulse*0.06)), 24, 1.8)
        local crossLen = 16; local crossHalf = 1
        local crossAlpha = 0.35 + emptyPulse * 0.20
        local crossCol2 = ImVec4toU32(imgui.ImVec4(qaCol.x,qaCol.y,qaCol.z,crossAlpha))
        emptyDl:AddRectFilled(imgui.ImVec2(cx-crossLen,cy-crossHalf), imgui.ImVec2(cx+crossLen,cy+crossHalf), crossCol2, 0)
        emptyDl:AddRectFilled(imgui.ImVec2(cx-crossHalf,cy-crossLen), imgui.ImVec2(cx+crossHalf,cy-crossHalf), crossCol2, 0)
        emptyDl:AddRectFilled(imgui.ImVec2(cx-crossHalf,cy+crossHalf), imgui.ImVec2(cx+crossHalf,cy+crossLen), crossCol2, 0)
        imgui.Dummy(imgui.ImVec2(0,130))
        local ht = u8("Выберите слот для редактирования")
        local hs = imgui.CalcTextSize(ht)
        imgui.SetCursorPosX((emptyW-hs.x)/2)
        imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(ht); imgui.PopStyleColor()
        local ht2 = u8("или нажмите «+ Создать слот»")
        local hs2 = imgui.CalcTextSize(ht2)
        imgui.SetCursorPosX((emptyW-hs2.x)/2)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.5))
        imgui.Text(ht2); imgui.PopStyleColor()
        imgui.Spacing(); imgui.Spacing()
        local statsText = u8(safeFormat("Слотов: %d | Пешком: %d | Транспорт: %d",
            #QA.foot + #QA.vehicle, #QA.foot, #QA.vehicle))
        local statsSz = imgui.CalcTextSize(statsText)
        imgui.SetCursorPosX((emptyW-statsSz.x)/2)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.35))
        imgui.Text(statsText); imgui.PopStyleColor()
        imgui.EndChild(); imgui.PopStyleVar(); imgui.PopStyleColor()
        return
    end

    -- ===== РЕДАКТОР (зеркало биндера) ========================================

    -- Стили полей ввода (идентично биндеру)
    local inputBg = imgui.ImVec4(t.input.x+0.05, t.input.y+0.05, t.input.z+0.05, 0.95)
    imgui.PushStyleColor(imgui.Col.FrameBg, inputBg)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered,
        imgui.ImVec4(inputBg.x+0.04, inputBg.y+0.04, inputBg.z+0.04, 0.98))
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1)
    imgui.PushStyleColor(imgui.Col.Border,
        imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.18))

    -- Breadcrumb: Быстрые действия › Имя слота
    do
        local bcDl  = imgui.GetWindowDrawList()
        local bcSp  = imgui.GetCursorScreenPos()
        local bcW   = imgui.GetContentRegionAvail().x
        bcDl:AddRectFilled(imgui.ImVec2(bcSp.x-8,bcSp.y),
            imgui.ImVec2(bcSp.x+bcW+8,bcSp.y+22),
            ImVec4toU32(imgui.ImVec4(t.sidebar.x,t.sidebar.y,t.sidebar.z,0.6)), 0)
        local bc1   = u8(QA.editTab==0 and "Пешком" or "Транспорт")
        local bc1sz = imgui.CalcTextSize(bc1)
        bcDl:AddText(imgui.ImVec2(bcSp.x,bcSp.y+4), ImVec4toU32(t.text3,0.5), bc1)
        local bcSep   = u8(" › ")
        local bcSepsz = imgui.CalcTextSize(bcSep)
        bcDl:AddText(imgui.ImVec2(bcSp.x+bc1sz.x,bcSp.y+4), ImVec4toU32(t.text3,0.25), bcSep)
        local bcName  = (slot.label and slot.label ~= "") and slot.label or "Слот"
        bcDl:AddText(imgui.ImVec2(bcSp.x+bc1sz.x+bcSepsz.x,bcSp.y+4), ImVec4toU32(t.accent2,0.85), u8(bcName))
        imgui.Dummy(imgui.ImVec2(bcW,22)); imgui.Spacing()
    end

    -- Хедер-полоска (зеркало биндера)
    local hdrDl  = imgui.GetWindowDrawList()
    local hdrPos = imgui.GetCursorScreenPos()
    local hdrW   = imgui.GetContentRegionAvail().x
    hdrDl:AddRectFilled(imgui.ImVec2(hdrPos.x-8,hdrPos.y-4),
        imgui.ImVec2(hdrPos.x+hdrW+8,hdrPos.y+32),
        ImVec4toU32(imgui.ImVec4(t.card.x,t.card.y,t.card.z,0.3)), 10)

    -- Статус-переключатель (включён/выключен бинд)
    local bind = QA.editingBind
    if bind then
        -- Переключатель у бинда
        if not B._qaEnabledBuf then B._qaEnabledBuf = imgui.new.bool(true) end
        if not B._qaEditorLoaded then B._qaEnabledBuf[0] = bind.enabled ~= false end
        if toggleSwitch("Включён", B._qaEnabledBuf) then
            bind.enabled = B._qaEnabledBuf[0]; saveBinds()
        end
        imgui.SameLine(0,16)
        local qaSC = #(bind.steps or {})
        badge(qaSC.." шагов", qaSC > 0 and t.accent2 or t.text3)
        imgui.SameLine(0,8)
        badge(tostring(bind.uses or 0).." исп.", (bind.uses or 0) > 0 and t.green or t.text3)
        -- Хоткей chip
        if B.editKeyBuf[0] ~= 0 then
            imgui.SameLine(0,8)
            local hkDl = imgui.GetWindowDrawList(); local hkSp = imgui.GetCursorScreenPos()
            local hkW  = drawKeyChip(hkDl,0,0,B.editKeyBuf[0],B.editKeyModBuf[0],t,0)
            drawKeyChip(hkDl,hkSp.x,hkSp.y+1,B.editKeyBuf[0],B.editKeyModBuf[0],t,0.9)
            imgui.Dummy(imgui.ImVec2(hkW+4,16))
        end
        -- Cmd badge
        local qaCmdStr0 = ffi.string(B.editCmdBuf)
        if qaCmdStr0 ~= "" then
            imgui.SameLine(0,8)
            badge((qaCmdStr0:match("^/?(%S+)") or qaCmdStr0), t.accent)
        end
        -- Избранное
        imgui.SameLine(0,8)
        local favLabel = B.editFavoriteBuf[0] and "* Избр." or "  Избр."
        if btn(favLabel.."##qafav", 0, 22, B.editFavoriteBuf[0] and "accent" or "ghost") then
            B.editFavoriteBuf[0] = not B.editFavoriteBuf[0]
        end
    else
        -- Нет бинда — показываем только режим
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.AlignTextToFramePadding()
        imgui.Text(u8("Режим: "..(QA.editTab==0 and "Пешком" or "В транспорте")))
        imgui.PopStyleColor()
    end
    imgui.Spacing()

    -- СЕКЦИЯ: Слот
    secTitle("Слот")
    imgui.PushStyleColor(imgui.Col.Text, t.text2)
    imgui.AlignTextToFramePadding(); imgui.Text(u8("Название:"))
    imgui.PopStyleColor(); imgui.SameLine(0,8)
    local lblBuf = ffi.new("char[64]", u8(slot.label or ""))
    imgui.PushItemWidth(180)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(12,8))
    if imgui.InputTextWithHint("##qalabel", u8("Название слота"), lblBuf, 64) then
        slot.label = u8:decode(ffi.string(lblBuf)); QA:save()
    end
    imgui.PopStyleVar(2); imgui.PopItemWidth()
    imgui.SameLine(0,24)
    imgui.PushStyleColor(imgui.Col.Text, t.text2)
    imgui.AlignTextToFramePadding(); imgui.Text(u8("Клавиша:"))
    imgui.PopStyleColor(); imgui.SameLine(0,8)
    if btn(" "..getKeyName(slot.key or 0, slot.keyMod or 0).." ##qaslotkey", 0, 0, "outline") then
        S.tempKey=slot.key or 0; S.tempMod=slot.keyMod or 0
        S.waitingForKey=true; S.keyBindContext="qa_slot"; S.keyBindPopupActive=true; QA._editSlot=slot
    end
    if (slot.key or 0) ~= 0 then
        imgui.SameLine(0,4)
        if btn("x##qaslotkeyrst", 24, 0, "danger") then slot.key=0; slot.keyMod=0; QA:save() end
    end

    -- СЕКЦИЯ: Цвет маркера (компактно в той же строке что у биндера — категория)
    imgui.SameLine(0,20)
    imgui.PushStyleColor(imgui.Col.Text, t.text3)
    imgui.AlignTextToFramePadding(); imgui.Text(u8("Маркер:"))
    imgui.PopStyleColor(); imgui.SameLine(0,8)
    local swColors = {{1,.82,.20},{.20,.90,.50},{.22,.52,1},{1,.30,.38},{.72,.52,1},{.13,.83,.78}}
    local curC2    = QA.editTab==0 and QA.footCol or QA.vehCol
    local swDl     = imgui.GetWindowDrawList()
    for si2, s in ipairs(swColors) do
        local sp2  = imgui.GetCursorScreenPos()
        local isA  = math.abs(curC2[1]-s[1])<0.06 and math.abs(curC2[2]-s[2])<0.06
        swDl:AddCircleFilled(imgui.ImVec2(sp2.x+7,sp2.y+7), 7, ImVec4toU32(imgui.ImVec4(s[1],s[2],s[3],1)), 20)
        if isA then
            swDl:AddCircle(imgui.ImVec2(sp2.x+7,sp2.y+7), 9, ImVec4toU32(imgui.ImVec4(1,1,1,.85)), 20, 1.6)
        end
        imgui.InvisibleButton("##sw"..si2, imgui.ImVec2(16,16))
        if imgui.IsItemClicked() then
            if QA.editTab==0 then QA.footCol={s[1],s[2],s[3],1}
            else QA.vehCol={s[1],s[2],s[3],1} end; QA:save()
        end
        imgui.SameLine(0,2)
    end

    thinSep()

    -- СЕКЦИЯ: Бинд
    secTitle("Бинд")

    if not bind then
        -- Создать или выбрать
        if btn("+ Создать новый бинд для этого слота##qanew", 0, 34, "accent") then
            local nb2 = { id=generateId(), name=slot.label or "QA бинд", cmd="", steps={},
                delay=settings.defaultDelay, key=0, key_mod=0, cooldown=0,
                enabled=true, favorite=false, category=0, uses=0, created=os.time(), desc="" }
            table.insert(binds, nb2); slot.bindId=nb2.id
            QA.editingBind=nb2; QA.editingBindIdx=#binds
            saveBinds(); QA:save(); B._qaEditorLoaded=false
        end
        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8("или выбери из существующих:"))
        imgui.PopStyleColor(); imgui.Spacing()
        local pickH = math.min(#binds*28+8, imgui.GetContentRegionAvail().y-20)
        if #binds > 0 then
            imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(t.card.x,t.card.y,t.card.z,0.4))
            imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 10)
            imgui.BeginChild("##qapicklist", imgui.ImVec2(-1, math.max(pickH,40)), true)
            for bi2, b2 in ipairs(binds) do
                local bn2 = (b2.name ~= "" and b2.name or "Без имени")
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0,0,0,0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(qaCol.x,qaCol.y,qaCol.z,0.12))
                imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 6)
                if imgui.Button(u8("  "..bn2.."##qapick"..b2.id), imgui.ImVec2(-1,26)) then
                    slot.bindId=b2.id; QA.editingBind=b2; QA.editingBindIdx=bi2
                    QA:save(); B._qaEditorLoaded=false
                end
                imgui.PopStyleVar(); imgui.PopStyleColor(2)
            end
            imgui.EndChild(); imgui.PopStyleVar(); imgui.PopStyleColor()
        else
            imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.Text(u8("Биндов ещё нет")); imgui.PopStyleColor()
        end

    else
        -- ===================================================================
        -- РЕДАКТОР БИНДА (зеркало основного биндера)
        -- ===================================================================
        if not B._qaEditorLoaded then
            B._qaEditorLoaded=true; S._stepsFieldActive=false
            if not B._qaEnabledBuf then B._qaEnabledBuf = imgui.new.bool(true) end
            B._qaEnabledBuf[0]  = bind.enabled ~= false
            ffi.copy(B.editNameBuf,  u8(bind.name or ""))
            ffi.copy(B.editCmdBuf,   (bind.cmd and bind.cmd ~= "") and ("/"..bind.cmd) or "")
            ffi.copy(B.editStepsBuf, u8(joinSteps(bind.steps or {})))
            ffi.copy(B.editDescBuf,  u8(bind.desc or ""))
            B.editDelayBuf[0]    = bind.delay    or settings.defaultDelay
            B.editKeyBuf[0]      = bind.key      or 0
            B.editKeyModBuf[0]   = bind.key_mod  or 0
            B.editCooldownBuf[0] = bind.cooldown or 0
            B.editFavoriteBuf[0] = bind.favorite or false
            B.editCategoryBuf[0] = bind.category or 0
        end

        -- Основное: название
        secTitle("Основное")
        imgui.PushItemWidth(-1)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
        imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(14,10))
        imgui.InputTextWithHint("##qaeName", u8("Название бинда"), B.editNameBuf, 256)
        imgui.PopStyleVar(2); imgui.PopItemWidth()

        -- Параметры: категория + задержка
        secTitle("Параметры")
        imgui.PushStyleColor(imgui.Col.Text, t.text2)
        imgui.AlignTextToFramePadding(); imgui.Text(u8("Категория:"))
        imgui.PopStyleColor(); imgui.SameLine(0,8)
        imgui.PushItemWidth(160)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
        imgui.Combo("##qaeCat", B.editCategoryBuf, U.bindCatNamesPtr, 4)
        imgui.PopStyleVar(); imgui.PopItemWidth()
        imgui.SameLine(0,24)
        imgui.PushStyleColor(imgui.Col.Text, t.text2)
        imgui.AlignTextToFramePadding(); imgui.Text(u8("Задержка:"))
        imgui.PopStyleColor(); imgui.SameLine(0,8)
        imgui.PushItemWidth(140)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
        imgui.InputInt("##qaeDel", B.editDelayBuf, 100, 500)
        imgui.PopStyleVar(); imgui.PopItemWidth()
        B.editDelayBuf[0] = clamp(B.editDelayBuf[0], C.MIN_DELAY, C.MAX_DELAY)
        imgui.SameLine(0,4)
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.AlignTextToFramePadding(); imgui.Text(u8("мс"))
        imgui.PopStyleColor()
        local qaeStepCount = #splitSteps(u8:decode(ffi.string(B.editStepsBuf)))
        if qaeStepCount > 0 then
            imgui.SameLine(0,16)
            imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.AlignTextToFramePadding()
            imgui.Text(u8(safeFormat("(~%.1fс)", qaeStepCount*B.editDelayBuf[0]/1000)))
            imgui.PopStyleColor()
        end

        -- Активация: команда + клавиша
        secTitle("Активация")
        imgui.PushStyleColor(imgui.Col.Text, t.text2)
        imgui.AlignTextToFramePadding(); imgui.Text(u8("Команда:"))
        imgui.PopStyleColor(); imgui.SameLine(0,8)
        imgui.PushItemWidth(imgui.GetContentRegionAvail().x - 180)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
        imgui.InputTextWithHint("##qaeCmd", u8("/команда {арг1} {арг2}"), B.editCmdBuf, 64)
        imgui.PopStyleVar(); imgui.PopItemWidth()
        imgui.SameLine(0,12)
        imgui.PushStyleColor(imgui.Col.Text, t.text2)
        imgui.AlignTextToFramePadding(); imgui.Text(u8("Клавиша:"))
        imgui.PopStyleColor(); imgui.SameLine(0,8)
        if btn(" "..getKeyName(B.editKeyBuf[0],B.editKeyModBuf[0]).." ##qaeKey", 0, 0, "outline") then
            S.tempKey=B.editKeyBuf[0]; S.tempMod=B.editKeyModBuf[0]
            S.waitingForKey=true; S.keyBindContext="bind"; S.keyBindPopupActive=true
        end
        if B.editKeyBuf[0] ~= 0 then
            imgui.SameLine(0,4)
            if btn("x##qaeResetKey", 24, 0, "danger") then B.editKeyBuf[0]=0; B.editKeyModBuf[0]=0 end
        end
        local qaeCmdStr = ffi.string(B.editCmdBuf); local qaeCmdArgs = {}
        for argName in qaeCmdStr:gmatch("{([^}]+)}") do table.insert(qaeCmdArgs, argName) end
        if #qaeCmdArgs > 0 then
            imgui.Spacing()
            imgui.PushStyleColor(imgui.Col.Text, t.accent2)
            imgui.Text(u8("Аргументы: "..table.concat(qaeCmdArgs,", ")))
            imgui.PopStyleColor()
            imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.Text(u8("Игрок указывает их после команды"))
            imgui.PopStyleColor()
        end

        -- Шаги
        secTitle("Шаги")
        if btn("Переменные {x}##qaevref", 0, 24, "outline") then
            U.showVarRef[0] = not U.showVarRef[0]
        end
        imgui.SameLine(0,12)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.5))
        imgui.Text(u8("{target_id} {target_nick} | [1500] | [repeat:3] | [if:hp>50]"))
        imgui.PopStyleColor(); imgui.Spacing()

        -- Анализ длин строк
        local qaeStepsRaw   = ffi.string(B.editStepsBuf)
        local qaeLineAnal   = analyzeStepLines(qaeStepsRaw)
        local qaeLong,qaeWarn = 0,0
        for _, la in ipairs(qaeLineAnal) do
            if la.isLong    then qaeLong = qaeLong+1 end
            if la.isWarning then qaeWarn = qaeWarn+1 end
        end
        if #splitSteps(u8:decode(qaeStepsRaw)) > 0 then
            imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.Text(u8(safeFormat("Шагов: %d", #splitSteps(u8:decode(qaeStepsRaw)))))
            imgui.PopStyleColor()
            if qaeWarn > 0 then
                imgui.SameLine(0,12)
                imgui.PushStyleColor(imgui.Col.Text, t.yellow)
                imgui.Text(u8(safeFormat("? %d строк 120-144", qaeWarn))); imgui.PopStyleColor()
            end
            if qaeLong > 0 then
                imgui.SameLine(0,12)
                imgui.PushStyleColor(imgui.Col.Text, t.red)
                imgui.Text(u8(safeFormat("? %d строк >144", qaeLong))); imgui.PopStyleColor()
            end
        end

        -- Поле шагов (зеркало биндера — пассивный/активный режим)
        local qaeStH = math.max(imgui.GetContentRegionAvail().y - 52, 80)
        if U.fontMono then imgui.PushFont(U.fontMono) end
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
        imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(12,8))
        if S._stepsFieldActive then
            imgui.InputTextMultiline("##qaeSteps", B.editStepsBuf, 32768,
                imgui.ImVec2(-1, qaeStH), imgui.InputTextFlags.None)
            if wasKeyPressed(C.KEY_ESC) then S._stepsFieldActive=false
            elseif imgui.IsMouseClicked(0) and not imgui.IsItemHovered() then S._stepsFieldActive=false end
        else
            drawStepsPassiveViewer(qaeStH)
        end
        imgui.PopStyleVar(2)
        if U.fontMono then imgui.PopFont() end

        -- Закрываем стили полей
        imgui.PopStyleColor(3); imgui.PopStyleVar()

        -- Панель кнопок (зеркало биндера)
        imgui.Spacing()
        local qaeBarDl  = imgui.GetWindowDrawList(); local qaeBarPos = imgui.GetCursorScreenPos()
        local qaeBarW   = imgui.GetContentRegionAvail().x
        qaeBarDl:AddLine(imgui.ImVec2(qaeBarPos.x,qaeBarPos.y),
            imgui.ImVec2(qaeBarPos.x+qaeBarW,qaeBarPos.y),
            ImVec4toU32(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.08)), 1)
        imgui.Dummy(imgui.ImVec2(0,6))

        -- Левая группа: Сохранить + Тест
        if btn(" Сохранить ##qaeSave", 0, 34, "accent") then
            local qaName = u8:decode(trim(ffi.string(B.editNameBuf)))
            local qaCmdR = trim(ffi.string(B.editCmdBuf))
            local qaCmd  = trim(qaCmdR:match("^/?(.+)") or "")
            local qaStR  = u8:decode(ffi.string(B.editStepsBuf))
            if qaName ~= "" and qaStR ~= "" then
                bind.name     = qaName; bind.cmd      = qaCmd
                bind.steps    = splitSteps(qaStR); bind.delay  = B.editDelayBuf[0]
                bind.key      = B.editKeyBuf[0];   bind.key_mod = B.editKeyModBuf[0]
                bind.cooldown = B.editCooldownBuf[0]; bind.enabled = B.editEnabledBuf[0]
                bind.favorite = B.editFavoriteBuf[0]; bind.category = B.editCategoryBuf[0]
                if slot.label == "" or slot.label == "Действие" then slot.label = bind.name end
                saveBinds(); QA:save(); addNotification("QA бинд сохранён!", C.NOTIFY_SUCCESS)
            else addNotification("Заполните название и шаги!", C.NOTIFY_ERROR) end
        end
        imgui.SameLine(0,8)
        if btn(" Тест ##qaeTest", 0, 34, "outline") then
            local stR = u8:decode(ffi.string(B.editStepsBuf))
            if stR ~= "" then
                lua_thread.create(function()
                    performBind({ name=u8:decode(ffi.string(B.editNameBuf)),
                        steps=splitSteps(stR), delay=B.editDelayBuf[0],
                        enabled=true, uses=0 }, {})
                end)
            end
        end

        -- Правая группа: Открыть в биндере + Отвязать
        imgui.SameLine(qaeBarW - 230)
        if btn(" Открыть в биндере ##qaeOpen", 0, 34, "ghost") then
            currentNav[0]=C.NAV_BINDER; QA.subTab=0
            if QA.editingBindIdx then discardAndSelect(QA.editingBindIdx) end
        end
        imgui.SameLine(0,8)
        if btn(" Другой бинд ##qaeDetach", 0, 34, "danger") then
            QA.editingBind=nil; QA.editingBindIdx=nil; slot.bindId=""; QA:save()
            B._qaEditorLoaded=false; S._stepsFieldActive=false
            imgui.EndChild(); imgui.PopStyleVar(); imgui.PopStyleColor()
            return
        end

        return  -- выходим без повторного PopStyleColor (уже вызван выше)
    end

    -- Закрываем стили (если нет бинда — closedestyle здесь)
    imgui.PopStyleColor(3); imgui.PopStyleVar()

    imgui.EndChild()
    imgui.PopStyleVar()
    imgui.PopStyleColor()
end


-- =========================================================================
-- БИНДЕР (с улучшениями 1,2,4,5,6,7,8 + убрано описание)
-- =========================================================================
local function drawBinder()
    local t = T()
    -- Подвкладки: Биндер | Быстрые действия
    local stW = math.floor((imgui.GetContentRegionAvail().x-8)/2)
    setWindowPadding(S.contentPadding,12)
    imgui.BeginChild("##bst_hdr",imgui.ImVec2(0,46),false)
    if btn("  Биндер  ##bst0",stW,34,QA.subTab==0 and "accent" or "ghost") then QA.subTab=0 end
    imgui.SameLine(0,8)
    if btn("  Быстрые действия  ##bst1",stW,34,QA.subTab==1 and "accent" or "ghost") then QA.subTab=1 end
    imgui.EndChild()
    if QA.subTab==1 then drawQuickActionsTab(); return end
    setWindowPadding(0,0)
    local av = imgui.GetContentRegionAvail()
    local listW = math.max(av.x * 0.25, 240)
    local editW = av.x - listW - 12

    -- ===== ЛЕВАЯ ПАНЕЛЬ =====
    imgui.PushStyleColor(imgui.Col.ChildBg, t.sidebar)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 18)
    pushWindowPadding(16, 14)
    imgui.BeginChild("##blist", imgui.ImVec2(listW, -1), true)

    -- Поиск
    imgui.PushItemWidth(-1)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 22)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(14, 9))
    imgui.InputTextWithHint("##bsearch", u8(" Поиск..."), U.searchBuf, ffi.sizeof(U.searchBuf))
    imgui.PopStyleVar(2); imgui.PopItemWidth()
    imgui.Spacing()

    -- Категории
do
    local cs = {"Все", "Свои бинды", "Системные", "ФБР", "Экспертизы"}
    local catColors = {t.accent, t.green, t.blue, t.red, t.yellow}
    local totalW = imgui.GetContentRegionAvail().x
    local tabH = 26
    local tabGap = 4

    local function drawCatTab(ci, tabW)
        local isActive = U.filterCategory[0] == ci
        local catCol = catColors[ci + 1]
        local tabId = "catr_" .. ci
        local hov = anim(tabId .. "_h", 0, 0.15)
        local bgAlpha = isActive and 0.65 or (hov * 0.12)
        local bgColor = isActive
            and imgui.ImVec4(catCol.x, catCol.y, catCol.z, bgAlpha)
            or imgui.ImVec4(t.card.x, t.card.y, t.card.z, 0.3 + hov * 0.15)
        imgui.PushStyleColor(imgui.Col.Button, bgColor)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(catCol.x, catCol.y, catCol.z, 0.25))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(catCol.x, catCol.y, catCol.z, 0.4))
        imgui.PushStyleColor(imgui.Col.Text, isActive and imgui.ImVec4(1,1,1,1) or lerpColor(t.text3, t.text2, hov))
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8)
        imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(0, 4))
        if imgui.Button(u8(cs[ci + 1]) .. "##catr" .. ci, imgui.ImVec2(tabW, tabH)) then
            U.filterCategory[0] = ci
        end
        if isActive then
            local mi2 = imgui.GetItemRectMin(); local ma2 = imgui.GetItemRectMax()
            local dl2 = imgui.GetWindowDrawList()
            dl2:AddRectFilled(imgui.ImVec2(mi2.x + 8, ma2.y - 3),
                imgui.ImVec2(ma2.x - 8, ma2.y), ImVec4toU32(catCol, 0.8), 2)
        end
        if imgui.IsItemHovered() then anim(tabId.."_h", 1, 0.15) else anim(tabId.."_h", 0, 0.08) end
        imgui.PopStyleVar(2); imgui.PopStyleColor(4)
    end

    -- Первый ряд: Все, Свои бинды, Системные
    local row1 = {0, 1, 2}
    local row1W = math.floor((totalW - tabGap * (#row1 - 1)) / #row1)
    for i, ci in ipairs(row1) do
        drawCatTab(ci, row1W)
        if i < #row1 then imgui.SameLine(0, tabGap) end
    end
    imgui.Dummy(imgui.ImVec2(0, 2))
    -- Второй ряд: ФБР, Экспертизы
    local row2 = {3, 4}
    local row2W = math.floor((totalW - tabGap * (#row2 - 1)) / #row2)
    for i, ci in ipairs(row2) do
        drawCatTab(ci, row2W)
        if i < #row2 then imgui.SameLine(0, tabGap) end
    end
end
    imgui.Spacing()

    -- Кнопка создания
    if btn("+ Создать", -1, 36, "accent") then
        if requestBindAction("create", nil) then
            S.isCreatingNew = true
            discardAndSelect(nil)
        end
    end
    imgui.Spacing()

    -- Фильтрация
    local st = ffi.string(U.searchBuf):lower()
    local filt = {}
    for i, b in ipairs(binds) do
        local matchSearch = (st == "" or (b.name and b.name:lower():find(st, 1, true))
            or (b.cmd and b.cmd:lower():find(st, 1, true)))
        local matchCat = (U.filterCategory[0] == 0) or (b.category == (U.filterCategory[0] - 1))
        if matchSearch and matchCat then table.insert(filt, i) end
    end

    -- Счётчик
    local filterActive = U.filterCategory[0] ~= 0 or st ~= ""
    if filterActive then
        imgui.PushStyleColor(imgui.Col.Text, t.accent2)
        imgui.Text(u8(safeFormat("Найдено: %d из %d", #filt, #binds)))
        imgui.PopStyleColor()
    else
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8(safeFormat("Биндов: %d", #binds)))
        imgui.PopStyleColor()
    end
    imgui.Spacing()

    -- Список биндов
    imgui.BeginChild("##bscroll", imgui.ImVec2(0, 0), false)

    if #filt == 0 then
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8(#binds == 0 and "Нет биндов" or "Нет совпадений"))
        imgui.PopStyleColor()
    else
        for fi, idx in ipairs(filt) do
            local b = binds[idx]
            local sel = (S.selectedBindIndex == idx)
            local nm = (b.name and b.name ~= "") and b.name or "Без имени"
            local en = b.enabled ~= false
            local lid = "bl_" .. idx
            local hov = anim(lid .. "_h", 0, 0.15)
            local bgCol

            if sel then
                bgCol = imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.16 + hov * 0.08)
            else
                bgCol = imgui.ImVec4(t.card.x, t.card.y, t.card.z, hov * 0.45)
            end

            -- Подсветка при drag-and-drop
            if S.dragBindIdx and S.dragTargetIdx == idx then
                bgCol = imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.25)
            end

            imgui.PushStyleColor(imgui.Col.Button, bgCol)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.12))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.22))
            imgui.PushStyleColor(imgui.Col.Text, en and t.text or t.text3)
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)

            -- УЛУЧШЕНИЕ #8: двухстрочные элементы
            local buttonH = 46
            local catTag = ({"", "[С]", "[Ф]", "[Э]"})[(b.category or 0) + 1] or ""
            local displayName = (en and "" or "~ ") .. nm .. (catTag ~= "" and (" " .. catTag) or "")

            if imgui.Button("##b" .. idx, imgui.ImVec2(-1, buttonH)) then
                if idx ~= S.selectedBindIndex then
                    if requestBindAction("select", idx) then
                        S.isCreatingNew = false
                        discardAndSelect(idx)
                    end
                end
            end

            -- Рисуем содержимое поверх кнопки
            local btnMin = imgui.GetItemRectMin()
            local btnMax = imgui.GetItemRectMax()
            local btnDl = imgui.GetWindowDrawList()

            -- Цвет категории (используется для hover-превью)
            local stripeCol = getBindCatColor(b.category)

            -- Первая строка: название
            local nameColor = en and t.text or t.text3
            btnDl:AddText(imgui.ImVec2(btnMin.x + 10, btnMin.y + 6),
                ImVec4toU32(nameColor), u8(displayName))

            -- Вторая строка: мета-информация (cmd, шаги, использования)
            local metaParts2 = {}
            if b.cmd and b.cmd ~= "" then
                table.insert(metaParts2, "/" .. (b.cmd:match("^(%S+)") or b.cmd))
            end
            table.insert(metaParts2, #(b.steps or {}) .. " шагов")
            if (b.uses or 0) > 0 then
                table.insert(metaParts2, b.uses .. " исп.")
            end
            local metaText = u8(table.concat(metaParts2, " · "))
            btnDl:AddText(imgui.ImVec2(btnMin.x + 12, btnMin.y + 24),
                ImVec4toU32(imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.6)), metaText)
            -- Хоткей как chip справа
            if b.key and b.key ~= 0 then
                local chipW = drawKeyChip(btnDl, 0, 0, b.key, b.key_mod or 0, t, 0)
                local chipX = btnMax.x - chipW - (b.favorite and 26 or 6)
                drawKeyChip(btnDl, chipX, btnMin.y + (buttonH - 18)/2, b.key, b.key_mod or 0, t, en and 0.85 or 0.35)
            end

            -- Индикатор избранного
            if b.favorite then
                btnDl:AddText(imgui.ImVec2(btnMax.x - 20, btnMin.y + 6),
                    ImVec4toU32(t.yellow, 0.7), u8("*"))
            end
            -- Цветная точка категории
            local catDotCol = getBindCatColor(b.category)
            local dotOffX = b.favorite and 38 or 18
            btnDl:AddCircleFilled(
                imgui.ImVec2(btnMax.x - dotOffX, btnMin.y + buttonH/2),
                3.5, ImVec4toU32(catDotCol, en and 0.65 or 0.22), 10)

            -- Hover-превью шагов бинда
            drawBindHoverPreview(b, btnMin, btnMax, stripeCol)

            -- Drag and Drop
            if imgui.IsItemActive() and imgui.IsMouseDragging(0, 3.0) then
                S.dragBindIdx = idx
            end
            if S.dragBindIdx and S.dragBindIdx ~= idx then
                local itemMin = imgui.GetItemRectMin()
                local itemMax = imgui.GetItemRectMax()
                local mouseY = imgui.GetMousePos().y
                local midY = (itemMin.y + itemMax.y) / 2
                if mouseY >= itemMin.y and mouseY <= itemMax.y then
                    S.dragTargetIdx = idx
                    local dl2 = imgui.GetWindowDrawList()
                    local lineY = mouseY < midY and itemMin.y or itemMax.y
                    dl2:AddLine(imgui.ImVec2(itemMin.x + 4, lineY),
                        imgui.ImVec2(itemMax.x - 4, lineY),
                        ImVec4toU32(t.accent, 0.8), 2)
                end
            end

            if imgui.IsItemHovered() then anim(lid .. "_h", 1, 0.15) else anim(lid .. "_h", 0, 0.08) end
            imgui.PopStyleVar(); imgui.PopStyleColor(4)

            -- Полоска выделения
            if sel then
                local dl2 = imgui.GetWindowDrawList()
                local mi, ma = imgui.GetItemRectMin(), imgui.GetItemRectMax()
                dl2:AddRectFilled(imgui.ImVec2(mi.x, mi.y + 3),
                    imgui.ImVec2(mi.x + 3, ma.y - 3), ImVec4toU32(t.accent), 2)
            end
        end

        -- Завершение drag-and-drop
        if S.dragBindIdx and not imgui.IsMouseDown(0) then
            if S.dragTargetIdx and S.dragTargetIdx ~= S.dragBindIdx then
                local movedBind = table.remove(binds, S.dragBindIdx)
                local insertAt = S.dragTargetIdx
                if S.dragBindIdx < S.dragTargetIdx then insertAt = insertAt - 1 end
                table.insert(binds, math.max(1, math.min(insertAt, #binds + 1)), movedBind)
                if S.selectedBindIndex == S.dragBindIdx then S.selectedBindIndex = insertAt end
                saveBinds(); addNotification("Бинд перемещён", C.NOTIFY_INFO)
            end
            S.dragBindIdx = nil; S.dragTargetIdx = nil
        end
    end

    imgui.EndChild()
    imgui.EndChild(); imgui.PopStyleVar(2); imgui.PopStyleColor()

    -- ===== ПРАВАЯ ПАНЕЛЬ =====
    imgui.SameLine(0, 12)
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 0)
    setWindowPadding(S.contentPadding, S.contentPadding)
    imgui.BeginChild("##bedit", imgui.ImVec2(editW, -1), false)
        -- 6.5/6.6: Проверка несохранённых изменений (не чаще 4 раз/сек)
    local now_check = os.clock()
    if now_check - S.lastChangeCheck > 0.25 then
        S.lastChangeCheck = now_check
        checkUnsavedChanges()
    end
    -- Стили полей ввода
    local inputBg = imgui.ImVec4(t.input.x + 0.05, t.input.y + 0.05, t.input.z + 0.05, 0.95)
    imgui.PushStyleColor(imgui.Col.FrameBg, inputBg)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered,
        imgui.ImVec4(inputBg.x + 0.04, inputBg.y + 0.04, inputBg.z + 0.04, 0.98))
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1)
    imgui.PushStyleColor(imgui.Col.Border,
        imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.18))

    -- УЛУЧШЕНИЕ #1: пустое состояние
    if not S.selectedBindIndex and not S.isCreatingNew then
        imgui.Spacing(); imgui.Spacing(); imgui.Spacing()
        local emptyDl = imgui.GetWindowDrawList()
        local emptyPos = imgui.GetCursorScreenPos()
        local emptyW = imgui.GetContentRegionAvail().x

        -- Большая иконка (анимированная)
        local cx = math.floor(emptyPos.x + emptyW / 2)
        local cy = math.floor(emptyPos.y + 80)
        local emptyPulse = (math.sin(os.clock() * 1.8) + 1) * 0.5
        -- Внешний пульсирующий круг
        local outerR = 38 + emptyPulse * 4
        emptyDl:AddCircle(imgui.ImVec2(cx, cy), outerR,
            ImVec4toU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z,
                0.06 + emptyPulse * 0.06)), 28, 1.5)
        -- Внутреннее свечение
        drawGlow(emptyDl, cx, cy, 30 + emptyPulse * 5, t.accent, 0.06 + emptyPulse * 0.05)
        -- Основной круг
        emptyDl:AddCircle(imgui.ImVec2(cx, cy), 34,
            ImVec4toU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z,
                0.12 + emptyPulse * 0.06)), 24, 1.8)
        -- Крест "+" — 3 непересекающихся прямоугольника
        local crossLen = 16
        local crossHalf = 1
        local crossAlpha = 0.35 + emptyPulse * 0.20
        local crossCol = ImVec4toU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, crossAlpha))
        emptyDl:AddRectFilled(
            imgui.ImVec2(cx - crossLen, cy - crossHalf),
            imgui.ImVec2(cx + crossLen, cy + crossHalf),
            crossCol, 0)
        emptyDl:AddRectFilled(
            imgui.ImVec2(cx - crossHalf, cy - crossLen),
            imgui.ImVec2(cx + crossHalf, cy - crossHalf),
            crossCol, 0)
        emptyDl:AddRectFilled(
            imgui.ImVec2(cx - crossHalf, cy + crossHalf),
            imgui.ImVec2(cx + crossHalf, cy + crossLen),
            crossCol, 0)

        imgui.Dummy(imgui.ImVec2(0, 130))

        -- Подсказки
        local hintText = u8("Выберите бинд из списка")
        local hintSize = imgui.CalcTextSize(hintText)
        imgui.SetCursorPosX((emptyW - hintSize.x) / 2)
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(hintText)
        imgui.PopStyleColor()

        local hintText2 = u8("или нажмите «+ Создать»")
        local hintSize2 = imgui.CalcTextSize(hintText2)
        imgui.SetCursorPosX((emptyW - hintSize2.x) / 2)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.5))
        imgui.Text(hintText2)
        imgui.PopStyleColor()

        imgui.Spacing(); imgui.Spacing()

        -- Мини-статистика
        local totalB = #binds; local enabledB = 0; local withKey = 0; local withCmd = 0
        for _, b in ipairs(binds) do
            if b.enabled ~= false then enabledB = enabledB + 1 end
            if b.key and b.key ~= 0 then withKey = withKey + 1 end
            if b.cmd and b.cmd ~= "" then withCmd = withCmd + 1 end
        end
        local statsText = u8(safeFormat("Всего: %d | Активных: %d | Хоткеев: %d | Команд: %d",
            totalB, enabledB, withKey, withCmd))
        local statsSize = imgui.CalcTextSize(statsText)
        imgui.SetCursorPosX((emptyW - statsSize.x) / 2)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.35))
        imgui.Text(statsText)
        imgui.PopStyleColor()

        -- Закрываем стили и выходим
        imgui.PopStyleColor(3); imgui.PopStyleVar()
        imgui.EndChild(); imgui.PopStyleVar(); imgui.PopStyleColor()
        return
    end

    -- ===== РЕДАКТОР (когда бинд выбран) =====

    -- Breadcrumb: Биндер › Имя бинда [Категория]
    do
        local bcDl = imgui.GetWindowDrawList()
        local bcSp = imgui.GetCursorScreenPos()
        local bcW  = imgui.GetContentRegionAvail().x
        -- Фон breadcrumb
        bcDl:AddRectFilled(imgui.ImVec2(bcSp.x - 8, bcSp.y),
            imgui.ImVec2(bcSp.x + bcW + 8, bcSp.y + 22),
            ImVec4toU32(imgui.ImVec4(t.sidebar.x, t.sidebar.y, t.sidebar.z, 0.6)), 0)
        -- "Биндер"
        local bc1 = u8("Биндер")
        local bc1sz = imgui.CalcTextSize(bc1)
        bcDl:AddText(imgui.ImVec2(bcSp.x, bcSp.y + 4), ImVec4toU32(t.text3, 0.5), bc1)
        -- "›"
        local bcSep = u8(" › ")
        local bcSepsz = imgui.CalcTextSize(bcSep)
        bcDl:AddText(imgui.ImVec2(bcSp.x + bc1sz.x, bcSp.y + 4),
            ImVec4toU32(t.text3, 0.25), bcSep)
        -- Имя бинда
        local selB = binds[S.selectedBindIndex]
        local bcName = selB and selB.name ~= "" and selB.name or (S.isCreatingNew and "Новый бинд" or "Бинд")
        local bcNameTxt = u8(bcName)
        local bcNameX = bcSp.x + bc1sz.x + bcSepsz.x
        bcDl:AddText(imgui.ImVec2(bcNameX, bcSp.y + 4), ImVec4toU32(t.accent2, 0.85), bcNameTxt)
        -- Категория tag
        if selB and selB.category and selB.category > 0 then
            local catNames2 = {"", "Системные", "ФБР", "Экспертизы"}
            local catN = catNames2[selB.category + 1] or ""
            if catN ~= "" then
                local bcNameSz = imgui.CalcTextSize(bcNameTxt)
                local tagX = bcNameX + bcNameSz.x + 6
                local tagTxt = u8(catN)
                local tagSz = imgui.CalcTextSize(tagTxt)
                bcDl:AddRectFilled(imgui.ImVec2(tagX - 1, bcSp.y + 3),
                    imgui.ImVec2(tagX + tagSz.x + 8, bcSp.y + 19),
                    ImVec4toU32(imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z, 0.12)), 5)
                bcDl:AddText(imgui.ImVec2(tagX + 3, bcSp.y + 5),
                    ImVec4toU32(t.accent, 0.75), tagTxt)
            end
        end
        imgui.Dummy(imgui.ImVec2(bcW, 22))
        imgui.Spacing()
    end

    -- УЛУЧШЕНИЕ #7: хедер с переключателем и бейджами
    local headerDl = imgui.GetWindowDrawList()
    local headerPos = imgui.GetCursorScreenPos()
    local headerW = imgui.GetContentRegionAvail().x

    -- Фоновая полоска
    headerDl:AddRectFilled(
        imgui.ImVec2(headerPos.x - 8, headerPos.y - 4),
        imgui.ImVec2(headerPos.x + headerW + 8, headerPos.y + 32),
        ImVec4toU32(imgui.ImVec4(t.card.x, t.card.y, t.card.z, 0.3)), 10)

    -- Переключатель
    toggleSwitch("Включён", B.editEnabledBuf)
        -- Индикатор автосохранения
    if S.hasUnsavedChanges then
        imgui.SameLine(0, 16)
        local savePulse = (math.sin(os.clock() * 6) + 1) * 0.5
        local saveDl = imgui.GetWindowDrawList()
        local dotSp = imgui.GetCursorScreenPos()
        local dotCy = dotSp.y + imgui.GetTextLineHeight() / 2 + 3
        saveDl:AddCircleFilled(
            imgui.ImVec2(dotSp.x, dotCy), 4,
            ImVec4toU32(imgui.ImVec4(t.green.x, t.green.y, t.green.z, 0.5 + savePulse * 0.5)), 12)
        drawGlow(saveDl, dotSp.x, dotCy, 4, t.green, 0.1 + savePulse * 0.15)
        imgui.Dummy(imgui.ImVec2(12, 0))
        imgui.SameLine(0, 4)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.green.x, t.green.y, t.green.z, 0.55 + savePulse * 0.3))
        imgui.SetCursorPosY(imgui.GetCursorPosY() + 3)
        imgui.Text(u8("Сохранение..."))
        imgui.PopStyleColor()
    end
    -- Бейджи
    imgui.SameLine(0, 16)
    local stepCount = #splitSteps(ffi.string(B.editStepsBuf))
    badge(stepCount .. " шагов", stepCount > 0 and t.accent2 or t.text3)

    -- Статистика выбранного бинда
    if S.selectedBindIndex and binds[S.selectedBindIndex] then
        local selBind = binds[S.selectedBindIndex]
        imgui.SameLine(0, 8)
        badge(tostring(selBind.uses or 0) .. " исп.", (selBind.uses or 0) > 0 and t.green or t.text3)

        if selBind.key and selBind.key ~= 0 then
            imgui.SameLine(0, 8)
            do
                local hkDl = imgui.GetWindowDrawList()
                local hkSp = imgui.GetCursorScreenPos()
                local hkW = drawKeyChip(hkDl, 0, 0, selBind.key, selBind.key_mod or 0, t, 0)
                drawKeyChip(hkDl, hkSp.x, hkSp.y+1, selBind.key, selBind.key_mod or 0, t, 0.9)
                imgui.Dummy(imgui.ImVec2(hkW + 4, 16))
            end
        end

        if selBind.cmd and selBind.cmd ~= "" then
            imgui.SameLine(0, 8)
            badge("/" .. (selBind.cmd:match("^(%S+)") or selBind.cmd), t.accent)
        end
    end

    imgui.Spacing()

    -- УЛУЧШЕНИЕ #3 (модифицированное): Название (без описания)
    secTitle("Основное")
    imgui.PushItemWidth(-1)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(14, 10))
    imgui.InputTextWithHint("##eName", u8("Название бинда"), B.editNameBuf, 256)
    imgui.PopStyleVar(2); imgui.PopItemWidth()

    -- УЛУЧШЕНИЕ #5: Категория + Задержка в одну строку
    secTitle("Параметры")

imgui.PushStyleColor(imgui.Col.Text, t.text2)
imgui.AlignTextToFramePadding()
imgui.Text(u8("Категория:"))
imgui.PopStyleColor()
imgui.SameLine(0, 8)
imgui.PushItemWidth(160)
imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
imgui.Combo("##eCat", B.editCategoryBuf, U.bindCatNamesPtr, 4)
imgui.PopStyleVar(); imgui.PopItemWidth()

imgui.SameLine(0, 24)

imgui.PushStyleColor(imgui.Col.Text, t.text2)
imgui.AlignTextToFramePadding()
imgui.Text(u8("Задержка:"))
imgui.PopStyleColor()
imgui.SameLine(0, 8)
imgui.PushItemWidth(140)
imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
imgui.InputInt("##eDel", B.editDelayBuf, 100, 500)
imgui.PopStyleVar(); imgui.PopItemWidth()
B.editDelayBuf[0] = clamp(B.editDelayBuf[0], C.MIN_DELAY, C.MAX_DELAY)
imgui.SameLine(0, 4)
imgui.PushStyleColor(imgui.Col.Text, t.text3)
imgui.AlignTextToFramePadding()
imgui.Text(u8("мс"))
imgui.PopStyleColor()

local currentStepCount = #splitSteps(u8:decode(ffi.string(B.editStepsBuf)))
if currentStepCount > 0 then
    imgui.SameLine(0, 16)
    imgui.PushStyleColor(imgui.Col.Text, t.text3)
    imgui.AlignTextToFramePadding()
    imgui.Text(u8(safeFormat("(~%.1fс)", currentStepCount * B.editDelayBuf[0] / 1000)))
    imgui.PopStyleColor()
end

    -- УЛУЧШЕНИЕ #4: Активация — команда и клавиша с подписями
    secTitle("Активация")

imgui.PushStyleColor(imgui.Col.Text, t.text2)
imgui.AlignTextToFramePadding()
imgui.Text(u8("Команда:"))
imgui.PopStyleColor()
imgui.SameLine(0, 8)
imgui.PushItemWidth(imgui.GetContentRegionAvail().x - 180)
imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
imgui.InputTextWithHint("##eCmd", u8("/команда {арг1} {арг2}"), B.editCmdBuf, 64)
imgui.PopStyleVar(); imgui.PopItemWidth()

imgui.SameLine(0, 12)
imgui.PushStyleColor(imgui.Col.Text, t.text2)
imgui.AlignTextToFramePadding()
imgui.Text(u8("Клавиша:"))
imgui.PopStyleColor()
imgui.SameLine(0, 8)
if btn(" " .. getKeyName(B.editKeyBuf[0], B.editKeyModBuf[0]) .. " ##eKey", 0, 0, "outline") then
    S.tempKey = B.editKeyBuf[0]; S.tempMod = B.editKeyModBuf[0]
    S.waitingForKey = true; S.keyBindContext = "bind"; S.keyBindPopupActive = true
end
if B.editKeyBuf[0] ~= 0 then
    imgui.SameLine(0, 4)
    if btn("x##resetKey", 24, 0, "danger") then
        B.editKeyBuf[0] = 0; B.editKeyModBuf[0] = 0
    end
end

local cmdStr = ffi.string(B.editCmdBuf); local cmdArgs = {}
for argName in cmdStr:gmatch("{([^}]+)}") do table.insert(cmdArgs, argName) end
if #cmdArgs > 0 then
    imgui.Spacing()
    imgui.PushStyleColor(imgui.Col.Text, t.accent2)
    imgui.Text(u8("Аргументы: " .. table.concat(cmdArgs, ", ")))
    imgui.PopStyleColor()
    imgui.PushStyleColor(imgui.Col.Text, t.text3)
    imgui.Text(u8("Игрок указывает их после команды"))
    imgui.PopStyleColor()
end

    -- УЛУЧШЕНИЕ #6: Компактная секция шагов
    secTitle("Шаги")

    -- Справка и подсказка в одну строку
    if btn("Переменные {x}##vref", 0, 24, "outline") then U.showVarRef[0] = not U.showVarRef[0] end
    imgui.SameLine(0, 12)
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.5))
    imgui.Text(u8("{my_id} {my_nick} | [1500] пауза | [repeat:3] | [if:hp>50]"))
    imgui.PopStyleColor()

    imgui.Spacing()

        -- 6.4 + улучшение: Анализ длины строк с монитором
    local stepsRaw = ffi.string(B.editStepsBuf)
    local stepsText = u8:decode(stepsRaw)
    local currentSteps = splitSteps(stepsText)
    local lineAnalysis = analyzeStepLines(stepsRaw)

    if #currentSteps > 0 then
        local longCount = 0
        local warnCount = 0
        for _, la in ipairs(lineAnalysis) do
            if la.isLong then longCount = longCount + 1 end
            if la.isWarning then warnCount = warnCount + 1 end
        end

        -- Основная информация
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8(safeFormat("Шагов: %d", #currentSteps)))
        imgui.PopStyleColor()

        if warnCount > 0 then
            imgui.SameLine(0, 12)
            imgui.PushStyleColor(imgui.Col.Text, t.yellow)
            imgui.Text(u8(safeFormat("? %d строк 120-144 сим.", warnCount)))
            imgui.PopStyleColor()
        end

        if longCount > 0 then
            imgui.SameLine(0, 12)
            imgui.PushStyleColor(imgui.Col.Text, t.red)
            imgui.Text(u8(safeFormat("? %d строк > 144 сим.", longCount)))
            imgui.PopStyleColor()
        end

        -- 6.4: Раскрывающийся монитор длин строк
        if (longCount > 0 or warnCount > 0) then
            imgui.Spacing()
            local monitorId = "line_monitor"
            local monitorOpen = anim(monitorId .. "_open", 0, 0.12)

            if btn("Показать проблемные строки##lm", 0, 22, "ghost") then
                anims[monitorId .. "_open"] = (monitorOpen < 0.5) and 1 or 0
            end

            if monitorOpen > 0.01 then
                imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, monitorOpen)
                local monH = math.min((longCount + warnCount) * 22 + 8, 120)
                imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(t.card.x, t.card.y, t.card.z, 0.5))
                imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 10)
                imgui.BeginChild("##line_monitor_list", imgui.ImVec2(-1, monH * monitorOpen), true)

                for _, la in ipairs(lineAnalysis) do
                    if la.isLong or la.isWarning then
                        local lineCol = la.isLong and t.red or t.yellow
                        local barW = clamp(la.processedLen / 180, 0, 1) * (imgui.GetContentRegionAvail().x - 140)

                        -- Номер строки
                        imgui.PushStyleColor(imgui.Col.Text, lineCol)
                        imgui.Text(u8(safeFormat("Стр %d:", la.num)))
                        imgui.PopStyleColor()

                        -- Длина
                        imgui.SameLine(70)
                        imgui.PushStyleColor(imgui.Col.Text, la.isLong and t.red or t.yellow)
                        local lenLabel = safeFormat("%d/144", la.processedLen)
                        if la.hasCustomArgs then lenLabel = lenLabel .. " (~)" end
                        imgui.Text(u8(lenLabel))
                        imgui.PopStyleColor()

                        -- Мини-прогрессбар
                        imgui.SameLine(130)
                        local barSp = imgui.GetCursorScreenPos()
                        local barDl = imgui.GetWindowDrawList()
                        local barH2 = 6
                        local barMaxW = imgui.GetContentRegionAvail().x - 10
                        barDl:AddRectFilled(
                            imgui.ImVec2(barSp.x, barSp.y + 5),
                            imgui.ImVec2(barSp.x + barMaxW, barSp.y + 5 + barH2),
                            ImVec4toU32(imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.1)), 3)
                        local fillW = clamp(la.processedLen / 144, 0, 1.3) * barMaxW
                        barDl:AddRectFilled(
                            imgui.ImVec2(barSp.x, barSp.y + 5),
                            imgui.ImVec2(barSp.x + fillW, barSp.y + 5 + barH2),
                            ImVec4toU32(lineCol, 0.7), 3)
                        -- Отметка 144
                        local mark144 = (144 / 180) * barMaxW
                        barDl:AddLine(
                            imgui.ImVec2(barSp.x + mark144, barSp.y + 3),
                            imgui.ImVec2(barSp.x + mark144, barSp.y + 5 + barH2 + 2),
                            ImVec4toU32(imgui.ImVec4(1, 1, 1, 0.3)), 1)
                        imgui.Dummy(imgui.ImVec2(barMaxW, barH2 + 4))
                    end
                end

                imgui.EndChild()
                imgui.PopStyleVar(); imgui.PopStyleColor()
                imgui.PopStyleVar()
            end
        end
    end

    -- Поле ввода шагов с подсветкой синтаксиса
    local stH = math.max(imgui.GetContentRegionAvail().y - 52, 80)

if U.fontMono then imgui.PushFont(U.fontMono) end
imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(12, 8))

if S._stepsFieldActive then
    imgui.InputTextMultiline("##eSteps", B.editStepsBuf, 32768,
        imgui.ImVec2(-1, stH), imgui.InputTextFlags.None)
    if wasKeyPressed(C.KEY_ESC) then
        S._stepsFieldActive = false
    elseif imgui.IsMouseClicked(0) and not imgui.IsItemHovered() then
        S._stepsFieldActive = false
    end
else
    drawStepsPassiveViewer(stH)
end

imgui.PopStyleVar(2)
if U.fontMono then imgui.PopFont() end

    -- УЛУЧШЕНИЕ #2: Кнопки действий (разделённые группы)
    imgui.Spacing()
    local actionBarDl = imgui.GetWindowDrawList()
    local actionBarPos = imgui.GetCursorScreenPos()
    local actionBarW = imgui.GetContentRegionAvail().x

    -- Разделитель
    actionBarDl:AddLine(
        imgui.ImVec2(actionBarPos.x, actionBarPos.y),
        imgui.ImVec2(actionBarPos.x + actionBarW, actionBarPos.y),
        ImVec4toU32(imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.08)), 1)
    imgui.Dummy(imgui.ImVec2(0, 6))

    -- Левая группа: Сохранить + Тест
    if btn(" Сохранить ", 0, 34, "accent") then
        saveCurrentBind(false)
    end

    imgui.SameLine(0, 8)
    if btn(" Тест ", 0, 34, "outline") then
        local stR = u8:decode(ffi.string(B.editStepsBuf))
        if stR ~= "" then
            lua_thread.create(function()
                performBind({
                    name = u8:decode(ffi.string(B.editNameBuf)),
                    steps = splitSteps(stR),
                    delay = B.editDelayBuf[0],
                    enabled = true, uses = 0
                }, {})
            end)
        end
    end

    -- Правая группа: Копия + Удалить
    if S.selectedBindIndex and binds[S.selectedBindIndex] then
        imgui.SameLine(actionBarW - 170)

        if btn(" Копия ", 0, 34, "ghost") then
            local cp = deepCopy(binds[S.selectedBindIndex]); cp.id = generateId()
            cp.name = (cp.name or "") .. " (2)"; cp.uses = 0; cp.lastUseTime = nil
            table.insert(binds, S.selectedBindIndex + 1, cp)
            S.selectedBindIndex = S.selectedBindIndex + 1
            saveBinds(); addNotification("Скопировано", C.NOTIFY_SUCCESS)
        end

        imgui.SameLine(0, 8)
        if btn(" Удалить ", 0, 34, "danger") then
            if settings.confirmDelete then
                S.deleteConfirmation.active = true
                S.deleteConfirmation.index = S.selectedBindIndex
            else
                table.remove(binds, S.selectedBindIndex); S.selectedBindIndex = nil
                ffi.copy(B.editNameBuf, ""); ffi.copy(B.editCmdBuf, "")
                ffi.copy(B.editStepsBuf, "")
                saveBinds(); addNotification("Удалено", C.NOTIFY_SUCCESS)
            end
        end
    end
        -- 6.5: Попап подтверждения несохранённых изменений
    if S.showUnsavedConfirm then
        imgui.OpenPopup(u8("Несохранённые изменения##unsaved"))
        S.showUnsavedConfirm = false
    end
    if imgui.BeginPopupModal(u8("Несохранённые изменения##unsaved"), nil, imgui.WindowFlags.AlwaysAutoResize) then
        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.Text, t.yellow)
        imgui.Text(u8("  ? Есть несохранённые изменения!"))
        imgui.PopStyleColor()
        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.Text, t.text2)
        imgui.Text(u8("  Сохранить перед переходом?"))
        imgui.PopStyleColor()
        imgui.Spacing(); imgui.Spacing()

        -- Кнопка "Сохранить и перейти"
        if btn(" Сохранить ", 110, 32, "accent") then
            -- Выполнить сохранение текущего бинда
            local name = u8:decode(trim(ffi.string(B.editNameBuf)))
            local cmdR = trim(ffi.string(B.editCmdBuf))
            local cmd = cmdR:match("^/?(.+)") or ""; cmd = trim(cmd)
            local stR = u8:decode(ffi.string(B.editStepsBuf))
            local desc = u8:decode(trim(ffi.string(B.editDescBuf)))
            if name ~= "" and stR ~= "" and S.selectedBindIndex and binds[S.selectedBindIndex] then
                binds[S.selectedBindIndex].name = name
                binds[S.selectedBindIndex].cmd = cmd
                binds[S.selectedBindIndex].desc = desc
                binds[S.selectedBindIndex].steps = splitSteps(stR)
                binds[S.selectedBindIndex].delay = B.editDelayBuf[0]
                binds[S.selectedBindIndex].key = B.editKeyBuf[0]
                binds[S.selectedBindIndex].key_mod = B.editKeyModBuf[0]
                binds[S.selectedBindIndex].cooldown = B.editCooldownBuf[0]
                binds[S.selectedBindIndex].enabled = B.editEnabledBuf[0]
                binds[S.selectedBindIndex].favorite = B.editFavoriteBuf[0]
                binds[S.selectedBindIndex].category = B.editCategoryBuf[0]
                saveBinds()
                addNotification("Автосохранено!", C.NOTIFY_SUCCESS)
            end
            -- Выполнить отложенное действие
            if S.unsavedAction then
                if S.unsavedAction.type == "select" then
                    discardAndSelect(S.unsavedAction.idx)
                elseif S.unsavedAction.type == "create" then
                    discardAndSelect(nil)
                end
                S.unsavedAction = nil
            end
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine(0, 8)

        -- Кнопка "Не сохранять"
        if btn(" Отменить изм. ", 130, 32, "danger") then
            S.isCreatingNew = false
            if S.unsavedAction then
                if S.unsavedAction.type == "select" then
                    discardAndSelect(S.unsavedAction.idx)
                elseif S.unsavedAction.type == "create" then
                    discardAndSelect(nil)
                end
                S.unsavedAction = nil
            end
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine(0, 8)

        -- Кнопка "Остаться"
        if btn(" Отмена ", 90, 32, "ghost") then
            S.unsavedAction = nil
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end
    -- Модалка подтверждения удаления
    if S.deleteConfirmation.active then
        imgui.OpenPopup(u8("Удалить?##cd"))
        S.deleteConfirmation.active = false
    end
    if imgui.BeginPopupModal(u8("Удалить?##cd"), nil, imgui.WindowFlags.AlwaysAutoResize) then
        imgui.Spacing()
        imgui.Text(u8(" Удалить бинд? "))
        imgui.Spacing()
        if btn(" Да ", 90, 0, "danger") then
            local di = S.deleteConfirmation.index
            if di and binds[di] then
                table.remove(binds, di)
                if S.selectedBindIndex == di then
                    S.selectedBindIndex = nil
                    ffi.copy(B.editNameBuf, ""); ffi.copy(B.editCmdBuf, "")
                    ffi.copy(B.editStepsBuf, "")
                elseif S.selectedBindIndex and S.selectedBindIndex > di then
                    S.selectedBindIndex = S.selectedBindIndex - 1
                end
                saveBinds(); addNotification("Удалено", C.NOTIFY_SUCCESS)
            end
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if btn(" Нет ", 90, 0, "ghost") then imgui.CloseCurrentPopup() end
        imgui.EndPopup()
    end

    -- Закрытие стилей
    imgui.PopStyleColor(3) -- FrameBg, FrameBgHovered, Border
    imgui.PopStyleVar()    -- FrameBorderSize
    imgui.EndChild(); imgui.PopStyleVar(); imgui.PopStyleColor()
end

-- =========================================================================
-- СПРАВОЧНИК
-- =========================================================================
local function drawReference()
    local t = T()
    setWindowPadding(S.contentPadding, S.contentPadding)
    imgui.BeginChild("##ref", imgui.ImVec2(0,0), false)
    secTitle("Справочник по процедурам")
    imgui.PushItemWidth(-1); imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 22)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(14, 9))
    imgui.InputTextWithHint("##rsearch", u8(" Поиск..."), U.refSearchBuf, ffi.sizeof(U.refSearchBuf))
    imgui.PopStyleVar(2); imgui.PopItemWidth(); imgui.Spacing()
    local stUtf8 = ffi.string(U.refSearchBuf); local st2 = u8:decode(stUtf8)
    for i, item in ipairs(menuData) do
        if st2 == "" or item.t:find(st2,1,true) or item.c:find(st2,1,true) then
            local rid = "ref_" .. i; local hov = anim(rid .. "_h", 0, 0.12)
            local itemColor = t.accent
            local label = safeFormat(" %02d | %s", i, item.t)
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(t.card.x, t.card.y, t.card.z, 0.5 + hov * 0.2))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(itemColor.x, itemColor.y, itemColor.z, 0.15))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(itemColor.x, itemColor.y, itemColor.z, 0.25))
            imgui.PushStyleColor(imgui.Col.Text, lerpColor(t.text2, t.text, hov))
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
            if imgui.Button(u8(label) .. "##rb" .. i, imgui.ImVec2(-1, 38)) then U.refDetailIdx = i; U.refDetailOpen[0] = true end
            if imgui.IsItemHovered() then anim(rid .. "_h", 1, 0.12) else anim(rid .. "_h", 0, 0.08) end
            if hov > 0.01 then
                local dl = imgui.GetWindowDrawList(); local mi = imgui.GetItemRectMin(); local ma = imgui.GetItemRectMax()
                dl:AddRectFilled(imgui.ImVec2(mi.x, mi.y + 6), imgui.ImVec2(mi.x + 3, ma.y - 6), ImVec4toU32(itemColor, hov * 0.8), 2)
            end
            imgui.PopStyleVar(); imgui.PopStyleColor(4); imgui.Spacing()
        end
    end
    imgui.EndChild()
end

imgui.OnFrame(
    function() return U.refDetailOpen[0] and U.refDetailIdx > 0 end,
    function(self)

        local t = T(); local item = menuData[U.refDetailIdx]
        if not item then U.refDetailOpen[0] = false; return end
        imgui.SetNextWindowSize(imgui.ImVec2(560, 480), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2,sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
        pushWindowPadding(24,20)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 20)
        imgui.Begin(u8(" " .. item.t), U.refDetailOpen, imgui.WindowFlags.NoCollapse)
        cardBegin("##rdc", imgui.ImVec2(0, -48))
        imgui.PushTextWrapPos(0); imgui.PushStyleColor(imgui.Col.Text, t.text2)
        imgui.TextWrapped(u8(item.c)); imgui.PopStyleColor(); imgui.PopTextWrapPos()
        cardEnd(); imgui.Spacing()
        if btn(" Закрыть ", 120, 32, "accent") then U.refDetailOpen[0] = false end
        imgui.End(); imgui.PopStyleVar(2)
    end
)

-- =========================================================================
-- СТАТИСТИКА
-- =========================================================================
local function drawStats()
    local t = T()
    setWindowPadding(S.contentPadding, S.contentPadding)
    imgui.BeginChild("##stats", imgui.ImVec2(0,0), false)
    secTitle("Статистика использования")
    local totalUses, totalFav = 0, 0; local topBind = { name = "—", uses = 0 }
    for _, b in ipairs(binds) do
        totalUses = totalUses + (b.uses or 0)
        if b.favorite then totalFav = totalFav + 1 end
        if (b.uses or 0) > topBind.uses then topBind = { name = b.name or "?", uses = b.uses } end
    end
    local cw = math.floor((imgui.GetContentRegionAvail().x - 30) / 3)
    cardBegin("##mb_Всего", imgui.ImVec2(cw, 72)); imgui.PushStyleColor(imgui.Col.Text, t.accent); imgui.Text(u8("# " .. #binds)); imgui.PopStyleColor()
    imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8("Всего биндов")); imgui.PopStyleColor(); cardEnd()
    imgui.SameLine(0,10)
    cardBegin("##mb_Исп", imgui.ImVec2(cw, 72)); imgui.PushStyleColor(imgui.Col.Text, t.green); imgui.Text(u8("> " .. totalUses)); imgui.PopStyleColor()
    imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8("Исп-й всего")); imgui.PopStyleColor(); cardEnd()
    imgui.SameLine(0,10)
    cardBegin("##mb_Сес", imgui.ImVec2(cw, 72)); imgui.PushStyleColor(imgui.Col.Text, t.yellow); imgui.Text(u8("* " .. S.totalSessionBinds)); imgui.PopStyleColor()
    imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8("За сессию")); imgui.PopStyleColor(); cardEnd()
    imgui.Spacing(); thinSep()
    secTitle("Топ биндов")
    local sorted = {}
    for i, b in ipairs(binds) do if (b.uses or 0) > 0 then table.insert(sorted, {i=i, b=b}) end end
    table.sort(sorted, function(a,b2) return (a.b.uses or 0) > (b2.b.uses or 0) end)
    if #sorted == 0 then imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8("Нет данных")); imgui.PopStyleColor()
    else
        for i = 1, math.min(#sorted, 10) do
            local b = sorted[i].b; local nm = (b.name and b.name ~= "") and b.name or "Бинд"; local uses = b.uses or 0
            imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8(safeFormat("#%d", i))); imgui.PopStyleColor()
            imgui.SameLine(40); imgui.PushStyleColor(imgui.Col.Text, t.text); imgui.Text(u8(nm)); imgui.PopStyleColor()
            imgui.SameLine(240); imgui.PushStyleColor(imgui.Col.Text, t.accent2); imgui.Text(u8(tostring(uses))); imgui.PopStyleColor()
            imgui.SameLine(300); imgui.PushItemWidth(imgui.GetContentRegionAvail().x)
            progressBar("", uses, topBind.uses, t.accent, false); imgui.PopItemWidth()
        end
    end
    thinSep()
    secTitle("История выполнений")
    if #bindHistory == 0 then imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8("Нет записей")); imgui.PopStyleColor()
    else
        for i = 1, math.min(#bindHistory, 15) do
            local h = bindHistory[i]; local col = h.success and t.green or t.red
            imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8(os.date("%H:%M:%S", h.time))); imgui.PopStyleColor()
            imgui.SameLine(90); imgui.PushStyleColor(imgui.Col.Text, col); imgui.Text(u8(h.name)); imgui.PopStyleColor()
            imgui.SameLine(280); imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.Text(u8(safeFormat("%.1fс | %d шагов", h.duration, h.steps))); imgui.PopStyleColor()
        end
    end
    imgui.EndChild()
end

-- =========================================================================
-- НАСТРОЙКИ
-- =========================================================================
local function drawSettings()
    local t = T(); local changed = false
    setWindowPadding(S.contentPadding, S.contentPadding)
    imgui.BeginChild("##set", imgui.ImVec2(0,0), false)
    -- Синхронизируем кэш-буферы при первом открытии вкладки
    if not B._settingsBufsSync then
        B._settingsBufsSync = true
        B.setDefaultDelay[0]   = settings.defaultDelay
        B.setMaxDuration[0]    = settings.maxBindDuration
        B.setAfInterval[0]     = autoFind.interval
        B.setAfDist[0]         = autoFind.proximityDistance
        B.setMariInterval[0]   = settings.membersAutoRefreshInterval
        B.uiScaleBuf[0]        = settings.uiScale
    end
    secTitle("Тайминги")
    cardBegin("##stim", imgui.ImVec2(-1, 160))
    imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.Text(u8("Задержка по умолчанию (мс)")); imgui.PopStyleColor()
    imgui.PushItemWidth(200); imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    if imgui.InputInt("##sdd", B.setDefaultDelay, 100, 500) then settings.defaultDelay = clamp(B.setDefaultDelay[0], C.MIN_DELAY, C.MAX_DELAY); changed = true end
    imgui.PopStyleVar(); imgui.PopItemWidth(); imgui.Spacing()
    imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.Text(u8("Макс. длительность бинда (мс)")); imgui.PopStyleColor()
    imgui.PushItemWidth(200); imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    if imgui.InputInt("##smd", B.setMaxDuration, 5000, 10000) then settings.maxBindDuration = clamp(B.setMaxDuration[0], C.MIN_BIND_DURATION, C.MAX_BIND_DURATION); changed = true end
    imgui.PopStyleVar(); imgui.PopItemWidth(); cardEnd(); imgui.Spacing()
    secTitle("Функции и внешний вид")
    local setColGap = 12
    local setColW = math.floor((imgui.GetContentRegionAvail().x - setColGap) / 2)
    -- Левая колонка: Функции
    cardBegin("##sfunc", imgui.ImVec2(setColW, 310))
    imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8("ФУНКЦИИ")); imgui.PopStyleColor()
    imgui.Dummy(imgui.ImVec2(0,4))
    local eg = imgui.new.bool(settings.enableGwarn); if toggleSwitch("Умный выговор (/gw)", eg) then settings.enableGwarn = eg[0]; changed = true end; imgui.Spacing()
    local eu = imgui.new.bool(settings.enableUk); if toggleSwitch("Умный розыск (/uk)", eu) then settings.enableUk = eu[0]; changed = true end; imgui.Spacing()
    local edm = imgui.new.bool(settings.enableDemoute); if toggleSwitch("Умный demoute (/dem)", edm) then settings.enableDemoute = edm[0]; changed = true end; imgui.Spacing()
    local eds = imgui.new.bool(settings.enableDismiss); if toggleSwitch("Умный dismiss (/dis)", eds) then settings.enableDismiss = eds[0]; changed = true end; imgui.Spacing()
    local sn = imgui.new.bool(settings.showNotifications); if toggleSwitch("Уведомления", sn) then settings.showNotifications = sn[0]; changed = true end; imgui.Spacing()
    local ab = imgui.new.bool(settings.autoBackup); if toggleSwitch("Автобэкап (5 мин)", ab) then settings.autoBackup = ab[0]; changed = true end
    cardEnd()
    imgui.SameLine(0, setColGap)
    -- Правая колонка: Отображение
    cardBegin("##sview", imgui.ImVec2(setColW, 310))
    imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8("ОТОБРАЖЕНИЕ")); imgui.PopStyleColor()
    imgui.Dummy(imgui.ImVec2(0,4))
    local so = imgui.new.bool(settings.showOverlay); if toggleSwitch("Оверлей при бинде", so) then settings.showOverlay = so[0]; changed = true end; imgui.Spacing()
    local cd = imgui.new.bool(settings.confirmDelete); if toggleSwitch("Подтверждение удаления", cd) then settings.confirmDelete = cd[0]; changed = true end; imgui.Spacing()
    local sp2 = imgui.new.bool(settings.showParticles); if toggleSwitch("Частицы в фоне", sp2) then settings.showParticles = sp2[0]; changed = true end; imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0,6))
    imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.AlignTextToFramePadding(); imgui.Text(u8("Позиция оверлея:")); imgui.PopStyleColor()
    imgui.Spacing()
    if btn("Сверху##op0", setColW - 48, 28, settings.overlayPosition == 0 and "accent" or "ghost") then settings.overlayPosition = 0; changed = true end
    imgui.Spacing()
    if btn("Снизу##op1", setColW - 48, 28, settings.overlayPosition == 1 and "accent" or "ghost") then settings.overlayPosition = 1; changed = true end
    cardEnd()
    imgui.Spacing()
    secTitle("Управление")
    cardBegin("##skeys", imgui.ImVec2(-1, 100), false, 4)

    -- Клавиша открытия меню
    imgui.PushStyleColor(imgui.Col.Text, t.text2)
    imgui.AlignTextToFramePadding()
    imgui.Text(u8("Открыть меню:"))
    imgui.PopStyleColor()
    imgui.SameLine(0, 8)
    if btn(" " .. getKeyName(settings.openKey, 0) .. " ##openKey", 0, 0, "outline") then
        S.tempKey = settings.openKey; S.tempMod = 0
        S.waitingForKey = true; S.keyBindContext = "open"; S.keyBindPopupActive = true
    end
    if settings.openKey ~= 0 then
        imgui.SameLine(0, 4)
        if btn("x##resetOpenKey", 24, 0, "danger") then
            settings.openKey = 0; saveSettings()
        end
    end

    imgui.Spacing()

    -- Стоп-клавиша
    imgui.PushStyleColor(imgui.Col.Text, t.text2)
    imgui.AlignTextToFramePadding()
    imgui.Text(u8("Стоп-клавиша:"))
    imgui.PopStyleColor()
    imgui.SameLine(0, 8)
    if btn(" " .. getKeyName(settings.stopKey, settings.stopKeyMod) .. " ##stopKey", 0, 0, "outline") then
        S.tempKey = settings.stopKey; S.tempMod = settings.stopKeyMod
        S.waitingForKey = true; S.keyBindContext = "stop"; S.keyBindPopupActive = true
    end
    if settings.stopKey ~= 0 then
        imgui.SameLine(0, 4)
        if btn("x##resetStopKey", 24, 0, "danger") then
            settings.stopKey = 0; settings.stopKeyMod = 0; saveSettings()
        end
    end

    cardEnd(); imgui.Spacing()
    secTitle("AutoFind")
    cardBegin("##safind", imgui.ImVec2(-1, 260))
    imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.Text(u8("Интервал поиска (мс)")); imgui.PopStyleColor()
    imgui.PushItemWidth(200); imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    if imgui.InputInt("##afint", B.setAfInterval, 500, 1000) then autoFind.interval = clamp(B.setAfInterval[0], 1000, 30000) end
    imgui.PopStyleVar(); imgui.PopItemWidth(); imgui.Spacing()
    local afs = imgui.new.bool(autoFind.suppressMessages)
    if toggleSwitch("Скрывать /find из чата", afs) then autoFind.suppressMessages = afs[0] end
    imgui.Spacing(); thinSep(); imgui.Spacing()
    -- Оповещение о близости
    local afpa = imgui.new.bool(autoFind.proximityAlert)
    if toggleSwitch("Оповещение о близости цели", afpa) then autoFind.proximityAlert = afpa[0] end
    imgui.Spacing()
    local afsa = imgui.new.bool(autoFind.soundAlert)
    if toggleSwitch("Звуковое оповещение", afsa) then autoFind.soundAlert = afsa[0] end
    imgui.Spacing()
    imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.AlignTextToFramePadding(); imgui.Text(u8("Радиус оповещения (м):")); imgui.PopStyleColor()
    imgui.SameLine(0, 10)
    imgui.PushItemWidth(120); imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    if imgui.InputInt("##afdist", B.setAfDist, 5, 20) then autoFind.proximityDistance = clamp(B.setAfDist[0], 5, 500) end
    imgui.PopStyleVar(); imgui.PopItemWidth()
    imgui.SameLine(0, 10)
    badge(tostring(autoFind.proximityDistance) .. "м", t.accent2)
    cardEnd(); imgui.Spacing()
    secTitle("Members Overlay")
    cardBegin("##smembers", imgui.ImVec2(-1, 250))
    local smo = imgui.new.bool(settings.showMembersOverlay); if toggleSwitch("Показывать оверлей", smo) then settings.showMembersOverlay = smo[0]; if not smo[0] then S.membersOverlayVisible = false end; changed = true end; imgui.Spacing()
    local smar = imgui.new.bool(settings.membersAutoRefresh); if toggleSwitch("Автообновление", smar) then settings.membersAutoRefresh = smar[0]; changed = true end; imgui.Spacing()
    imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.Text(u8("Интервал автообновления (мс)")); imgui.PopStyleColor()
    imgui.PushItemWidth(200); imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    if imgui.InputInt("##marint", B.setMariInterval, 5000, 10000) then settings.membersAutoRefreshInterval = clamp(B.setMariInterval[0], 10000, 600000); changed = true end
    imgui.PopStyleVar(); imgui.PopItemWidth()
    imgui.PushStyleColor(imgui.Col.Text, t.text3); imgui.Text(u8("Мин: 10сек, Макс: 10мин")); imgui.PopStyleColor(); imgui.Spacing()
    if btn("Сбросить позицию##mb_reset_pos", 180, 28, "ghost") then settings.membersOverlayRightX = -1; settings.membersOverlayPosY = -1; changed = true; addNotification("Позиция сброшена", C.NOTIFY_INFO) end
    imgui.SameLine(0, 10)
    if btn("Обновить сейчас##mb_refresh_now", 180, 28, "outline") then
        if not membersOverlay.isChecking then membersOverlay.isChecking = true;membersOverlay._checkStartTime = os.clock(); membersOverlay.tempList = {}; safeSendChat("/members"); addNotification("Members: сканирование...", C.NOTIFY_INFO) end
    end
    cardEnd(); imgui.Spacing()
    secTitle("Оформление")
    do
        -- Рисуем темы рядами по 7 штук
        local rowSize = 7
        local gapH = 8
        local totalW = imgui.GetContentRegionAvail().x
        local tw = math.floor((totalW - (rowSize - 1) * gapH) / rowSize)
        local thH = 72

        local function drawThemeCard(key, tw2)
            local th = colorThemes[key]; if not th then return end
            local act = (settings.currentTheme == key)
            local tid = "theme_"..key
            imgui.PushStyleColor(imgui.Col.ChildBg, th.card)
            imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 16)
            imgui.PushStyleVarFloat(imgui.StyleVar.ChildBorderSize, 0)
            local prevPadT = pushPadding(10, 8)
            imgui.BeginChild("##tc_"..key, imgui.ImVec2(tw2, thH), true)
            imgui.GetStyle().WindowPadding = prevPadT
            local isH = imgui.IsWindowHovered(imgui.HoveredFlags.ChildWindows)
            anim(tid.."_h", isH and 1 or 0, 0.12)
            local dl2 = imgui.GetWindowDrawList()
            local wp2 = imgui.GetWindowPos(); local ws2 = imgui.GetWindowSize()
            dl2:AddRectFilled(imgui.ImVec2(wp2.x,wp2.y), imgui.ImVec2(wp2.x+ws2.x,wp2.y+ws2.y),
                ImVec4toU32(th.bg), 16)
            -- Полноширинная градиентная полоса
            drawGradRounded(dl2, wp2.x, wp2.y, ws2.x, 5, th.grad1, th.grad2, 16)
            -- Мягкое свечение от полосы вниз
            drawGradV(dl2, wp2.x + 8, wp2.y + 5, ws2.x - 16, 14,
                imgui.ImVec4(th.grad1.x, th.grad1.y, th.grad1.z, 0.08),
                imgui.ImVec4(th.grad1.x, th.grad1.y, th.grad1.z, 0.0))
            local dotY = wp2.y + 20; local dotColors = {th.accent, th.green, th.yellow, th.red}
            for j, c2 in ipairs(dotColors) do
                dl2:AddCircleFilled(imgui.ImVec2(wp2.x + 10 + (j-1)*11, dotY), 3.2, ImVec4toU32(c2), 12)
            end
            dl2:AddText(imgui.ImVec2(wp2.x+7, wp2.y+34), ImVec4toU32(th.text, 0.8), u8(th.name))
            if act then
                dl2:AddRect(imgui.ImVec2(wp2.x,wp2.y), imgui.ImVec2(wp2.x+ws2.x,wp2.y+ws2.y),
                    ImVec4toU32(th.accent, 0.80), 16, 15, 2)
                drawGlowRect(dl2, wp2.x, wp2.y, wp2.x+ws2.x, wp2.y+ws2.y, th.accent, 0.12, 16)
                -- Активная метка снизу
                dl2:AddRectFilled(
                    imgui.ImVec2(wp2.x + 8,    wp2.y + ws2.y - 4),
                    imgui.ImVec2(wp2.x + ws2.x - 8, wp2.y + ws2.y - 1),
                    ImVec4toU32(th.accent, 0.7), 2)
            end
            imgui.SetCursorPos(imgui.ImVec2(0, 0))
            imgui.InvisibleButton("##thb_"..key, imgui.ImVec2(tw2, thH))
            if imgui.IsItemClicked() then settings.currentTheme = key; applyTheme(key); changed = true end
            imgui.EndChild(); imgui.PopStyleVar(3); imgui.PopStyleColor()
        end

        -- Рендерим все темы автоматическими рядами
        for i, key in ipairs(themeOrder) do
            local posInRow = (i - 1) % rowSize
            if posInRow == 0 and i > 1 then imgui.Spacing() end
            drawThemeCard(key, tw)
            local isLastInRow = posInRow == rowSize - 1
            local isLast = i == #themeOrder
            if not isLastInRow and not isLast then imgui.SameLine(0, gapH) end
        end
    end
    imgui.Spacing(); thinSep()
    secTitle("Масштаб интерфейса (DPI)")
    cardBegin("##sdpi", imgui.ImVec2(-1, 90), false, 4)
    imgui.PushStyleColor(imgui.Col.Text, t.text2)
    imgui.Text(u8("Масштаб окна (0.5 — 2.0):"))
    imgui.PopStyleColor()
    imgui.PushItemWidth(200); imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    if imgui.SliderFloat("##sdpi_val", B.uiScaleBuf, 0.5, 2.0, "%.2f") then
        settings.uiScale = clamp(B.uiScaleBuf[0], 0.5, 2.0); changed = true
    end
    imgui.PopStyleVar(); imgui.PopItemWidth()
    imgui.SameLine(0, 10)
    if btn("1.0##dpi_reset", 0, 0, "ghost") then
        settings.uiScale = 1.0; B.uiScaleBuf[0] = 1.0; changed = true
    end
    imgui.Spacing()
    imgui.PushStyleColor(imgui.Col.Text, t.text3)
    imgui.Text(u8("Изменение применится после перезапуска скрипта"))
    imgui.PopStyleColor()
    cardEnd()
    imgui.Spacing(); thinSep()
    secTitle("РП отыгрыш оружия")
    -- Переключатель + пол
    cardBegin("##srpw_top", imgui.ImVec2(-1, 100), false, 4)
    local rpwe = imgui.new.bool(settings.rpWeaponEnabled)
    if toggleSwitch("Авто /me при смене оружия", rpwe) then
        settings.rpWeaponEnabled = rpwe[0]; changed = true
    end
    imgui.Spacing()
    local rpwf = imgui.new.bool(settings.rpWeaponFemale)
    if toggleSwitch("Женский род (сняла / убрала)", rpwf) then
        settings.rpWeaponFemale = rpwf[0]; changed = true; rpGuns.initialize()
    end
    imgui.Spacing()
    imgui.PushStyleColor(imgui.Col.Text, t.text3)
    imgui.Text(u8("Формат: /me достал пистолет Desert Eagle из кобуры"))
    imgui.PopStyleColor()
    cardEnd()
    imgui.Spacing()
    -- Список оружий
    local rpTakeLabels = {u8("Спина"), u8("Карман"), u8("Пояс"), u8("Кобура")}
    local rpTakeColors = {t.blue, t.green, t.yellow, t.accent}
    local rpGunListH   = math.min(#rpGuns.data.rp_guns * 28 + 12, 320)
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(t.card.x,t.card.y,t.card.z,0.4))
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 14)
    imgui.BeginChild("##rpgunlist", imgui.ImVec2(-1, rpGunListH), true)
    -- Заголовок
    imgui.PushStyleColor(imgui.Col.Text, t.text3)
    imgui.Text(u8(" ID   Оружие (винит. падеж)                  Расположение    Вкл"))
    imgui.PopStyleColor()
    for gi, weapon in ipairs(rpGuns.data.rp_guns) do
        -- Полоска через строку
        if gi % 2 == 0 then
            local rsp = imgui.GetCursorScreenPos()
            local rdl = imgui.GetWindowDrawList()
            rdl:AddRectFilled(imgui.ImVec2(rsp.x-4, rsp.y),
                imgui.ImVec2(rsp.x + imgui.GetContentRegionAvail().x+4, rsp.y+26),
                ImVec4toU32(imgui.ImVec4(0,0,0,0.10)), 0)
        end
        -- ID
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8(string.format("%-4d", weapon.id)))
        imgui.PopStyleColor()
        imgui.SameLine(0,8)
        -- Имя (редактируемое)
        local nameBuf = ffi.new("char[64]", u8(weapon.name))
        imgui.PushItemWidth(220)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8)
        imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(6, 3))
        if imgui.InputText("##rpgn"..gi, nameBuf, 64) then
            weapon.name = u8:decode(ffi.string(nameBuf))
        end
        if imgui.IsItemDeactivatedAfterEdit() then rpGuns.saveConfig() end
        imgui.PopStyleVar(2); imgui.PopItemWidth()
        imgui.SameLine(0, 12)
        -- Расположение (цветные кнопки)
        for ti = 1, 4 do
            local isAct = weapon.rpTake == ti
            local tc    = rpTakeColors[ti]
            imgui.PushStyleColor(imgui.Col.Button,
                isAct and imgui.ImVec4(tc.x,tc.y,tc.z,0.55) or imgui.ImVec4(t.card.x,t.card.y,t.card.z,0.4))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(tc.x,tc.y,tc.z,0.30))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  imgui.ImVec4(tc.x,tc.y,tc.z,0.70))
            imgui.PushStyleColor(imgui.Col.Text,
                isAct and imgui.ImVec4(1,1,1,1) or imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.7))
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 6)
            imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(6,3))
            if imgui.Button(rpTakeLabels[ti].."##rpt"..gi.."_"..ti, imgui.ImVec2(56, 22)) then
                weapon.rpTake = ti; rpGuns.initialize(); rpGuns.saveConfig()
            end
            imgui.PopStyleVar(2); imgui.PopStyleColor(4)
            imgui.SameLine(0, 3)
        end
        -- Включить/выключить
        imgui.SameLine(0, 8)
        local enBuf = imgui.new.bool(weapon.enable)
        if toggleSwitch("##rpgen"..gi, enBuf) then
            weapon.enable = enBuf[0]; rpGuns.initialize(); rpGuns.saveConfig()
        end
    end
    imgui.EndChild(); imgui.PopStyleVar(); imgui.PopStyleColor()
    imgui.Spacing()
    if btn(" Сохранить список ##rpgsave", 0, 28, "accent") then
        rpGuns.saveConfig(); addNotification("Конфиг оружий сохранён", C.NOTIFY_SUCCESS)
    end
    imgui.SameLine(0, 8)
    if btn(" Сбросить к дефолту ##rpgreset", 0, 28, "danger") then
        rpGuns.configFile = rpGuns.configFile  -- no-op ref
        pcall(os.remove, rpGuns.configFile)
        -- reload defaults from the hardcoded table
        rpGuns.data.rp_guns = deepCopy(rpGuns.data.rp_guns)  -- keep same
        rpGuns.initialize()
        addNotification("Сброс не применяется — редактируйте вручную", C.NOTIFY_WARNING)
    end
    imgui.Spacing(); thinSep()
    secTitle("Данные")
    if btn(" Экспорт ", 140, 34, "outline") then exportBinds(configDirectory .. "/binds_export.json") end
    imgui.SameLine()
    if btn(" Импорт ", 140, 34, "outline") then importBinds(configDirectory .. "/binds_export.json") end
    imgui.SameLine(0, 18)
    if btn(" Бэкап сейчас ", 0, 34, "ghost") then autoBackup(); addNotification("Бэкап создан", C.NOTIFY_SUCCESS) end
    imgui.SameLine(0, 18)
    if btn(" Сброс стат. ", 0, 34, "danger") then
        for _, b in ipairs(binds) do b.uses = 0; b.lastUseTime = nil end
        S.totalSessionBinds = 0; recentActivity = {}; bindHistory = {}; hourlyStats = {}
        saveBinds(); saveActivityLog(); addNotification("Статистика сброшена", C.NOTIFY_SUCCESS)
    end
    imgui.Spacing(); thinSep()
        secTitle("Обновления")
    cardBegin("##supdate", imgui.ImVec2(-1, updater.updateAvailable and 280 or 160))

    -- Статус
    if updater.checking then
        local checkPulse = (math.sin(os.clock() * 4) + 1) * 0.5
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.yellow.x, t.yellow.y, t.yellow.z, 0.7 + checkPulse * 0.3))
        imgui.Text(u8("Проверка обновлений..."))
        imgui.PopStyleColor()
    elseif updater.downloading then
        local dlPulse = (math.sin(os.clock() * 3) + 1) * 0.5
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.7 + dlPulse * 0.3))
        imgui.Text(u8(safeFormat("Загрузка: %d/%d — %s",
            updater.downloadProgress.current,
            updater.downloadProgress.total,
            updater.downloadProgress.currentFile)))
        imgui.PopStyleColor()
        imgui.Spacing()
        progressBar("update_dl",
            updater.downloadProgress.current,
            updater.downloadProgress.total, t.accent)
    elseif updater.updateAvailable then
        -- Доступно обновление
        imgui.PushStyleColor(imgui.Col.Text, t.green)
        imgui.Text(u8("Доступно обновление!"))
        imgui.PopStyleColor()
        imgui.Spacing()

        imgui.PushStyleColor(imgui.Col.Text, t.text2)
        imgui.Text(u8("Текущая: v" .. C.SCRIPT_VERSION))
        imgui.PopStyleColor()
        imgui.SameLine(0, 20)
        imgui.PushStyleColor(imgui.Col.Text, t.green)
        imgui.Text(u8("Новая: v" .. updater.newVersion))
        imgui.PopStyleColor()

        -- Changelog
        if updater.changelog ~= "" then
            imgui.Spacing()
            imgui.PushStyleColor(imgui.Col.Text, t.accent2)
            imgui.Text(u8("Что нового:"))
            imgui.PopStyleColor()
            imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.PushTextWrapPos(imgui.GetContentRegionAvail().x)
            imgui.TextWrapped(u8(updater.changelog))
            imgui.PopTextWrapPos()
            imgui.PopStyleColor()
        end

        imgui.Spacing(); imgui.Spacing()

        -- Кнопки обновления
        if btn(" Обновить всё ", 0, 34, "accent") then
            updater.downloadFullUpdate()
        end
        imgui.SameLine(0, 8)
        if btn(" Только скрипт ", 0, 34, "outline") then
            updater.downloadScriptOnly()
        end
    elseif updater.pendingReload then
        imgui.PushStyleColor(imgui.Col.Text, t.yellow)
        imgui.Text(u8("Обновление установлено!"))
        imgui.PopStyleColor()
        imgui.Spacing()
        if btn(" Перезагрузить скрипт ", 0, 34, "accent") then
            thisScript():reload()
        end
    else
        -- Нет обновлений или ещё не проверяли
        imgui.PushStyleColor(imgui.Col.Text, t.text2)
        if updater.lastCheck > 0 then
            imgui.Text(u8("Версия актуальна (v" .. C.SCRIPT_VERSION .. ")"))
        else
            imgui.Text(u8("Текущая версия: v" .. C.SCRIPT_VERSION))
        end
        imgui.PopStyleColor()

        if updater.checkError then
            imgui.Spacing()
            imgui.PushStyleColor(imgui.Col.Text, t.red)
            imgui.Text(u8("Ошибка: " .. updater.checkError))
            imgui.PopStyleColor()
        end
    end

    imgui.Spacing()

    -- Кнопка проверки (если не идёт загрузка)
    if not updater.downloading and not updater.checking then
        if btn(" Проверить обновления ", 0, 30, "outline") then
            updater.checkForUpdates(false)
        end

        if updater.lastCheck > 0 then
            imgui.SameLine(0, 12)
            imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.Text(u8("Проверено: " .. formatTime(os.clock() - updater.lastCheck) .. " назад"))
            imgui.PopStyleColor()
        end
    end

    cardEnd()
imgui.Spacing()
    secTitle("Информация")
    local totalU = 0; for _, b in ipairs(binds) do totalU = totalU + (b.uses or 0) end
    cardBegin("##sinfo", imgui.ImVec2(-1, 85))
    imgui.PushStyleColor(imgui.Col.Text, t.text2)
    imgui.BulletText(u8("Версия: " .. C.SCRIPT_VERSION .. " | Тема: " .. (T().name or "?")))
    imgui.BulletText(u8("Биндов: " .. #binds .. " | Использований: " .. totalU))
    imgui.BulletText(u8("Сессия: " .. formatTime(os.clock() - S.sessionStartTime)))
    imgui.PopStyleColor(); cardEnd()
    imgui.Spacing(); imgui.Dummy(imgui.ImVec2(0, 40))
    if changed then saveSettings() end
    imgui.EndChild()
end
-- =========================================================================
-- ЖУРНАЛ
-- =========================================================================
local function drawJournal()
    local t = T()
    local now = os.clock()
    setWindowPadding(S.contentPadding, S.contentPadding)
    imgui.BeginChild("##journal", imgui.ImVec2(0, 0), false)

    if U.fontTitle then imgui.PushFont(U.fontTitle) end
    imgui.PushStyleColor(imgui.Col.Text, t.accent)
    imgui.Text(u8("Журнал"))
    imgui.PopStyleColor()
    if U.fontTitle then imgui.PopFont() end
    imgui.Spacing()

    -- Фильтры
    secTitle("Фильтр")

    -- Pill-tabs фильтра (единый стиль с биндером)
    local filters = {
        { id = "all",    label = "Все",      color = t.accent },
        { id = "bind",   label = "Бинды",    color = t.accent2 },
        { id = "gwarn",  label = "Выговоры", color = t.yellow },
        { id = "uk",     label = "Розыск",   color = t.red },
        { id = "system", label = "Система",  color = t.blue },
    }
    local pillGap = 6
    local pillTotalW = imgui.GetContentRegionAvail().x
    local pillW = math.floor((pillTotalW - pillGap * (#filters - 1)) / #filters)
    local pillH = 28
    for i, f in ipairs(filters) do
        local isActive = S.journalFilter == f.id
        local pid = "jf_" .. f.id
        local phov = anim(pid .. "_h", 0, 0.14)
        local pbgAlpha = isActive and 0.65 or (phov * 0.12)
        local pbg = isActive
            and imgui.ImVec4(f.color.x, f.color.y, f.color.z, pbgAlpha)
            or imgui.ImVec4(t.card.x, t.card.y, t.card.z, 0.3 + phov * 0.15)
        imgui.PushStyleColor(imgui.Col.Button, pbg)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(f.color.x, f.color.y, f.color.z, 0.22))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(f.color.x, f.color.y, f.color.z, 0.38))
        imgui.PushStyleColor(imgui.Col.Text,
            isActive and imgui.ImVec4(1,1,1,1) or lerpColor(t.text3, t.text2, phov))
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, pillH / 2)
        imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(0, 4))
        if imgui.Button(u8(f.label) .. "##jfp_" .. f.id, imgui.ImVec2(pillW, pillH)) then
            S.journalFilter = f.id
        end
        if isActive then
            local pmi = imgui.GetItemRectMin(); local pma = imgui.GetItemRectMax()
            local pdl = imgui.GetWindowDrawList()
            pdl:AddRectFilled(imgui.ImVec2(pmi.x + 10, pma.y - 3),
                imgui.ImVec2(pma.x - 10, pma.y),
                ImVec4toU32(f.color, 0.80), 2)
        end
        if imgui.IsItemHovered() then anim(pid .. "_h", 1, 0.14) else anim(pid .. "_h", 0, 0.08) end
        imgui.PopStyleVar(2); imgui.PopStyleColor(4)
        if i < #filters then imgui.SameLine(0, pillGap) end
    end

    imgui.Spacing(); thinSep()
    secTitle("События")

    if #recentActivity == 0 then
        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.Text, t.text3)
        imgui.Text(u8("Журнал пуст"))
        imgui.PopStyleColor()
    else
        cardBegin("##journal_list", imgui.ImVec2(-1, imgui.GetContentRegionAvail().y - 60), false, 8)
        local jDl = imgui.GetWindowDrawList()
        local shownCount = 0
        local typeLabels = { bind = "БИНД", gwarn = "GWARN", uk = "УК", system = "СИС" }

        for i, act in ipairs(recentActivity) do
            if S.journalFilter ~= "all" and act.atype ~= S.journalFilter then
                -- пропускаем
            else
                shownCount = shownCount + 1
                local el = now - act.time
                local col = act.atype == "bind" and t.accent2
                    or act.atype == "gwarn" and t.yellow
                    or act.atype == "uk" and t.red
                    or act.atype == "system" and t.blue
                    or t.text2

                local linePos = imgui.GetCursorScreenPos()

                -- Вертикальная линия
                if i < #recentActivity then
                    jDl:AddLine(
                        imgui.ImVec2(linePos.x + 8, linePos.y + 16),
                        imgui.ImVec2(linePos.x + 8, linePos.y + 34),
                        ImVec4toU32(imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.08)), 1)
                end

                -- Точка
                local dotSize = (shownCount == 1) and 5 or 3.5
                jDl:AddCircleFilled(imgui.ImVec2(linePos.x + 8, linePos.y + 8),
                    dotSize, ImVec4toU32(col, 0.8), 12)
                if shownCount == 1 then drawGlow(jDl, linePos.x + 8, linePos.y + 8, 4, col, 0.3) end

                -- Дата (если есть и отличается)
                if act.date and act.date ~= "" then
                    local prevDate = (i > 1 and recentActivity[i - 1]) and recentActivity[i - 1].date or ""
                    if shownCount == 1 or prevDate ~= act.date then
                        imgui.Dummy(imgui.ImVec2(22, 0)); imgui.SameLine()
                        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.4))
                        imgui.Text(u8("— " .. act.date .. " —"))
                        imgui.PopStyleColor()
                    end
                end

                -- Время
                imgui.Dummy(imgui.ImVec2(22, 0)); imgui.SameLine()
                if U.fontMono then imgui.PushFont(U.fontMono) end
                imgui.PushStyleColor(imgui.Col.Text, t.text3)
                imgui.Text(u8(act.timestamp or ""))
                imgui.PopStyleColor()
                if U.fontMono then imgui.PopFont() end

                -- Тип
                imgui.SameLine(0, 10)
                badge(typeLabels[act.atype] or "?", col)

                -- Текст
                imgui.SameLine(0, 10)
                imgui.PushStyleColor(imgui.Col.Text, shownCount == 1 and t.text or lerpColor(t.text2, t.text3, 0.3))
                imgui.Text(u8(act.text))
                imgui.PopStyleColor()

                -- Время назад
                if el < 300 then
                    imgui.SameLine(imgui.GetContentRegionAvail().x - 40)
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.3))
                    if el < 60 then
                        imgui.Text(u8(safeFormat("%dс", math.floor(el))))
                    else
                        imgui.Text(u8(safeFormat("%dм", math.floor(el / 60))))
                    end
                    imgui.PopStyleColor()
                end
            end
        end

        if shownCount == 0 then
            imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.Text(u8("Нет событий этого типа"))
            imgui.PopStyleColor()
        end

        cardEnd()
    end

    -- Кнопка очистки
    imgui.Spacing()
    if btn("Очистить журнал", 0, 28, "danger") then
        recentActivity = {}
        saveActivityLog()
        addNotification("Журнал очищен", C.NOTIFY_SUCCESS)
    end

    imgui.EndChild()
end

-- =========================================================================
-- ЗАМЕТКИ
-- =========================================================================
local function drawNotes()
    local t = T()
    setWindowPadding(S.contentPadding, S.contentPadding)
    imgui.BeginChild("##notes", imgui.ImVec2(0, 0), false)

    if U.fontTitle then imgui.PushFont(U.fontTitle) end
    imgui.PushStyleColor(imgui.Col.Text, t.accent)
    imgui.Text(u8("Заметки"))
    imgui.PopStyleColor()
    if U.fontTitle then imgui.PopFont() end
    imgui.Spacing()

    -- Загрузка при первом открытии
    if not B.notesLoaded then
        B.notesLoaded = true
        local notesPath = configDirectory .. "/notes.txt"
        if doesFileExistSafe(notesPath) then
            local f = io.open(notesPath, 'r')
            if f then
                local content = f:read('*a'); f:close()
                if content then ffi.copy(B.notesBuf, u8(content)) end
            end
        end
    end

    -- Быстрые вставки
    secTitle("Быстрая вставка")
    local quickInserts = {
        { label = "Дата",    text = os.date("%d.%m.%Y") },
        { label = "Время",   text = os.date("%H:%M") },
        { label = "Линия",   text = "\n————————————————\n" },
        { label = "TODO",    text = "\n[ ] " },
        { label = "DONE",    text = "\n[x] " },
        { label = "Заметка", text = "\n> " },
    }

    for i, qi in ipairs(quickInserts) do
        if btn(qi.label .. "##qi" .. i, 0, 24, "ghost") then
            local current = ffi.string(B.notesBuf)
            local newContent = current .. qi.text
            if #newContent < 65535 then
                ffi.copy(B.notesBuf, newContent)
            else
                addNotification("Заметки переполнены!", C.NOTIFY_WARNING)
            end
        end
        if i < #quickInserts then imgui.SameLine(0, 4) end
    end
    imgui.Spacing()

    -- Поле ввода
    local notesH = imgui.GetContentRegionAvail().y - 50

    if U.fontMono then imgui.PushFont(U.fontMono) end
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(14, 10))

    local inputBg = imgui.ImVec4(t.input.x + 0.03, t.input.y + 0.03, t.input.z + 0.03, 0.95)
    imgui.PushStyleColor(imgui.Col.FrameBg, inputBg)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered,
        imgui.ImVec4(inputBg.x + 0.03, inputBg.y + 0.03, inputBg.z + 0.03, 0.98))

    imgui.InputTextMultiline("##notesInput", B.notesBuf, 65536,
        imgui.ImVec2(-1, notesH), imgui.InputTextFlags.None)

    imgui.PopStyleColor(2)
    imgui.PopStyleVar(2)
    if U.fontMono then imgui.PopFont() end

    -- Кнопки
    imgui.Spacing()
    if btn(" Сохранить ", 0, 30, "accent") then
        local notesPath = configDirectory .. "/notes.txt"
        local f = io.open(notesPath, 'w')
        if f then
            local content = u8:decode(ffi.string(B.notesBuf))
            f:write(content); f:close()
            addNotification("Заметки сохранены", C.NOTIFY_SUCCESS)
        end
    end

    imgui.SameLine(0, 8)
    if btn(" Очистить ", 0, 30, "danger") then
        ffi.copy(B.notesBuf, "")
        addNotification("Заметки очищены", C.NOTIFY_INFO)
    end

    -- Счётчик символов и автосохранение
    imgui.SameLine(0, 16)
    local notesLen = #ffi.string(B.notesBuf)
    imgui.PushStyleColor(imgui.Col.Text, t.text3)
    imgui.AlignTextToFramePadding()
    imgui.Text(u8(safeFormat("%d символов", notesLen)))
    imgui.PopStyleColor()

    imgui.EndChild()
end

-- =========================================================================
-- НАВИГАЦИЯ САЙДБАРА
-- =========================================================================
local navLabels = { "Дашборд", "Биндер", "Справочник", "Настройки", "Журнал", "Заметки" }

local function drawNavButton(dl, x, y, w, h, idx, active)
    local id = "nav_" .. idx
    local mx, my = imgui.GetMousePos().x, imgui.GetMousePos().y
    local hovered = mx >= x and mx <= x + w and my >= y and my <= y + h
    local hovTarget = active and 1 or (hovered and 0.6 or 0)
    local hov = anim(id.."_a", hovTarget, 0.12)
    local t = T()
    if hov > 0.01 then
        dl:AddRectFilled(imgui.ImVec2(x+6, y+2), imgui.ImVec2(x+w-6, y+h-2),
            ImVec4toU32(imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,hov * 0.22)), 12)
    end
    if active then
        local indicatorH = h * 0.45; local iy1, iy2 = y + (h-indicatorH)/2, y + (h+indicatorH)/2
        dl:AddRectFilled(imgui.ImVec2(x+2, iy1), imgui.ImVec2(x+5, iy2), ImVec4toU32(t.accent, hov), 3)
        drawGlow(dl, x+3, (iy1+iy2)/2, 4, t.accent, hov*0.4)
    end
    local iconColor = lerpColor(t.text3, active and t.accent or t.text, hov)
    local iconDraw = iconDrawers[idx+1]
    if iconDraw then iconDraw(dl, x + 28, y + h/2, 20, iconColor) end
    local textColor = lerpColor(t.text3, active and t.accent or t.text, hov)
    -- Альтернатива (работает везде):
local navLabel = u8(navLabels[idx + 1] or "")
local navLabelSize = imgui.CalcTextSize(navLabel)
local textY = y + h / 2 - navLabelSize.y / 2
dl:AddText(imgui.ImVec2(x + 48, textY), ImVec4toU32(textColor), navLabel)
dl:AddText(imgui.ImVec2(x + 48.7, textY), ImVec4toU32(textColor, 0.5), navLabel) -- полужирный эффект
    return hovered and imgui.IsMouseClicked(0)
end

-- =========================================================================
-- ГЛАВНОЕ ОКНО
-- =========================================================================
imgui.OnFrame(
    function() return mainWindow.alpha > 0 end,
    function(self)
        self.HideCursor = not isAnyCursorWindowOpen()
        local t = T()
        -- Сбрасываем WindowPadding в начале кадра, чтобы прямые мутации стиля
        -- (setWindowPadding без Push/Pop) не накапливались между кадрами
        imgui.GetStyle().WindowPadding = imgui.ImVec2(0, 0)
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, mainWindow.alpha)
        setWindowPadding(0,0)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2,sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
        local dpi = clamp(settings.uiScale or 1.0, 0.5, 2.0)
        imgui.SetNextWindowSize(imgui.ImVec2(1100*dpi, 720*dpi), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowSizeConstraints(imgui.ImVec2(720*dpi, 460*dpi), imgui.ImVec2(1400*dpi, 920*dpi))
        local wF = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoTitleBar
        if mainWindow.alpha < 1 then wF = wF + imgui.WindowFlags.NoInputs end
        imgui.Begin("###snatch_main", mainWindowOpen, wF)
        if not mainWindowOpen[0] and mainWindow.state then mainWindow.switch2() end
        local dl = imgui.GetWindowDrawList(); local wp = imgui.GetWindowPos(); local ws = imgui.GetWindowSize()
        drawShadow(dl, wp.x, wp.y, wp.x+ws.x, wp.y+ws.y, 18, 8, 0.7)
        dl:AddRectFilled(imgui.ImVec2(wp.x, wp.y), imgui.ImVec2(wp.x+S.sidebarWidth, wp.y+ws.y), ImVec4toU32(t.sidebar), 18, 5)
        local logoPad = 1; local logoAreaY = wp.y + 16; local logoSize = S.sidebarWidth - logoPad * 2
        local logoCenterX = wp.x + S.sidebarWidth / 2
        local logoX1, logoY1 = wp.x + logoPad, logoAreaY
        local logoX2, logoY2 = wp.x + S.sidebarWidth - logoPad, logoAreaY + logoSize
        if textures.logo ~= nil then
            dl:AddImage(textures.logo, imgui.ImVec2(logoX1, logoY1), imgui.ImVec2(logoX2, logoY2), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), 0xFFFFFFFF)
        else
            local logoPulse = (math.sin(os.clock()*1.5)+1)*0.5
            drawGlow(dl, logoCenterX, logoAreaY + logoSize/2, 20, t.accent, 0.1+logoPulse*0.08)
            dl:AddRectFilled(imgui.ImVec2(logoX1, logoY1), imgui.ImVec2(logoX2, logoY2), ImVec4toU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.08 + logoPulse*0.04)), 16)
            dl:AddRect(imgui.ImVec2(logoX1, logoY1), imgui.ImVec2(logoX2, logoY2), ImVec4toU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.15)), 16)
            local shT = u8("SH"); local shS = imgui.CalcTextSize(shT)
            dl:AddText(imgui.ImVec2(logoCenterX - shS.x/2, logoAreaY + logoSize/2 - shS.y/2), ImVec4toU32(t.accent, 0.7), shT)
        end
        local titleY = logoAreaY + logoSize + 8
        local titleText2 = u8("Snatch Helper"); local titleSize2 = imgui.CalcTextSize(titleText2)
        dl:AddText(imgui.ImVec2(logoCenterX - titleSize2.x/2, titleY), ImVec4toU32(t.accent2, 0.9), titleText2)
        local verText = u8("by StepD"); local verSize = imgui.CalcTextSize(verText)
        dl:AddText(imgui.ImVec2(logoCenterX - verSize.x/2, titleY + 16), ImVec4toU32(t.text3, 0.5), verText)
        local sepY = titleY + 36; local sepInset = 20
        drawGrad(dl, wp.x + sepInset, sepY, (S.sidebarWidth - sepInset*2)/2, 1, imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.02), imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.15))
        drawGrad(dl, wp.x + S.sidebarWidth/2, sepY, (S.sidebarWidth - sepInset*2)/2, 1, imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.15), imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.02))
        local navStartY = sepY + 14; local navBtnH = 40
        for i = 0, 5 do
            if drawNavButton(dl, wp.x, navStartY + i*(navBtnH + 4), S.sidebarWidth, navBtnH, i, currentNav[0]==i) then
                S.prevNav = currentNav[0]; currentNav[0] = i; S.navTransition = 0
                -- Сбросить синхронизацию буферов настроек при смене вкладки
                if i ~= C.NAV_SETTINGS then B._settingsBufsSync = false end
            end
        end
        if S.navTransition < 1 then S.navTransition = math.min(S.navTransition + 0.06, 1) end
        local bottomY = wp.y + ws.y - 40
        if S.activeBinder then pulsingDot(dl, wp.x + 20, bottomY + 8, 4, t.yellow, 5)
            dl:AddText(imgui.ImVec2(wp.x + 32, bottomY), ImVec4toU32(t.yellow, 0.8), u8("Бинд активен"))
        else local greenPulse = (math.sin(os.clock()*1.5)+1)*0.5
            dl:AddCircleFilled(imgui.ImVec2(wp.x + 20, bottomY + 8), 4, ImVec4toU32(imgui.ImVec4(t.green.x,t.green.y,t.green.z,0.35+greenPulse*0.25)), 16)
            dl:AddText(imgui.ImVec2(wp.x + 32, bottomY), ImVec4toU32(t.green, 0.6), u8("Готов")) end
        dl:AddRectFilled(imgui.ImVec2(wp.x+S.sidebarWidth, wp.y+8), imgui.ImVec2(wp.x+S.sidebarWidth+1, wp.y+ws.y-8), ImVec4toU32(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.10)))
        dl:AddRectFilled(imgui.ImVec2(wp.x+S.sidebarWidth+1, wp.y), imgui.ImVec2(wp.x+ws.x, wp.y+S.headerHeight), ImVec4toU32(t.header), 18, 10)
        drawGradRounded(dl, wp.x+S.sidebarWidth+1, wp.y, ws.x - S.sidebarWidth - 1, 2, t.grad1, t.grad2, 18)
        dl:AddText(imgui.ImVec2(wp.x+S.sidebarWidth+22, wp.y+18), ImVec4toU32(t.text), u8(navLabels[currentNav[0]+1] or ""))
        local closeHov = anim("close_h", 0, 0.15)
        local closeCx = math.floor(wp.x + ws.x - 26)
        local closeCy = math.floor(wp.y + S.headerHeight / 2)
        imgui.SetCursorScreenPos(imgui.ImVec2(closeCx - 13, closeCy - 13))
        if imgui.InvisibleButton("##close_btn", imgui.ImVec2(26, 26)) then mainWindow.switch2(); mainWindowOpen[0] = false end
        if imgui.IsItemHovered() then anim("close_h", 1, 0.15) else anim("close_h", 0, 0.10) end
        local closeR = 11
        dl:AddCircleFilled(imgui.ImVec2(closeCx, closeCy), closeR,
            ImVec4toU32(imgui.ImVec4(t.red.x, t.red.y, t.red.z, 0.10 + closeHov * 0.38)), 20)
        if closeHov > 0.05 then
            drawGlow(dl, closeCx, closeCy, closeR, t.red, closeHov * 0.22)
        end
        local cs = 4.5
        local crossCol2 = ImVec4toU32(lerpColor(t.text3, imgui.ImVec4(1,1,1,1), closeHov))
        dl:AddLine(imgui.ImVec2(closeCx - cs, closeCy - cs), imgui.ImVec2(closeCx + cs, closeCy + cs), crossCol2, 1.8)
        dl:AddLine(imgui.ImVec2(closeCx + cs, closeCy - cs), imgui.ImVec2(closeCx - cs, closeCy + cs), crossCol2, 1.8)
        local infoText = u8("v" .. C.SCRIPT_VERSION .. " | " .. os.date("%H:%M")); local infoSize = imgui.CalcTextSize(infoText)
        dl:AddText(imgui.ImVec2(wp.x+ws.x-infoSize.x-48, wp.y+20), ImVec4toU32(t.text3), infoText)
        dl:AddRectFilled(imgui.ImVec2(wp.x+S.sidebarWidth+1, wp.y+S.headerHeight-1), imgui.ImVec2(wp.x+ws.x, wp.y+S.headerHeight), ImVec4toU32(imgui.ImVec4(t.text3.x,t.text3.y,t.text3.z,0.06)))
        imgui.SetCursorPos(imgui.ImVec2(S.sidebarWidth + 15, S.headerHeight))
        imgui.PushStyleColor(imgui.Col.ChildBg, t.bg)
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 0)
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildBorderSize, 0)
        imgui.BeginChild("##content", imgui.ImVec2(ws.x - S.sidebarWidth - 29, ws.y - S.headerHeight), false)
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, ease.outCubic(S.navTransition) * mainWindow.alpha)
        if currentNav[0] == C.NAV_DASHBOARD then drawDashboard()
        elseif currentNav[0] == C.NAV_BINDER then drawBinder()
        elseif currentNav[0] == C.NAV_REFERENCE then drawReference()
        elseif currentNav[0] == C.NAV_SETTINGS then drawSettings()
        elseif currentNav[0] == C.NAV_JOURNAL then drawJournal()
        elseif currentNav[0] == C.NAV_NOTES then drawNotes() end
        imgui.PopStyleVar(); imgui.EndChild()
        imgui.PopStyleVar(2); imgui.PopStyleColor()
        imgui.End(); imgui.PopStyleVar()
    end
)

-- =========================================================================
-- ОКНО ПЕРЕМЕННЫХ
-- =========================================================================
imgui.OnFrame(
    function() return U.showVarRef[0] end,
    function(self)
        local t = T()
        imgui.SetNextWindowSize(imgui.ImVec2(480, 500), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2+260,sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
        pushWindowPadding(18,14)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 18)
        imgui.Begin(u8(" Переменные"), U.showVarRef, imgui.WindowFlags.NoCollapse)
        secTitle("Доступные переменные")
        cardBegin("##vl", imgui.ImVec2(0, -80))
        local sortedVars = {}
        for n, e in pairs(simpleVariables) do table.insert(sortedVars, {n=n, d=e.desc}) end
        table.sort(sortedVars, function(a,b) return a.n < b.n end)
        for _, it in ipairs(sortedVars) do
            if U.fontMono then imgui.PushFont(U.fontMono) end
imgui.PushStyleColor(imgui.Col.Text, t.accent2)
imgui.Text(u8("{" .. it.n .. "}")); imgui.PopStyleColor()
if U.fontMono then imgui.PopFont() end
            imgui.SameLine(210); imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.Text(u8(it.d)); imgui.PopStyleColor()
            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                imgui.PushStyleColor(imgui.Col.Text, t.green)
                local ok, val = pcall(resolveVariable, it.n)
                imgui.Text(u8("= " .. (ok and val or "N/A")))
                imgui.PopStyleColor()
                imgui.EndTooltip()
            end
        end
        cardEnd(); imgui.Spacing()
        secTitle("Спецкоманды")
        imgui.PushStyleColor(imgui.Col.Text, t.accent2); imgui.Text(u8("[1500]")); imgui.PopStyleColor()
        imgui.SameLine(210); imgui.Text(u8("Пауза (мс)"))
        imgui.PushStyleColor(imgui.Col.Text, t.accent2); imgui.Text(u8("[wait_random:500,2000]")); imgui.PopStyleColor()
        imgui.SameLine(210); imgui.Text(u8("Случайная пауза"))
        imgui.Spacing()
        if btn(" Закрыть ", 100, 28, "accent") then U.showVarRef[0] = false end
        imgui.End(); imgui.PopStyleVar(2)
    end
)

-- =========================================================================
-- УНИВЕРСАЛЬНАЯ СИСТЕМА ДЕЙСТВИЙ (УЛУЧШЕНИЕ #13)
-- =========================================================================
local ActionSystem = {
    rpSteps = {
        gwarn = { "/do КПК находится на поясном держателе.", "/me берёт в руки свой КПК и включает его, авторизуется в системе ЭБГО.", "/me находит в системе профиль нужного гос.служащего, вносит в него корректировки.", "/do Изменения успешно сохранены - сотрудник наказан по решению агентов ФБР." },
        demoute = { "/do КПК находится на поясном держателе.", "/me берёт в руки свой КПК и включает его, авторизуется в системе ЭБГО.", "/me находит в системе профиль нужного гос.служащего, вносит в него корректировки.", "/do Изменения успешно сохранены - сотрудник наказан по решению агентов ФБР." },
        dismiss = { "/do КПК находится на поясном держателе.", "/me берёт в руки свой КПК и включает его, авторизуется в системе ЭБГО.", "/me находит в системе профиль нужного гос.служащего, вносит в него корректировки.", "/do Изменения успешно сохранены - сотрудник уволен по решению агентов ФБР." },
        wanted = {},
    },
    buildCommand = {
        gwarn = function(pid, reason, _) return safeFormat("/gwarn %d %s", pid, reason) end,
        demoute = function(pid, reason, extra) return safeFormat("/demoute %d %d %s", pid, extra.value or 0, reason) end,
        dismiss = function(pid, reason, _) return safeFormat("/dismiss %d %s", pid, reason) end,
        wanted = function(pid, reason, extra) local msg = "/su " .. pid; if extra.lvl then msg = msg .. " " .. extra.lvl end; msg = msg .. " " .. reason; return msg end,
    },
    notifyText = {
        gwarn = function(reason, _) return "Выдан выговор: " .. reason end,
        demoute = function(reason, extra) return "Demoute: " .. reason .. ", дней: " .. (extra.value or 0) end,
        dismiss = function(reason, _) return "Dismiss: " .. reason end,
        wanted = function(reason, extra) return "Розыск: " .. reason .. ", уровень: " .. (extra.lvl or "?") end,
    },
    activityType = { gwarn = "gwarn", demoute = "system", dismiss = "system", wanted = "uk" },
    activeFlags = { gwarn = false, demoute = false, dismiss = false, wanted = false },
}

local function sendActionRP(actionType, pid, reason, extra)
    extra = extra or {}
    if ActionSystem.activeFlags[actionType] then return end
    ActionSystem.activeFlags[actionType] = true

    local pname = (function()
        if sampIsPlayerConnected(pid) then
            return sampGetPlayerNickname(pid) or ("ID_" .. pid)
        end
        return "ID_" .. pid
    end)()

    local actText = actionType:upper() .. ": " .. pname .. "[" .. pid .. "] — " .. reason
    if extra.value then actText = actText .. " [" .. extra.value .. "]" end
    if extra.lvl then actText = actText .. " [" .. extra.lvl .. "]" end
    addActivity(actText, ActionSystem.activityType[actionType] or "system")

    local steps = ActionSystem.rpSteps[actionType]
    if steps then
        for _, s2 in ipairs(steps) do
            if S.stopCurrentBind then break end
            safeSendChat(s2)
            wait(settings.defaultDelay)
        end
    end

    if not S.stopCurrentBind then
        local cmdBuilder = ActionSystem.buildCommand[actionType]
        if cmdBuilder then
            local msg = cmdBuilder(pid, reason, extra)
            safeSendChat(msg)
            local nb = ActionSystem.notifyText[actionType]
            if nb then addNotification(nb(reason, extra), C.NOTIFY_SUCCESS) end
        end

        if extra.postSteps then
            for _, s2 in ipairs(extra.postSteps) do
                if S.stopCurrentBind then break end
                safeSendChat(s2)
                wait(settings.defaultDelay)
            end
        end

        -- Webhook
        webhookSend("bind_" .. actionType, {
            targetId = pid,
            targetName = pname,
            reason = reason,
        })
    end

    ActionSystem.activeFlags[actionType] = false
end

local function getPlayerNameById(id)
    if sampIsPlayerConnected(id) then return sampGetPlayerNickname(id) or ("ID_"..id) end; return nil
end

-- =========================================================================
-- GWARN/UK/DEMOUTE/DISMISS ОКНА
-- =========================================================================
local path_ustav_json = configDirectory .. "/ustav.json"
local ustav_data, ustav_names = {}, {}
local function load_ustav()
    if not doesFileExistSafe(path_ustav_json) then return end
    local f = io.open(path_ustav_json, 'r'); if not f then return end
    local c = f:read('*a'); f:close()
    local ok, data = pcall(decodeJson, c)
    if ok and type(data) == "table" then ustav_data = data; ustav_names = {}
        for _, u2 in ipairs(ustav_data) do if u2.name then table.insert(ustav_names, u2.name) end end end
end
load_ustav()

local path_uk_json = configDirectory .. "/uk.json"
local uk_data, uk_names = {}, {}
local function load_uk()
    if not doesFileExistSafe(path_uk_json) then return end
    local f = io.open(path_uk_json, 'r'); if not f then return end
    local c = f:read('*a'); f:close()
    local ok, data = pcall(decodeJson, c)
    if ok and type(data) == "table" then uk_data = data; uk_names = {}
        for _, s2 in ipairs(uk_data) do if s2.name then table.insert(uk_names, s2.name) end end end
end
load_uk()

local SumMenuWindow = imgui.new.bool(false)
local WantedMenuWindow = imgui.new.bool(false)
local DemouteMenuWindow = imgui.new.bool(false)
local demouteValueBuf = imgui.new.int(0)
local DismissMenuWindow = imgui.new.bool(false)

function isAnyCursorWindowOpen()
    return (mainWindow ~= nil and mainWindow.state) or S.keyBindPopupActive
        or (SumMenuWindow ~= nil and SumMenuWindow[0]) or (WantedMenuWindow ~= nil and WantedMenuWindow[0])
        or (DemouteMenuWindow ~= nil and DemouteMenuWindow[0]) or (DismissMenuWindow ~= nil and DismissMenuWindow[0])
        or (U.showVarRef ~= nil and U.showVarRef[0]) or (U.refDetailOpen ~= nil and U.refDetailOpen[0] and U.refDetailIdx > 0)
end

-- =========================================================================
-- КАРТОЧКА ЦЕЛИ (для gwarn/wanted/demoute/dismiss окон)
-- =========================================================================
local function getDistToPlayer(pid)
    local ok1, h = pcall(sampGetCharHandleBySampPlayerId, pid)
    if not ok1 or not h then return nil end
    local ok2, tx, ty, tz = pcall(getCharCoordinates, h)
    local ok3, mx, my, mz = pcall(getCharCoordinates, playerPed)
    if not ok2 or not ok3 then return nil end
    local dx, dy, dz = tx-mx, ty-my, tz-mz
    return math.floor(math.sqrt(dx*dx + dy*dy + dz*dz))
end

local function drawTargetCard(pid, name, actionLabel)
    local t, dl, sp, cw = T(), imgui.GetWindowDrawList(), imgui.GetCursorScreenPos(), imgui.GetContentRegionAvail().x
    dl:AddRectFilled(imgui.ImVec2(sp.x,sp.y), imgui.ImVec2(sp.x+cw,sp.y+52), ImVec4toU32(imgui.ImVec4(t.card.x,t.card.y,t.card.z,0.7)), 12)
    dl:AddRect(imgui.ImVec2(sp.x,sp.y), imgui.ImVec2(sp.x+cw,sp.y+52), ImVec4toU32(imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.18)), 12, 15, 0.5)
    dl:AddCircleFilled(imgui.ImVec2(sp.x+28,sp.y+26), 18, ImVec4toU32(imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.15)), 24)
    dl:AddCircle(imgui.ImVec2(sp.x+28,sp.y+26), 18, ImVec4toU32(imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.35)), 24, 0.8)
    local initSz = imgui.CalcTextSize(u8(name:upper():sub(1,2)))
    dl:AddText(imgui.ImVec2(sp.x+28-initSz.x/2, sp.y+26-initSz.y/2), ImVec4toU32(t.accent2,0.9), u8(name:upper():sub(1,2)))
    dl:AddText(imgui.ImVec2(sp.x+54, sp.y+8), ImVec4toU32(t.text,0.9), u8(name))
    local meta = {"ID: "..pid}
    local s1,sc = pcall(sampGetPlayerScore,pid); if s1 and sc then meta[#meta+1]="LVL "..sc end
    local s2,pg = pcall(sampGetPlayerPing,pid);  if s2 and pg then meta[#meta+1]=pg.."ms" end
    local ok3,h3 = pcall(sampGetCharHandleBySampPlayerId,pid)
    if ok3 and h3 then
        local o4,tx,ty,tz=pcall(getCharCoordinates,h3); local o5,mx,my,mz=pcall(getCharCoordinates,playerPed)
        if o4 and o5 then
            local dist=math.floor(math.sqrt((tx-mx)^2+(ty-my)^2+(tz-mz)^2))
            local ms=imgui.CalcTextSize(u8(table.concat(meta," · ")))
            dl:AddText(imgui.ImVec2(sp.x+54,sp.y+28), ImVec4toU32(t.text3,0.55), u8(table.concat(meta," · ")))
            dl:AddText(imgui.ImVec2(sp.x+54+ms.x,sp.y+28), ImVec4toU32(dist<=20 and t.green or (dist<=60 and t.yellow or t.text3),0.75), u8(" · "..dist.."м"))
        end
    else
        dl:AddText(imgui.ImVec2(sp.x+54,sp.y+28), ImVec4toU32(t.text3,0.55), u8(table.concat(meta," · ")))
    end
    local lsz=imgui.CalcTextSize(u8(actionLabel))
    dl:AddRectFilled(imgui.ImVec2(sp.x+cw-lsz.x-26,sp.y+17), imgui.ImVec2(sp.x+cw-8,sp.y+35), ImVec4toU32(imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.12)), 6)
    dl:AddText(imgui.ImVec2(sp.x+cw-lsz.x-20,sp.y+18), ImVec4toU32(t.accent2,0.8), u8(actionLabel))
    imgui.Dummy(imgui.ImVec2(cw, 58))
end

-- Универсальный рендер меню выбора причины с поиском
local function renderReasonMenu(windowBool, title, dataList, namesList, onSelect, searchBuf)
    local t = T()
    if #dataList == 0 then
        imgui.TextColored(imgui.ImVec4(1,0.2,0.2,1), u8("Данные не найдены!"))
        return
    end

    -- Строка поиска
    if searchBuf then
        imgui.PushItemWidth(-1)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
        imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(12, 8))
        imgui.InputTextWithHint("##rsearch_" .. title, u8("Поиск статьи или причины..."), searchBuf, ffi.sizeof(searchBuf))
        imgui.PopStyleVar(2); imgui.PopItemWidth()
        imgui.Spacing()
    end

    local query = searchBuf and trim(u8:decode(ffi.string(searchBuf)):lower()) or ""
    local isSearching = query ~= ""

    if isSearching then
        local found = 0
        for i, sec in ipairs(dataList) do
            if sec and sec.item then
                for j, item in ipairs(sec.item) do
                    local needle = (item.reason or "")..(item.text or "")..(item.lvl or "")
                    if needle:lower():find(query, 1, true) then
                        found = found + 1
                        local disp = item.reason or ("Пункт "..j)
                        if item.text then disp = disp.." — "..item.text:sub(1,80) end
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(t.card.x,t.card.y,t.card.z,0.5))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.14))
                        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(t.accent.x,t.accent.y,t.accent.z,0.25))
                        imgui.PushStyleColor(imgui.Col.Text, t.text)
                        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 10)
                        local sp3, cw3 = imgui.GetCursorScreenPos(), imgui.GetContentRegionAvail().x
                        if imgui.Button("##ri_"..title..i.."_"..j, imgui.ImVec2(cw3, 36)) then
                            windowBool[0] = false; onSelect(item)
                        end
                        imgui.PopStyleVar(); imgui.PopStyleColor(4)
                        local dl3 = imgui.GetWindowDrawList()
                        dl3:AddText(imgui.ImVec2(sp3.x+10, sp3.y+5), ImVec4toU32(t.text,0.88), u8(disp:sub(1,70)))
                        local sub3 = (namesList[i] or ""):sub(1,20); if item.lvl then sub3=sub3.."  ·  ст."..item.lvl end
                        dl3:AddText(imgui.ImVec2(sp3.x+10, sp3.y+22), ImVec4toU32(t.text3,0.5), u8(sub3))
                        dl3:AddCircleFilled(imgui.ImVec2(sp3.x+cw3-12, sp3.y+18), 3, ImVec4toU32(t.accent,0.5), 8)
                        imgui.Spacing()
                    end
                end
            end
        end
        if found == 0 then
            imgui.PushStyleColor(imgui.Col.Text, t.text3)
            imgui.Text(u8("Нет совпадений")); imgui.PopStyleColor()
        end
    else
        -- Режим аккордеона (без поиска — стандартный)
        for i, name in ipairs(namesList) do
            if imgui.CollapsingHeader(u8(name) .. "##sec" .. title .. i) then
                imgui.Indent(16); local sec = dataList[i]
                if sec and sec.item then
                    for j, item in ipairs(sec.item) do
                        local txt = item.reason or ("Пункт " .. j)
                        if item.text then txt = txt .. " — " .. item.text:sub(1,80) end
                        if item.lvl then txt = txt .. "  [ст." .. item.lvl .. "]" end
                        if btn(txt .. "##" .. title .. i .. "_" .. j, -1, 28, "default") then
                            windowBool[0] = false; onSelect(item)
                        end; imgui.Spacing()
                    end
                end
                imgui.Unindent(16)
            end
        end
    end
end

imgui.OnFrame(function() return SumMenuWindow[0] end, function(self)
 local t = T()
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2,sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(800, 620), imgui.Cond.FirstUseEver)
    pushWindowPadding(16,12); imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 18)
    imgui.Begin(u8(" Выговор"), SumMenuWindow, imgui.WindowFlags.NoCollapse)
    drawTargetCard(S.selectedPlayerId, S.selectedPlayerName, "GWARN")
    if btn("УК##gwTab0", 140, 32, S.gwarnTabIdx == 0 and "accent" or "ghost") then S.gwarnTabIdx = 0; ffi.copy(B.gwarnSearch, "") end
    imgui.SameLine(0, 8)
    if btn("Уставы##gwTab1", 140, 32, S.gwarnTabIdx == 1 and "accent" or "ghost") then S.gwarnTabIdx = 1; ffi.copy(B.gwarnSearch, "") end
    imgui.Spacing(); thinSep(); imgui.Spacing()
    imgui.BeginChild("##gwarnScroll", imgui.ImVec2(0, -50), false)
    local gwData = S.gwarnTabIdx == 0 and uk_data or ustav_data
    local gwNames = S.gwarnTabIdx == 0 and uk_names or ustav_names
    renderReasonMenu(SumMenuWindow, "gw", gwData, gwNames, function(item)
        local pid, reason = S.selectedPlayerId, item.reason
        lua_thread.create(function() sendActionRP("gwarn", pid, reason) end)
    end, B.gwarnSearch)
    imgui.EndChild(); imgui.Spacing(); thinSep()
    imgui.SetCursorPosX(imgui.GetWindowWidth()/2 - 50)
    if btn("Отмена", 100, 28, "accent") then SumMenuWindow[0] = false end
    imgui.End(); imgui.PopStyleVar(2)
end)

imgui.OnFrame(function() return WantedMenuWindow[0] end, function(self)
local t = T()
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2,sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5,0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(800, 620), imgui.Cond.FirstUseEver)
    pushWindowPadding(16,12); imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 18)
    imgui.Begin(u8(" Розыск"), WantedMenuWindow, imgui.WindowFlags.NoCollapse)
    drawTargetCard(S.selectedWantedPlayerId, S.selectedWantedPlayerName, "WANTED")
    imgui.BeginChild("##wantedScroll", imgui.ImVec2(0, -50), false)
    renderReasonMenu(WantedMenuWindow, "uk", uk_data, uk_names, function(item)
        local pid, reason, lvl = S.selectedWantedPlayerId, item.reason, item.lvl
        lua_thread.create(function()
            sendActionRP("wanted", pid, reason, { lvl = lvl, postSteps = {
                "/me сняв КПК с пояса и открыв базу данных, начал поиск по описанию преступника",
                "/me найдя необходимого человека, внес его в список розыскиваемых лиц",
                "/do КПК: Преступник был успешно объявлен, по статье: " .. reason .. ", степень: " .. (lvl or "?")
            }})
        end)
    end, B.wantedSearch)
    imgui.EndChild(); imgui.Spacing(); thinSep()
    imgui.SetCursorPosX(imgui.GetWindowWidth()/2 - 50)
    if btn("Отмена", 100, 28, "accent") then WantedMenuWindow[0] = false end
    imgui.End(); imgui.PopStyleVar(2)
end)

imgui.OnFrame(function() return DemouteMenuWindow[0] end, function(self)
local t = T()
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(820, 650), imgui.Cond.FirstUseEver)
    pushWindowPadding(16, 12); imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 18)
    imgui.Begin(u8(" Умный Demoute"), DemouteMenuWindow, imgui.WindowFlags.NoCollapse)
    drawTargetCard(S.selectedDemoutePlayerId, S.selectedDemoutePlayerName, "DEMOUTE")
    imgui.PushStyleColor(imgui.Col.Text, t.text2); imgui.Text(u8("Дней запрета (0-14):")); imgui.PopStyleColor()
    imgui.SameLine(0, 10); imgui.PushItemWidth(120); imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    imgui.InputInt("##demouteVal", demouteValueBuf, 1, 1); imgui.PopStyleVar(); imgui.PopItemWidth()
    demouteValueBuf[0] = clamp(demouteValueBuf[0], 0, 14)
    imgui.SameLine(0, 20); badge("Текущее: " .. demouteValueBuf[0], t.accent2)
    imgui.Spacing(); thinSep(); imgui.Spacing()
    if btn("УК##demTab0", 140, 32, S.demouteTabIdx == 0 and "accent" or "ghost") then S.demouteTabIdx = 0; ffi.copy(B.demSearch, "") end
    imgui.SameLine(0, 8)
    if btn("Уставы##demTab1", 140, 32, S.demouteTabIdx == 1 and "accent" or "ghost") then S.demouteTabIdx = 1; ffi.copy(B.demSearch, "") end
    imgui.Spacing(); thinSep(); imgui.Spacing()
    imgui.BeginChild("##demouteScroll", imgui.ImVec2(0, -50), false)
    local demData = S.demouteTabIdx == 0 and uk_data or ustav_data
    local demNames = S.demouteTabIdx == 0 and uk_names or ustav_names
    renderReasonMenu(DemouteMenuWindow, "dem", demData, demNames, function(item)
        local pid, reason, val = S.selectedDemoutePlayerId, item.reason, demouteValueBuf[0]
        lua_thread.create(function() sendActionRP("demoute", pid, reason, { value = val }) end)
    end, B.demSearch)
    imgui.EndChild(); imgui.Spacing(); thinSep()
    imgui.SetCursorPosX(imgui.GetWindowWidth() / 2 - 50)
    if btn("Отмена", 100, 28, "accent") then DemouteMenuWindow[0] = false end
    imgui.End(); imgui.PopStyleVar(2)
end)

imgui.OnFrame(function() return DismissMenuWindow[0] end, function(self)
local t = T()
    imgui.SetNextWindowPos(imgui.ImVec2(sizeX/2, sizeY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(820, 620), imgui.Cond.FirstUseEver)
    pushWindowPadding(16, 12); imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 18)
    imgui.Begin(u8(" Умный Dismiss"), DismissMenuWindow, imgui.WindowFlags.NoCollapse)
    drawTargetCard(S.selectedDismissPlayerId, S.selectedDismissPlayerName, "DISMISS")
    if btn("УК##disTab0", 140, 32, S.dismissTabIdx == 0 and "accent" or "ghost") then S.dismissTabIdx = 0; ffi.copy(B.disSearch, "") end
    imgui.SameLine(0, 8)
    if btn("Уставы##disTab1", 140, 32, S.dismissTabIdx == 1 and "accent" or "ghost") then S.dismissTabIdx = 1; ffi.copy(B.disSearch, "") end
    imgui.Spacing(); thinSep(); imgui.Spacing()
    imgui.BeginChild("##dismissScroll", imgui.ImVec2(0, -50), false)
    local disData = S.dismissTabIdx == 0 and uk_data or ustav_data
    local disNames = S.dismissTabIdx == 0 and uk_names or ustav_names
    renderReasonMenu(DismissMenuWindow, "dis", disData, disNames, function(item)
        local pid, reason = S.selectedDismissPlayerId, item.reason
        lua_thread.create(function() sendActionRP("dismiss", pid, reason) end)
    end, B.disSearch)
    imgui.EndChild(); imgui.Spacing(); thinSep()
    imgui.SetCursorPosX(imgui.GetWindowWidth() / 2 - 50)
    if btn("Отмена", 100, 28, "accent") then DismissMenuWindow[0] = false end
    imgui.End(); imgui.PopStyleVar(2)
end)

-- =========================================================================
-- ИНИЦИАЛИЗАЦИЯ
-- =========================================================================
imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    applyTheme(settings.currentTheme)

    local imguiIO = imgui.GetIO()
    local cyrillic = imguiIO.Fonts:GetGlyphRangesCyrillic()
    local fontsDir = configDirectory .. "/fonts/"
    ensureDirectory(fontsDir)

    -- Хелпер: загрузить шрифт или fallback
    local function loadFont(primaryPath, fallbackPath, size)
        if doesFileExist(primaryPath) then
            return imguiIO.Fonts:AddFontFromFileTTF(primaryPath, size, nil, cyrillic)
        elseif doesFileExist(fallbackPath) then
            return imguiIO.Fonts:AddFontFromFileTTF(fallbackPath, size, nil, cyrillic)
        end
        return nil
    end

    -- ============================================
    -- ВЫБЕРИ ОДИН ВАРИАНТ И РАСКОММЕНТИРУЙ:
    -- ============================================

    -- ВАРИАНТ A: Montserrat (геометричный, модный)
    local fontRegular  = fontsDir .. "Montserrat-Regular.ttf"
    local fontSemibold = fontsDir .. "Montserrat-SemiBold.ttf"
    local fontBold     = fontsDir .. "Montserrat-Bold.ttf"

    -- ВАРИАНТ B: Nunito (округлый, мягкий)
    -- local fontRegular  = fontsDir .. "Nunito-Regular.ttf"
    -- local fontSemibold = fontsDir .. "Nunito-SemiBold.ttf"
    -- local fontBold     = fontsDir .. "Nunito-Bold.ttf"

    -- ВАРИАНТ C: Exo 2 (футуристичный)
    -- local fontRegular  = fontsDir .. "Exo2-Regular.ttf"
    -- local fontSemibold = fontsDir .. "Exo2-SemiBold.ttf"
    -- local fontBold     = fontsDir .. "Exo2-Bold.ttf"

    -- ВАРИАНТ D: Rubik (игровой)
    -- local fontRegular  = fontsDir .. "Rubik-Regular.ttf"
    -- local fontSemibold = fontsDir .. "Rubik-SemiBold.ttf"
    -- local fontBold     = fontsDir .. "Rubik-Bold.ttf"

    -- Fallback пути (Windows)
    local fallbackRegular  = "C:/Windows/Fonts/segoeui.ttf"
    local fallbackSemibold = "C:/Windows/Fonts/seguisb.ttf"
    local fallbackMono     = "C:/Windows/Fonts/consola.ttf"

    -- Основной шрифт (первый = по умолчанию)
    loadFont(fontRegular, fallbackRegular, 15.0)

    -- Полужирный для секций
    U.fontSemibold = loadFont(fontSemibold, fallbackSemibold, 16.0)

    -- Крупный для заголовков
    U.fontTitle = loadFont(fontBold, fallbackSemibold, 24.0)

    -- Средний для чисел в карточках
    U.fontMedium = loadFont(fontSemibold, fallbackSemibold, 18.0)

    -- Моноширинный для шагов
    local monoPath = fontsDir .. "JetBrainsMono-Regular.ttf"
    U.fontMono = loadFont(monoPath, fallbackMono, 13.0)

    -- Логотип
    local logoPath = configDirectory .. "/logo.png"
    if doesFileExist(logoPath) then
        local success, texture = pcall(imgui.CreateTextureFromFile, logoPath)
        if success and texture ~= nil then textures.logo = texture end
    end

    -- Аватарка
    local avatarPath = configDirectory .. "/avatar.png"
    if doesFileExist(avatarPath) then
        local success, texture = pcall(imgui.CreateTextureFromFile, avatarPath)
        if success and texture ~= nil then textures.avatar = texture end
    end
end)

-- =========================================================================
-- SAMPEV (УЛУЧШЕНИЕ #29 — pcall)
-- =========================================================================
function sampev.onServerMessage(color, text)
    local ok, result = pcall(function()
        -- === ПОДСВЕТКА СОЗДАТЕЛЯ ===
        local nickPos = text:find(creatorNick, 1, true)
        if nickPos then
            -- Цвет из параметра color (RRGGBBAA — первые 3 байта)
            local baseHex = "FFFFFF"
            if type(color) == "number" then
                local n = color
                if n < 0 then n = n + 0x100000000 end
                local hex = string.format("%08X", n)
                baseHex = hex:sub(1, 6)
            end

            -- Проверить [ID] или (ID) после ника
            local afterNick = text:sub(nickPos + #creatorNick)
            local bracket = afterNick:match("^(%[%d+%])") or afterNick:match("^(%(%d+%))")
            local skipLen = #creatorNick + (bracket and #bracket or 0)

            -- Собрать и вставить
            local highlighted = buildCreatorNick(baseHex, bracket)
            local newText = text:sub(1, nickPos - 1) .. highlighted .. text:sub(nickPos + skipLen)
            return {color, newText}
        end

        -- === AUTOFIND ===
        if autoFind.active and autoFind.lastId ~= -1 then
            local foundNick = text:match("Местоположение (%S+)%[%d+%] отмечено на карте")
            if foundNick then
                local cleanNick = foundNick:gsub('{.-}', '')
                if cleanNick ~= autoFind.lastNick then
                    addNotification("AutoFind: " .. autoFind.lastNick .. " вышел!", C.NOTIFY_WARNING)
                    afReset()
                end
                if autoFind.waitInta then
                    addNotification("AutoFind: " .. autoFind.lastNick .. " вышел из интерьера!", C.NOTIFY_INFO)
                    autoFind.waitInta = false
                end
                return false
            end
            if text:find("Игрок находится в", 1, true) then
                if not autoFind.waitInta then
                    addNotification("AutoFind: " .. autoFind.lastNick .. " зашёл в интерьер!", C.NOTIFY_WARNING)
                    autoFind.waitInta = true
                end
                return false
            end
        end
        return nil  -- пропустить событие дальше
    end)
    if not ok then print("[SH] onServerMessage error: " .. tostring(result)); return nil end
    return result
end

function sampev.onShowTextDraw(id, data)
    local ok, result = pcall(function()
        if autoFind.active and data and data.text and string.find(data.text, "GPS") then return false end
        return nil
    end)
    if not ok then print("[SH] onShowTextDraw error: " .. tostring(result)); return nil end
    return result
end

function sampev.onTextDrawSetString(id, text)
    local ok, result = pcall(function()
        if autoFind.active and string.find(text, "GPS") then return false end
        return nil
    end)
    if not ok then print("[SH] onTextDrawSetString error: " .. tostring(result)); return nil end
    return result
end

-- =========================================================================
-- MEMBERS OVERLAY: ПАРСЕР
-- =========================================================================
function sampev.onShowDialog(dialogid, style, title, button1, button2, text)
    local ok, result = pcall(function()
        if not membersOverlay.isChecking then return end
        local isMembersDialog = title:find('(.+)%(В сети') or title:find('В сети всего') or title:find('members') or title:find('Члены организации') or title:find('Состав')
        if not isMembersDialog then return end
        local fracName = title:match('(.+)%(В сети') or ""
        if fracName ~= "" then membersOverlay.fraction = fracName:gsub('{.-}', ''):gsub('%s+$', '') end
        local next_page, next_page_i, count = false, 0, 0
        for line in text:gmatch('[^\r\n]+') do
            count = count + 1
            if not line:find('страница') and not line:find('Ник') and not line:find('Имя') and not line:find('Название') then
                local optional_info = ''
                if line:find('{FFA500}%(Вы%)') then line = line:gsub("{FFA500}%(Вы%)", "") end
                if line:find(' / В деморгане') then line = line:gsub(" / В деморгане", ""); optional_info = optional_info .. ' (JAIL)' end
                if line:find(' / MUTED') then line = line:gsub(" / MUTED", ""); optional_info = optional_info .. ' (MUTE)' end
                local color2, nickname, id, rank, rank_number = nil, nil, nil, nil, nil
                local warns, afk = "0", "0"
                color2, nickname, id, rank, rank_number, _, _, warns, afk =
                    line:match("{(%x%x%x%x%x%x)}([%w_]+)%((%d+)%)%s*([^%(]+)%((%d+)%)%s*{(%x%x%x%x%x%x)}%(([^%)]+)%)%s*{FFFFFF}(%d+)%s*%[%d+%]%s*/%s*(%d+)%s*%d+ шт")
                if not nickname then
                    color2, nickname, id, rank, rank_number, _, warns, afk =
                        line:match("{(%x%x%x%x%x%x)}%s*([^%(]+)%((%d+)%)%s*([^%(]+)%((%d+)%)%s*([^{}]+){FFFFFF}%s*(%d+)%s*%[%d+%]%s*/%s*(%d+)%s*%d+ шт")
                end
                if not nickname then
                    nickname, id, rank, rank_number, warns = line:match("(.+)%((%d+)%)%s+(.+)%((%d+)%).+(%d) / 3")
                    if nickname then color2 = "FFFFFF" end
                end
                if not nickname then
                    nickname, id, rank, rank_number = line:match("([%w_]+)%((%d+)%)%s+(.-)%((%d+)%)")
                    if nickname then color2 = "FFFFFF" end
                end
                if nickname and id then
                    nickname = nickname:gsub('{.-}', ''):gsub('^%s+', ''):gsub('%s+$', '')
                    if rank then rank = rank:gsub('{.-}', ''):gsub('%s+$', ''):gsub('^%s+', '') end
                    local working = color2 and color2:find('90EE90') and true or false
                    table.insert(membersOverlay.tempList, {
                        nick = nickname, id = tonumber(id) or 0, rank = rank or "?",
                        rank_number = tonumber(rank_number) or 0, afk = tonumber(afk) or 0,
                        warns = tonumber(warns) or 0, working = working, info = optional_info })
                end
            end
            if line:match('Следующая страница') then next_page = true; next_page_i = count - 2 end
        end
        if next_page then sampSendDialogResponse(dialogid, 1, next_page_i, 0); return false end
        if #membersOverlay.tempList > 0 then
            membersOverlay.list = membersOverlay.tempList; membersOverlay.tempList = {}
            membersOverlay.lastUpdate = os.clock(); membersOverlay.isChecking = false
            membersOverlay._checkStartTime = nil
            membersOverlay._parseFailCount = 0; S.membersOverlayVisible = true
        else
            membersOverlay.tempList = {}; membersOverlay.isChecking = false
            membersOverlay._checkStartTime = nil
            membersOverlay._parseFailCount = (membersOverlay._parseFailCount or 0) + 1
            if membersOverlay._parseFailCount >= 3 then
                addNotification("Members: неизвестный формат (3 попытки)", C.NOTIFY_ERROR)
                membersOverlay._parseFailCount = 0
            else
                addNotification("Members: список пуст! (попытка " .. membersOverlay._parseFailCount .. "/3)", C.NOTIFY_WARNING)
            end
        end
        sampSendDialogResponse(dialogid, 0, 0, 0); return false
    end)
    if not ok then print("[SH] onShowDialog error: " .. tostring(result)); membersOverlay.isChecking = false; membersOverlay._checkStartTime = nil end
    return result
end

-- Хелпер: строит текст списка Members для копирования (избегает дублирование)
local function buildMembersList()
    local lines = {}
    local frac = membersOverlay.fraction ~= "" and (membersOverlay.fraction .. " | ") or ""
    table.insert(lines, frac .. "Online: " .. #membersOverlay.list)
    for _, m in ipairs(membersOverlay.list) do
        local extras = {}
        if m.afk and m.afk > 0 then table.insert(extras, "AFK") end
        if m.warns and m.warns > 0 then table.insert(extras, "W:" .. m.warns) end
        if m.info and m.info ~= "" and m.info ~= "-" then
            table.insert(extras, m.info)
        end
        local extStr = #extras > 0 and (" [" .. table.concat(extras, ", ") .. "]") or ""
        table.insert(lines, m.nick .. "(" .. m.id .. ") [" .. (m.rank_number or 0) .. "]" .. extStr)
    end
    return table.concat(lines, "\n")
end

-- =========================================================================
-- MEMBERS OVERLAY: РЕНДЕР (УЛУЧШЕНИЕ #28)
-- =========================================================================
-- =========================================================================
-- MEMBERS OVERLAY: РЕНДЕР (исправлено обрезание текста)
-- =========================================================================
imgui.OnFrame(
    function() return settings.showMembersOverlay and S.membersOverlayVisible end,
    function(self)
        local t = T(); local now = os.clock()
        local cursorActive = isAnyCursorWindowOpen()
        self.HideCursor = not cursorActive

        local lineH, maxVisible = 20, 25
        local hasData = #membersOverlay.list > 0
        local listCount = hasData and math.min(#membersOverlay.list, maxVisible) or 0

        -- Таймаут для isChecking
        if membersOverlay.isChecking and membersOverlay._checkStartTime then
            if now - membersOverlay._checkStartTime > 15 then
                membersOverlay.isChecking = false
                membersOverlay.tempList = {}
                membersOverlay._checkStartTime = nil
            end
        end

        -- === СБОР ДАННЫХ И РАСЧЁТ МАКСИМАЛЬНОЙ ШИРИНЫ ===
        local entries = {}  -- {nick, id, rankNum, afk, warns, info, working, isTruncated}
        local maxTextW = 0

        if U.fontSemibold then imgui.PushFont(U.fontSemibold) end

        -- Заголовок
        local headerStr = u8("Online: " .. (hasData and #membersOverlay.list or 0)
            .. (membersOverlay.fraction ~= "" and ("  " .. membersOverlay.fraction) or ""))
        local headerW = imgui.CalcTextSize(headerStr).x
        if headerW > maxTextW then maxTextW = headerW end

        if hasData then
            for i = 1, listCount do
                local m = membersOverlay.list[i]
                -- Строка: ник + (id) [ранг]
                local nickStr = u8(m.nick .. "(" .. m.id .. ")")
                local nickW = imgui.CalcTextSize(nickStr).x
                -- Бейдж ранга
                local rankStr = u8("[" .. m.rank_number .. "]")
                local rankW = imgui.CalcTextSize(rankStr).x + 8  -- +8 = padding pill
                local rowW = 12 + nickW + 6 + rankW  -- 12=dot, 6=gap
                -- Суффикс состояния
                local suffix = ""
                if m.afk and m.afk > 0 then suffix = suffix .. " AFK" end
                if m.warns and m.warns > 0 then suffix = suffix .. " W" .. m.warns end
                if m.info and m.info ~= "" and m.info ~= "-" then suffix = suffix .. " " .. trim(m.info) end
                local sfxW = 0
                if suffix ~= "" then
                    sfxW = imgui.CalcTextSize(u8(suffix)).x + 4
                    rowW = rowW + sfxW
                end
                if rowW > maxTextW then maxTextW = rowW end
                table.insert(entries, { m = m, nickStr = nickStr, nickW = nickW,
                    rankStr = rankStr, rankW = rankW, suffix = suffix, sfxW = sfxW })
            end
            if #membersOverlay.list > maxVisible then
                local str = u8("+ " .. (#membersOverlay.list - maxVisible) .. " ещё")
                local w = imgui.CalcTextSize(str).x
                if w > maxTextW then maxTextW = w end
            end
        else
            local str = membersOverlay.isChecking
                and u8("Загрузка" .. string.rep(".", math.floor(now * 2) % 4))
                or u8("Ожидание данных...")
            local w = imgui.CalcTextSize(str).x
            if w > maxTextW then maxTextW = w end
        end

        if U.fontSemibold then imgui.PopFont() end

        local overlayW = maxTextW + 24
        membersOverlay.cachedW = overlayW

        -- Позиция правого края
        local rightEdge = settings.membersOverlayRightX
        if rightEdge < 0 then rightEdge = sizeX - 10 end
        local topY = settings.membersOverlayPosY
        if topY < 0 then topY = 80 end
        if rightEdge > sizeX then rightEdge = sizeX - 10 end
        if topY < 0 then topY = 0 end
        if topY > sizeY - 40 then topY = sizeY - 40 end

        local posX = rightEdge - overlayW

        if not cursorActive or not membersOverlay.dragActive then
            imgui.SetNextWindowPos(imgui.ImVec2(posX, topY), imgui.Cond.Always)
            if cursorActive then membersOverlay.dragActive = true end
        end
        if not cursorActive then membersOverlay.dragActive = false end

        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 0)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
        setWindowPadding(0, 0)
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))

        local fl = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoScrollbar
            + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoCollapse
            + imgui.WindowFlags.NoBackground + imgui.WindowFlags.AlwaysAutoResize
        if not cursorActive then
            fl = fl + imgui.WindowFlags.NoInputs + imgui.WindowFlags.NoMove
        end

        imgui.Begin("##members_overlay_float", nil, fl)

        if U.fontSemibold then imgui.PushFont(U.fontSemibold) end
        imgui.Dummy(imgui.ImVec2(overlayW, 0))

        local dl = imgui.GetWindowDrawList()
        local wp = imgui.GetWindowPos()
        local curY = wp.y + 6

        -- Заголовок
        local hdrSz = imgui.CalcTextSize(headerStr)
        dl:AddText(imgui.ImVec2(wp.x + overlayW - hdrSz.x - 6, curY),
            ImVec4toU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, 0.85)), headerStr)
        dl:AddText(imgui.ImVec2(wp.x + overlayW - hdrSz.x - 5, curY),
            ImVec4toU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, 0.45)), headerStr)
        curY = curY + 22

        -- Разделитель
        dl:AddLine(imgui.ImVec2(wp.x + 4, curY), imgui.ImVec2(wp.x + overlayW - 4, curY),
            ImVec4toU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.12)), 0.5)
        curY = curY + 6

        if hasData then
            -- Ранговые цвета (1-4 серый, 5-7 синий, 8-9 золото, 10+ пурпур)
            local function getRankColor(rn)
                if rn >= 10 then return imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 1) end
                if rn >= 8  then return imgui.ImVec4(t.yellow.x, t.yellow.y, t.yellow.z, 1) end
                if rn >= 5  then return imgui.ImVec4(t.blue.x, t.blue.y, t.blue.z, 1) end
                return imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 1)
            end

            for _, e in ipairs(entries) do
                local m = e.m
                local rowX = wp.x + 6

                -- Статус-точка (зелёная = онлайн/работает, жёлтая = AFK, красная = JAIL/деморган)
                local dotCol
                if m.info and (m.info:find("JAIL") or m.info:find("деморган")) then
                    dotCol = imgui.ImVec4(t.red.x, t.red.y, t.red.z, 0.9)
                elseif m.afk and m.afk > 0 then
                    dotCol = imgui.ImVec4(t.yellow.x, t.yellow.y, t.yellow.z, 0.9)
                elseif m.working then
                    dotCol = imgui.ImVec4(t.green.x, t.green.y, t.green.z, 0.9)
                else
                    dotCol = imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.4)
                end
                dl:AddCircleFilled(imgui.ImVec2(rowX + 3, curY + 7), 3.5, ImVec4toU32(dotCol), 10)
                -- Свечение для онлайн-точки
                if m.working and not (m.afk and m.afk > 0) then
                    dl:AddCircle(imgui.ImVec2(rowX + 3, curY + 7), 5.5,
                        ImVec4toU32(imgui.ImVec4(dotCol.x, dotCol.y, dotCol.z, 0.25)), 12, 0.5)
                end

                -- Ник + ID
                local nickAlpha = (m.afk and m.afk > 0) and 0.50 or 0.88
                dl:AddText(imgui.ImVec2(rowX + 10, curY), ImVec4toU32(t.text, nickAlpha), e.nickStr)

                -- Ранг-бейдж справа
                local rc = getRankColor(m.rank_number)
                local rankPillW = e.rankW
                local pillX2 = wp.x + overlayW - rankPillW - 4
                local pillY2 = curY + 1
                dl:AddRectFilled(imgui.ImVec2(pillX2, pillY2),
                    imgui.ImVec2(pillX2 + rankPillW, pillY2 + 13),
                    ImVec4toU32(imgui.ImVec4(rc.x, rc.y, rc.z, 0.12)), 4)
                dl:AddText(imgui.ImVec2(pillX2 + 4, pillY2 + 1),
                    ImVec4toU32(imgui.ImVec4(rc.x, rc.y, rc.z, 0.80)), e.rankStr)

                -- Суффикс (MUTE/AFK-время)
                if e.suffix ~= "" then
                    dl:AddText(imgui.ImVec2(pillX2 - e.sfxW - 2, curY),
                        ImVec4toU32(imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.40)), u8(e.suffix))
                end

                curY = curY + lineH
            end
            if #membersOverlay.list > maxVisible then
                local moreStr = u8("+ " .. (#membersOverlay.list - maxVisible) .. " ещё")
                local moreSz = imgui.CalcTextSize(moreStr)
                dl:AddText(imgui.ImVec2(wp.x + overlayW - moreSz.x - 6, curY),
                    ImVec4toU32(imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.30)), moreStr)
                curY = curY + lineH
            end
        else
            local statusStr = membersOverlay.isChecking
                and u8("Загрузка" .. string.rep(".", math.floor(now * 2) % 4))
                or u8("Ожидание данных...")
            local statusSz = imgui.CalcTextSize(statusStr)
            local statusCol = membersOverlay.isChecking
                and imgui.ImVec4(t.yellow.x, t.yellow.y, t.yellow.z, 0.7)
                or imgui.ImVec4(t.text3.x, t.text3.y, t.text3.z, 0.5)
            dl:AddText(imgui.ImVec2(wp.x + overlayW - statusSz.x - 6, curY),
                ImVec4toU32(statusCol), statusStr)
            curY = curY + lineH
        end

        imgui.Dummy(imgui.ImVec2(overlayW, curY - wp.y))

        -- Кнопка "Копировать список" — только когда курсор активен
        if cursorActive and hasData then
            imgui.Spacing()
            -- высота 0 = авторазмер по шрифту + FramePadding, чтобы текст не обрезался
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 10)
            imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(8, 5))
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(t.card.x, t.card.y, t.card.z, 0.72))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.22))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.40))
            imgui.PushStyleColor(imgui.Col.Text, t.accent2)
            if imgui.Button(u8("[ Копировать список ]"), imgui.ImVec2(overlayW, 0)) then
                copyToClipboard(buildMembersList(), "Список скопирован (" .. #membersOverlay.list .. " чел.)")
            end
            imgui.PopStyleColor(4); imgui.PopStyleVar(2)
            imgui.Dummy(imgui.ImVec2(0, 2)) -- нижний отступ
        end

        if U.fontSemibold then imgui.PopFont() end

        -- Сохранение позиции при перетаскивании
        if cursorActive then
            local ws = imgui.GetWindowSize()
            local newRX = wp.x + ws.x
            local newPY = wp.y
            if math.abs(newRX - settings.membersOverlayRightX) > 2 or math.abs(newPY - settings.membersOverlayPosY) > 2 then
                settings.membersOverlayRightX = newRX
                settings.membersOverlayPosY = newPY
                S.overlayDebounceSave = os.clock() + 1.0
            end
        end

        imgui.End()
        imgui.PopStyleColor()
        imgui.PopStyleVar(2)
    end
)

-- =========================================================================
-- MAIN
-- =========================================================================
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    initVariables(); registerBindCommands(); loadActivityLog(); QA:load()
    sampRegisterChatCommand("snatch", function() mainWindow.switch(); mainWindowOpen[0] = mainWindow.state end)

    sampRegisterChatCommand("rpguns", function()
        -- Открывает меню Snatch Helper на вкладке Настройки ? РП оружие
        if not mainWindow.state then mainWindow.switch(); mainWindowOpen[0] = true end
        currentNav[0] = C.NAV_SETTINGS
        addNotification("РП оружие: открыто в Настройки ? РП отыгрыш оружия", C.NOTIFY_INFO)
    end)

    sampRegisterChatCommand("gw", function(arg)
        if not settings.enableGwarn then sampAddChatMessage("{FF0000}[SH]{FFFFFF} /gw отключён", -1); return end
        if ActionSystem.activeFlags.gwarn then addNotification("Занят!", C.NOTIFY_WARNING); return end
        local id = tonumber(arg); if not id or id < 0 or id > 999 then sampAddChatMessage("{FF0000}[SH]{FFFFFF} /gw [ID]", -1); return end
        local name = getPlayerNameById(id); if not name then addNotification("Не найден!", C.NOTIFY_ERROR); return end
        if #ustav_data == 0 then addNotification("ustav.json!", C.NOTIFY_ERROR); return end
        S.selectedPlayerId = id; S.selectedPlayerName = name; SumMenuWindow[0] = true
    end)

    sampRegisterChatCommand("uk", function(arg)
        if not settings.enableUk then sampAddChatMessage("{FF0000}[SH]{FFFFFF} /uk отключён", -1); return end
        if ActionSystem.activeFlags.wanted then addNotification("Занят!", C.NOTIFY_WARNING); return end
        local id = tonumber(arg); if not id or id < 0 or id > 999 then sampAddChatMessage("{FF0000}[SH]{FFFFFF} /uk [ID]", -1); return end
        local name = getPlayerNameById(id); if not name then addNotification("Не найден!", C.NOTIFY_ERROR); return end
        if #uk_data == 0 then addNotification("uk.json!", C.NOTIFY_ERROR); return end
        S.selectedWantedPlayerId = id; S.selectedWantedPlayerName = name; WantedMenuWindow[0] = true
    end)

    sampRegisterChatCommand("dem", function(arg)
        if not settings.enableDemoute then sampAddChatMessage("{FF0000}[SH]{FFFFFF} /dem отключён", -1); return end
        if ActionSystem.activeFlags.demoute then addNotification("Занят!", C.NOTIFY_WARNING); return end
        local id = tonumber(arg); if not id or id < 0 or id > 999 then sampAddChatMessage("{FF0000}[SH]{FFFFFF} /dem [ID]", -1); return end
        local name = getPlayerNameById(id); if not name then addNotification("Не найден!", C.NOTIFY_ERROR); return end
        S.selectedDemoutePlayerId = id; S.selectedDemoutePlayerName = name; demouteValueBuf[0] = 0; DemouteMenuWindow[0] = true
    end)

    sampRegisterChatCommand("dis", function(arg)
        if not settings.enableDismiss then sampAddChatMessage("{FF0000}[SH]{FFFFFF} /dis отключён", -1); return end
        if ActionSystem.activeFlags.dismiss then addNotification("Занят!", C.NOTIFY_WARNING); return end
        local id = tonumber(arg); if not id or id < 0 or id > 999 then sampAddChatMessage("{FF0000}[SH]{FFFFFF} /dis [ID]", -1); return end
        local name = getPlayerNameById(id); if not name then addNotification("Не найден!", C.NOTIFY_ERROR); return end
        S.selectedDismissPlayerId = id; S.selectedDismissPlayerName = name; DismissMenuWindow[0] = true
    end)

    sampRegisterChatCommand("mb", function()
        if not settings.showMembersOverlay then sampAddChatMessage("{FF0000}[SH]{FFFFFF} Оверлей отключён", -1); return end
        if membersOverlay.isChecking then addNotification("Уже сканируется!", C.NOTIFY_WARNING); return end
        membersOverlay.isChecking = true;membersOverlay._checkStartTime = os.clock(); membersOverlay.tempList = {}; safeSendChat("/members"); addNotification("Members: сканирование...", C.NOTIFY_INFO)
    end)

    sampRegisterChatCommand("mbcopy", function()
        if #membersOverlay.list == 0 then
            addNotification("Members: список пуст! Сначала /mb", C.NOTIFY_WARNING); return
        end
        copyToClipboard(buildMembersList(), "Список скопирован (" .. #membersOverlay.list .. " чел.)")
    end)

    sampRegisterChatCommand("afind", function(arg) afCommand(arg) end)

    sampRegisterChatCommand("shupdate", function()
    updater.checkForUpdates(false)
    end)

    -- Единый поток Members (УЛУЧШЕНИЕ #3)
    lua_thread.create(function()
        wait(5000)
        -- Автозагрузка Members при старте (до 3 попыток)
        -- Исправлена логика: теперь ждём ответа или таймаута перед следующей попыткой
        for retry = 1, 3 do
            if not settings.showMembersOverlay then break end
            if #membersOverlay.list > 0 then break end
            if membersOverlay.isChecking then
                -- предыдущая попытка ещё идёт: ждём
                local t0 = os.clock()
                while membersOverlay.isChecking and os.clock() - t0 < 16 do wait(500) end
                if #membersOverlay.list > 0 then break end
            end
            membersOverlay.isChecking = true
            membersOverlay._checkStartTime = os.clock()
            membersOverlay.tempList = {}
            safeSendChat("/members")
            addNotification("Авто Members: попытка " .. retry .. "/3...", C.NOTIFY_INFO)
            -- ждём пока isChecking не сбросится (16с макс.)
            local waited = 0
            while membersOverlay.isChecking and waited < 16000 do
                wait(500); waited = waited + 500
            end
            -- Явный сброс на случай если диалог так и не пришёл (таймаут)
            if membersOverlay.isChecking then
                membersOverlay.isChecking = false
                membersOverlay._checkStartTime = nil
                membersOverlay.tempList = {}
            end
            if #membersOverlay.list > 0 then break end
            if retry < 3 then wait(3000) end
        end
        if #membersOverlay.list == 0 then
            addNotification("Members: не удалось загрузить автоматически. Используйте /mb", C.NOTIFY_WARNING, 8)
        end
        -- главный цикл автообновления: срабатывает даже если инициальная загрузка не удалась
        S.membersRetryAt = 0  -- время следующей попытки если список пуст
        while true do
            wait(1000)
            if settings.membersAutoRefresh and settings.showMembersOverlay and not membersOverlay.isChecking then
                local needRefresh = false
                if membersOverlay.lastUpdate > 0 then
                    -- плановая ротация
                    needRefresh = (os.clock() - membersOverlay.lastUpdate) * 1000 >= settings.membersAutoRefreshInterval
                elseif #membersOverlay.list == 0 then
                    -- список пуст и lastUpdate == 0: повторять раз в 60 секунд без блокировки треда
                    if S.membersRetryAt == 0 then S.membersRetryAt = os.clock() + 60 end
                    needRefresh = os.clock() >= S.membersRetryAt
                    if needRefresh then S.membersRetryAt = os.clock() + 60 end
                end
                if needRefresh then
                    membersOverlay.isChecking = true
                    membersOverlay._checkStartTime = os.clock()
                    membersOverlay.tempList = {}
                    safeSendChat("/members")
                end
            end
        end
    end)

    -- QA thread: binds/addActivity/performBind доступны здесь (объявлены до main)
    lua_thread.create(function()
        local prevState = {}
        local lastFire  = 0
        local COOLDOWN  = 0.5
        while true do
            wait(0)
            if not QA.active or QA.targetSid == -1 or S.activeBinder then
                prevState = {}; goto qa_next
            end
            do
                local snapMode  = QA.mode
                local snapSid   = QA.targetSid
                local snapNick  = QA.targetNick
                local snapSlots = snapMode=="foot" and QA.foot or QA.vehicle
                if not snapSlots then goto qa_next end
                for si, slot in ipairs(snapSlots) do
                    local k = slot.key or 0
                    if k ~= 0 then
                        local dn  = isKeyDown(k)
                        local was = prevState[k] or false
                        if dn and not was then
                            if os.clock() - lastFire >= COOLDOWN then
                                local bind = nil
                                if slot.bindId and slot.bindId ~= "" then
                                    for _, b in ipairs(binds) do
                                        if b.id == slot.bindId then bind=b; break end
                                    end
                                end
                                local ok = QA:execute(slot, bind, snapSid, snapNick)
                                if ok then
                                    lastFire     = os.clock()
                                    prevState[k] = true
                                    addActivity("QA "..(slot.label or "?")..": "..snapNick.."["..snapSid.."]", "system")
                                    lua_thread.create(function()
                                        performBind(bind, {})
                                        QA.execTargetId=nil; QA.execTargetNick=nil
                                    end)
                                end
                                break
                            end
                        else
                            prevState[k] = dn
                        end
                    end
                end
            end
            ::qa_next::
        end
    end)

    -- AutoFind поток
    lua_thread.create(function() while true do wait(autoFind.interval); if autoFind.active and autoFind.lastId ~= -1 then afDoFind() end end end)


    sampAddChatMessage("{ff0000}[Snatch Helper] {ff6666}v" .. C.SCRIPT_VERSION .. " | F3 — меню | /snatch | /mbcopy — копировать список", -1)
    addNotification("Snatch Helper v" .. C.SCRIPT_VERSION .. " загружен!", C.NOTIFY_SUCCESS)
        -- Автопроверка обновлений через 5 секунд после запуска
    lua_thread.create(function()
        wait(5000)
        updater.checkForUpdates(true) -- silent = true
    end)
    -- УЛУЧШЕНИЕ #5 — блокировка ввода при назначении клавиши
    addEventHandler('onWindowMessage', function(msg, wparam)
        if msg == C.KEY_WM_KEYDOWN or msg == C.KEY_WM_SYSKEYDOWN then
            if S.waitingForKey and S.keyBindPopupActive then
                if wparam == C.KEY_ESC then S.waitingForKey = false
                elseif wparam ~= C.KEY_SHIFT and wparam ~= C.KEY_CTRL and wparam ~= C.KEY_ALT then
                    S.tempKey = wparam; S.tempMod = 0
                    if isKeyDown(C.KEY_CTRL) then S.tempMod = 1 elseif isKeyDown(C.KEY_SHIFT) then S.tempMod = 2 elseif isKeyDown(C.KEY_ALT) then S.tempMod = 3 end
                    S.waitingForKey = false
                end
                consumeWindowMessage(true, true); return
            end
            if wparam == settings.openKey then mainWindow.switch(); mainWindowOpen[0] = mainWindow.state end
            if wparam == settings.binderKey then
                if not mainWindow.state then mainWindow.switch(); mainWindowOpen[0] = mainWindow.state end
                currentNav[0] = C.NAV_BINDER
            end
        end
        -- Кнопки мыши при назначении хоткея
        -- WM_LBUTTONDOWN=0x201, WM_RBUTTONDOWN=0x204, WM_MBUTTONDOWN=0x207, WM_XBUTTONDOWN=0x20B
        if S.waitingForKey and S.keyBindPopupActive then
            local mouseVK = nil
            if     msg == 0x201 then mouseVK = 0x01
            elseif msg == 0x204 then mouseVK = 0x02
            elseif msg == 0x207 then mouseVK = 0x04
            elseif msg == 0x20B then
                local xbtn = math.floor(wparam / 65536)
                mouseVK = xbtn == 1 and 0x05 or 0x06
            end
            if mouseVK then
                S.tempKey = mouseVK; S.tempMod = 0
                if isKeyDown(C.KEY_CTRL) then S.tempMod = 1 elseif isKeyDown(C.KEY_SHIFT) then S.tempMod = 2 elseif isKeyDown(C.KEY_ALT) then S.tempMod = 3 end
                S.waitingForKey = false
                consumeWindowMessage(true, true)
            end
        else
            -- Отслеживаем нажатия мыши для запуска биндов
            if     msg == 0x201 then S._mouseJustPressed = 0x01
            elseif msg == 0x204 then S._mouseJustPressed = 0x02
            elseif msg == 0x207 then S._mouseJustPressed = 0x04
            elseif msg == 0x20B then
                local xbtn = math.floor(wparam / 65536)
                S._mouseJustPressed = xbtn == 1 and 0x05 or 0x06
            end
            -- QA: всё управляется через isKeyDown в qa_thread
        end
    end)

    while true do
        wait(0)
        S._mouseJustPressed = 0  -- сбрасываем каждый кадр
        local _now = os.clock()  -- один вызов на всю итерацию
        -- РП оружие: отслеживаем смену оружия каждый кадр
        if settings.rpWeaponEnabled then
            local curW = getCurrentCharWeapon(playerPed) or 0
            if rpGuns.data.nowGun == nil then
                rpGuns.data.nowGun = curW  -- первичная инициализация без /me
            elseif curW ~= rpGuns.data.nowGun then
                rpGuns.data.oldGun = rpGuns.data.nowGun
                rpGuns.data.nowGun = curW
                rpGuns.process(rpGuns.data.oldGun, curW)
            end
        end
        -- Quick Actions
        QA:update()
        -- Автосохранение бинда: 1.5 сек после последнего изменения
        if S.hasUnsavedChanges and S.selectedBindIndex and not S.isCreatingNew then
            if S.autoSaveTimer == 0 then
                S.autoSaveTimer = _now + 1.5
            elseif _now >= S.autoSaveTimer then
                S.autoSaveTimer = 0
                saveCurrentBind(true)  -- silent=true, без уведомления
            end
        else
            S.autoSaveTimer = 0
        end
        -- УЛУЧШЕНИЕ #6 — очистка анимаций
        if _now - S.animCleanupTimer > C.ANIM_CLEANUP_INTERVAL then S.animCleanupTimer = _now; cleanupAnims() end
        -- Автобэкап + УЛУЧШЕНИЕ #19
        if settings.autoBackup and _now - S.lastAutoBackup > C.AUTO_BACKUP_INTERVAL then S.lastAutoBackup = _now; autoBackup() end
        -- Стоп-клавиша + принудительный сброс флагов по таймауту
        if S.activeBinder or ActionSystem.activeFlags.gwarn or ActionSystem.activeFlags.wanted or ActionSystem.activeFlags.demoute or ActionSystem.activeFlags.dismiss then
            if settings.stopKey ~= 0 and checkKeyCombo(settings.stopKey, settings.stopKeyMod) then
                S.stopCurrentBind = true
                if S.stopSentTime == 0 then S.stopSentTime = os.clock() end
                addNotification("Стоп...", C.NOTIFY_WARNING)
            end
            -- Принудительный сброс если поток завис более 5 секунд после стопа
            if S.stopCurrentBind and S.stopSentTime > 0 and _now - S.stopSentTime > 5 then
                S.activeBinder = false; S.stopCurrentBind = false; S.stopSentTime = 0
                for k in pairs(ActionSystem.activeFlags) do ActionSystem.activeFlags[k] = false end
                addNotification("Принудительный сброс (таймаут)", C.NOTIFY_WARNING)
            end
        else
            S.stopSentTime = 0
        end
        -- Debounce: save overlay position
        if S.overlayDebounceSave > 0 and _now >= S.overlayDebounceSave then
            S.overlayDebounceSave = 0; saveSettings()
        end
        -- Хоткеи биндов (хэш-индекс)
        if not S.activeBinder and not mainWindow.state and not S.keyBindPopupActive then
            for combo, bind in pairs(keyBindMap) do
                local k = math.floor(combo / 10)
                local m = combo % 10
                if checkKeyCombo(k, m) then
                    local canRun = true
                    if bind.cooldown and bind.cooldown > 0 and bind.lastUseTime then
                        if (os.clock() - bind.lastUseTime)*1000 < bind.cooldown then canRun = false end
                    end
                    if canRun then
                        local ref = bind
                        -- FIX C: если бинд имеет пользовательские аргументы -- хоткей не может их запросить
                        local hasCustomVars = false
                        if ref.cmd and ref.cmd ~= "" then
                            hasCustomVars = ref.cmd:find("{") ~= nil
                        else
                            local cvTmp = extractCustomVars(ref.steps or {})
                            hasCustomVars = #cvTmp > 0
                        end
                        if hasCustomVars then
                            addNotification("Бинд «" .. (ref.name or "?") .. "» требует аргументы — используйте /" .. (ref.cmd and ref.cmd:match("^(%S+)") or "?") .. " в чате", C.NOTIFY_WARNING)
                        else
                            lua_thread.create(function() performBind(ref, {}) end)
                        end
                    end
                    break
                end
            end
        end
    end
end

function onScriptTerminate(scr, quitGame)
    if scr == thisScript() then
        saveSettings(); saveBinds(); saveActivityLog(); QA:save(); unregisterBindCommands()
        -- Автосохранение заметок
        if B.notesLoaded then
            local notesPath = configDirectory .. "/notes.txt"
            local f = io.open(notesPath, 'w')
            if f then
                local content = u8:decode(ffi.string(B.notesBuf))
                f:write(content); f:close()
            end
        end
    end
end