-- Hyprland: "Draconyx Dark" im Windows-11-Stil
-- Schwebende Taskleiste unten (Waybar), Startmenü (nwg-drawer), Desktop mit Icons (pcmanfm-qt), schwebende Fenster.
-- Farben: Schwarz-Grün, Aurora-Farbwelt: Akzent Blau #4d8fe0, Zweitakzent #6ba9ff

------------------
---- MONITORE ----
------------------
-- Die Anordnung der Bildschirme liegt NICHT hier, sondern pro Rechner in monitors_local.lua (Aurora → Bildschirme).

-- Monitore stehen pro Rechner in ~/.config/hypr/monitors_local.lua (Vorlage: monitors_local.lua.example)
local okMon = pcall(require, "monitors_local")
if not okMon then hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 }) end


---------------------
---- PROGRAMME ------
---------------------
local terminal    = os.getenv("HOME") .. "/.local/bin/dx-terminal"
local fileManager = "dolphin"
local browser     = "gtk-launch \"$(xdg-settings get default-web-browser)\""
local runMenu     = "fuzzel"
-- Draconyx Shell (Quickshell) mit Waybar/nwg-drawer als Fallback, falls Quickshell fehlt
local shellBar    = "sh -c 'command -v qs >/dev/null && QS_ICON_THEME=Papirus-Dark exec qs -c draconyx || exec waybar'"
local startMenu   = "sh -c 'qs -c draconyx ipc call shell toggleStart 2>/dev/null || " .. os.getenv("HOME") .. "/.config/hypr/scripts/start-menu.sh'"
local quickPanel  = "sh -c 'qs -c draconyx ipc call shell toggleControl 2>/dev/null || pavucontrol'"


---------------------
---- AUTOSTART ------
---------------------
-- Startet ein Programm nur, wenn es installiert ist (kein Fehler auf Rechnern ohne es)
local function ifInstalled(bin, cmd)
    return "sh -c 'command -v " .. bin .. " >/dev/null 2>&1 && exec " .. (cmd or bin) .. "'"
end
local function fileExists(path) local f = io.open(path, "r"); if f then f:close(); return true end; return false end

-- Mauszeiger: der Windows-Zeiger, wenn er installiert ist, sonst Adwaita (sonst fehlt der Zeiger ganz)
local HOME_ = os.getenv("HOME") or ""
local CURSOR = "Adwaita"
for _, dir in ipairs({ HOME_ .. "/.icons", HOME_ .. "/.local/share/icons", "/usr/share/icons" }) do
    if fileExists(dir .. "/Windows10Light/index.theme") then CURSOR = "Windows10Light"; break end
end

hl.on("hyprland.start", function()
    -- Polkit-Agent (Passwortabfragen): der erste vorhandene
    hl.exec_cmd("sh -c 'for p in /usr/lib/hyprpolkitagent/hyprpolkitagent /usr/lib/polkit-kde-authentication-agent-1 /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 /usr/lib/mate-polkit/polkit-mate-authentication-agent-1; do [ -x \"$p\" ] && exec \"$p\"; done'")
    hl.exec_cmd("sh -c 'command -v qs >/dev/null || exec pcmanfm-qt --desktop'")  -- Desktop: Draconyx Shell, Fallback pcmanfm-qt
    hl.exec_cmd(shellBar)                              -- Taskleiste (Draconyx Shell)
    hl.exec_cmd(ifInstalled("swaync"))                 -- Benachrichtigungen
    hl.exec_cmd(ifInstalled("hypridle"))
    hl.exec_cmd(ifInstalled("nm-applet", "nm-applet --indicator"))
    hl.exec_cmd(ifInstalled("blueman-applet"))
    hl.exec_cmd(ifInstalled("cliphist", "wl-paste --watch cliphist store"))    -- Zwischenablage-Verlauf (Win+V)
    hl.exec_cmd("hyprctl setcursor " .. CURSOR .. " 24")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. CURSOR)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark")
    -- optionale Zusatzprogramme: nur wenn vorhanden
    hl.exec_cmd(ifInstalled("easyeffects", "easyeffects --hide-window --service-mode"))
    hl.exec_cmd(ifInstalled("jamesdsp"))
    if fileExists(HOME_ .. "/Jetbrains_Toolbox/jetbrains-toolbox") then hl.exec_cmd(HOME_ .. "/Jetbrains_Toolbox/jetbrains-toolbox --minimize") end
