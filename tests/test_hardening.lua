-- Härtung dx_snap/dx_tiling/dx_binds: gemockte Hyprland-API, keine Live-Sitzung.
local timers, handlers, actions = {}, {}, {}
local realOpen = io.open
io.open = function(path, mode)
    if path == "/proc/uptime" then return realOpen(path, mode) end
    if mode == "w" then return { write = function() end, close = function() end } end
    return nil
end
local mon = { name = "DP-1", x = -1920, y = 0, width = 3840, height = 2160, scale = 2, reserved = { top = 0, bottom = 60, left = 0, right = 0 } }
local wins = {}
local function mk(addr, x, y, w, h)
    local t = { address = addr, floating = true, fullscreen = 0, fullscreen_client = 0, mapped = true, class = "T", pid = 1,
        at = { x = x, y = y }, size = { x = w, y = h }, workspace = { id = 1, name = "1" }, monitor = mon }
    wins[#wins + 1] = t
    return t
end
local active
local function action(name) return function(a) return { name = name, args = a } end end
hl = {
    on = function(ev, fn) handlers[ev] = handlers[ev] or {}; table.insert(handlers[ev], fn) end,
    is_key_down = function() return false end,
    get_windows = function() return wins end,
    get_monitors = function() return { mon } end,
    get_active_window = function() return active end,
    get_active_monitor = function() return mon end,
    get_active_workspace = function() return { id = 1 } end,
    get_cursor_pos = function() return { x = 0, y = 0 } end,
    exec_cmd = function() end,
    bind = function() return nil end,          -- wie Hyprland: ungültige Kombination -> nil
    timer = function(fn, o) local t = { fn = fn, o = o }; function t:set_enabled() end; timers[#timers + 1] = t; return t end,
    dsp = { window = setmetatable({}, { __index = function(_, k) return action(k) end }), no_op = function() end, focus = action("focus") },
    dispatch = function(a)
        actions[#actions + 1] = a
        local p, target = a.args or {}, nil
        for _, w in ipairs(wins) do if p.window == "address:" .. w.address then target = w end end
        if target == nil and p.window == nil then target = active end
        if target == nil then return end
        if a.name == "move" and p.x then target.at = { x = p.x, y = p.y } end
        if a.name == "resize" then target.size = { x = p.x, y = p.y } end
    end,
}
package.preload.dx_zones = function() error("keine Zonen im Test") end
local function fire(ev, ...) for _, f in ipairs(handlers[ev] or {}) do f(...) end end
local function run(maxMs) for _, t in ipairs(timers) do if t.o.type == "oneshot" and t.o.timeout <= maxMs and not t.done then t.done = true; t.fn() end end end

local snap = dofile("hypr/dx_snap.lua")

-- 1. Skalierung: Arbeitsfläche in logischen Pixeln (3840/2 = 1920 breit, 1080 hoch, 60 unten reserviert)
local a = mk("0xa", -1500, 100, 800, 600)
snap.snapWindow(a, "right")
assert(a.size.x == math.floor((1920 - 16 - 8) / 2), "Skalierung nicht beachtet: " .. a.size.x)
assert(a.at.x + a.size.x <= mon.x + 1920, "Fenster ragt über den Monitor")
assert(a.size.y == 1080 - 60 - 16 - 30 or a.size.y == 1080 - 60 - 16, "Höhe passt nicht: " .. a.size.y)

-- 2. toggleMaxAddr eines verschwundenen Fensters darf das aktive Fenster NICHT umschalten
active = a
snap.toggleMaxAddr("0xgone")
assert(not snap.isMaxed(a), "aktives Fenster wurde ersatzweise maximiert")
snap.toggleMaxAddr(nil)
assert(not snap.isMaxed(a))

-- 3. Andocken hebt den Maximiert-Zustand auf
snap.setMax(a)
assert(snap.isMaxed(a))
snap.snapWindow(a, "left")
assert(not snap.isMaxed(a), "angedocktes Fenster gilt noch als maximiert")

-- 4. Zustand wird beim Schließen verworfen (Adress-Wiederverwendung)
snap.setMax(a)
fire("window.close", a)
assert(not snap.isMaxed(a) and snap.maxedOrig(a) == nil, "Zustand überlebt Schließen")

-- 5. veraltete Zone: von Hand verschobenes Fenster hat keine Zone mehr (Win+Hoch maximiert statt Viertel)
local b = mk("0xb", 0, 0, 500, 400)
snap.snapWindow(b, "left")
b.at.x, b.at.y = -1000, 300; b.size.x = 500
active = b
snap.arrow("up")
assert(snap.isMaxed(b), "veraltete Zone führte zu Viertel statt Maximieren")

-- 6. fitRect holt unsichtbare Geometrie (abgesteckter Monitor) zurück
local x, y, w, h = snap.fitRect(9000, 9000, 800, 600, b)
assert(x >= mon.x and x + w <= mon.x + 1920 and y >= 0 and y + h <= 1080, "fitRect liegt außerhalb")
local x2 = snap.fitRect(-500, 100, 800, 600, b)
assert(x2 == -500, "sichtbare Geometrie darf nicht verändert werden")

-- 7. unminimize ohne Desktop-Angabe fällt auf Ursprung/aktiven Desktop zurück und merkt sich nichts Altes
local c = mk("0xc", 0, 0, 600, 400)
snap.minimize("0xc")
c.workspace = { id = 11, name = "minimized" }
snap.unminimize("0xc", nil)
local moved
for _, ac in ipairs(actions) do if ac.name == "move" and ac.args.workspace == 1 then moved = true end end
assert(moved, "unminimize ohne Desktop hat nichts bewegt")
assert(snap.restoreLast() == false, "restoreLast findet ein schon zurückgeholtes Fenster")

-- 8. Doppelte Fenster-Ereignisse laufen nicht ineinander
local d = mk("0xd", 0, 0, 600, 400)
d.fullscreen = 1
fire("window.fullscreen", d)
run(2000)

-- 9. Tiling: setDefault(nil) ändert nichts, Zustand wird beim Schließen verworfen
local tiling = dofile("hypr/dx_tiling.lua")
tiling.setDefault(nil); assert(tiling.getDefault() == "floating")
local e = mk("0xe", 0, 0, 600, 400)
tiling.add(e); assert(tiling.isTiled(e))
tiling.setMaxed("0xe", true)
fire("window.close", e)
assert(not tiling.isTiled(e))
tiling.add(e); assert(tiling.isTiled(e))
tiling.retile(1)
assert(e.size.x > 100, "wiederverwendete Adresse blieb als maximiert ausgeschlossen")
e.workspace = { id = 12, name = "minimized" }
assert(tiling.dropAt(e, 0, 0) == true or true)   -- darf nicht abstürzen
tiling.liveSwap(nil, nil, nil)
tiling.shift(1)

-- 10. dx_binds: ungültige Kombination (hl.bind gibt nil) -> keine Ausnahme, wirksame Kombination leer
local DXB = dofile("hypr/dx_binds.lua")
assert(DXB.bind("t1", "Test", "BOGUS + zzz", function() end) == nil)
assert(DXB.combo("t1") == "")

print("OK: Skalierung, toggleMaxAddr, Andocken/Maximieren, Schließen, veraltete Zone, fitRect, unminimize, Tiling, Binds")
