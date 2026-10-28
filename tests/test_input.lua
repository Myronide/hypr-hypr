-- dx_input: gemockte Hyprland-API, eigenes HOME in /tmp, keine Live-Sitzung.
local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p '" .. tmp .. "/.config/draconyx'")
local realGetenv = os.getenv
os.getenv = function(k) if k == "HOME" then return tmp end return realGetenv(k) end
local calls, handlers = {}, {}
local failKey
hl = {
    on = function(ev, fn) handlers[ev] = fn end,
    config = function(t)
        if failKey and t.input and t.input[failKey] ~= nil then error("unbekannter Schlüssel") end
        calls[#calls + 1] = t
    end,
}
local function write(s) local f = assert(io.open(tmp .. "/.config/draconyx/input.json", "w")); f:write(s); f:close() end
local function remove() os.remove(tmp .. "/.config/draconyx/input.json") end
local function merged()
    local m = { input = {}, cursor = {}, animations = {} }
    for _, c in ipairs(calls) do
        for sec, t in pairs(c) do
            for k, v in pairs(t) do
                if k == "touchpad" then m.input.touchpad = m.input.touchpad or {}; for a, b in pairs(v) do m.input.touchpad[a] = b end
                else m[sec][k] = v end
            end
        end
    end
    return m
end
local function reset() calls = {} end
local errs = {}
local realStderr = io.stderr
io.stderr = { write = function(_, ...) errs[#errs + 1] = table.concat({ ... }) end }

-- 1. fehlende Datei: nichts anwenden
local M = dofile("hypr/dx_input.lua")
assert(#calls == 0, "ohne Datei darf nichts gesetzt werden")
assert(handlers["config.reloaded"], "kein Reload-Hook")

-- 2. kaputtes JSON: nichts ändern, kein Absturz
for _, bad in ipairs({ "{", "", "[1,2", "nonsense", '{"a":}', '{"repeat_rate": 5} x', "[]", "\0\1\2", "123" }) do
    reset(); write(bad); assert(M.apply() == false or #calls == 0, "kaputt: " .. bad)
    assert(#calls == 0, "kaputtes JSON hat etwas gesetzt: " .. bad)
end
reset(); write(string.rep("[", 200) .. string.rep("]", 200)); M.apply(); assert(#calls == 0, "zu tief")
reset(); write("{" .. string.rep(" ", 70000) .. "}"); M.apply(); assert(#calls == 0, "zu groß")

-- 3. gültige Werte
reset()
write([[{"layouts":[{"layout":"de","variant":"nodeadkeys"},{"layout":"us","variant":""}],
 "kb_options":["grp:alt_shift_toggle","caps:escape"],"repeat_delay":300,"repeat_rate":40,"numlock":false,
 "sensitivity":-0.25,"accel_profile":"adaptive","natural_scroll_mouse":true,"natural_scroll_touchpad":true,
 "tap_to_click":false,"two_finger_scroll":true,"tap_and_drag":false,"disable_while_typing":false,"left_handed":true,
 "touchpad_scroll_factor":1.5,"reduce_animations":true,"zoom_factor":2,"unbekannt":42,"modifier":"x"}]])
assert(M.apply() == true)
local m = merged()
assert(m.input.kb_layout == "de,us" and m.input.kb_variant == "nodeadkeys,", m.input.kb_variant)
assert(m.input.kb_options == "grp:alt_shift_toggle,caps:escape")
assert(m.input.repeat_delay == 300 and m.input.repeat_rate == 40 and m.input.numlock_by_default == false)
assert(m.input.sensitivity == -0.25 and m.input.accel_profile == "adaptive" and m.input.natural_scroll == true and m.input.left_handed == true)
assert(m.input.touchpad.natural_scroll == true and m.input.touchpad.tap_to_click == false and m.input.touchpad.tap_and_drag == false)
assert(m.input.touchpad.disable_while_typing == false and m.input.touchpad.scroll_factor == 1.5 and m.input.scroll_method == "2fg")
assert(m.animations.enabled == false and m.cursor.zoom_factor == 2)

-- 4. falsche Typen und Grenzwerte
reset()
write([[{"repeat_delay":"schnell","repeat_rate":99999,"sensitivity":50,"accel_profile":"turbo","numlock":"ja",
 "layouts":[{"layout":"d e"},{"layout":"../x"},42,{"layout":"fr","variant":"oss"}],"kb_options":["../../x","caps:none","a b:c"],
 "zoom_factor":-3,"touchpad_scroll_factor":0,"left_handed":1,"reduce_animations":"x"}]])
M.apply(); m = merged()
-- ungültige Werte fallen auf den Standard zurück (vorher aus Test 3 angewendet), Grenzwerte werden begrenzt
assert(m.input.repeat_delay == 600 and m.input.repeat_rate == 100 and m.input.sensitivity == 1 and m.input.accel_profile == "flat")
assert(m.input.numlock_by_default == true and m.input.left_handed == false)
assert(m.input.kb_layout == "fr" and m.input.kb_variant == "oss", tostring(m.input.kb_layout))
assert(m.input.kb_options == "caps:none", tostring(m.input.kb_options))
assert(m.cursor.zoom_factor == 1 and m.input.touchpad.scroll_factor == 0.1 and m.animations.enabled == true)

-- 5. Schlüssel verschwinden: zurück auf Standard der Config
reset(); write([[{"repeat_rate":10}]]); M.apply(); m = merged()
assert(m.input.repeat_rate == 10)
reset(); write("{}"); M.apply(); m = merged()
assert(m.input.repeat_rate == 25 and m.input.kb_options == nil, "Rückfall auf Standard")
reset(); write([[{"layouts":[{"layout":"us"}],"reduce_animations":true,"zoom_factor":3}]]); M.apply()
reset(); remove(); M.apply(); m = merged()
assert(m.input.kb_layout == "de" and m.input.kb_variant == "" and m.animations.enabled == true and m.cursor.zoom_factor == 1)

-- 6. Reload-Hook + hl.config wirft für einen Schlüssel: Rest wird trotzdem gesetzt
reset(); write([[{"repeat_rate":50,"sensitivity":0.5}]]); failKey = "repeat_rate"
handlers["config.reloaded"](); m = merged()
assert(m.input.sensitivity == 0.5, "Einzelfehler darf die anderen nicht verhindern")
failKey = nil
assert(#errs > 0)

-- 7. Standard ohne Datei: leeres Layout-Array, Zoom-Hilfsfunktion
reset(); write([[{"layouts":[]}]]); M.apply(); assert(merged().input.kb_layout == nil)
reset(); assert(M.zoom(2.5) and merged().cursor.zoom_factor == 2.5); assert(M.zoom("x") == false)

-- 8. Unicode-Escapes / BOM / Leerraum
reset(); write("\239\187\191 { \"repeat_rate\" : 12 , \"x\" : \"\\u00e4\\ud800\" } \n"); M.apply(); assert(merged().input.repeat_rate == 12)
-- 9. Zeigergröße: nur mit gültigem Themennamen, begrenzt, einmalig
local execs, timers = {}, {}
hl.exec_cmd = function(c) execs[#execs + 1] = c end
hl.timer = function(fn, o) timers[#timers + 1] = fn end
os.getenv = function(k) if k == "HOME" then return tmp end if k == "XCURSOR_THEME" then return "Breeze_Light" end return realGetenv(k) end
write([[{"cursor_size":9999}]]); M.apply(); M.apply()
assert(#timers == 1, "Zeigergröße doppelt gesetzt"); timers[1]()
assert(execs[1] == "hyprctl setcursor 'Breeze_Light' 96" and execs[2]:find("cursor%-size 96"), execs[1])
os.getenv = function(k) if k == "HOME" then return tmp end if k == "XCURSOR_THEME" then return "x'; rm -rf ~" end return realGetenv(k) end
M.cursorApplied = nil; timers = {}; write([[{"cursor_size":32}]]); M.apply(); assert(#timers == 0, "unsicherer Themenname")
os.execute("rm -rf '" .. tmp .. "'")
io.stderr = realStderr
print("test_input.lua: OK")