end)


-------------------------------
---- UMGEBUNGSVARIABLEN -------
-------------------------------
hl.env("XCURSOR_THEME", CURSOR)      -- klassischer Windows-Mauszeiger (falls vorhanden)
hl.env("HYPRCURSOR_THEME", CURSOR)
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")      -- KDE-Farbschema (dunkel) auch unter Hyprland, z. B. für Dolphin
hl.env("GTK_THEME", "adw-gtk3-dark")
-- Electron-Apps (Discord, Vesktop, Slack, VS Code, Obsidian …) laufen über XWayland: Hyprland ignoriert das Minimieren-Symbol nativer
-- Wayland-Fenster, bei XWayland-Fenstern fängt die Shell es ab. Über diese Umgebungsvariable gilt das für JEDEN Start (Autostart, Terminal,
-- Startmenü) – nicht nur für Starter, die wir angelegt haben. Aus: Datei ~/.config/draconyx/electron-native anlegen.
do
    local f = io.open((os.getenv("HOME") or "") .. "/.config/draconyx/electron-native", "r")
    if f then f:close() else hl.env("ELECTRON_OZONE_PLATFORM_HINT", "x11") end
end
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")


-----------------------
---- LOOK AND FEEL ----
-----------------------
hl.config({
    general = {
        gaps_in  = 4,
        gaps_out = 8,
        border_size = 1,
        col = {
            active_border   = { colors = {"rgba(4d8fe0dd)", "rgba(6ba9ffdd)"}, angle = 45 },
            inactive_border = "rgba(ffffff12)",
        },
        resize_on_border = true,    -- Fenster an den Rändern ziehen wie in Windows
        allow_tearing = false,
        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 22,
            render_power = 3,
            color        = 0x66000000,
        },

        blur = {
            enabled   = true,
            size      = 9,
            passes    = 3,
            vibrancy  = 0.2,
            noise     = 0.02,
            brightness = 0.95,
        },
    },

    animations = {
        enabled = true,
    },
})

hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOut",    { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("quick",        { type = "bezier", points = { {0.15, 0},    {0.1, 1}  } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,  bezier = "default" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.5, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 90%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.8, bezier = "quick",        style = "popin 90%" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3,   bezier = "quick" })
hl.animation({ leaf = "border",        enabled = true, speed = 5,   bezier = "easeOutQuint" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.8, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,   bezier = "easeOutQuint", style = "slide bottom" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.8, bezier = "quick",        style = "slide bottom" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 3,   bezier = "easeOutQuint", style = "slide" })

hl.config({
    dwindle = { preserve_split = true },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
        middle_click_paste      = false,
    },
})


---------------
---- INPUT ----
---------------
do   -- Tastaturbelegung aus ~/.config/draconyx/keymap ("de" oder "us"), Standard: de
    local f = io.open((os.getenv("HOME") or "") .. "/.config/draconyx/keymap", "r")
    local k = f and f:read("*l") or ""
    if f then f:close() end
    DX_KEYMAP = (k ~= "" and k:match("^[%a_,]+$")) and k or "de"
end
hl.config({
    input = {
        kb_layout    = DX_KEYMAP,     -- Tastaturbelegung: de (QWERTZ) oder us (QWERTY), Auswahl im Installer / in den Aurora-Einstellungen
        kb_variant   = "",
        kb_model     = "",
        kb_options   = "",
        kb_rules     = "",
        numlock_by_default = true,
        follow_mouse = 2,             -- wie Windows: Fokus wechselt nur per Klick, nicht beim Drüberfahren
        sensitivity  = 0,
        accel_profile = "flat",
        touchpad = { natural_scroll = false },
    },
    cursor = {
        no_warps = true,              -- Maus springt bei Alt+Tab / Fokuswechsel nicht zum Fenster
    },
})


