-- Lua-Hooks/Timer kontrolliert ausführen, ohne echte Fenster oder Eingaben.
local timers, binds, actions = {}, {}, {}
local originalOpen = io.open
io.open = function(path, mode)
    if path == "/proc/uptime" then return originalOpen(path, mode) end
    if mode == "w" then return { write = function() end, close = function() end } end
    return nil -- weder Nutzereinstellungen lesen noch die echte Release-Datei schreiben
end
local mon = { name = "DP-1", x = 0, y = 0, width = 2560, height = 1440, reserved = {} }
local w = { address = "0x123", floating = true, fullscreen = 0, mapped = true,
    class = "Test", at = { x = 100, y = 100 }, size = { x = 800, y = 600 },
    workspace = { id = 1, name = "1" }, monitor = mon }
local cursor = { x = 200, y = 90 }
local noanim = "0"
local function action(name)
    return function(args) return { name = name, args = args } end
end
hl = {
    on = function() end, is_key_down = function() return false end,
    get_windows = function() return { w } end,
    get_monitors = function() return { mon } end,
    get_active_window = function() return w end,
    get_active_monitor = function() return mon end,
    get_cursor_pos = function() return cursor end,
    exec_cmd = function() end,
    bind = function(combo, fn, opts) if combo == "mouse:272" then binds[opts.release and "up" or "down"] = fn end end,
    timer = function(fn, opts)
        local t = { fn = fn, opts = opts, enabled = true }
        function t:set_enabled(b) self.enabled = b end
        timers[#timers + 1] = t
        return t
    end,
    dsp = { window = setmetatable({}, { __index = function(_, k) return action(k) end }), no_op = function() end },
    dispatch = function(a)
        actions[#actions + 1] = a
        local p = a.args
        if a.name == "set_prop" then noanim = p.value end
        if a.name == "move" and p.x then w.at = { x = p.x, y = p.y } end
        if a.name == "resize" then w.size = { x = p.x, y = p.y } end
    end,
}
package.preload.dx_zones = function() error("keine Zonen im Test") end
local snap = dofile(arg[1] or "hypr/dx_snap.lua")
snap.bindMouse()
-- Alte Timer dürfen Animationen im später gestarteten Drag nicht reaktivieren.
snap.toggleMax(w)
local before = #timers
binds.down()
snap.beginDrag(w.address, "first", cursor.x, cursor.y)
for i = 1, #timers do
    local t = timers[i]
    if t.opts.type == "oneshot" and t.opts.timeout < 1000 then t.fn() end
end
assert(noanim == "1", "Animation wurde mitten im Drag aktiviert")
snap.moveDrag(w.address, "first", 300, 200)
assert(w.at.x == 300)
-- Release sperrt auch einen Move, der beim Helfer bereits unterwegs war.
binds.up()
local releaseTimer = timers[#timers]
snap.moveDrag(w.address, "first", 500, 200)
assert(w.at.x == 300, "Move nach Release überschreibt Andocken")
snap.beginDrag(w.address, "late", 200, 90)
snap.moveDrag(w.address, "late", 500, 200)
assert(w.at.x == 300, "Verspäteter Prozessstart reaktiviert losgelassenen Drag")
-- Neuer Klick vor Ablauf des alten 40-ms-Timers bleibt erhalten.
binds.down()
snap.beginDrag(w.address, "second", 200, 90)
releaseTimer.fn()
snap.endDrag(w.address, "first")
snap.moveDrag(w.address, "second", 400, 200)
assert(w.at.x == 400, "Alter Release/Prozess beendet neuen Drag")
-- Der eigene Release darf weiterhin am Rand andocken.
cursor = { x = 0, y = 600 }
binds.up()
timers[#timers].fn()
assert(w.at.x == 8, "Neuer Klick verlor seinen Snap-Zustand")
-- Animation nach vollständigem Ende wieder aktivieren.
for _, t in ipairs(timers) do
    if t.opts.type == "oneshot" and t.opts.timeout == 80 then t.fn() end
end
assert(noanim == "0")
print("OK: Animationen, Release/Move-Rennen, verspäteter Start, schnelle Folgeklicks und Snap")
