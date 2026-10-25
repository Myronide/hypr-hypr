-- Aurora desktop for Hyprland 0.56.2.
local base = os.getenv('HOME') .. '/.config/hypr/aurora/'
-- Alle Tastenkombinationen laufen über B(): in den Aurora-Einstellungen frei umbindbar (dx_binds.lua)
local DXB = require('dx_binds')
local B = DXB.bind
-- Haupttaste für alle Aurora-Kombinationen (Aurora-Einstellungen -> Tastenkombinationen):
--   super (Standard) | both (Super und Strg+Alt) | ctrl-alt (Super aus, Strg+Alt ersetzt sie) | caps (Feststelltaste wird Super)
local modmode = 'super'
do
    local f = io.open(os.getenv('HOME') .. '/.config/draconyx/modifier', 'r')
    if f then modmode = ((f:read('*l') or 'super'):gsub('%s', '')); f:close() end
end
local MOD  = (modmode == 'ctrl-alt') and 'CTRL + ALT' or 'SUPER'
local MOD2 = (modmode == 'ctrl-alt') and 'CTRL + ALT + SHIFT' or 'SUPER + CTRL'   -- für Kombinationen, die selbst schon Strg enthalten
if modmode == 'caps' then hl.config({ input = { kb_options = 'caps:super' } }) end
-- Load only the plugin built for the running compositor; an upgrade must rebuild it.
local compatible = false
local version = io.open('/usr/include/hyprland/src/version.h', 'r')
if version then
    compatible = version:read('*a'):find('efb50993780079460b0cbed1363e2166a2de1d9f', 1, true) ~= nil
    version:close()
end
if compatible then
    hl.plugin.load(base .. 'hyprbars.so')
    hl.plugin.load(base .. 'aurora-native.so')