---------------------
---- TASTENKÜRZEL ---
---------------------
local mainMod = "CTRL + ALT"   -- Strg+Alt ist der Hauptmodifikator für ALLE Kombis (Super-Taste wird nicht benutzt)
-- Alle Tastenkombinationen laufen über B(): in den Aurora-Einstellungen frei umbindbar (dx_binds.lua)
local DXB = require("dx_binds")
local B = DXB.bind

-- Windows-Taste allein = Startmenü
B("start_menu", "Startmenü", mainMod .. " + space", hl.dsp.exec_cmd(startMenu))                 -- Startmenü
-- Strg+Space öffnet die Suche NUR auf dem Desktop (kein Fenster im Fokus). Die Taste bleibt nicht verbraucht (non_consuming),
-- Apps bekommen sie also weiter (z. B. Autovervollständigung im Editor).
-- "Auf dem Desktop" heißt: kein Fenster aktiv, das aktive Fenster ist minimiert/versteckt, ODER der leere Desktop wurde zuletzt angeklickt
-- (die Shell setzt dann DX_DESK_CLICK; es gilt, bis ein anderes Fenster den Fokus bekommt oder irgendwo ein Fenster angeklickt wird).
DX_DESK_CLICK = nil
hl.on("window.active", function(w)
    if DX_DESK_CLICK ~= nil and (w == nil or w.address ~= DX_DESK_CLICK) then DX_DESK_CLICK = nil end
end)
hl.bind("mouse:272", function() DX_DESK_CLICK = nil end, { non_consuming = true })   -- jeder Linksklick löscht die Markierung (der Desktop setzt sie danach neu)
B("desktop_search", "Suche (nur auf dem leeren Desktop)", "CTRL + space", function()
    local w = hl.get_active_window()
    local onDesktop = (w == nil) or (w.workspace == nil) or (w.mapped == false) or (w.hidden == true)
        or (w.workspace.name == "minimized") or (DX_DESK_CLICK ~= nil)
    if onDesktop then hl.exec_cmd("qs -c draconyx ipc call shell toggleSearchBox") end
end, { non_consuming = true })

B("file_manager", "Dateimanager", mainMod .. " + E", hl.dsp.exec_cmd(fileManager))                 -- Explorer
B("run_menu", "Ausführen", mainMod .. " + R", hl.dsp.exec_cmd(runMenu))                     -- Ausführen
B("terminal", "Terminal", mainMod .. " + T", hl.dsp.exec_cmd(terminal))
B("browser", "Browser", mainMod .. " + B", hl.dsp.exec_cmd(browser))
B("lock", "Bildschirm sperren", mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))                  -- Sperren
B("clipboard_history", "Zwischenablage-Verlauf", mainMod .. " + V", hl.dsp.exec_cmd("cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"))
B("notifications", "Benachrichtigungen", mainMod .. " + N", hl.dsp.exec_cmd("swaync-client -t -sw"))      -- Benachrichtigungen
B("window_menu", "Fenstermenü (für Apps ohne Titelleiste)", "ALT + space", function()   -- Fenstermenü wie unter Windows (für Apps ohne Titelleiste, z. B. Dolphin)
    local w = hl.get_active_window()
    if w ~= nil then
        hl.exec_cmd(string.format("sh -c 'qs -c draconyx ipc call shell windowMenu %s %d %d'", w.address, math.floor(w.at.x), math.floor(w.at.y)))
    end
end)
B("coding_space", "Coding Space", mainMod .. " + K", hl.dsp.exec_cmd("sh -c 'qs -c draconyx ipc call shell toggleCode'"))   -- Coding Space
B("task_view", "Fensterübersicht (Task View)", mainMod .. " + Tab", hl.dsp.exec_cmd("sh -c 'qs -c draconyx ipc call shell toggleTaskView'"))   -- Task View
B("quick_settings", "Schnelleinstellungen", mainMod .. " + A", hl.dsp.exec_cmd(quickPanel))                  -- Schnelleinstellungen
B("search", "Suche (Startmenü)", mainMod .. " + S", hl.dsp.exec_cmd(startMenu))                   -- Suche (Startmenü)
B("exit_hyprland", "Notausgang: Hyprland beenden", mainMod .. " + SHIFT + Q", hl.dsp.exit())                 -- Notausgang: Hyprland beenden
B("screenshot_region", "Screenshot: Bereich wählen (Snip-Werkzeug)", mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("qs -c draconyx ipc call shell snip region"))
B("screenshot_snip", "Screenshot: Bereich wählen (Druck)", "Print", hl.dsp.exec_cmd("qs -c draconyx ipc call shell snip region"))
B("screenshot_screen", "Screenshot: ganzer Bildschirm (kopiert + speichert)", "SHIFT + Print", hl.dsp.exec_cmd("qs -c draconyx ipc call shell snip screen"))

