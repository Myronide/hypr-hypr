-- Draconyx Binds: alle Tastenkombinationen an einer Stelle, vom Nutzer umbindbar (Aurora-Einstellungen → Tastenkombinationen).
--   B(id, beschriftung, standard, aktion [, optionen])   wie hl.bind, nur mit Kennung, Beschriftung und Standardkombination
-- Überschreibungen: ~/.config/draconyx/binds.conf, Zeilen "kennung=KOMBINATION" (leer = Kombination aus).
-- Die Liste aller Aktionen schreibt flush() nach ~/.config/draconyx/binds-registry.tsv (für die Einstellungs-App).
local M = {}

local HOME = os.getenv("HOME") or ""
local DIR = HOME .. "/.config/draconyx"
local OVERRIDES = DIR .. "/binds.conf"
local REGISTRY = DIR .. "/binds-registry.tsv"

local over = {}
local reg = {}
local effective = {}

do
    local f = io.open(OVERRIDES, "r")
    if f then
        for line in f:lines() do
            local id, combo = line:match("^%s*([%w_%.%-]+)%s*=%s*(.-)%s*$")
            if id then over[id] = combo end
        end
        f:close()
    end
end

-- Bindet eine Aktion. Gibt das Bind-Handle zurück (oder nil, wenn die Kombination abgeschaltet ist).
function M.bind(id, label, default, action, opts)
    reg[#reg + 1] = { id = id, label = label or id, default = default }
    local combo = over[id]
    if combo == nil then combo = default end
    effective[id] = combo
    if combo == nil or combo == "" then return nil end
    local ok, handle = pcall(hl.bind, combo, action, opts)
    if not ok then
        -- ungültige Kombination: Standard versuchen, damit nichts unbedienbar wird
        effective[id] = default
        if combo ~= default then
            local ok2, h2 = pcall(hl.bind, default, action, opts)
            if ok2 then return h2 end
        end
        return nil
    end
    return handle
end

-- Wirksame Kombination einer Aktion (nach dem Binden), z. B. für Module, die das Modifikator-Präfix brauchen
function M.combo(id) return effective[id] end

-- Präfix vor "mouse:NNN" der wirksamen Kombination ("ALT + ", "" wenn ohne Modifikator, nil wenn aus)
function M.mousePrefix(id)
    local c = effective[id]
    if c == nil or c == "" then return nil end
    return (c:gsub("%s*mouse:%d+%s*$", ""):gsub("%s*%+%s*$", ""):gsub("^%s+", "")) .. (c:match("^%s*mouse:") and "" or " + ")
end

-- Liste aller Aktionen für die Einstellungs-App schreiben (Kennung, Beschriftung, Standard, wirksam)
function M.flush()
    pcall(function()
        os.execute('mkdir -p "' .. DIR .. '"')
        local f = io.open(REGISTRY, "w")
        if not f then return end
        for _, r in ipairs(reg) do
            f:write(r.id, "\t", (r.label or ""):gsub("[\t\n]", " "), "\t", r.default or "", "\t", effective[r.id] or "", "\n")
        end
        f:close()
    end)
end

return M
