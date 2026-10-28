-- dx_input: Eingabe-Einstellungen aus ~/.config/draconyx/input.json (geschrieben von den Aurora-Seiten
-- "Tastatur", "Maus & Touchpad" und "Eingabehilfen") auf Hyprland anwenden.
--   * beim Start (require) und bei "config.reloaded"
--   * live: hyprctl eval "DXInput.apply()"
-- Es werden nur Schlüssel angewendet, die in der Datei stehen. Verschwindet ein Schlüssel wieder (Seite setzt auf Standard
-- zurück), geht der Wert auf den Standard der Config zurück. Ohne Datei oder bei kaputtem JSON ändert sich nichts.
-- Alles ist gegen falsche Typen und Grenzwerte abgesichert, ein Fehler hier darf die Config nie abbrechen.
local M = {}

local MAX_BYTES = 64 * 1024

------------------------------------------------------------------ JSON (klein, fehlertolerant über pcall)
local function decode(s)
    local pos, depth = 1, 0
    local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
    local value
    local function str()
        local out, i = {}, pos + 1
        while true do
            local c = s:sub(i, i)
            if c == "" then error("string offen") end
            if c == '"' then pos = i + 1; return table.concat(out) end
            if c == "\\" then
                local e = s:sub(i + 1, i + 1)
                local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ["/"] = "/", ["\\"] = "\\", ['"'] = '"' }
                if e == "u" then
                    local hex = s:sub(i + 2, i + 5)
                    if not hex:match("^%x%x%x%x$") then error("\\u ungültig") end
                    local cp = tonumber(hex, 16)
                    out[#out + 1] = utf8.char(cp >= 0xD800 and cp <= 0xDFFF and 0xFFFD or cp)
                    i = i + 6
                elseif map[e] then out[#out + 1] = map[e]; i = i + 2
                else error("Escape ungültig") end
            else out[#out + 1] = c; i = i + 1 end
        end
    end
    function value()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            depth = depth + 1; if depth > 8 then error("zu tief") end
            local t = {}; pos = pos + 1; ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1; depth = depth - 1; return t end
            while true do
                ws(); if s:sub(pos, pos) ~= '"' then error("Schlüssel erwartet") end
                local k = str(); ws()
                if s:sub(pos, pos) ~= ":" then error(": erwartet") end
                pos = pos + 1; t[k] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == "}" then depth = depth - 1; return t end
                if d ~= "," then error(", erwartet") end
            end
        elseif c == "[" then
            depth = depth + 1; if depth > 8 then error("zu tief") end
            local t = {}; pos = pos + 1; ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1; depth = depth - 1; return t end
            while true do
                t[#t + 1] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == "]" then depth = depth - 1; return t end
                if d ~= "," then error(", erwartet") end
            end
        elseif c == '"' then return str()
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
            if not num or num == "" then error("Wert ungültig") end
            local n = tonumber(num); if not n then error("Zahl ungültig") end
            pos = pos + #num; return n
        end
    end
    local v = value(); ws()
    if pos <= #s then error("Text nach dem JSON") end
    return v
end
M.decode = decode

------------------------------------------------------------------ Prüfen
local function num(v, lo, hi)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    if v < lo then return lo elseif v > hi then return hi end
    return v
end
local function int(v, lo, hi) local n = num(v, lo, hi); return n and math.floor(n + 0.5) or nil end
local function bool(v) if type(v) == "boolean" then return v end return nil end
local function oneof(v, list) for _, x in ipairs(list) do if v == x then return v end end return nil end
local function fmt(n) return tonumber(string.format("%.3f", n)) end

-- Standardwerte = Werte der Config ohne Nutzeränderung (hyprland.lua, Hyprland-Vorgaben)
local function defaults()
    return {
        kb_layout = rawget(_G, "DX_KEYMAP") or "de", kb_variant = "", kb_options = "",
        repeat_delay = 600, repeat_rate = 25, numlock_by_default = true,
        sensitivity = 0, accel_profile = "flat", natural_scroll = false, left_handed = false,
        tp_natural = false, tp_tap = true, tp_drag = true, tp_dwt = true, tp_scroll_factor = 1.0, tp_drag_lock = false,
        scroll_method = nil, animations = true, zoom = 1.0, cursor_size = 24,
    }
end

-- Wandelt die geladene Tabelle in Hyprland-Werte um. Gibt (werte, hinweise) zurück; ungültige Schlüssel werden übersprungen.
function M.sanitize(cfg)
    local out, notes = {}, {}
    if type(cfg) ~= "table" then return out, { "Wurzel ist kein Objekt" } end
    local function skip(k) notes[#notes + 1] = "ungültig: " .. k end

    if cfg.layouts ~= nil then
        local lay, var = {}, {}
        if type(cfg.layouts) == "table" then
            for i, e in ipairs(cfg.layouts) do
                if i > 4 then break end   -- XKB erlaubt höchstens vier Gruppen
                local l, v = e, ""
                if type(e) == "table" then l, v = e.layout, e.variant or "" end
                if type(l) == "string" and l:match("^[%w_]+$") and #l <= 16 and type(v) == "string" and (v == "" or (v:match("^[%w_%-]+$") and #v <= 32)) then
                    lay[#lay + 1] = l; var[#var + 1] = v
                else skip("layouts[" .. i .. "]") end
            end
        else skip("layouts") end
        if #lay > 0 then out.kb_layout = table.concat(lay, ","); out.kb_variant = table.concat(var, ",") end
    end
    if cfg.kb_options ~= nil then
        local list = {}
        if type(cfg.kb_options) == "table" then
            for i, o in ipairs(cfg.kb_options) do
                if i > 32 then break end
                if type(o) == "string" and o:match("^[%w_]+:[%w_%-%.]+$") and #o <= 48 then list[#list + 1] = o else skip("kb_options[" .. i .. "]") end
            end
            out.kb_options = table.concat(list, ",")
        else skip("kb_options") end
    end
    local function put(key, v, name) if v ~= nil then out[key] = v else skip(name or key) end end
    local function opt(name, key, conv) if cfg[name] ~= nil then put(key, conv(cfg[name]), name) end end
    opt("repeat_delay", "repeat_delay", function(v) return int(v, 100, 2000) end)
    opt("repeat_rate", "repeat_rate", function(v) return int(v, 1, 100) end)
    opt("numlock", "numlock_by_default", bool)
    opt("sensitivity", "sensitivity", function(v) local n = num(v, -1, 1); return n and fmt(n) end)
    opt("accel_profile", "accel_profile", function(v) return oneof(v, { "flat", "adaptive" }) end)
    opt("natural_scroll_mouse", "natural_scroll", bool)
    opt("left_handed", "left_handed", bool)
    opt("natural_scroll_touchpad", "tp_natural", bool)
    opt("tap_to_click", "tp_tap", bool)
    opt("tap_and_drag", "tp_drag", bool)
    opt("drag_lock", "tp_drag_lock", bool)
    opt("disable_while_typing", "tp_dwt", bool)
    opt("touchpad_scroll_factor", "tp_scroll_factor", function(v) local n = num(v, 0.1, 5); return n and fmt(n) end)
    opt("two_finger_scroll", "scroll_method", function(v) if v == true then return "2fg" elseif v == false then return "edge" end return nil end)
    opt("reduce_animations", "animations", function(v) if type(v) == "boolean" then return not v end return nil end)
    opt("cursor_size", "cursor_size", function(v) return int(v, 16, 96) end)
    opt("zoom_factor", "zoom", function(v) local n = num(v, 1, 10); return n and fmt(n) end)
    return out, notes
end

------------------------------------------------------------------ Lesen / Anwenden
function M.path() return (os.getenv("HOME") or "") .. "/.config/draconyx/input.json" end

-- Gibt (Tabelle, nil) zurück, (nil, nil) wenn die Datei fehlt, (nil, Fehler) bei kaputtem Inhalt.
function M.load()
    local f = io.open(M.path(), "r")
    if not f then return nil, nil end
    local s = f:read(MAX_BYTES + 1); f:close()
    if not s or #s > MAX_BYTES then return nil, "Datei zu groß oder nicht lesbar" end
    s = s:gsub("^\239\187\191", "")
    local ok, v = pcall(decode, s)
    if not ok then return nil, tostring(v) end
    if type(v) ~= "table" then return nil, "kein Objekt" end
    return v, nil
end

local applied = {}   -- zuletzt angewendete Schlüssel (für das Zurückfallen auf den Standard)
M.last = {}

local function try(label, fn)
    local ok, err = pcall(fn)
    if not ok then io.stderr:write("[dx_input] ", label, ": ", tostring(err), "\n") end
    return ok
end

function M.apply()
    local cfg, err = M.load()
    if err then
        io.stderr:write("[dx_input] input.json ignoriert: ", err, "\n")
        return false
    end
    local vals = cfg and M.sanitize(cfg) or {}
    local def = defaults()
    local eff = {}   -- wirksame Werte: Nutzerwert, sonst (nur wenn vorher angewendet) Standard
    for k, v in pairs(vals) do eff[k] = v end
    for k in pairs(applied) do if eff[k] == nil and def[k] ~= nil then eff[k] = def[k] end end
    -- layouts und Varianten gehören zusammen
    if eff.kb_layout ~= nil and eff.kb_variant == nil then eff.kb_variant = "" end
    -- scroll_method hat keinen festen Standard: ohne Wert den Schlüssel gar nicht setzen
    if eff.scroll_method == nil and applied.scroll_method then eff.scroll_method = "2fg" end
    M.last = eff
    if not hl or type(hl.config) ~= "function" then return false end

    local inp, tp = {}, {}
    for _, k in ipairs({ "kb_layout", "kb_variant", "kb_options", "repeat_delay", "repeat_rate", "numlock_by_default",
        "sensitivity", "accel_profile", "natural_scroll", "left_handed" }) do inp[k] = eff[k] end
    tp.natural_scroll = eff.tp_natural; tp.tap_to_click = eff.tp_tap; tp.tap_and_drag = eff.tp_drag
    tp.drag_lock = eff.tp_drag_lock; tp.disable_while_typing = eff.tp_dwt; tp.scroll_factor = eff.tp_scroll_factor
    if next(tp) then inp.touchpad = tp end
    if eff.scroll_method ~= nil then inp.scroll_method = eff.scroll_method end
    -- Sektionen einzeln, damit ein Wert, den diese Hyprland-Version nicht kennt, die anderen nicht verhindert
    if next(inp) then
        -- erst alles zusammen, bei Fehler jeden Schlüssel einzeln
        if not pcall(hl.config, { input = inp }) then
            for k, v in pairs(inp) do
                if k ~= "touchpad" then try("input." .. k, function() hl.config({ input = { [k] = v } }) end) end
            end
            for k, v in pairs(tp) do try("touchpad." .. k, function() hl.config({ input = { touchpad = { [k] = v } } }) end) end
        end
    end
    if eff.animations ~= nil then try("animations", function() hl.config({ animations = { enabled = eff.animations } }) end) end
    if eff.zoom ~= nil then try("cursor.zoom_factor", function() hl.config({ cursor = { zoom_factor = eff.zoom } }) end) end

    -- Zeigergröße: Hyprland-Zeiger und GTK-Einstellung; Thema bleibt unverändert (Umgebung), nie ohne gültigen Namen
    if eff.cursor_size ~= nil and eff.cursor_size ~= M.cursorApplied then
        local theme = os.getenv("XCURSOR_THEME") or ""
        if theme:match("^[%w_%-%. ]+$") and type(hl.exec_cmd) == "function" then
            local size = eff.cursor_size
            M.cursorApplied = size
            local function go()
                try("cursor_size", function()
                    hl.exec_cmd(string.format("hyprctl setcursor '%s' %d", theme, size))
                    hl.exec_cmd(string.format("gsettings set org.gnome.desktop.interface cursor-size %d", size))
                end)
            end
            if type(hl.timer) == "function" then hl.timer(go, { timeout = 1500, type = "oneshot" }) else go() end
        end
    end

    applied = {}
    for k in pairs(vals) do applied[k] = true end
    return true
end

-- Bildschirmlupe: Faktor setzen (nur zur Laufzeit, ohne die Datei zu ändern)
function M.zoom(f)
    f = num(tonumber(f), 1, 10)
    if not f or not hl or type(hl.config) ~= "function" then return false end
    return pcall(hl.config, { cursor = { zoom_factor = fmt(f) } })
end

if type(hl) == "table" and type(hl.on) == "function" then
    hl.on("config.reloaded", function() try("apply", M.apply) end)
end
try("apply", M.apply)

return M