-- Fenster-Snapping wie unter Windows: links/rechts halbe Seite, oben ganzer Bildschirm,
-- unten zurück auf normale Größe mittig. Lässt den Platz der Taskleiste (reserved) frei.
local SNAP_GAP = 8
local function snap(where)
    local w = hl.get_active_window()
    if w == nil then return end
    local m = w.monitor or hl.get_active_monitor()
    local r = m.reserved or {}
    local x0 = m.x + (r.left or 0) + SNAP_GAP
    local y0 = m.y + (r.top or 0) + SNAP_GAP
    local aw = m.width  - (r.left or 0) - (r.right or 0)  - 2 * SNAP_GAP
    local ah = m.height - (r.top or 0)  - (r.bottom or 0) - 2 * SNAP_GAP

    local x, y, ww, wh = x0, y0, aw, ah
    if where == "left" then
        ww = math.floor((aw - SNAP_GAP) / 2)
    elseif where == "right" then
        ww = math.floor((aw - SNAP_GAP) / 2)
        x  = x0 + ww + SNAP_GAP
    elseif where == "restore" then
        ww = math.floor(aw * 0.62)
        wh = math.floor(ah * 0.72)
        x  = x0 + math.floor((aw - ww) / 2)
        y  = y0 + math.floor((ah - wh) / 2)
    end

    if w.fullscreen ~= 0 then hl.dispatch(hl.dsp.window.fullscreen({ action = "unset" })) end
    if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "set" })) end   -- "set" schaltet um: nur wenn nötig
    hl.dispatch(hl.dsp.window.resize({ x = ww, y = wh, relative = false }))
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false }))
end

-- Fenster
B("window_kill", "Fenster sofort beenden (kill)", "ALT + F4",         hl.dsp.window.kill())    -- sofort beenden (SIGKILL), ohne Nachfrage
B("window_close", "Fenster schließen", mainMod .. " + Q",  hl.dsp.window.close())   -- normal schließen
-- Maximieren = echtes Hyprland-Maximieren (gleich wie der Maximieren-Knopf der Apps)
local function toggleMax()
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
end

-- Minimieren (Hyprland hat es nicht nativ): Fenster in den versteckten Special-Workspace "minimized" legen,
-- Wiederherstellen = zurück auf den aktuellen Desktop + fokussieren.
local MIN_WS = "name:minimized"          -- normaler, nie angezeigter Workspace (Special-Workspaces blenden sich ein)
local minOrigin = {}   -- address -> { ws, x, y, w, h }: so kehrt ein Fenster an seinen Platz zurück
local function noAnim(addr)
    hl.dispatch(hl.dsp.window.set_prop({ window = "address:" .. addr, prop = "no_anim", value = "1" }))
    hl.timer(function()
        hl.dispatch(hl.dsp.window.set_prop({ window = "address:" .. addr, prop = "no_anim", value = "0" }))
    end, { timeout = 900, type = "oneshot" })
