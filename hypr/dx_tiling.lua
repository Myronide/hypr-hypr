-- Draconyx Tiling: eigener Kachel-Modus für freischwebende Fenster (statt Hyprlands Dwindle).
-- Fenster bleiben standardmäßig floating. Mit Tastenkürzel wandern einzelne Fenster (oder ein ganzer
-- Desktop) in ein automatisch angeordnetes Raster. Nicht gekachelte Fenster bleiben unberührt.
local M = {}

local GAP = 8
local MODES = { "zones", "grid", "columns", "rows", "master" }
local MODE_NAMES = { zones = "Eigene Zonen", grid = "Auto-Raster", columns = "Spalten", rows = "Zeilen", master = "Master + Stapel" }
M.mode = "zones"
local okZ, Z = pcall(require, "dx_zones")
if not okZ then Z = nil end

local tiled = {}      -- address -> true
local order = {}      -- Reihenfolge der gekachelten Fenster (Adressen)
local orig = {}       -- address -> { x, y, w, h } Geometrie vor dem Kacheln
local wsAuto = {}     -- Desktop-ID -> true: neue Fenster werden automatisch gekachelt
local applying = false

-- Standard-Fenstermodus (einstellbar, bleibt gespeichert): "floating" oder "tiling".
-- Bei "tiling" werden neue Fenster auf jedem Desktop automatisch in das Raster gesetzt.
local MODE_FILE = (os.getenv("HOME") or "") .. "/.config/draconyx/window-mode"
M.defaultTiling = false
do
    local f = io.open(MODE_FILE, "r")
    if f then
        local v = f:read("*l"); f:close()
        M.defaultTiling = (v == "tiling")
    end
end

local function addr(a) return "address:" .. a end

local function indexOf(a)
    for i, v in ipairs(order) do if v == a then return i end end
    return nil
end

local maxed = {}      -- address -> true: vom Nutzer maximiert (steigt vorübergehend aus dem Raster aus)
local pendingAdd = {} -- address -> Token des Timers, der ein neues Fenster ins Raster setzt (Schließen/Adress-Wiederverwendung verwirft ihn)

local function forget(a)
    tiled[a] = nil
    orig[a] = nil
    maxed[a] = nil
    pendingAdd[a] = nil
    local i = indexOf(a)
    if i then table.remove(order, i) end
end

-- Darf ins Raster: sichtbar, gemappt, kein echtes Vollbild, normaler Desktop (nicht "minimized"/special)
local function canTile(w)
    if w == nil or not w.mapped or w.hidden then return false end
    if w.fullscreen == 2 or w.fullscreen == 3 then return false end   -- echtes Vollbild bleibt unberührt
    local ws = w.workspace
    if ws == nil or ws.id == nil or ws.id < 1 or ws.name == "minimized" then return false end
    return w.at ~= nil and w.size ~= nil
end
-- Liegt gerade im Raster: nur Fenster, die NICHT maximiert sind. Ein maximiertes Fenster steigt
-- vorübergehend aus (bleibt in der Reihenfolge) und kehrt beim Wiederherstellen zurück.
function M.setMaxed(a, on)
    if a == nil then return end
    maxed[a] = on or nil
end
local function eligible(w)
    return canTile(w) and w.fullscreen == 0 and not maxed[w.address]
end

local function windowMap()
    local map = {}
    for _, w in ipairs(hl.get_windows()) do map[w.address] = w end
    return map
end

-- Arbeitsfläche eines Monitors; width/height sind physische Pixel, x/y/reserved logische -> durch die Skalierung teilen
local function usable(m)
    local r = m.reserved or {}
    local sc = m.scale
    if type(sc) ~= "number" or sc <= 0 then sc = 1 end
    local x = m.x + (r.left or 0) + GAP
    local y = m.y + (r.top or 0) + GAP
    local w = math.max(200, m.width / sc - (r.left or 0) - (r.right or 0) - 2 * GAP)
    local h = math.max(120, m.height / sc - (r.top or 0) - (r.bottom or 0) - 2 * GAP)
    return x, y, w, h
end

