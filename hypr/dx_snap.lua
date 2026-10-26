-- Draconyx Snap: Fenster andocken wie unter KDE/Windows.
--  * Ziehen an Bildschirmrand = Hälfte, Ecke = Viertel, oberer Rand = maximieren (mit Vorschau in der Shell)
--  * Win+Pfeile in Ketten: links -> hoch = oben links, usw.
--  * Gekachelte Fenster (dx_tiling) tauschen beim Loslassen den Platz mit dem Fenster unter dem Zeiger
local M = {}

local GAP = 8
local EDGE = 6          -- Pixel am Rand, ab denen angedockt wird
local CORNER = 120      -- Eckbereich für Viertel
local PREVIEW = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/draconyx-snap.txt"

local tiling, opts = nil, {}
local okZ, Z = pcall(require, "dx_zones")
if not okZ then Z = nil end
local function shiftDown() return hl.is_key_down(50) or hl.is_key_down(62) end
local zoneOf = {}       -- address -> letzte Andock-Zone

function M.setup(t, o)
    tiling = t
    opts = o or {}
end

-- ---------- Geometrie ----------
-- Platz für die Titelleisten der Shell (TitleBars.qml): eine Leiste sitzt direkt ÜBER dem Fenster, also bleibt beim Andocken und
-- Maximieren oben ein Streifen frei – aber nur bei Fenstern, die auch eine Leiste bekommen (wie in der Shell: schwebend, Klasse nicht in
-- csd-apps, kein GTK-Programm; ~/.config/draconyx/titlebar-force erzwingt eine Leiste). Aus, wenn "titleBars" in den Shell-Einstellungen aus ist.
local TITLEBAR = 30
local HOME = os.getenv("HOME") or ""
local barsOn, csdSet, forceSet, csdAt = true, {}, {}, 0
local gtkPid = {}       -- pid -> true/false (einmal je Prozess aus /proc/PID/maps)

local function readSet(path, into)
    local f = io.open(path, "r")
    if not f then return end
    for line in f:lines() do
        local k = line:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if k ~= "" and k:sub(1, 1) ~= "#" then into[k] = true end
    end
    f:close()
end

local function refreshLists()
    local now = os.time()
    if now - csdAt < 5 then return end
    csdAt = now
    csdSet, forceSet = {}, {}
    readSet(HOME .. "/.config/hypr/csd-apps", csdSet)
    readSet(HOME .. "/.config/hypr/aurora/csd-apps", csdSet)
    readSet(HOME .. "/.config/draconyx/titlebar-force", forceSet)
    local f = io.open(HOME .. "/.local/state/draconyx/settings.json", "r")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    barsOn = not s:find('"titleBars"%s*:%s*false')
end
refreshLists()
hl.on("config.reloaded", function() csdAt = 0; refreshLists() end)

local function usesGtk(pid)
    if pid == nil then return false end
    if gtkPid[pid] ~= nil then return gtkPid[pid] end
    local r = false
    local f = io.open("/proc/" .. tostring(pid) .. "/maps", "r")
    if f then
        for line in f:lines() do
            if line:find("libgtk%-[34]") or line:find("libadwaita") then r = true; break end
        end
        f:close()
    end
    gtkPid[pid] = r
    return r
end

-- Bekommt dieses Fenster eine Titelleiste der Shell? (gleiche Regeln wie in TitleBars.qml)
local function wantsBar(w)
    if w == nil then return false end
    refreshLists()
    if not barsOn then return false end
    local cls = (w.class or ""):lower()
    if cls == "" or cls:find("^steam_app_") then return false end
    if forceSet[cls] then return true end
    if csdSet[cls] then return false end
    return not usesGtk(w.pid)
end

local function area(m, w)
    local r = m.reserved or {}
    local tb = wantsBar(w) and TITLEBAR or 0
    local x = m.x + (r.left or 0) + GAP
    local y = m.y + (r.top or 0) + GAP + tb
    local ww = m.width - (r.left or 0) - (r.right or 0) - 2 * GAP
    local h = m.height - (r.top or 0) - (r.bottom or 0) - 2 * GAP - tb
    return x, y, ww, h
end