end
local function minimizeWindow(w)
    if w == nil then return end
    if w.workspace ~= nil and w.workspace.name ~= "minimized" then
        minOrigin[w.address] = { ws = w.workspace.id, x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
    end
    noAnim(w.address)
    hl.dispatch(hl.dsp.window.move({ window = "address:" .. w.address, workspace = MIN_WS, follow = false }))
end
local function restoreWindow(w)
    if w == nil then return end
    local o = minOrigin[w.address]
    local ws = hl.get_active_workspace()
    local target = o and o.ws or (ws and ws.id or 1)
    noAnim(w.address)
    hl.dispatch(hl.dsp.window.move({ window = "address:" .. w.address, workspace = target, follow = false }))
    if o then
        hl.dispatch(hl.dsp.window.resize({ window = "address:" .. w.address, x = o.w, y = o.h, relative = false }))
        hl.dispatch(hl.dsp.window.move({ window = "address:" .. w.address, x = o.x, y = o.y, relative = false }))
    end
    hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
end
local function lastMinimized()
    for _, w in ipairs(hl.get_windows()) do
        if w.workspace ~= nil and w.workspace.name == "minimized" then return w end
    end
    return nil
end
-- Der Minimieren-Knopf von Apps (z. B. Ghostty, Brave) wird von der Draconyx Shell abgefangen
-- (Hyprland meldet "minimized>>adresse,1" auf dem Event-Socket; Lua kennt in 0.56 kein window.minimize).

-- Win+Pfeil runter wie unter Windows: maximiert -> normal, normal -> minimieren
local function restoreOrShrink()
    local w = hl.get_active_window()
    if w == nil then return end
    if w.fullscreen ~= 0 then
        hl.dispatch(hl.dsp.window.fullscreen({ action = "unset" }))
    else
        minimizeWindow(w)
    end
end
B("window_minimize", "Fenster minimieren", mainMod .. " + M",         function() minimizeWindow(hl.get_active_window()) end)
B("window_restore", "Minimiertes Fenster zurückholen", mainMod .. " + SHIFT + M", function() restoreWindow(lastMinimized()) end)
-- Draconyx Tiling (eigener Kachel-Modus) + Snap (Andocken an Ränder/Ecken, Windows-Ketten)
DXZones = require("dx_zones")
DXTiling = require("dx_tiling")
DXSnap = require("dx_snap")
DXSnap.setup(DXTiling, { minimize = minimizeWindow })
DXSizes = require("dx_sizes")   -- Fenstergröße beim Schließen merken, beim Öffnen wiederherstellen
DXSizes.setup(DXSnap)

B("snap_up", "Fenster nach oben (Snap/Maximieren)", mainMod .. " + Up",    function() DXSnap.arrow("up") end)
B("snap_down", "Fenster nach unten (Snap/Wiederherstellen)", mainMod .. " + Down",  function() DXSnap.arrow("down") end)
B("snap_left", "Fenster nach links (Snap)", mainMod .. " + Left",  function() DXSnap.arrow("left") end)
B("snap_right", "Fenster nach rechts (Snap)", mainMod .. " + Right", function() DXSnap.arrow("right") end)

-- Kachel-Modus: Fenster bleiben normal frei schwebend; diese Tasten ordnen sie in einem Raster an
local function zonesShell(fn) return "sh -c 'qs -c draconyx ipc call shell " .. fn .. "'" end
B("grid_toggle", "Aktives Fenster ins Raster / heraus", mainMod .. " + G",              function() DXTiling.toggle(); hl.exec_cmd(zonesShell("flashZones")) end)   -- aktives Fenster ins Raster / heraus
B("grid_toggle_workspace", "Ganzen Desktop kacheln an/aus", mainMod .. " + SHIFT + G",      function() DXTiling.toggleWorkspace(); hl.exec_cmd(zonesShell("flashZones")) end)  -- ganzer Desktop kacheln an/aus
B("grid_panic", "NOTAUSGANG: alles aus dem Raster, Overlays zu", mainMod .. " + BackSpace", function() DXTiling.releaseAll(); hl.exec_cmd("sh -c 'qs -c draconyx ipc call shell closeAll; qs -c draconyx ipc call shell closeGrid'") end)   -- NOTAUSGANG: alles aus dem Raster, Overlays zu
B("zones_cycle", "Raster-Vorlage wechseln", mainMod .. " + H",              function() hl.exec_cmd(zonesShell("cycleZones")) end)      -- Raster-Vorlage wechseln
B("grid_mode", "Auto-Layout wechseln (Zonen/Raster/Spalten/Zeilen/Master)", mainMod .. " + J",              function() DXTiling.cycleMode() end)        -- Auto-Layout: Zonen / Raster / Spalten / Zeilen / Master
B("zones_edit", "Raster-Editor", mainMod .. " + Z",              function() hl.exec_cmd(zonesShell("editZones")) end)       -- Raster-Editor
B("zones_pick", "Zone für aktives Fenster wählen", mainMod .. " + X",              function() if DXZones.rememberActive() then hl.exec_cmd(zonesShell("pickZone")) end end)  -- Zone für aktives Fenster wählen        -- Raster / Spalten / Zeilen / Master
B("grid_shift_prev", "Platz im Raster tauschen (zurück)", mainMod .. " + comma",          function() DXTiling.shift(-1) end)          -- Platz im Raster tauschen
B("grid_shift_next", "Platz im Raster tauschen (vor)", mainMod .. " + period",         function() DXTiling.shift(1) end)
B("fullscreen", "Vollbild", mainMod .. " + F",  hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
B("fullscreen_f11", "Vollbild (F11)", "F11",              hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
B("window_center", "Fenster zentrieren", mainMod .. " + C",  hl.dsp.window.center())


-- Maus befreien: Fokus + Zeiger auf einen anderen Monitor. Ein Fenster (z. B. Spiel),
-- das die Maus festhält, verliert dabei den Fokus und muss sie freigeben.
local function freeMouse()
    local cur = hl.get_active_monitor()
    local target = nil
    for _, m in ipairs(hl.get_monitors()) do
        if cur == nil or m.name ~= cur.name then target = m; break end
    end
    if target == nil then return end
    hl.dispatch(hl.dsp.focus({ monitor = target.name }))
    hl.dispatch(hl.dsp.cursor.move({ x = target.x + math.floor(target.width / 2),
                                     y = target.y + math.floor(target.height / 2) }))
end
B("free_mouse", "Maus aus Spielen/Fenstern befreien", mainMod .. " + Escape", freeMouse, { locked = true })

-- Alt+Tab wie Windows: Umschalter der Draconyx Shell mit allen Fenstern (zuletzt benutzt zuerst).
-- Alt halten + Tab = weiter, Shift+Tab = zurück, Alt loslassen = wechseln.
-- Ersatz, falls die Shell nicht läuft: direkt zum letzten Fenster.
local function switcher(action)
    return hl.dsp.exec_cmd("sh -c 'qs -c draconyx ipc call switcher " .. action
        .. " 2>/dev/null || { [ " .. action .. " = next ] && hyprctl dispatch \"hl.dsp.focus({ last = true })\"; }'")
end
B("switcher_next", "Alt+Tab: nächstes Fenster", "ALT + Tab",            switcher("next"))
B("switcher_prev", "Alt+Tab: voriges Fenster", "ALT + SHIFT + Tab",    switcher("prev"))
B("switcher_commit", "Alt+Tab bestätigen (Alt loslassen)", "ALT + Alt_L",          switcher("commit"), { release = true, transparent = true })
B("switcher_commit_shift", "Alt+Tab bestätigen (mit Shift)", "ALT + SHIFT + Alt_L",  switcher("commit"), { release = true, transparent = true })
B("switcher_cancel", "Alt+Tab abbrechen", "ALT + Escape",         switcher("cancel"))

-- Wie Windows: Win + Shift + Pfeil = Fenster auf anderen Bildschirm
B("window_to_left_monitor", "Fenster auf linken Monitor", mainMod .. " + SHIFT + Left",  hl.dsp.window.move({ monitor = "l", follow = true }))
B("window_to_right_monitor", "Fenster auf rechten Monitor", mainMod .. " + SHIFT + Right", hl.dsp.window.move({ monitor = "r", follow = true }))

-- Virtuelle Desktops
B("desktop_prev", "Vorheriger Desktop", mainMod .. " + Prior", hl.dsp.focus({ workspace = "e-1" }))     -- Bild hoch
B("desktop_next", "Nächster Desktop", mainMod .. " + Next",  hl.dsp.focus({ workspace = "e+1" }))     -- Bild runter
for i = 1, 9 do
    B("ws_focus_" .. i, "Zu Desktop n", mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    B("ws_move_" .. i, "Fenster auf Desktop n", mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Mit Super + Maus verschieben / Größe ändern
B("window_drag", "Fenster verschieben (Maus)", mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
B("window_resize", "Fenstergröße ändern (Maus)", mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
-- Alt + Maus geht auch (für Fenster ohne Titelleiste)
B("window_drag_alt", "Fenster verschieben (Maus, zweite Kombination)", "ALT + mouse:272", hl.dsp.window.drag(),   { mouse = true })
B("window_resize_alt", "Fenstergröße ändern (Maus, zweite Kombination)", "ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })
DXSnap.bindMouse(DXB)   -- Ziehen-Erkennung (Vorschau/Einrasten) folgt den gewählten Maus-Kombinationen

-- Lautstärke / Medien
B("volume_up", "Lauter", "XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
B("volume_down", "Leiser", "XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
B("volume_mute", "Stumm", "XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
B("media_next", "Medien: nächster Titel", "XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
B("media_pause", "Medien: Pause", "XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
B("media_play", "Medien: Wiedergabe", "XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
B("media_prev", "Medien: voriger Titel", "XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


--------------------------------
---- FENSTER-REGELN ------------
--------------------------------
-- Alle Fenster schweben und öffnen zentriert, wie unter Windows
hl.window_rule({
    name  = "windows-style-float",
    match = { class = ".*" },
    float  = true,
    center = true,
})

-- Terminals nie winzig öffnen (schwebende Ghostty-Fenster kamen mit ~138 px Breite)
hl.window_rule({ name = "ghostty-size", match = { class = "^(com\\.mitchellh\\.ghostty|kitty)$" },
    min_size = { 760, 460 } })

-- Spiele: echtes Vollbild auf eigenem Desktop (10) auf dem 180-Hz-Monitor.
-- So liegt die Taskleiste nicht darüber, und Alt+Tab lässt das Spiel im Hintergrund weiterlaufen.
hl.workspace_rule({ workspace = "10", default_name = "Spiel" })
hl.workspace_rule({ workspace = "8", default_name = "Code" })
-- no_shortcuts_inhibit: Spiele dürfen Alt+Tab / Super nicht schlucken
hl.window_rule({ name = "games-steam", match = { class = "^(steam_app_.*|gamescope|RocketLeague.*)$" },
    float = false, fullscreen = true, workspace = "10", no_shortcuts_inhibit = true, idle_inhibit = "fullscreen" })
hl.window_rule({ name = "games-content", match = { content = "game" },
    float = false, fullscreen = true, workspace = "10", no_shortcuts_inhibit = true, idle_inhibit = "fullscreen" })

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- Layer: Milchglas für Taskleiste, Startmenü, Launcher, Benachrichtigungen
hl.layer_rule({ match = { namespace = "waybar" },                       blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "^draconyx-(bar|start|control|calendar|alttab|taskview|code|windowmenu|grid|notif.*|settings)$" }, blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "^draconyx-bar$" },               no_anim = true })   -- Leiste animiert sich selbst
hl.layer_rule({ match = { namespace = "nwg-drawer" },                   blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "launcher" },                     blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "swaync-control-center" },        blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ match = { namespace = "swaync-notification-window" },   blur = true, ignore_alpha = 0.3 })

DXB.flush()   -- Liste aller Aktionen für die Einstellungs-App schreiben

-- Einstellungen aus der Aurora-Einstellungs-App (Rahmen, Unschärfe, Tastaturbelegung, Fokus …): ohne diese Zeilen hätten sie
-- bei einer reinen Draconyx-Installation keine Wirkung.
aurora_bindings = aurora_bindings or {}
do
    local f = io.open((os.getenv("HOME") or "") .. "/.config/hypr/aurora/preferences.lua", "r")
    if f then f:close(); pcall(dofile, (os.getenv("HOME") or "") .. "/.config/hypr/aurora/preferences.lua") end
end
