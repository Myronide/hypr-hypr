-- Draconyx: merkt sich die Größe eines Fensters, wenn man es schließt, und stellt sie beim nächsten Öffnen derselben App wieder her.
--   Liste: ~/.config/draconyx/window-sizes.tsv   (Klasse <TAB> Breite <TAB> Höhe)
--   Aus:   Datei ~/.config/draconyx/window-size-memory mit dem Inhalt "off" (Aurora → Fenster → „Fenstergröße merken“)
--   Nie anfassen: ~/.config/draconyx/window-size-exclude (eine Klasse pro Zeile, * = beliebig)
-- Nur schwebende Fenster, nur das erste Fenster einer App (Dialoge behalten ihre eigene Größe), nie im Vollbild.
local M = {}
local HOME = os.getenv("HOME") or ""
local DIR = HOME .. "/.config/draconyx"
local FILE, FLAG, EXCL = DIR .. "/window-sizes.tsv", DIR .. "/window-size-memory", DIR .. "/window-size-exclude"
local snap = nil
local sizes = {}

local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local t = f:read("*a"); f:close(); return t
end

local function enabled()
    local v = read(FLAG)
    return not (v and v:gsub("%s", "") == "off")
end

local function load()
    sizes = {}
    local t = read(FILE) or ""
    for line in t:gmatch("[^\n]+") do
        local c, w, h = line:match("^(.-)\t(%d+)\t(%d+)$")
        if c then sizes[c] = { w = tonumber(w), h = tonumber(h) } end
    end
end

local function save()
    os.execute('mkdir -p "' .. DIR .. '"')
    local f = io.open(FILE, "w")
    if not f then return end
    for c, s in pairs(sizes) do f:write(c, "\t", s.w, "\t", s.h, "\n") end
    f:close()
end

local DEFAULT_EXCLUDE = { "^$", "^steam_app_", "^gamescope", "^xdg%-desktop%-portal", "^org%.freedesktop%.impl%.portal", "^Rocket", "^dx%-", "^draconyx%-" }
local function excluded(class)
    if class == nil or class == "" then return true end
    for _, p in ipairs(DEFAULT_EXCLUDE) do if class:match(p) then return true end end
    local t = read(EXCL)
    if t then
        for line in t:gmatch("[^\n]+") do
            local pat = line:gsub("%s+$", ""):gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1"):gsub("%*", ".*")
            if pat ~= "" and class:lower():match("^" .. pat:lower() .. "$") then return true end
        end
    end
    return false
end

local function others(w)
    local n = 0
    for _, o in ipairs(hl.get_windows()) do
        if o.address ~= w.address and o.class == w.class and o.mapped ~= false then n = n + 1 end
    end
    return n
end

function M.setup(snapModule) snap = snapModule end

-- Beim Schließen: Größe merken (das letzte Fenster einer App = das Hauptfenster)
hl.on("window.close", function(w)
    pcall(function()
        if w == nil or not enabled() or excluded(w.class) or others(w) > 0 then return end
        local width, height
        if snap ~= nil and snap.maxedOrig then width, height = snap.maxedOrig(w) end   -- maximiert: Größe davor merken
        if width == nil then
            if not w.floating or w.fullscreen ~= 0 then return end
            width, height = w.size.x, w.size.y
        end
        if width < 260 or height < 160 then return end                                  -- Menüs, Popups, Mini-Fenster
        sizes[w.class] = { w = math.floor(width), h = math.floor(height) }
        save()
    end)
end)

-- Beim Öffnen: gemerkte Größe anwenden (kurz warten, bis das Fenster seine Klasse/Größe gemeldet hat)
hl.on("window.open", function(w)
    pcall(function()
        if w == nil or not enabled() then return end
        local addr = w.address
        hl.timer(function()
            pcall(function()
                for _, x in ipairs(hl.get_windows()) do
                    if x.address == addr then
                        local s = sizes[x.class]
                        if s == nil or excluded(x.class) or not x.floating or x.fullscreen ~= 0 or others(x) > 0 then return end
                        local m = x.monitor or hl.get_active_monitor()
                        local mw, mh = m.width / (m.scale or 1), m.height / (m.scale or 1)
                        local nw, nh = math.min(s.w, mw - 40), math.min(s.h, mh - 80)
                        local a = "address:" .. addr
                        hl.dispatch(hl.dsp.window.resize({ window = a, x = nw, y = nh, relative = false }))
                        hl.dispatch(hl.dsp.window.move({ window = a, x = m.x + (mw - nw) / 2, y = m.y + (mh - nh) / 2, relative = false }))
                        return
                    end
                end
            end)
        end, { timeout = 220, type = "oneshot" })
    end)
end)

load()
return M
