-- Draconyx Zonen: selbst eingestellte Raster (wie FancyZones).
-- Die Zonen werden in der Draconyx Shell bearbeitet; die Shell schreibt sie als Zeilen
--   MONITOR index x y breite hoehe        (globale Pixel-Koordinaten)
-- nach $XDG_RUNTIME_DIR/draconyx-zones.txt. Dieses Modul liest sie und setzt Fenster hinein.
local M = {}

local FILE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/draconyx-zones.txt"
local pickWin = nil      -- Adresse des Fensters, das per Auswahl-Overlay platziert werden soll

function M.load()
    local zones = {}
    local f = io.open(FILE, "r")
    if f == nil then return zones end
    for line in f:lines() do
        local mon, idx, x, y, w, h = line:match("^(%S+)%s+(%d+)%s+(%-?%d+)%s+(%-?%d+)%s+(%d+)%s+(%d+)")
        if mon ~= nil then
            zones[mon] = zones[mon] or {}
            zones[mon][tonumber(idx)] = { x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
        end
    end
    f:close()
    return zones
end

function M.zones(mon)
    return M.load()[mon] or {}
end

-- Zone unter einem Punkt (Index oder nil)
function M.zoneAt(mon, cx, cy)
    for i, z in ipairs(M.zones(mon)) do
        if cx >= z.x and cx <= z.x + z.w and cy >= z.y and cy <= z.y + z.h then return i, z end
    end
    return nil
end

local function find(address)
    for _, w in ipairs(hl.get_windows()) do
        if w.address == address then return w end
    end
    return nil
end

-- Fenster in Zone idx seines Monitors setzen (wird frei schwebend)
function M.place(w, idx)
    if w == nil or tonumber(idx) == nil then return false end
    local m = w.monitor or hl.get_active_monitor()
    if m == nil then return false end
    local z = M.zones(m.name)[tonumber(idx)]
    if z == nil then return false end
    local a = "address:" .. w.address
    if w.fullscreen == 1 then hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = "maximized", action = "unset" })) end
    if w.fullscreen == 2 or w.fullscreen == 3 then return false end
    if DXSnap ~= nil and DXSnap.clearMax ~= nil then DXSnap.clearMax(w) end   -- in eine Zone gesetzt = nicht mehr maximiert
    if not w.floating then hl.dispatch(hl.dsp.window.float({ window = a, action = "set" })) end   -- "set" schaltet in dieser Version um: nur wenn nötig
    hl.dispatch(hl.dsp.window.resize({ window = a, x = z.w, y = z.h, relative = false }))
    hl.dispatch(hl.dsp.window.move({ window = a, x = z.x, y = z.y, relative = false }))
    return true
end

-- Auswahl-Overlay: erst Fenster merken, dann Zone wählen
function M.rememberActive()
    local w = hl.get_active_window()
    pickWin = w and w.address or nil
    return pickWin ~= nil
end

function M.placePicked(idx)
    local w = pickWin and find(pickWin) or nil
    pickWin = nil
    if w ~= nil and tonumber(idx) ~= nil then
        if DXTiling ~= nil and DXTiling.isTiled(w) then DXTiling.release(w) end
        M.place(w, idx)
        hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
    end
end

function M.count(mon) return #M.zones(mon) end

return M