function M.rectFor(m, zone, w)
    local x0, y0, aw, ah = area(m, w)
    local hw = math.floor((aw - GAP) / 2)
    local hh = math.floor((ah - GAP) / 2)
    local x, y, w, h = x0, y0, aw, ah
    if zone == "left" then w = hw
    elseif zone == "right" then w = hw; x = x0 + hw + GAP
    elseif zone == "top" then h = hh
    elseif zone == "bottom" then h = hh; y = y0 + hh + GAP
    elseif zone == "tl" then w = hw; h = hh
    elseif zone == "tr" then w = hw; h = hh; x = x0 + hw + GAP
    elseif zone == "bl" then w = hw; h = hh; y = y0 + hh + GAP
    elseif zone == "br" then w = hw; h = hh; x = x0 + hw + GAP; y = y0 + hh + GAP
    elseif zone == "restore" then
        w = math.floor(aw * 0.62); h = math.floor(ah * 0.72)
        x = x0 + math.floor((aw - w) / 2); y = y0 + math.floor((ah - h) / 2)
    end
    return x, y, w, h
end

function M.snapWindow(w, zone)
    if w == nil then return end
    local m = w.monitor or hl.get_active_monitor()
    if m == nil then return end
    local x, y, ww, wh = M.rectFor(m, zone, w)
    local a = "address:" .. w.address
    if w.fullscreen ~= 0 then
        hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = "maximized", action = "unset" }))
        hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = "fullscreen", action = "unset" }))
    end
    if tiling ~= nil and tiling.isTiled(w) then tiling.release(w) end
    if not w.floating then hl.dispatch(hl.dsp.window.float({ window = a, action = "set" })) end   -- "set" schaltet in dieser Version um: nur wenn nötig
    hl.dispatch(hl.dsp.window.resize({ window = a, x = ww, y = wh, relative = false }))
    hl.dispatch(hl.dsp.window.move({ window = a, x = x, y = y, relative = false }))
    zoneOf[w.address] = (zone ~= "restore") and zone or nil
end

-- ---------- Eigenes Maximieren: ein eigener Zustand je Fenster ----------
-- Hyprlands "maximized" setzt ein Vollbild-Flag am Desktop; dann gehen Mausklicks an das maximierte Fenster, obwohl ein anderes darüber
-- liegt. Deshalb ist maximieren hier: schwebendes Fenster in Arbeitsflächengröße. Der Zustand gehört UNS (Tabelle maxed), nicht der App:
--  * Der App wird er nur mitgeteilt (fullscreen_state: intern 0, für die App 1), damit ihr Knopf "Wiederherstellen" zeigt und sie
--    nicht ständig neu "maximieren" verlangt.
--  * Wünsche der App (Maximieren-/Wiederherstellen-Knopf, Doppelklick auf ihre Titelleiste) zählen nur, wenn kurz vorher wirklich
--    geklickt wurde. Alles andere (Steam maximiert sich selbst, Brave meldet beim Minimieren "maximiert" …) wird zurückgenommen.
--  * Minimieren/Zurückholen (Shell) merkt sich nichts an der Geometrie der App ab: nach dem Zurückholen wird unser Zustand neu angewendet.
local userMax = {}   -- address -> { x, y, w, h } Geometrie vor dem Maximieren
local maxed = {}     -- address -> true: von uns maximiert (die einzige Wahrheit)
local normal = {}    -- address -> letzte normale Geometrie (für Apps, die sich vor unserem Ereignis schon selbst vergrößert haben)
local quietUntil = {} -- address -> bis wann App-Wünsche ignoriert werden (Minimieren/Zurückholen)
local lastPressT = -10
local quietAll = -10     -- bis wann App-Wünsche ALLER Fenster ignoriert werden (ein Minimieren ist unterwegs, Fenster noch unbekannt)

-- Echte Uhrzeit in Sekunden (os.clock wäre die Rechenzeit von Hyprland und läuft viel langsamer)
local function now()
    local f = io.open("/proc/uptime", "r")
    if not f then return os.time() end
    local s = f:read("*n")
    f:close()
    return s or os.time()
end
function M.notePress() lastPressT = now() end

local function nearArea(w)
    local m = w.monitor or hl.get_active_monitor()
    if m == nil then return false end
    local x, y, aw, ah = area(m, w)
    return math.abs(w.size.x - aw) < 12 and math.abs(w.size.y - ah) < 12 and math.abs(w.at.x - x) < 12 and math.abs(w.at.y - y) < 12
