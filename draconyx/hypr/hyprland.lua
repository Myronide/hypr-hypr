-- Hyprland: "Draconyx Dark" im Windows-11-Stil
-- Schwebende Taskleiste unten (Waybar), Startmenü (nwg-drawer), Desktop mit Icons (pcmanfm-qt), schwebende Fenster.
-- Farben: Schwarz-Grün, Akzent Violett #8b5cf6, Zweitakzent Grün #6ee05c (Augen des Drachens)

------------------
---- MONITORE ----
------------------
-- Anordnung wie in COSMIC: links DP-1, Mitte DP-2, rechts HDMI-A-2 (alle oben bündig)
-- HDR: cm = "hdr". Helligkeit normaler (SDR) Fenster = 80 nits × sdrbrightness (KDE hatte 200 bzw. 300 nits).
-- Zu hell? Wert senken, zu dunkel? erhöhen. Mit `hyprctl reload` sofort sichtbar.

hl.monitor({
    output        = "DP-1",            -- Acer VG270U E
    mode          = "2560x1440@59.95",
    position      = "0x0",
    scale         = 1,
    bitdepth      = 10,
    cm            = "hdr",
    sdrbrightness = 3.75,          -- ≈ 300 nits wie vorher in KDE
    sdrsaturation = 1.0,
})

hl.monitor({
    output        = "DP-2",            -- Acer XV271U M3 (180 Hz)
    mode          = "2560x1440@179.88",
    position      = "2560x0",
    scale         = 1,
    bitdepth      = 10,
    cm            = "hdr",
    sdrbrightness = 2.5,           -- ≈ 200 nits wie vorher in KDE
    sdrsaturation = 1.0,
    vrr           = 1,
})

hl.monitor({
    output   = "HDMI-A-2",             -- 236 FHD (kein HDR)
    mode     = "1920x1080@60",
    position = "5120x0",
    scale    = 1,
})

-- Alles andere (z. B. neuer Monitor): rechts anhängen
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })


---------------------
---- PROGRAMME ------
---------------------
local terminal    = "sh -c 'command -v ghostty >/dev/null && exec ghostty || exec kitty'"
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
hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/lib/hyprpolkitagent/hyprpolkitagent")
    hl.exec_cmd("sh -c 'command -v qs >/dev/null || exec pcmanfm-qt --desktop'")  -- Desktop: Draconyx Shell, Fallback pcmanfm-qt
    hl.exec_cmd(shellBar)                              -- Taskleiste (Draconyx Shell)
    hl.exec_cmd("swaync")                              -- Benachrichtigungen
    hl.exec_cmd("hypridle")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("wl-paste --watch cliphist store")    -- Zwischenablage-Verlauf (Win+V)
    hl.exec_cmd("hyprctl setcursor Windows10Light 24")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme Windows10Light")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark")
    -- deine bisherigen Autostarts
    hl.exec_cmd("easyeffects --hide-window --service-mode")
    hl.exec_cmd("jamesdsp")
    hl.exec_cmd(os.getenv("HOME") .. "/Jetbrains_Toolbox/jetbrains-toolbox --minimize")
end)


-------------------------------
---- UMGEBUNGSVARIABLEN -------
-------------------------------
hl.env("XCURSOR_THEME", "Windows10Light")      -- klassischer Windows-Mauszeiger
hl.env("HYPRCURSOR_THEME", "Windows10Light")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")      -- KDE-Farbschema (dunkel) auch unter Hyprland, z. B. für Dolphin
hl.env("GTK_THEME", "adw-gtk3-dark")
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
            active_border   = { colors = {"rgba(8b5cf6dd)", "rgba(6ee05cdd)"}, angle = 45 },
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
hl.config({
    input = {
        kb_layout    = "de",          -- deutsche Tastatur
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

-- Windows-Taste allein = Startmenü
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd(startMenu))                 -- Startmenü

hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))                 -- Explorer
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(runMenu))                     -- Ausführen
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))                  -- Sperren
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("swaync-client -t -sw"))      -- Benachrichtigungen
hl.bind("ALT + space", function()   -- Fenstermenü wie unter Windows (für Apps ohne Titelleiste, z. B. Dolphin)
    local w = hl.get_active_window()
    if w ~= nil then
        hl.exec_cmd(string.format("sh -c 'qs -c draconyx ipc call shell windowMenu %s %d %d'", w.address, math.floor(w.at.x), math.floor(w.at.y)))
    end
end)
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("sh -c 'qs -c draconyx ipc call shell toggleCode'"))   -- Coding Space
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd("sh -c 'qs -c draconyx ipc call shell toggleTaskView'"))   -- Task View
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(quickPanel))                  -- Schnelleinstellungen
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd(startMenu))                   -- Suche (Startmenü)
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exit())                 -- Notausgang: Hyprland beenden
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("hyprshot -m region --clipboard-only"))
hl.bind("Print", hl.dsp.exec_cmd("hyprshot -m output --clipboard-only"))

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
hl.bind("ALT + F4",         hl.dsp.window.kill())    -- sofort beenden (SIGKILL), ohne Nachfrage
hl.bind(mainMod .. " + Q",  hl.dsp.window.close())   -- normal schließen
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
hl.bind(mainMod .. " + M",         function() minimizeWindow(hl.get_active_window()) end)
hl.bind(mainMod .. " + SHIFT + M", function() restoreWindow(lastMinimized()) end)
-- Draconyx Tiling (eigener Kachel-Modus) + Snap (Andocken an Ränder/Ecken, Windows-Ketten)
DXZones = require("dx_zones")
DXTiling = require("dx_tiling")
DXSnap = require("dx_snap")
DXSnap.setup(DXTiling, { minimize = minimizeWindow })