-- Rechtecke für n Fenster im Bereich (ax, ay, aw, ah)
local function layout(n, mode, ax, ay, aw, ah)
    local rects = {}
    if n == 1 then
        rects[1] = { x = ax, y = ay, w = aw, h = ah }
    elseif mode == "columns" then
        local cw = (aw - GAP * (n - 1)) / n
        for i = 1, n do rects[i] = { x = ax + (i - 1) * (cw + GAP), y = ay, w = cw, h = ah } end
    elseif mode == "rows" then
        local rh = (ah - GAP * (n - 1)) / n
        for i = 1, n do rects[i] = { x = ax, y = ay + (i - 1) * (rh + GAP), w = aw, h = rh } end
    elseif mode == "master" then
        local mw = math.floor(aw * 0.58)
        rects[1] = { x = ax, y = ay, w = mw, h = ah }
        local rest = n - 1
        local sw = aw - mw - GAP
        local sh = (ah - GAP * (rest - 1)) / rest
        for i = 1, rest do rects[i + 1] = { x = ax + mw + GAP, y = ay + (i - 1) * (sh + GAP), w = sw, h = sh } end
    else -- grid
        local cols = math.ceil(math.sqrt(n))
        local rows = math.ceil(n / cols)
        local rh = (ah - GAP * (rows - 1)) / rows
        for r = 1, rows do
            local inRow = (r < rows) and cols or (n - cols * (rows - 1))
            local cw = (aw - GAP * (inRow - 1)) / inRow
            for c = 1, inRow do
                rects[#rects + 1] = { x = ax + (c - 1) * (cw + GAP), y = ay + (r - 1) * (rh + GAP), w = cw, h = rh }
            end
        end
    end
    return rects
end

-- gemerkte Geometrie auf einen sichtbaren Bereich bringen (Monitor könnte inzwischen fehlen)
local function fit(o, w)
    if DXSnap ~= nil and DXSnap.fitRect ~= nil then
        local x, y, ww, wh = DXSnap.fitRect(o.x, o.y, o.w, o.h, w)
        return { x = x, y = y, w = ww, h = wh }
    end
    return o
end

local function place(w, r)
    hl.dispatch(hl.dsp.window.resize({ window = addr(w.address), x = math.floor(r.w), y = math.floor(r.h), relative = false }))
    hl.dispatch(hl.dsp.window.move({ window = addr(w.address), x = math.floor(r.x), y = math.floor(r.y), relative = false }))
end

-- gekachelte Fenster eines Desktops in Reihenfolge
local function tiledOn(wsId, map)
    local list = {}
    for _, a in ipairs(order) do
        local w = map[a]
        if w ~= nil and eligible(w) and w.workspace.id == wsId then table.insert(list, w) end
    end
    return list
end

function M.retile(wsId)
    if applying or wsId == nil then return end
    applying = true
    local ok = pcall(function()
        local map = windowMap()
        local list = tiledOn(wsId, map)
        if #list == 0 then return end
        local m = list[1].monitor or hl.get_active_monitor()
        if m == nil then return end
        local zones = (M.mode == "zones" and Z ~= nil) and Z.zones(m.name) or {}
        if #zones > 0 then
            -- eigene Zonen: Fenster i kommt in Zone i; überzählige Fenster bleiben unberührt (frei schwebend)
            local overflow = {}
            for i, w in ipairs(list) do
                if zones[i] == nil then
                    table.insert(overflow, w)
                else
                    if not w.floating then hl.dispatch(hl.dsp.window.float({ window = addr(w.address), action = "set" })) end
                    place(w, zones[i])
                end
            end
            -- kein Platz mehr: Fenster wird wieder frei (Originalposition), statt auf einer Zone zu liegen
            for _, w in ipairs(overflow) do
                local o = orig[w.address]
                forget(w.address)
                if o ~= nil then place(w, fit(o, w)) end
            end
            if #overflow > 0 then
                hl.exec_cmd("notify-send -a 'Draconyx' -t 2500 'Raster voll' '" .. #zones .. " Zonen belegt – weitere Fenster bleiben frei. Raster bearbeiten: Strg+Alt+Z'")
            end
        else
            local ax, ay, aw, ah = usable(m)
            local mode = (M.mode == "zones") and "grid" or M.mode
            local rects = layout(#list, mode, ax, ay, aw, ah)
            for i, w in ipairs(list) do
                if not w.floating then hl.dispatch(hl.dsp.window.float({ window = addr(w.address), action = "set" })) end
                place(w, rects[i])
            end
        end
    end)
    applying = false
    return ok
end

function M.retileAll()
    local map = windowMap()
    local seen = {}
    for _, a in ipairs(order) do
        local w = map[a]
        if w ~= nil and w.workspace ~= nil and not seen[w.workspace.id] then
            seen[w.workspace.id] = true
            M.retile(w.workspace.id)
        end
    end
end

local function notify(text)
    hl.exec_cmd("notify-send -a 'Draconyx' -t 1800 'Tiling' '" .. text .. "'")
end

local function unmaximize(w)
    if w.fullscreen == 1 then hl.dispatch(hl.dsp.window.fullscreen({ window = addr(w.address), mode = "maximized", action = "unset" })) end
end

function M.add(w)
    if not canTile(w) or tiled[w.address] then return end
    unmaximize(w)
    orig[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
    tiled[w.address] = true
    table.insert(order, w.address)
    M.retile(w.workspace.id)
end

function M.release(w)
    if w == nil or not tiled[w.address] then return end
    local o = orig[w.address]
    local wsId = w.workspace and w.workspace.id
    forget(w.address)
    if o ~= nil and eligible(w) then place(w, fit(o, w)) end   -- maximiert: bleibt maximiert
    M.retile(wsId)
end

-- Aktives Fenster ins Raster / wieder heraus
function M.toggle(w)
    w = w or hl.get_active_window()
    if w == nil then return end
    if tiled[w.address] then
        M.release(w)
        notify("Fenster ist wieder frei")
    else
        M.add(w)
        if tiled[w.address] then notify("Fenster im Raster (nochmal Strg+Alt+G = wieder frei)") end
    end
end

function M.toggleAddr(a)
    for _, w in ipairs(hl.get_windows()) do
        if w.address == a then M.toggle(w); return end
    end
end

function M.isTiled(w) return w ~= nil and tiled[w.address] == true end

-- Ganzer Desktop: alle Fenster kacheln (und neue automatisch), erneut = alles lösen
function M.toggleWorkspace()
    local ws = hl.get_active_workspace()
    if ws == nil then return end
    if wsAuto[ws.id] then
        wsAuto[ws.id] = nil
        for _, w in ipairs(tiledOn(ws.id, windowMap())) do M.release(w) end
        notify("Desktop " .. ws.id .. ": Kacheln aus")
    else
        wsAuto[ws.id] = true
        for _, w in ipairs(hl.get_windows()) do
            if canTile(w) and w.workspace.id == ws.id and not tiled[w.address] then
                unmaximize(w)
                orig[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
                tiled[w.address] = true
                table.insert(order, w.address)
            end
        end
        M.retile(ws.id)
        notify("Desktop " .. ws.id .. ": Kacheln an (" .. MODE_NAMES[M.mode] .. ")")
    end
end

-- Standardmodus umstellen: "tiling" kachelt alle passenden Fenster, "floating" gibt alle frei
function M.setDefault(mode)
    if mode ~= "tiling" and mode ~= "floating" then return end   -- nil/Unsinn aus einem fehlerhaften Aufruf darf die Einstellung nicht auf "floating" setzen
    local tilingNow = (mode == "tiling")
    pcall(function()
        local f = io.open(MODE_FILE, "w")
        if f then f:write(tilingNow and "tiling\n" or "floating\n"); f:close() end
    end)
    M.defaultTiling = tilingNow
    if tilingNow then
        local seen = {}
        for _, w in ipairs(hl.get_windows()) do
            if canTile(w) and not tiled[w.address] then
                unmaximize(w)
                orig[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
                tiled[w.address] = true
                table.insert(order, w.address)
                seen[w.workspace.id] = true
            end
        end
        M.retileAll()
        notify("Standard: Kacheln (" .. MODE_NAMES[M.mode] .. ")")
    else
        M.releaseAll()
        notify("Standard: Frei schwebend")
    end
end
function M.getDefault() return M.defaultTiling and "tiling" or "floating" end

function M.releaseAll()
    local map = windowMap()
    local list = {}
    for _, a in ipairs(order) do if map[a] ~= nil then table.insert(list, map[a]) end end
    for k in pairs(wsAuto) do wsAuto[k] = nil end
    for _, w in ipairs(list) do M.release(w) end
    -- alles vergessen, auch Fenster, die es nicht mehr gibt
    for k in pairs(tiled) do tiled[k] = nil end
    for k in pairs(maxed) do maxed[k] = nil end
    for i = #order, 1, -1 do table.remove(order, i) end
    notify("Raster aus: alle Fenster sind wieder frei")
end

function M.cycleMode()
    local cur = 1
    for i, m in ipairs(MODES) do if m == M.mode then cur = i end end
    M.mode = MODES[(cur % #MODES) + 1]
    M.retileAll()
    notify("Layout: " .. MODE_NAMES[M.mode])
end

-- Position mit Nachbarn tauschen (dir = -1 vorheriges, +1 nächstes)
function M.shift(dir)
    local w = hl.get_active_window()
    if w == nil or w.workspace == nil or not tiled[w.address] then return end
    local list = tiledOn(w.workspace.id, windowMap())
    local pos
    for i, x in ipairs(list) do if x.address == w.address then pos = i end end
    local other = pos and list[pos + dir]
    if other == nil then return end
    local i, j = indexOf(w.address), indexOf(other.address)
    if i == nil or j == nil then return end
    order[i], order[j] = order[j], order[i]
    M.retile(w.workspace.id)
end

-- Fenster per Maus losgelassen: bei Kachel-Fenstern mit dem Fenster unter dem Zeiger tauschen
-- Platz Nr. idx (in Reihenfolge der gekachelten Fenster eines Desktops) als Rechteck
local function slotRect(list, idx, m)
    local zones = (M.mode == "zones" and Z ~= nil) and Z.zones(m.name) or {}
    if #zones > 0 then return zones[idx] end
    local ax, ay, aw, ah = usable(m)
    local mode = (M.mode == "zones") and "grid" or M.mode
    return layout(#list, mode, ax, ay, aw, ah)[idx]
end

-- Live-Tauschen beim Ziehen: Zieht man ein gekacheltes Fenster über ein anderes, gleitet dieses sofort in den
-- Platz des gezogenen (animiert). Das gezogene Fenster folgt weiter der Maus und rastet beim Loslassen ein.
local lastSwap = 0
-- Echte Uhrzeit in Sekunden (os.clock wäre die Rechenzeit von Hyprland und läuft viel langsamer)
local function realNow()
    local f = io.open("/proc/uptime", "r")
    local v = f and f:read("*n")
    if f then f:close() end
    return v or os.time()
end
function M.liveSwap(w, cx, cy)
    if w == nil or w.workspace == nil or not tiled[w.address] or applying or cx == nil or cy == nil then return false end
    local now = realNow()
    if now - lastSwap < 0.25 then return false end
    local map = windowMap()
    local list = tiledOn(w.workspace.id, map)
    for _, o in ipairs(list) do
        if o.address ~= w.address
           and cx >= o.at.x and cx <= o.at.x + o.size.x and cy >= o.at.y and cy <= o.at.y + o.size.y then
            local i, j = indexOf(w.address), indexOf(o.address)
            if i == nil or j == nil then return false end
            order[i], order[j] = order[j], order[i]
            lastSwap = now
            local m = o.monitor or hl.get_active_monitor()
            if m == nil then return false end
            local fresh = tiledOn(w.workspace.id, map)
            -- o übernimmt den Platz, den w verlassen hat (neuer Index i in der neu sortierten Liste)
            local r
            for k, ww in ipairs(fresh) do if ww.address == o.address then r = slotRect(fresh, k, m) end end
            if r ~= nil then
                applying = true
                pcall(place, o, r)
                applying = false
            end
            return true
        end
    end
    return false
end

function M.dropAt(w, cx, cy)
    if w == nil or w.workspace == nil or not tiled[w.address] then return false end
    local map = windowMap()
    for _, o in ipairs(tiledOn(w.workspace.id, map)) do
        if o.address ~= w.address
           and cx >= o.at.x and cx <= o.at.x + o.size.x and cy >= o.at.y and cy <= o.at.y + o.size.y then
            local i, j = indexOf(w.address), indexOf(o.address)
            if i ~= nil and j ~= nil then order[i], order[j] = order[j], order[i] end
            break
        end
    end
    M.retile(w.workspace.id)
    return true
end

-- Ereignisse: Raster aktuell halten
local lastErr = nil
local function safe(fn) return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and tostring(err) ~= lastErr then lastErr = tostring(err); io.stderr:write("[dx_tiling] ", lastErr, "\n") end
end end

hl.on("window.open", safe(function(w)
    if w ~= nil and w.address ~= nil and w.workspace ~= nil and (wsAuto[w.workspace.id] or M.defaultTiling) then
        local address, token = w.address, {}
        pendingAdd[address] = token
        hl.timer(safe(function()
            if pendingAdd[address] ~= token then return end        -- Fenster schon wieder weg (oder Adresse neu vergeben)
            pendingAdd[address] = nil
            for _, x in ipairs(hl.get_windows()) do               -- frischen Zustand holen, nicht das alte Fensterobjekt
                if x.address == address then M.add(x); return end
            end
        end), { timeout = 120, type = "oneshot" })
    end
end))
local function gone(w)
    if w == nil or not tiled[w.address] then return end
    local wsId = w.workspace and w.workspace.id
    forget(w.address)
    if wsId then hl.timer(function() M.retile(wsId) end, { timeout = 60, type = "oneshot" }) end
end
hl.on("window.close", safe(gone))
hl.on("window.destroy", safe(gone))
hl.on("window.move_to_workspace", safe(function(w)
    if w ~= nil and tiled[w.address] then hl.timer(function() M.retileAll() end, { timeout = 80, type = "oneshot" }) end
end))
hl.on("window.fullscreen", safe(function(w)
    if w ~= nil and tiled[w.address] and w.workspace ~= nil then
        local id = w.workspace.id
        hl.timer(function() M.retile(id) end, { timeout = 90, type = "oneshot" })
    end
end))
hl.on("monitor.layout_changed", safe(function() M.retileAll() end))
hl.on("config.reloaded", safe(function() M.retileAll() end))

return M
