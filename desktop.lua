-- Aurora desktop for Hyprland 0.56.2.
local base = os.getenv('HOME') .. '/.config/hypr/aurora/'
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
                local pattern = class:gsub('([%W])', '\\%1')
                hl.window_rule({ name = 'aurora-csd-' .. n, match = { class = '^' .. pattern .. '$' }, ['hyprbars:no_bar'] = true })
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
_G.aurora_bindings.launcher = hl.bind('SUPER + A', hl.dsp.exec_cmd(base .. 'launcher'))
_G.aurora_bindings.mode = hl.bind('SUPER + SHIFT + F', hl.dsp.exec_cmd(base .. 'mode --toggle'))
hl.bind('ALT + Tab', hl.dsp.exec_cmd(base .. 'desktop-ui switcher'))
hl.bind('ALT + SHIFT + Tab', hl.dsp.exec_cmd(base .. 'desktop-ui switcher --reverse'))
-- Track Alt before the asynchronous keybinding command starts.
local altkeys = {}
hl.on('input.keyboard.key', function(code, _, state)
    if code == 64 or code == 108 then
        altkeys[code] = state ~= 0
        local out = io.open(os.getenv('XDG_RUNTIME_DIR') .. '/aurora-alt-state', 'w')
        if out then out:write((altkeys[64] or altkeys[108]) and 'down' or 'up'); out:close() end
    end
end)
_G.aurora_bindings.desktop = hl.bind('SUPER + D', hl.dsp.exec_cmd(base .. 'desktop-ui show-desktop'))
_G.aurora_bindings.minimize = hl.bind('SUPER + H', hl.dsp.exec_cmd(base .. 'desktop-ui minimize'))
_G.aurora_bindings.clipboard = hl.bind('SUPER + V', hl.dsp.exec_cmd(base .. 'desktop-ui clipboard'))
hl.on('hyprland.start', function() hl.exec_cmd(base .. 'start-desktop') end)

hl.bind('SUPER + J', hl.dsp.exec_cmd(base .. 'desktop-ui layout-cycle'))
hl.bind('SUPER + RETURN', hl.dsp.exec_cmd(base .. 'desktop-ui make-master'))
hl.bind('SUPER + CTRL + left', hl.dsp.exec_cmd(base .. 'desktop-ui ratio -0.05'))
hl.bind('SUPER + CTRL + right', hl.dsp.exec_cmd(base .. 'desktop-ui ratio 0.05'))
hl.bind('SUPER + SHIFT + V', hl.dsp.exec_cmd(base .. 'desktop-ui detach'))

-- Desktop icons stay above both static and animated wallpaper surfaces.
hl.layer_rule({name='aurora-desktop-order',match={namespace='^aurora-desktop$'},order=10})
hl.layer_rule({name='aurora-wallpaper-order',match={namespace='^(aurora-wallpaper|hyprpaper)$'},order=-10})
hl.config({input={follow_mouse=0}})
_G.aurora_bindings.settings = hl.bind('SUPER + comma',hl.dsp.exec_cmd(base .. 'settings-app'))
local prefs = io.open(base .. 'preferences.lua', 'r')
if prefs then prefs:close(); dofile(base .. 'preferences.lua') end

hl.bind('SUPER + SHIFT + A',hl.dsp.exec_cmd(base .. 'desktop-ui controls'))

hl.bind('SUPER + Escape',function() if hl.plugin.aurora_native then hl.plugin.aurora_native.repair_focus() end end)

-- Dark Qt/KDE controls and application color-scheme hints.
hl.env('QT_QPA_PLATFORMTHEME','kde')
hl.env('QT_STYLE_OVERRIDE','kvantum')
hl.env('QT_QUICK_CONTROLS_MATERIAL_THEME','Dark')
hl.env('QT_QUICK_CONTROLS_UNIVERSAL_THEME','Dark')

-- A bare Super tap opens the launcher; Super chords never do.
local superkeys = {}
local super_chord = false
hl.on('input.keyboard.key', function(code, _, state)
    if code == 133 or code == 134 then
        if state ~= 0 then
            if not superkeys[133] and not superkeys[134] then super_chord = false end
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

-- Keep dock icons above the panel when adaptive visibility raises Waybar.
hl.layer_rule({name='aurora-dock-panel-order',match={namespace='^aurora$'},order=20})
hl.layer_rule({name='aurora-dock-icons-order',match={namespace='^aurora-apps$'},order=30})
hl.layer_rule({name='aurora-dock-menus-order',match={namespace='^(aurora-window-previews|aurora-control-center)$'},order=40})
hl.layer_rule({name='aurora-popup-order',match={namespace='^aurora-popup$'},order=50})