hl.bind(mainMod .. " + Up",    function() DXSnap.arrow("up") end)
hl.bind(mainMod .. " + Down",  function() DXSnap.arrow("down") end)
hl.bind(mainMod .. " + Left",  function() DXSnap.arrow("left") end)
hl.bind(mainMod .. " + Right", function() DXSnap.arrow("right") end)

-- Kachel-Modus: Fenster bleiben normal frei schwebend; diese Tasten ordnen sie in einem Raster an
local function zonesShell(fn) return "sh -c 'qs -c draconyx ipc call shell " .. fn .. "'" end
hl.bind(mainMod .. " + G",              function() DXTiling.toggle(); hl.exec_cmd(zonesShell("flashZones")) end)   -- aktives Fenster ins Raster / heraus
hl.bind(mainMod .. " + SHIFT + G",      function() DXTiling.toggleWorkspace(); hl.exec_cmd(zonesShell("flashZones")) end)  -- ganzer Desktop kacheln an/aus
hl.bind(mainMod .. " + BackSpace", function() DXTiling.releaseAll(); hl.exec_cmd("sh -c 'qs -c draconyx ipc call shell closeAll; qs -c draconyx ipc call shell closeGrid'") end)   -- NOTAUSGANG: alles aus dem Raster, Overlays zu
hl.bind(mainMod .. " + H",              function() hl.exec_cmd(zonesShell("cycleZones")) end)      -- Raster-Vorlage wechseln
hl.bind(mainMod .. " + J",              function() DXTiling.cycleMode() end)        -- Auto-Layout: Zonen / Raster / Spalten / Zeilen / Master
hl.bind(mainMod .. " + Z",              function() hl.exec_cmd(zonesShell("editZones")) end)       -- Raster-Editor
hl.bind(mainMod .. " + X",              function() if DXZones.rememberActive() then hl.exec_cmd(zonesShell("pickZone")) end end)  -- Zone für aktives Fenster wählen        -- Raster / Spalten / Zeilen / Master
hl.bind(mainMod .. " + comma",          function() DXTiling.shift(-1) end)          -- Platz im Raster tauschen
hl.bind(mainMod .. " + period",         function() DXTiling.shift(1) end)
hl.bind(mainMod .. " + F",  hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind("F11",              hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + C",  hl.dsp.window.center())


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
hl.bind(mainMod .. " + Escape", freeMouse, { locked = true })

-- Alt+Tab wie Windows: Umschalter der Draconyx Shell mit allen Fenstern (zuletzt benutzt zuerst).
-- Alt halten + Tab = weiter, Shift+Tab = zurück, Alt loslassen = wechseln.
-- Ersatz, falls die Shell nicht läuft: direkt zum letzten Fenster.
local function switcher(action)
    return hl.dsp.exec_cmd("sh -c 'qs -c draconyx ipc call switcher " .. action
        .. " 2>/dev/null || { [ " .. action .. " = next ] && hyprctl dispatch \"hl.dsp.focus({ last = true })\"; }'")
end
hl.bind("ALT + Tab",            switcher("next"))
hl.bind("ALT + SHIFT + Tab",    switcher("prev"))
hl.bind("ALT + Alt_L",          switcher("commit"), { release = true, transparent = true })
hl.bind("ALT + SHIFT + Alt_L",  switcher("commit"), { release = true, transparent = true })
hl.bind("ALT + Escape",         switcher("cancel"))

-- Wie Windows: Win + Shift + Pfeil = Fenster auf anderen Bildschirm
hl.bind(mainMod .. " + SHIFT + Left",  hl.dsp.window.move({ monitor = "l", follow = true }))
hl.bind(mainMod .. " + SHIFT + Right", hl.dsp.window.move({ monitor = "r", follow = true }))

-- Virtuelle Desktops
hl.bind(mainMod .. " + Prior", hl.dsp.focus({ workspace = "e-1" }))     -- Bild hoch
hl.bind(mainMod .. " + Next",  hl.dsp.focus({ workspace = "e+1" }))     -- Bild runter
for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Mit Super + Maus verschieben / Größe ändern
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
-- Alt + Maus geht auch (für Fenster ohne Titelleiste)
hl.bind("ALT + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Lautstärke / Medien
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


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
hl.workspace_rule({ workspace = "10", monitor = "DP-2", default_name = "Spiel" })
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
