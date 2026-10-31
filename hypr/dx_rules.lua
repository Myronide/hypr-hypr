-- Hypr Hypr: Fensterregeln. Beim Öffnen eines Fensters werden passende Regeln angewendet (Bildschirm, Desktop, Modus, Größe, Mitte).
--   Datei: ~/.config/draconyx/window-rules.tsv   (bearbeiten: Aurora → Fensterregeln)
--   Spalten: an(1/0) <TAB> Klasse <TAB> Titel <TAB> Bildschirm <TAB> Desktop <TAB> Modus <TAB> Größe <TAB> Mitte(1/0)
--   Klasse/Titel: * = beliebig viele Zeichen, Groß/Klein egal; leer = jedes.  Modus: leer | float | tile | maximize | fullscreen
local M = {}
local FILE = (os.getenv("HOME") or "") .. "/.config/draconyx/window-rules.tsv"
local snap = nil
function M.setup(snapModule) snap = snapModule end

local lastErr = nil
local function logErr(err)
    if tostring(err) == lastErr then return end
    lastErr = tostring(err)
    io.stderr:write("[dx_rules] ", lastErr, "\n")
end
local pending = {}      -- address -> Token des laufenden Regel-Timers (Schließen/Adress-Wiederverwendung macht ihn ungültig)

local function read()
    local f = io.open(FILE, "r")
    if not f then return {} end
    local rules = {}
    for line in f:lines() do
        local on, class, title, mon, ws, mode, size, center = line:match("^([01])\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([01])")
        if on == "1" then rules[#rules + 1] = { class = class, title = title, mon = mon, ws = ws, mode = mode, size = size, center = center == "1" } end
    end
    f:close()
    return rules
end

local function matches(pat, text)
    if pat == nil or pat == "" then return true end
    local lp = pat:lower():gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1"):gsub("%*", ".*")
    return (text or ""):lower():match("^" .. lp .. "$") ~= nil
end

local function apply(w)
    if w == nil then return end
    for _, r in ipairs(read()) do
        if matches(r.class, w.class) and matches(r.title, w.title) then
            local a = "address:" .. w.address
            if r.mode == "float" or r.mode == "maximize" or r.size ~= "" then
                if not w.floating then hl.dispatch(hl.dsp.window.float({ window = a, action = "set" })) end
            elseif r.mode == "tile" then
                if w.floating then hl.dispatch(hl.dsp.window.float({ window = a, action = "unset" })) end
            end
            if r.ws ~= "" then
                local id = tonumber(r.ws) or r.ws
                hl.dispatch(hl.dsp.window.move({ window = a, workspace = id, follow = false }))
            end
            if r.mon ~= "" then hl.dispatch(hl.dsp.window.move({ window = a, monitor = r.mon, follow = false })) end
            local token = {}
            pending[w.address] = token
            hl.timer(function()
                local ok, err = pcall(function()
                    if pending[w.address] ~= token then return end
                    pending[w.address] = nil
                    for _, x in ipairs(hl.get_windows()) do
                        if x.address == w.address then
                            local m = x.monitor or hl.get_active_monitor()
                            if m == nil then return end
                            local sc = (type(m.scale) == "number" and m.scale > 0) and m.scale or 1
                            local mw, mh = m.width / sc, m.height / sc
                            local nw, nh = x.size.x, x.size.y
                            local sw, sh = r.size:match("^(%d+)x(%d+)$")
                            if sw then nw, nh = math.min(tonumber(sw), mw - 20), math.min(tonumber(sh), mh - 20)
                                hl.dispatch(hl.dsp.window.resize({ window = a, x = nw, y = nh, relative = false })) end
                            if r.center then
                                hl.dispatch(hl.dsp.window.move({ window = a, x = m.x + (mw - nw) / 2, y = m.y + (mh - nh) / 2, relative = false }))
                            end
                            if r.mode == "maximize" and snap ~= nil and snap.setMax then snap.setMax(x)
                            elseif r.mode == "fullscreen" then hl.dispatch(hl.dsp.window.fullscreen({ window = a, mode = "fullscreen", action = "set" })) end
                            return
                        end
                    end
                end)
                if not ok then logErr(err) end
            end, { timeout = 160, type = "oneshot" })
            return          -- die erste passende Regel gilt
        end
    end
end

function M.applyAll()
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped ~= false then
            local ok, err = pcall(apply, w)
            if not ok then logErr(err) end
        end
    end
end

local openPending = {}  -- address -> Token des 380-ms-Timers
hl.on("window.open", function(w)
    local ok, err = pcall(function()
        if w == nil or w.address == nil then return end
        local address, token = w.address, {}
        openPending[address] = token
        hl.timer(function()
            local ok2, err2 = pcall(function()
                if openPending[address] ~= token then return end        -- Fenster schon weg (oder Adresse neu vergeben)
                openPending[address] = nil
                for _, x in ipairs(hl.get_windows()) do if x.address == address then apply(x) return end end
            end)
            if not ok2 then logErr(err2) end
        end, { timeout = 380, type = "oneshot" })      -- nach der Fenstergrößen-Erinnerung (220 ms), damit Regeln gewinnen
    end)
    if not ok then logErr(err) end
end)

local function gone(w)
    if w == nil or w.address == nil then return end
    pending[w.address], openPending[w.address] = nil, nil
end
hl.on("window.close", gone)
hl.on("window.destroy", gone)

return M