end

-- Größe vor dem Maximieren (für die Fenstergrößen-Erinnerung dx_sizes), sonst nil
function M.maxedOrig(w)
    local o = w ~= nil and userMax[w.address] or nil
    if o ~= nil then return o.w, o.h end
    return nil
end

function M.isMaxed(w)
    return w ~= nil and maxed[w.address] == true
end

local function winByAddr(address)
    for _, w in ipairs(hl.get_windows()) do
        if w.address == address then return w end
    end
    return nil
end

local function parked(w)
    return w == nil or w.workspace == nil or w.workspace.id == nil or w.workspace.id < 1 or w.workspace.name == "minimized"
end

-- Der App unseren Zustand mitteilen (ohne dass Hyprland selbst maximiert: intern 0)
local toldAt = {}
local function tellApp(address, on)
    toldAt[address] = now()
    hl.dispatch(hl.dsp.window.fullscreen_state({ window = "address:" .. address, internal = 0, client = on and 1 or 0 }))
end

local function noAnimFor(address, ms)
    local a = "address:" .. address
    hl.dispatch(hl.dsp.window.set_prop({ window = a, prop = "no_anim", value = "1" }))
    hl.timer(function() pcall(function() hl.dispatch(hl.dsp.window.set_prop({ window = a, prop = "no_anim", value = "0" })) end) end,
             { timeout = ms or 700, type = "oneshot" })
end

local function applyArea(w)
    local m = w.monitor or hl.get_active_monitor()
    local x, y, aw, ah = area(m, w)
    local a = "address:" .. w.address
    hl.dispatch(hl.dsp.window.resize({ window = a, x = aw, y = ah, relative = false }))
    hl.dispatch(hl.dsp.window.move({ window = a, x = x, y = y, relative = false }))
end

