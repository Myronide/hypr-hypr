-- Spiele-Desktop: (1) fremde Fenster (Steam, Discord, Launcher, Dialoge), die waehrend eines Vollbild-Spiels auf dem Spiele-Desktop
-- aufgehen, werden still auf den zuletzt benutzten normalen Desktop verschoben, damit sie nicht ueber dem Spiel schweben und das
-- Spiel den Fokus behaelt (Alt+Tab ginge sonst nur ueber dasselbe Fenster). (2) Verlaesst der Fokus ein Spiel/Vollbild-Fenster, wird der
-- Zeiger EINMAL aus dessen Flaeche gesetzt, sonst bleibt der Zeiger-Fang (pointer constraint) des Spiels bestehen (cursor.no_warps
-- verhindert sonst jedes Mitziehen). Normale Fokuswechsel bleiben unberuehrt.
local M = {}
local GAME_WS = 10

local function isGame(w)
    if w == nil then return false end
    local c = w.class or ""
    if c:find("^steam_app_") or c:find("^gamescope") or c:find("^RocketLeague") then return true end
    return w.content_type == "game" or w.contentType == "game"
end
M.isGame = isGame

local lastWs = {}       -- Monitor-ID -> zuletzt benutzter normaler Desktop
local function normalWs(ws)
    return ws ~= nil and ws.id ~= nil and ws.id > 0 and ws.id ~= GAME_WS and ws.name ~= "minimized" and not tostring(ws.name):find("^special")
end

local function gameOnSpielDesktop(except)
    for _, x in ipairs(hl.get_windows()) do
        if x.mapped and x.address ~= except and x.workspace ~= nil and x.workspace.id == GAME_WS and isGame(x) then return x end
    end
    return nil
end

local function targetWs(w)
    local mid = w.monitor and w.monitor.id
    local t = mid and lastWs[mid]
    if t ~= nil then return t end
    local used = {}
    for _, x in ipairs(hl.get_windows()) do if x.workspace then used[x.workspace.id] = true end end
    for i = 1, 9 do if not used[i] then return i end end
    return 1
end

local moved = {}        -- Schutz: jedes Fenster hoechstens einmal verschieben
local function evict(addr)
    pcall(function()
        local w
        for _, x in ipairs(hl.get_windows()) do if x.address == addr then w = x break end end
        if w == nil or not w.mapped or moved[addr] then return end
        if w.workspace == nil or w.workspace.id ~= GAME_WS or isGame(w) then return end
        local g = gameOnSpielDesktop(addr)
        if g == nil then return end
        moved[addr] = true
        local wasActive = hl.get_active_window()
        hl.dispatch(hl.dsp.window.move({ window = "address:" .. addr, workspace = targetWs(w), follow = false }))   -- follow=false: still
        if wasActive ~= nil and wasActive.address == addr then hl.dispatch(hl.dsp.focus({ window = "address:" .. g.address })) end
    end)
end

hl.on("window.open", function(w)
    if w == nil then return end
    local addr = w.address
    hl.timer(function() evict(addr) end, { timeout = 250, type = "oneshot" })   -- erst wenn Klasse/Desktop feststehen
    hl.timer(function() evict(addr) end, { timeout = 1200, type = "oneshot" })  -- Nachzuegler (Fenster, die erst spaeter den Desktop wechseln)
end)
hl.on("window.close", function(w) if w then moved[w.address] = nil end end)

-- Fokus verlaesst ein Spiel-/Vollbild-Fenster -> Zeiger einmal heraussetzen
local prev = nil        -- { address, game, x, y, w, h } des zuletzt aktiven Fensters
local function snapshot(w)
    if w == nil or w.at == nil or w.size == nil then return nil end
    return { address = w.address, hold = isGame(w) or (w.fullscreen or 0) ~= 0, x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
end
local function freeCursor(from, to)
    pcall(function()
        local c = hl.get_cursor_pos()
        if c == nil then return end
        if c.x < from.x or c.x >= from.x + from.w or c.y < from.y or c.y >= from.y + from.h then return end   -- Zeiger liegt schon woanders
        local cx, cy
        if to ~= nil and to.at ~= nil and to.size ~= nil and to.mapped then
            cx, cy = to.at.x + math.floor(to.size.x / 2), to.at.y + math.floor(to.size.y / 2)
        end
        if cx == nil then
            -- kein Zielfenster: auf einen anderen Monitor, sonst an den Rand der Spielflaeche
            cx, cy = nil, nil
            local cur = hl.get_active_monitor()
            for _, m in ipairs(hl.get_monitors()) do
                if cur == nil or m.name ~= cur.name then cx, cy = m.x + math.floor(m.width / 2), m.y + math.floor(m.height / 2) break end
            end
            if cx == nil then cx, cy = from.x + from.w - 2, from.y + from.h - 2 end
        end
        hl.dispatch(hl.dsp.cursor.move({ x = cx, y = cy }))
    end)
end

hl.on("window.active", function(w)
    pcall(function()
        if w ~= nil and normalWs(w.workspace) and w.monitor then lastWs[w.monitor.id] = w.workspace.id end
        local from = prev
        prev = snapshot(w)
        if from ~= nil and from.hold and (w == nil or w.address ~= from.address) then
            local addr = w and w.address
            hl.timer(function()
                local to
                if addr then for _, x in ipairs(hl.get_windows()) do if x.address == addr then to = x break end end end
                freeCursor(from, to)
            end, { timeout = 120, type = "oneshot" })
        end
    end)
end)
hl.on("window.fullscreen", function(w) pcall(function() if prev ~= nil and w ~= nil and w.address == prev.address then prev = snapshot(w) end end) end)

return M