end
local bars_ready = compatible and hl.plugin.hyprbars ~= nil
if bars_ready then
    hl.config({ plugin = { hyprbars = {
        enabled = true, bar_height = 28, bar_color = 'rgb(282d34)',
        ['col.text'] = 'rgb(edf1f7)', bar_text_font = 'Sans', bar_text_size = 10,
        bar_text_weight = 'semibold', bar_text_align = 'center', bar_padding = 16,
        bar_button_padding = 10, bar_part_of_window = true, bar_blur = false,
        inactive_button_color = 'rgb(4a535f)', icon_on_hover = false,
        on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    } } })
    hl.plugin.hyprbars.add_button({ bg_color = 'rgb(424b57)', fg_color = 'rgb(edf1f7)', size = 12, icon = '×', action = [[hyprctl dispatch 'hl.dsp.window.close()']] })
    hl.plugin.hyprbars.add_button({ bg_color = 'rgb(424b57)', fg_color = 'rgb(edf1f7)', size = 12, icon = '□', action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']] })
    hl.plugin.hyprbars.add_button({ bg_color = 'rgb(424b57)', fg_color = 'rgb(edf1f7)', size = 12, icon = '−', action = base .. 'desktop-ui minimize' })
    local csd = io.open(base .. 'csd-apps', 'r')
    if csd then
        local n = 0
        for class in csd:lines() do
            if class ~= '' then
                n = n + 1
                local pattern = class:gsub('([%W])', '\\%1'):gsub('\\%*', '.*')   -- * = beliebig viele Zeichen (z. B. org.gnome.*)
                hl.window_rule({ name = 'aurora-csd-' .. n, match = { class = '(?i)^' .. pattern .. '$' }, ['hyprbars:no_bar'] = true })
            end
        end
        csd:close()
    end
end
-- Native maximize is supported in both Aurora modes.
hl.on('window.open', function(w)
    local dialog = w.floating
    if not w.floating and w.fullscreen == 0 then
        hl.dispatch(hl.dsp.window.float({ window = w, action = 'set' }))
    end
    hl.exec_cmd(base .. 'desktop-ui window-open ' .. w.address .. (dialog and ' --dialog' or ''))
end)

hl.layer_rule({ name = 'aurora-glass', match = { namespace = '^(aurora|aurora-apps|waybar|rofi)$' }, blur = true, ignore_alpha = 0.2 })
hl.config({ general = { border_size = 0, gaps_in = 0, gaps_out = 0, resize_on_border = true, extend_border_grab_area = 8 }, decoration = { rounding = 12, blur = { enabled = true, size = 6, passes = 3 } } })
_G.aurora_bindings = {}
_G.aurora_bindings.launcher = B("aurora_launcher", "Launcher öffnen", MOD .. ' + A', hl.dsp.exec_cmd(base .. 'launcher'))
_G.aurora_bindings.mode = B("aurora_mode", "Fenstermodus wechseln (Schweben / Kacheln)", MOD .. ' + SHIFT + F', hl.dsp.exec_cmd(base .. 'mode --toggle'))
B("aurora_switcher", "Alt+Tab: nächstes Fenster", 'ALT + Tab', hl.dsp.exec_cmd(base .. 'desktop-ui switcher'))
B("aurora_switcher_prev", "Alt+Tab: voriges Fenster", 'ALT + SHIFT + Tab', hl.dsp.exec_cmd(base .. 'desktop-ui switcher --reverse'))
-- Track Alt before the asynchronous keybinding command starts.
local altkeys = {}
hl.on('input.keyboard.key', function(code, _, state)
    if code == 64 or code == 108 then
        altkeys[code] = state ~= 0
        local out = io.open(os.getenv('XDG_RUNTIME_DIR') .. '/aurora-alt-state', 'w')
        if out then out:write((altkeys[64] or altkeys[108]) and 'down' or 'up'); out:close() end
    end
end)
_G.aurora_bindings.desktop = B("aurora_desktop", "Schreibtisch zeigen", MOD .. ' + D', hl.dsp.exec_cmd(base .. 'desktop-ui show-desktop'))
_G.aurora_bindings.minimize = B("aurora_minimize", "Aktives Fenster minimieren", MOD .. ' + H', hl.dsp.exec_cmd(base .. 'desktop-ui minimize'))
_G.aurora_bindings.clipboard = B("aurora_clipboard", "Zwischenablage-Verlauf", MOD .. ' + V', hl.dsp.exec_cmd(base .. 'desktop-ui clipboard'))
hl.on('hyprland.start', function() hl.exec_cmd(base .. 'start-desktop') end)

B("aurora_layout_cycle", "Layout wechseln", MOD .. ' + J', hl.dsp.exec_cmd(base .. 'desktop-ui layout-cycle'))
B("aurora_make_master", "Fenster zum Hauptfenster machen", MOD .. ' + RETURN', hl.dsp.exec_cmd(base .. 'desktop-ui make-master'))
B("aurora_ratio_minus", "Hauptfenster schmaler", MOD2 .. ' + left', hl.dsp.exec_cmd(base .. 'desktop-ui ratio -0.05'))
B("aurora_ratio_plus", "Hauptfenster breiter", MOD2 .. ' + right', hl.dsp.exec_cmd(base .. 'desktop-ui ratio 0.05'))
B("aurora_detach", "Fenster abtrennen", MOD .. ' + SHIFT + V', hl.dsp.exec_cmd(base .. 'desktop-ui detach'))

-- Desktop icons stay above both static and animated wallpaper surfaces.
hl.layer_rule({name='aurora-desktop-order',match={namespace='^aurora-desktop$'},order=10})
hl.layer_rule({name='aurora-wallpaper-order',match={namespace='^(aurora-wallpaper|hyprpaper)$'},order=-10})
hl.config({input={follow_mouse=0}})
hl.config({cursor={no_warps=true}})   -- Maus springt beim Fokuswechsel (z. B. Klick in der Taskleiste) nicht in die Fenstermitte
_G.aurora_bindings.settings = B("aurora_settings", "Einstellungen öffnen", MOD .. ' + comma',hl.dsp.exec_cmd(base .. 'settings-app'))
local prefs = io.open(base .. 'preferences.lua', 'r')
if prefs then prefs:close(); dofile(base .. 'preferences.lua') end

B("aurora_controls", "Kontrollzentrum", MOD .. ' + SHIFT + A',hl.dsp.exec_cmd(base .. 'desktop-ui controls'))

-- Zusätzlich zu Super auch Strg+Alt (Modus "both"); im Modus "ctrl-alt" tragen die Haupttaste-Binds oben schon Strg+Alt
if modmode == 'both' then
B("aurora_alt_launcher", "Launcher (Strg+Alt)", 'CTRL + ALT + space',hl.dsp.exec_cmd(base .. 'launcher'))
B("aurora_alt_settings", "Einstellungen (Strg+Alt)", 'CTRL + ALT + comma',hl.dsp.exec_cmd(base .. 'settings-app'))
B("aurora_alt_desktop", "Schreibtisch zeigen (Strg+Alt)", 'CTRL + ALT + D',hl.dsp.exec_cmd(base .. 'desktop-ui show-desktop'))
B("aurora_alt_minimize", "Minimieren (Strg+Alt)", 'CTRL + ALT + H',hl.dsp.exec_cmd(base .. 'desktop-ui minimize'))
B("aurora_alt_clipboard", "Zwischenablage (Strg+Alt)", 'CTRL + ALT + V',hl.dsp.exec_cmd(base .. 'desktop-ui clipboard'))
B("aurora_alt_mode", "Fenstermodus (Strg+Alt)", 'CTRL + ALT + F',hl.dsp.exec_cmd(base .. 'mode --toggle'))
B("aurora_alt_controls", "Kontrollzentrum (Strg+Alt)", 'CTRL + ALT + A',hl.dsp.exec_cmd(base .. 'desktop-ui controls'))
end
if modmode == 'ctrl-alt' then hl.bind('CTRL + ALT + space',hl.dsp.exec_cmd(base .. 'launcher')) end   -- Strg+Alt+Leertaste öffnet wie bisher den Launcher
-- Strg+Space öffnet die Suche nur auf dem leeren Desktop; in Apps bleibt die Taste unberührt (non_consuming)
B("desktop_search", "Suche (nur auf dem leeren Desktop)", 'CTRL + space',function()
    local w = hl.get_active_window()
    if w == nil or w.workspace == nil or w.mapped == false or w.hidden == true then hl.exec_cmd(base .. 'launcher') end
end,{non_consuming=true})

B("aurora_repair_focus", "Tastaturfokus reparieren", MOD .. ' + Escape',function() if hl.plugin.aurora_native then hl.plugin.aurora_native.repair_focus() end end)

-- Dark Qt/KDE controls and application color-scheme hints.
hl.env('QT_QPA_PLATFORMTHEME','kde')
hl.env('QT_STYLE_OVERRIDE','kvantum')
hl.env('QT_QUICK_CONTROLS_MATERIAL_THEME','Dark')
hl.env('QT_QUICK_CONTROLS_UNIVERSAL_THEME','Dark')

-- A bare, short Super tap opens the launcher; Super chords and long presses never do.
local superkeys = {}
local super_chord = false
local super_hold_token = 0
local SUPER_HOLD_MS = 350   -- länger gehalten = kein Launcher
if modmode ~= 'ctrl-alt' then
hl.on('input.keyboard.key', function(code, _, state)
    if code == 133 or code == 134 then
        if state ~= 0 then
            if not superkeys[133] and not superkeys[134] then
                super_chord = false
                -- Länger gehaltene Super-Taste öffnet den Launcher nicht (nur kurzes Antippen)
                super_hold_token = super_hold_token + 1
                local token = super_hold_token
                hl.timer(function()
                    if token == super_hold_token and (superkeys[133] or superkeys[134]) then super_chord = true end
                end, { timeout = SUPER_HOLD_MS, type = 'oneshot' })
            end
            superkeys[code] = true
        else
            local was_down = superkeys[code]
            superkeys[code] = false
            if was_down and not superkeys[133] and not superkeys[134] and not super_chord then hl.exec_cmd(base .. 'launcher') end
        end
    elseif state ~= 0 and (superkeys[133] or superkeys[134]) then
        super_chord = true
    end
end)
end

-- Keep dock icons above the panel when adaptive visibility raises Waybar.
hl.layer_rule({name='aurora-dock-panel-order',match={namespace='^aurora$'},order=20})
hl.layer_rule({name='aurora-dock-icons-order',match={namespace='^aurora-apps$'},order=30})
hl.layer_rule({name='aurora-dock-menus-order',match={namespace='^(aurora-window-previews|aurora-control-center)$'},order=40})
hl.layer_rule({name='aurora-popup-order',match={namespace='^aurora-popup$'},order=50})

-- Kachel-Modus der Draconyx-Shell: ersetzt das Layout des alten Aurora-Daemons (Modus-Knopf, Raster, Zonen).
-- DXTiling/DXZones sind global, damit die Shell sie per `hyprctl eval` ansprechen kann (Fenstermodus-Knopf in der Taskleiste).
local okTiling, tilingModule = pcall(require, 'dx_tiling')
if okTiling and tilingModule then
    DXTiling = tilingModule
    pcall(function() DXZones = require('dx_zones') end)
    B('aurora_grid_window', 'Aktives Fenster ins Raster / heraus', MOD .. ' + G', function() DXTiling.toggle() end)
    B('aurora_grid_workspace', 'Ganzen Desktop kacheln an/aus', MOD .. ' + SHIFT + G', function() DXTiling.toggleWorkspace() end)
    B('aurora_grid_mode', 'Kachel-Layout wechseln (Zonen/Raster/Spalten/Zeilen/Master)', MOD .. ' + SHIFT + J', function() DXTiling.cycleMode() end)
    B('aurora_grid_prev', 'Platz im Raster tauschen (zurück)', MOD .. ' + SHIFT + comma', function() DXTiling.shift(-1) end)
    B('aurora_grid_next', 'Platz im Raster tauschen (vor)', MOD .. ' + SHIFT + period', function() DXTiling.shift(1) end)
    B('aurora_grid_panic', 'NOTAUSGANG: alles aus dem Raster', MOD .. ' + BackSpace', function() DXTiling.releaseAll() end)
end

-- Sicherheitsnetz: Shell zusätzlich zum Autostart über start-desktop prüfen und notfalls starten (mehrere Versuche, Protokoll in
-- ~/.cache/draconyx/shell-start.log). Läuft sie schon, passiert nichts.
hl.on('hyprland.start', function()
    hl.exec_cmd("sh -c 'sleep 4; exec " .. os.getenv('HOME') .. "/.local/bin/dx-shell-ensure'")
end)

DXB.flush()   -- Liste aller Aktionen für die Einstellungs-App