-- Letzte normale Geometrie mitschreiben; wer ein maximiertes Fenster von Hand verkleinert/verschiebt, hat es damit "wiederhergestellt"
local drift = {}
local function watchStates()
    pcall(function()
        for _, w in ipairs(hl.get_windows()) do
            if w.mapped and w.floating and w.fullscreen == 0 and not parked(w) and w.monitor ~= nil and w.size.x > 100 and w.size.y > 60 then
                local near = nearArea(w)
                if maxed[w.address] then
                    if near then drift[w.address] = nil
                    else
                        drift[w.address] = (drift[w.address] or 0) + 1
                        if drift[w.address] >= 3 then                  -- seit gut einer Sekunde nicht mehr in Maximal-Größe: gilt als normal
                            maxed[w.address], userMax[w.address], drift[w.address] = nil, nil, nil
                            tellApp(w.address, false)
                        end
                    end
                elseif not near then
                    normal[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
                end
            end
        end
    end)
end

function M.setMax(w)
    if w == nil then return end
    local a = "address:" .. w.address
    if w.fullscreen == 2 or w.fullscreen == 3 then return end   -- echtes Vollbild nicht anfassen
    if tiling ~= nil and tiling.isTiled(w) then tiling.setMaxed(w.address, true) end
    if not maxed[w.address] then
        local o = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
        if (w.fullscreen == 1 or nearArea(w)) and normal[w.address] ~= nil then o = normal[w.address] end   -- App hat sich schon selbst vergrößert
        userMax[w.address] = o
    end
    maxed[w.address], drift[w.address] = true, nil
    if not w.floating then hl.dispatch(hl.dsp.window.float({ window = a, action = "set" })) end   -- "set" schaltet in dieser Version um: nur wenn nötig
    tellApp(w.address, true)
    applyArea(w)
end

function M.unMax(w)
    if w == nil then return end
    local a = "address:" .. w.address
    local o = userMax[w.address] or normal[w.address]
    maxed[w.address], userMax[w.address], drift[w.address] = nil, nil, nil
    tellApp(w.address, false)
    if tiling ~= nil then tiling.setMaxed(w.address, false) end
    if tiling ~= nil and tiling.isTiled(w) then
        tiling.retile(w.workspace and w.workspace.id)
        return
    end
    if o ~= nil then
        hl.dispatch(hl.dsp.window.resize({ window = a, x = o.w, y = o.h, relative = false }))
        hl.dispatch(hl.dsp.window.move({ window = a, x = o.x, y = o.y, relative = false }))
    else
        M.snapWindow(w, "restore")
    end
end

-- Der "Wiederherstellen"-Knopf einer App ändert nur ihren eigenen Zustand (für die App nicht mehr maximiert); Hyprland meldet dafür kein
-- Ereignis. Deshalb nach jedem Klick (und regelmäßig) vergleichen: hat die App ihn geändert? Nach einem Klick ins aktive Fenster gilt
-- das als Wunsch des Nutzers, sonst wird unser Zustand wiederhergestellt.
local function syncClient(afterClick)
    pcall(function()
        local act = hl.get_active_window()
        local t = now()
        for _, w in ipairs(hl.get_windows()) do
            local a = w.address
            if w.mapped and (w.fullscreen or 0) == 0 and not parked(w) and t - (toldAt[a] or -10) > 0.3 then
                local fc = w.fullscreen_client or 0
                if maxed[a] and fc == 0 then
                    if afterClick and act ~= nil and act.address == a and (quietUntil[a] or 0) < t and quietAll < t then
                        noAnimFor(a, 600)
                        M.unMax(w)
                    else
                        tellApp(a, true)
                    end
                elseif not maxed[a] and fc == 1 then
                    tellApp(a, false)
                end
            end
        end
    end)
end
function M.afterClick()
    hl.timer(function() syncClient(true) end, { timeout = 80, type = "oneshot" })
    hl.timer(function() syncClient(true) end, { timeout = 300, type = "oneshot" })
end
hl.timer(function() watchStates(); if now() - lastPressT > 1.2 then syncClient(false) end end, { timeout = 400, type = "repeat" })

-- Ein maximiertes Fenster wird an der Titelleiste gezogen (Shell-Leiste, XWayland-Apps): erst auf die alte Größe zurück, und zwar so,
-- dass der Zeiger im gleichen Verhältnis auf der Leiste bleibt wie vorher (wie unter Windows). cx/cy = Zeigerposition.
function M.restoreForDrag(address, cx, cy)
    local w = winByAddr(address)
    if w == nil or not M.isMaxed(w) then return end
    local o = userMax[address] or normal[address]
    local fx = (cx - w.at.x) / math.max(1, w.size.x)
    local oy = cy - w.at.y
    noAnimFor(address, 400)
    M.unMax(w)
    if o ~= nil then
        hl.dispatch(hl.dsp.window.move({ window = "address:" .. address, x = math.floor(cx - fx * o.w), y = cy - oy, relative = false }))
    end
end

function M.toggleMax(w)
    w = w or hl.get_active_window()
    if w == nil then return end
    noAnimFor(w.address, 500)
    if M.isMaxed(w) then M.unMax(w) else M.setMax(w) end
end

function M.toggleMaxAddr(address)
    M.toggleMax(winByAddr(address))
end

-- Minimieren/Zurückholen (von der Shell und dem X11-Wächter gemeldet). Beide geben ein leeres Dispatch-Ergebnis zurück, damit die
-- Shell sie direkt über den Hyprland-Socket aufrufen kann ("dispatch DXSnap.…").
function M.noteMinimize(address)
    quietUntil[address] = now() + 2.0
    return hl.dsp.no_op()
end
-- Der X11-Wächter sieht "Minimieren" sofort, braucht aber einen Moment, um das Fenster zu finden: so lange gilt Ruhe für alle
function M.noteMinimizeAny()
    quietAll = now() + 0.6
    return hl.dsp.no_op()
end

-- Nach dem Zurückholen: Geometrie nach UNSEREM Zustand setzen – maximiert bleibt maximiert, sonst die Geometrie von vor dem Minimieren
function M.afterRestore(address, x, y, ww, hh)
    quietUntil[address] = now() + 2.0
    local function apply()
        pcall(function()
            local w = winByAddr(address)
            if w == nil or parked(w) then return end
            if maxed[address] then
                tellApp(address, true)
                if not nearArea(w) then applyArea(w) end
            elseif x ~= nil and ww ~= nil and ww > 0 then
                local a = "address:" .. address
                if math.abs(w.size.x - ww) > 3 or math.abs(w.size.y - hh) > 3 then hl.dispatch(hl.dsp.window.resize({ window = a, x = ww, y = hh, relative = false })) end
                if math.abs(w.at.x - x) > 3 or math.abs(w.at.y - y) > 3 then hl.dispatch(hl.dsp.window.move({ window = a, x = x, y = y, relative = false })) end
            end
        end)
    end
    apply()
    hl.timer(apply, { timeout = 150, type = "oneshot" })     -- Apps ändern ihre Größe beim Wiederauftauchen manchmal selbst
    hl.timer(apply, { timeout = 500, type = "oneshot" })
    return hl.dsp.no_op()
end

-- Maximieren-/Wiederherstellen-Wünsche der App (xdg set/unset_maximized, X11 _NET_WM_STATE): Hyprland meldet "fullscreen".
-- Wunsch einer App (Maximieren-/Wiederherstellen-Knopf, Doppelklick auf ihre Titelleiste) entscheiden. want: true/false.
-- Gezählt wird er nur nach einem echten Klick und wenn kein Minimieren unterwegs ist. Entschieden wird nach 45 ms: Brave schickt beim
-- Minimieren zuerst "maximieren" und gleich danach "minimieren" – so wird dabei nie sichtbar maximiert.
local function appWants(address, want)
    noAnimFor(address, 800)
    local function decide()
        pcall(function()
            local t = now()
            local ww = winByAddr(address)
            if ww == nil or parked(ww) then return end
            local byUser = (t - lastPressT) < 1.0 and (quietUntil[address] or 0) < t and quietAll < t
            if not byUser then                                     -- kein Klick dahinter: unser Zustand bleibt
                tellApp(address, maxed[address] == true)
                if maxed[address] and not nearArea(ww) then applyArea(ww) end
                return
            end
            if want and not maxed[address] then M.setMax(ww)
            elseif not want and maxed[address] then M.unMax(ww)
            else tellApp(address, maxed[address] == true) end
            -- Manche Apps ändern danach noch einmal selbst ihre Größe: unseren Zustand kurz darauf erneut durchsetzen
            local function reassert()
                pcall(function()
                    local w3 = winByAddr(address)
                    if w3 == nil or parked(w3) then return end
                    if maxed[address] then
                        if not nearArea(w3) then applyArea(w3) end
                        if (w3.fullscreen_client or 0) ~= 1 or (w3.fullscreen or 0) ~= 0 then tellApp(address, true) end
                    elseif (w3.fullscreen or 0) ~= 0 or (w3.fullscreen_client or 0) ~= 0 then
                        tellApp(address, false)
                    end
                end)
            end
            hl.timer(reassert, { timeout = 150, type = "oneshot" })
            hl.timer(reassert, { timeout = 450, type = "oneshot" })
        end)
    end
    hl.timer(decide, { timeout = 45, type = "oneshot" })
end

-- X11-Apps: Hyprland soll ihre Maximieren-Wünsche gar nicht erst selbst ausführen (Fensterregel suppress_event, siehe hyprland.lua);
-- der X11-Wächter (dx-x11-iconify) liest sie mit und meldet sie hierher. action: "add" | "remove" | "toggle"
function M.appRequest(address, action)
    pcall(function()
        local want = (action == "add") or (action == "toggle" and not maxed[address])
        appWants(address, want)
    end)
    return hl.dsp.no_op()
end

-- Wayland-Apps (xdg set/unset_maximized): Hyprland meldet "fullscreen"
hl.on("window.fullscreen", function(w)
    pcall(function()
        if w == nil then return end
        local address = w.address
        local fi, fc = w.fullscreen or 0, w.fullscreen_client or 0
        if fi == 2 or fi == 3 then return end                       -- echtes Vollbild: Sache von Hyprland und der App
        local want
        if fi == 1 then want = true                                  -- App will maximiert werden
        elseif fc == 0 and maxed[address] then want = false           -- App will nicht mehr maximiert sein (ihr Wiederherstellen-Knopf)
        elseif fc == 1 and not maxed[address] then want = nil         -- App behauptet maximiert, ist es bei uns aber nicht
        else return end                                               -- passt zu unserem Zustand (z. B. unser eigenes tellApp)
        -- Hyprland hat bei fi == 1 schon selbst maximiert: sofort zurücknehmen (Hyprland stellt dabei die alte Größe wieder her)
        noAnimFor(address, 800)
        tellApp(address, maxed[address] == true)
        if want ~= nil then appWants(address, want) end
    end)
end)

-- ---------- Minimieren / Zurückholen (die Shell ruft das direkt über den Hyprland-Socket auf) ----------
local minGeo = {}    -- address -> { x, y, w, h } Geometrie beim Minimieren (nur für nicht maximierte Fenster nötig)
function M.minimize(address)
    pcall(function()
        quietUntil[address] = now() + 2.0
        local w = winByAddr(address)
        if w == nil or parked(w) then return end
        if not maxed[address] then minGeo[address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y } end
        noAnimFor(address, 1000)
        hl.dispatch(hl.dsp.window.move({ window = "address:" .. address, workspace = "name:minimized", follow = false }))
    end)
    return hl.dsp.no_op()
end

function M.unminimize(address, ws)
    pcall(function()
        quietUntil[address] = now() + 2.0
        noAnimFor(address, 1000)
        hl.dispatch(hl.dsp.window.move({ window = "address:" .. address, workspace = ws, follow = false }))
        local g = minGeo[address]
        M.afterRestore(address, g and g.x, g and g.y, g and g.w, g and g.h)
    end)
    return hl.dsp.no_op()
end

local function forget(w)
    pcall(function()
        if w == nil then return end
        local a = w.address
        userMax[a], maxed[a], normal[a], quietUntil[a], drift[a], minGeo[a] = nil, nil, nil, nil, nil, nil
    end)
end
hl.on("window.destroy", forget)
hl.on("window.close", forget)

-- ---------- Tastatur: Windows-artige Ketten ----------
function M.arrow(dir)
    local w = hl.get_active_window()
    if w == nil then return end
    local z = zoneOf[w.address]
    local maximized = w.fullscreen ~= 0
    if dir == "left" then
        M.snapWindow(w, z == "right" and "restore" or "left")
    elseif dir == "right" then
        M.snapWindow(w, z == "left" and "restore" or "right")
    elseif dir == "up" then
        if z == "left" then M.snapWindow(w, "tl")
        elseif z == "right" then M.snapWindow(w, "tr")
        elseif z == "bl" then M.snapWindow(w, "left")
        elseif z == "br" then M.snapWindow(w, "right")
        else M.toggleMax(w) end
    elseif dir == "down" then
        if M.isMaxed(w) then M.unMax(w)
        elseif maximized then hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" }))
        elseif z == "left" then M.snapWindow(w, "bl")
        elseif z == "right" then M.snapWindow(w, "br")
        elseif z == "tl" then M.snapWindow(w, "left")
        elseif z == "tr" then M.snapWindow(w, "right")
        elseif opts.minimize then opts.minimize(w) end
    end
end

-- ---------- Maus: Zonen am Rand ----------
local function overlap(a1, a2, b1, b2) return a1 < b2 and b1 < a2 end

local function hasNeighbor(m, side)
    for _, o in ipairs(hl.get_monitors()) do
        if o.name ~= m.name then
            if side == "left" and o.x + o.width == m.x and overlap(o.y, o.y + o.height, m.y, m.y + m.height) then return true end
            if side == "right" and o.x == m.x + m.width and overlap(o.y, o.y + o.height, m.y, m.y + m.height) then return true end
            if side == "top" and o.y + o.height == m.y and overlap(o.x, o.x + o.width, m.x, m.x + m.width) then return true end
        end
    end
    return false
end

function M.zoneAt(m, cx, cy)
    local lx, rx = cx - m.x, m.x + m.width - cx
    local ty, by = cy - m.y, m.y + m.height - cy
    local atL = lx <= EDGE and not hasNeighbor(m, "left")
    local atR = rx <= EDGE and not hasNeighbor(m, "right")
    local atT = ty <= EDGE and not hasNeighbor(m, "top")
    if atL then
        if ty <= CORNER then return "tl" elseif by <= CORNER then return "bl" else return "left" end
    elseif atR then
        if ty <= CORNER then return "tr" elseif by <= CORNER then return "br" else return "right" end
    elseif atT then
        if lx <= CORNER then return "tl" elseif rx <= CORNER then return "tr" else return "max" end
    end
    return nil
end

local function monitorAt(cx, cy)
    for _, m in ipairs(hl.get_monitors()) do
        if cx >= m.x and cx < m.x + m.width and cy >= m.y and cy < m.y + m.height then return m end
    end
    return nil
end

local press = nil           -- { pos = { address -> {x,y} } }
local lastText = ""
local timer = nil

local function writePreview(text)
    if text == lastText then return end
    lastText = text
    hl.exec_cmd("sh -c 'printf %s \"" .. text .. "\" > " .. PREVIEW .. "'")
end

-- Fenster, das seit dem Klick bewegt wurde (egal welches gerade fokussiert ist)
local function movedWindow()
    if press == nil then return nil end
    for _, w in ipairs(hl.get_windows()) do
        local p = press.pos[w.address]
        if p ~= nil and w.mapped and w.floating and w.fullscreen == 0
           and w.workspace ~= nil and w.workspace.id ~= nil and w.workspace.id > 0 and w.workspace.name ~= "minimized" then   -- auch nach einem Bildschirmwechsel (anderer Desktop) zählt das Fenster
            if math.abs(w.at.x - p.x) + math.abs(w.at.y - p.y) > 24 then return w end
        end
    end
    return nil
end

local function zoneNow()
    local c = hl.get_cursor_pos()
    if c == nil then return nil, nil, nil end
    local m = monitorAt(c.x, c.y)
    if m == nil then return nil, nil, c end
    return M.zoneAt(m, c.x, c.y), m, c
end

local function tick()
    if press == nil then return end
    local w = movedWindow()
    if w == nil then writePreview("none"); press.zoneIdx = nil; return end
    -- Shift gedrückt: eigene Zonen anzeigen, Zone unter dem Zeiger hervorheben
    if Z ~= nil and shiftDown() then
        local c = hl.get_cursor_pos()
        local mon = c and monitorAt(c.x, c.y)
        if mon ~= nil and #Z.zones(mon.name) > 0 then
            local idx, z = Z.zoneAt(mon.name, c.x, c.y)
            press.zoneIdx, press.zoneMon, press.zoneT = idx, mon.name, now()
            if idx ~= nil then
                writePreview(string.format("zones %s %d %d %d %d %d", mon.name, idx, z.x, z.y, z.w, z.h))
            else
                writePreview("zones " .. mon.name .. " 0 0 0 0 0")
            end
            return
        end
    end
    if tiling ~= nil and tiling.isTiled(w) then
        writePreview("none")
        local c = hl.get_cursor_pos()
        if c ~= nil then pcall(tiling.liveSwap, w, c.x, c.y) end
        return
    end
    -- angedocktes Fenster wird gezogen: ein anderes angedocktes Fenster unter dem Zeiger gleitet live auf dessen alten Platz
    if press.snaps ~= nil and press.snaps[w.address] ~= nil and now() - (press.lastSwap or 0) > 0.25 then
        local c = hl.get_cursor_pos()
        if c ~= nil then
            for _, o in ipairs(hl.get_windows()) do
                local oz = press.snaps[o.address]
                if o.address ~= w.address and oz ~= nil and o.mapped and o.floating and o.workspace ~= nil and w.workspace ~= nil
                   and o.workspace.id == w.workspace.id and o.monitor ~= nil and w.monitor ~= nil and o.monitor.name == w.monitor.name
                   and c.x >= o.at.x and c.x <= o.at.x + o.size.x and c.y >= o.at.y and c.y <= o.at.y + o.size.y then
                    local wz = press.snaps[w.address]
                    local x, y, ww, wh = M.rectFor(o.monitor, wz, o)
                    local oa = "address:" .. o.address
                    hl.dispatch(hl.dsp.window.resize({ window = oa, x = ww, y = wh, relative = false }))
                    hl.dispatch(hl.dsp.window.move({ window = oa, x = x, y = y, relative = false }))
                    press.snaps[o.address], press.snaps[w.address] = wz, oz     -- o sitzt jetzt in w's Zone, w "gehört" zu o's alter Zone
                    zoneOf[o.address] = wz
                    press.lastSwap = now()
                    break
                end
            end
        end
    end
    local zone, m = zoneNow()
    if zone == nil then writePreview("none"); return end
    local rz = (zone == "max") and "max" or zone
    local x, y, ww, wh = M.rectFor(m, rz, w)
    writePreview(string.format("%s %d %d %d %d", m.name, x, y, ww, wh))
end

local function onPress()
    M.notePress()
    local pos = {}
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and w.floating then pos[w.address] = { x = w.at.x, y = w.at.y, ws = w.workspace and w.workspace.id } end
    end
    press = { pos = pos, snaps = {}, lastSwap = 0 }
    -- Fenster, die gerade genau in ihrer Andock-Zone sitzen (Halbbild, Viertel …): dürfen beim Ziehen live tauschen
    for _, w in ipairs(hl.get_windows()) do
        local z = zoneOf[w.address]
        if z ~= nil and z ~= "max" and w.mapped and w.floating and w.workspace ~= nil and w.monitor ~= nil then
            local ok, x, y, ww, wh = pcall(function()
                local a, b, c, d = M.rectFor(w.monitor, z, w); return a, b, c, d
            end)
            if ok and x ~= nil and math.abs(w.at.x - x) + math.abs(w.at.y - y) + math.abs(w.size.x - ww) + math.abs(w.size.y - wh) < 16 then
                press.snaps[w.address] = z
            end
        end
    end
    if timer == nil then
        timer = hl.timer(tick, { timeout = 70, type = "repeat" })
    else
        timer:set_enabled(true)
    end
end

local function finish()
    local p = press
    press = nil
    if timer ~= nil then timer:set_enabled(false) end
    writePreview("none")
    if p == nil then return end
    press = p
    local w = movedWindow()
    press = nil
    if w == nil then return end
    -- losgelassen über einer eigenen Zone (Shift war beim Ziehen gedrückt): einrasten
    if Z ~= nil and p.zoneIdx ~= nil and p.zoneT ~= nil and now() - p.zoneT < 0.45 then
        if tiling ~= nil and tiling.isTiled(w) then tiling.release(w) end
        Z.place(w, p.zoneIdx)
        return
    end
    local zone, m, c = zoneNow()
    if tiling ~= nil and tiling.isTiled(w) then
        if c ~= nil then tiling.dropAt(w, c.x, c.y) end
    elseif zone ~= nil then
        hl.exec_cmd("sh -c 'echo \"$(date +%T) snap " .. zone .. " " .. tostring(w.class) .. "\" >> ~/.local/state/draconyx/snap.log'")
        if zone == "max" then
            M.setMax(w)
            zoneOf[w.address] = "max"
        else
            M.snapWindow(w, zone)
        end
    end
end

-- Loslassen der linken Maustaste sofort festhalten (Datei mit neuem Zeitstempel): die Verschiebe-Helfer der Shell (dx-window-drag,
-- dx-x11-iconify) hören darauf auf, damit sie das Andocken beim Loslassen nicht überschreiben – unabhängig davon, wann die Shell es merkt.
local MOUSEUP = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/draconyx-mouse-up"
local function markRelease()
    local f = io.open(MOUSEUP, "w")
    if f then f:write(tostring(os.time()), "\n"); f:close() end
end

local function onRelease()
    markRelease()
    M.afterClick()
    -- Hyprland beendet das Ziehen erst nach dem Loslassen: kurz warten, dann auswerten
    hl.timer(finish, { timeout = 40, type = "oneshot" })
end

-- Klick-Hooks (nicht verbrauchend) für das Ziehen: ohne Modifikator (Titelleisten) und mit den Modifikatoren der
-- Maus-Kombinationen "window_drag"/"window_drag_alt" (umbindbar in den Aurora-Einstellungen). Ohne Registry: Alt und Strg+Alt.
function M.bindMouse(DXB)
    local mods, seen = { "" }, { [""] = true }
    local function add(pre) if pre ~= nil and not seen[pre] then seen[pre] = true; table.insert(mods, pre) end end
    if DXB ~= nil then
        add(DXB.mousePrefix("window_drag")); add(DXB.mousePrefix("window_drag_alt"))
    else
        add("ALT + "); add("CTRL + ALT + ")
    end
    for _, mod in ipairs(mods) do
        hl.bind(mod .. "mouse:272", onPress, { non_consuming = true })
        hl.bind(mod .. "mouse:272", onRelease, { release = true, non_consuming = true })
    end
end

return M
