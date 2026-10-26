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
-- Maximieren oben ein Streifen frei. Aus, wenn die Shell-Einstellung "titleBars" ausgeschaltet ist (gelesen beim Laden/Neuladen).
local TITLEBAR = 30
local TB = TITLEBAR
local function readTB()
    local f = io.open((os.getenv("HOME") or "") .. "/.local/state/draconyx/settings.json", "r")
    if not f then return TITLEBAR end
    local s = f:read("*a") or ""
    f:close()
    if s:find('"titleBars"%s*:%s*false') then return 0 end
    return TITLEBAR
end
TB = readTB()
hl.on("config.reloaded", function() TB = readTB() end)

local function area(m)
    local r = m.reserved or {}
    local x = m.x + (r.left or 0) + GAP
    local y = m.y + (r.top or 0) + GAP + TB
    local w = m.width - (r.left or 0) - (r.right or 0) - 2 * GAP
    local h = m.height - (r.top or 0) - (r.bottom or 0) - 2 * GAP - TB
    return x, y, w, h
end

function M.rectFor(m, zone)
    local x0, y0, aw, ah = area(m)
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
    local x, y, ww, wh = M.rectFor(m, zone)
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

-- ---------- Eigenes Maximieren ----------
-- Hyprlands "maximized" setzt ein Vollbild-Flag am Desktop; dann gehen Mausklicks an das maximierte Fenster,
-- obwohl ein anderes darüber liegt. Deshalb: maximieren = normales schwebendes Fenster in Arbeitsflächengröße.
local userMax = {}   -- address -> { x, y, w, h } Geometrie vor dem Maximieren

local function nearArea(w)
    local m = w.monitor or hl.get_active_monitor()
    if m == nil then return false end
    local x, y, aw, ah = area(m)
    return math.abs(w.size.x - aw) < 12 and math.abs(w.size.y - ah) < 12
end

-- Größe vor dem Maximieren (für die Fenstergrößen-Erinnerung dx_sizes), sonst nil
function M.maxedOrig(w)
    local o = w ~= nil and userMax[w.address] or nil
    if o ~= nil then return o.w, o.h end
    return nil
end

function M.isMaxed(w)
    return w ~= nil and userMax[w.address] ~= nil and nearArea(w)
end

local function applyArea(w)
    local m = w.monitor or hl.get_active_monitor()
    local x, y, aw, ah = area(m)
    local a = "address:" .. w.address
    hl.dispatch(hl.dsp.window.resize({ window = a, x = aw, y = ah, relative = false }))
    hl.dispatch(hl.dsp.window.move({ window = a, x = x, y = y, relative = false }))
end

function M.setMax(w)
    if w == nil then return end
    local a = "address:" .. w.address
    if w.fullscreen == 1 then hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = "maximized", action = "unset" })) end
    if w.fullscreen == 2 or w.fullscreen == 3 then return end   -- echtes Vollbild nicht anfassen
    if tiling ~= nil and tiling.isTiled(w) then tiling.setMaxed(w.address, true) end
    if userMax[w.address] == nil or not nearArea(w) then
        userMax[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
    end
    if not w.floating then hl.dispatch(hl.dsp.window.float({ window = a, action = "set" })) end   -- "set" schaltet in dieser Version um: nur wenn nötig
    applyArea(w)
end

function M.unMax(w)
    if w == nil then return end
    local a = "address:" .. w.address
    if w.fullscreen == 1 then hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = "maximized", action = "unset" })) end
    local o = userMax[w.address]
    userMax[w.address] = nil
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

function M.toggleMax(w)
    w = w or hl.get_active_window()
    if w == nil then return end
    if M.isMaxed(w) then M.unMax(w) else M.setMax(w) end
end

function M.toggleMaxAddr(address)
    for _, w in ipairs(hl.get_windows()) do
        if w.address == address then M.toggleMax(w); return end
    end
end

-- Maximieren-Knopf der App (xdg set_maximized, auch X11): Hyprland meldet "fullscreen" mit Zustand 1.
-- Das wird in eigenes Maximieren umgewandelt (an/aus je nach aktuellem Zustand).
hl.on("window.fullscreen", function(w)
    pcall(function()
        if w ~= nil and w.fullscreen == 1 then
            local a = "address:" .. w.address
            local wasMax = M.isMaxed(w)
            hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = "maximized", action = "unset" }))
            -- Die App (z. B. Brave über XWayland) reagiert auf das Zurücknehmen mit einer eigenen Größenänderung.
            -- Erst danach das eigene Maximieren/Wiederherstellen anwenden, sonst springt das Fenster wieder klein.
            local addr = w.address
            local function apply()
                for _, ww in ipairs(hl.get_windows()) do
                    if ww.address == addr then
                        if wasMax then M.unMax(ww) else M.setMax(ww) end
                        return
                    end
                end
            end
            hl.timer(apply, { timeout = 140, type = "oneshot" })
            hl.timer(function() pcall(function()
                for _, ww in ipairs(hl.get_windows()) do
                    if ww.address == addr then
                        if wasMax then if M.isMaxed(ww) then M.unMax(ww) end else if not M.isMaxed(ww) then M.setMax(ww) end end
                        return
                    end
                end
            end) end, { timeout = 420, type = "oneshot" })
        end
    end)
end)
hl.on("window.destroy", function(w) pcall(function() if w ~= nil then userMax[w.address] = nil end end) end)
hl.on("window.close", function(w) pcall(function() if w ~= nil then userMax[w.address] = nil end end) end)

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
           and w.workspace ~= nil and w.workspace.id == p.ws and w.workspace.name ~= "minimized" then
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
            press.zoneIdx, press.zoneMon, press.zoneT = idx, mon.name, os.clock()
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
    if press.snaps ~= nil and press.snaps[w.address] ~= nil and os.clock() - (press.lastSwap or 0) > 0.25 then
        local c = hl.get_cursor_pos()
        if c ~= nil then
            for _, o in ipairs(hl.get_windows()) do
                local oz = press.snaps[o.address]
                if o.address ~= w.address and oz ~= nil and o.mapped and o.floating and o.workspace ~= nil and w.workspace ~= nil
                   and o.workspace.id == w.workspace.id and o.monitor ~= nil and w.monitor ~= nil and o.monitor.name == w.monitor.name
                   and c.x >= o.at.x and c.x <= o.at.x + o.size.x and c.y >= o.at.y and c.y <= o.at.y + o.size.y then
                    local wz = press.snaps[w.address]
                    local x, y, ww, wh = M.rectFor(o.monitor, wz)
                    local oa = "address:" .. o.address
                    hl.dispatch(hl.dsp.window.resize({ window = oa, x = ww, y = wh, relative = false }))
                    hl.dispatch(hl.dsp.window.move({ window = oa, x = x, y = y, relative = false }))
                    press.snaps[o.address], press.snaps[w.address] = wz, oz     -- o sitzt jetzt in w's Zone, w "gehört" zu o's alter Zone
                    zoneOf[o.address] = wz
                    press.lastSwap = os.clock()
                    break
                end
            end
        end
    end
    local zone, m = zoneNow()
    if zone == nil then writePreview("none"); return end
    local rz = (zone == "max") and "max" or zone
    local x, y, ww, wh = M.rectFor(m, rz)
    writePreview(string.format("%s %d %d %d %d", m.name, x, y, ww, wh))
end

local function onPress()
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
                local a, b, c, d = M.rectFor(w.monitor, z); return a, b, c, d
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
    if Z ~= nil and p.zoneIdx ~= nil and p.zoneT ~= nil and os.clock() - p.zoneT < 0.45 then
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

local function onRelease()
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
