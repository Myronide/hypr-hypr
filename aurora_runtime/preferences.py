import json,subprocess,os,re,shutil,time,tempfile
from pathlib import Path
BASE=Path.home()/'.config/hypr/aurora'
SHELL=(Path.home()/'.config/quickshell/draconyx/shell.qml').exists()   # Hypr Hypr-Shell vorhanden -> eigene Taskleiste statt waybar
DEFAULTS={'scroll_speed':1.0,'dock_visibility':'always','dock_monitor':'DP-2','dock_icon_size':32,'dock_opacity':0.95,'desktop_icon_size':44,'desktop_font_size':11,'grid_snap':True,'grid_visible':False,'grid_width':122,'grid_height':112,'titlebar_height':28,'titlebar_font':10,'tile_gap':12,'rounding':12,'border_size':0,'blur':True,'blur_size':6,'blur_passes':3,'wallpaper':'','wallpaper_monitor':'','wallpaper_fit':'cover','workshop':'/mnt/Games/Steam/steamapps/workshop/content/431960','engine_assets':'/mnt/Games/Steam/steamapps/common/wallpaper_engine/assets','engine_fps':30,'engine_volume':0,'engine_path':'','engine_monitor':'DP-2','engine_mouse':True,'engine_parallax':True,'engine_fullscreen_pause':True,'engine_active':False}

def atomic_write(path,text):
 """Schreibt text über eine eindeutige Temp-Datei im selben Ordner und ersetzt die Zieldatei atomar (nie halb geschriebene Dateien)."""
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
 fd,tmp=tempfile.mkstemp(dir=str(path.parent),prefix='.'+path.name+'.',suffix='.tmp')
 try:
  with os.fdopen(fd,'w',encoding='utf-8') as f:f.write(text)
  try:os.chmod(tmp,(path.stat().st_mode&0o777) if path.exists() else 0o644)
  except OSError:pass
  os.replace(tmp,path)
 except BaseException:
  try:os.unlink(tmp)
  except OSError:pass
  raise
def run_quiet(args,timeout=10):
 """Programm ohne Ausgabe starten; fehlendes Programm oder Zeitüberschreitung ergibt False statt eines Absturzes."""
 try:return subprocess.run(args,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=timeout).returncode==0
 except (OSError,subprocess.SubprocessError):return False
def _kind(v):
 if isinstance(v,bool):return bool
 if isinstance(v,(int,float)):return float
 return type(v)
def sanitize_preferences(raw):
 """Defaults + gelesene Werte; Werte mit falschem Typ (z. B. Text statt Zahl) fallen auf den Standard zurück."""
 out=DEFAULTS.copy()
 if not isinstance(raw,dict):return out
 for k,v in raw.items():
  if k in DEFAULTS and _kind(v)!=_kind(DEFAULTS[k]):continue
  out[k]=v
 for k in ('shortcuts','wallpapers','engine_properties'):
  if k in out and not isinstance(out[k],dict):del out[k]
 return out
def number(p,key,lo,hi,default=None):
 """Zahl aus den Einstellungen, auf [lo,hi] begrenzt; kaputte Werte ergeben den Standard."""
 try:v=int(float(p.get(key,DEFAULTS.get(key,lo) if default is None else default)))
 except (TypeError,ValueError,OverflowError):v=int(DEFAULTS.get(key,lo) if default is None else default)
 return max(lo,min(hi,v))
def load_preferences():
 try:return sanitize_preferences(json.loads((BASE/'preferences.json').read_text(encoding='utf-8')))
 except (OSError,ValueError):return DEFAULTS.copy()
def send_ui(*args):
 import socket
 try:
  with socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM) as s:s.sendto(json.dumps(args).encode(),str(Path(os.environ.get('XDG_RUNTIME_DIR','/nonexistent'))/'aurora-ui.sock'))
 except (OSError,KeyError):pass
def modifier_mode():
 """Haupttaste (Aurora-Einstellungen): super | both | ctrl-alt | caps – gemeinsame Datei mit der Hypr Hypr-Shell."""
 try:m=(Path.home()/'.config/draconyx/modifier').read_text().strip()
 except (OSError,ValueError):return 'super'
 return m if m in MODIFIERS else 'super'
MODIFIERS=('super','both','ctrl-alt','caps')
def set_modifier_mode(mode):
 if mode not in MODIFIERS:raise ValueError('Unbekannte Haupttaste: '+repr(mode))
 atomic_write(Path.home()/'.config/draconyx/modifier',mode+'\n')
KEYMAPS=('de','us')   # QWERTZ (Deutsch) / QWERTY (US)
def current_keymap():
 try:k=(Path.home()/'.config/draconyx/keymap').read_text().strip()
 except (OSError,ValueError):k=''
 return k if re.fullmatch(r'[a-z]{2,8}',k or '') else 'de'
ACTIONS={'launcher':'launcher','clipboard':'desktop-ui clipboard','settings':'settings-app','desktop':'desktop-ui show-desktop','mode':'mode --toggle','minimize':'desktop-ui minimize'}
MODS=('SUPER','CTRL','ALT','SHIFT')
KEY_RE=re.compile(r'[A-Za-z0-9_]{1,24}|mouse:27[2-6]|mouse_(?:up|down)|code:\d{1,3}')
def normalize_combo(combo):
 """Prüft eine Hyprland-Kombination („SUPER + SHIFT + F“, „ALT + mouse:272“). Gibt die Schreibweise mit ' + ' zurück,
 '' für „ausgeschaltet“; ungültige Eingaben lösen ValueError aus (nie Zeichen, die Lua oder die Shell verwirren)."""
 if not isinstance(combo,str):raise ValueError('Ungültige Tastenkombination: '+repr(combo))
 combo=combo.strip()
 if not combo:return ''
 if not re.fullmatch(r'[A-Za-z0-9 +_:\-]*',combo):raise ValueError('Ungültige Tastenkombination: '+combo)
 parts=[x.strip() for x in combo.split('+')]
 if any(not x for x in parts):raise ValueError('Ungültige Tastenkombination (leerer Teil): '+combo)
 *mods,key=parts
 mods_u=[m.upper() for m in mods]
 if any(m not in MODS for m in mods_u):raise ValueError('Unbekannte Zusatztaste in: '+combo)
 if len(set(mods_u))!=len(mods_u):raise ValueError('Zusatztaste doppelt in: '+combo)
 if key.upper() in MODS:raise ValueError('Es fehlt die Haupttaste in: '+combo)
 if not KEY_RE.fullmatch(key):raise ValueError('Unbekannte Taste in: '+combo)
 if key.startswith('mouse') and not mods:raise ValueError('Mausklicks brauchen eine Zusatztaste: '+combo)
 return ' + '.join(mods_u+[key])
def find_conflict(binds,aid,combo):
 """binds: {id: (Name, Kombination)}; liefert den Namen einer anderen Aktion mit derselben Kombination (Groß/Klein egal) oder None."""
 if not combo:return None
 c=combo.replace(' ','').lower()
 for k,(name,cur) in binds.items():
  if k!=aid and cur and cur.replace(' ','').lower()==c:return name
 return None
def read_binds_conf(path=None):
 """binds.conf (id=Kombination je Zeile); kaputte Zeilen werden übersprungen."""
 path=Path(path) if path else Path.home()/'.config/draconyx/binds.conf';over={}
 try:text=path.read_text(encoding='utf-8',errors='replace')
 except OSError:return over
 for line in text.splitlines():
  if '=' in line and not line.lstrip().startswith('#'):
   k,v=line.split('=',1);k=k.strip()
   if k:over[k]=v.strip()
 return over
def write_binds_conf(over,path=None):
 path=Path(path) if path else Path.home()/'.config/draconyx/binds.conf'
 atomic_write(path,''.join('%s=%s\n'%(k,v) for k,v in over.items()))
def save_preferences(p):
 p=dict(p)
 p['shortcuts']=dict(p['shortcuts']) if isinstance(p.get('shortcuts'),dict) else {}
 atomic_write(BASE/'preferences.json',json.dumps(p,ensure_ascii=False,indent=2))
 home=Path.home();shared=home/'.config/draconyx'
 term=p.get('terminal')
 if isinstance(term,str) and term.strip() and re.fullmatch(r'[A-Za-z0-9_.+\-/ ]+',term.strip()):
  atomic_write(shared/'terminal',term.strip()+'\n')   # gemeinsam mit dem Hypr Hypr-Teil (hyhy-terminal)
 n=lambda key,lo,hi:number(p,key,lo,hi)
 source='hl.config({general={border_size=%d,resize_on_border=true,extend_border_grab_area=8},decoration={rounding=%d,blur={enabled=%s,size=%d,passes=%d}}})\n'%(n('border_size',0,6),n('rounding',0,40),'true' if p.get('blur',True) else 'false',n('blur_size',1,15),n('blur_passes',1,5))
 source+='if hl.plugin.hyprbars then hl.config({plugin={hyprbars={bar_height=%d,bar_text_size=%d}}}) end\n'%(n('titlebar_height',22,48),n('titlebar_font',8,16))
 if p.get('focus_follows_mouse'):source+='hl.config({input={follow_mouse=1}})\n'   # nur wenn ausdrücklich gewählt; sonst gilt follow_mouse aus hyprland.lua (Hover soll in jedem Fenster ankommen)

 try:mo=float(p.get('motion',1) or 0)
 except (TypeError,ValueError):mo=1.0
 if mo!=mo or mo in (float('inf'),float('-inf')):mo=1.0
 if mo<=0:source+='hl.config({animations={enabled=false}})\n'
 elif abs(mo-1)>0.01:   # Animationen schneller/weicher: Geschwindigkeit der wichtigsten Übergänge skalieren (Hyprland: größer = langsamer)
  mo=min(mo,10.0)
  for leaf,sp,bez,extra in (('windows',4.5,'easeOutQuint',''),('windowsIn',4.1,'easeOutQuint',',style="popin 90%"'),('windowsOut',1.8,'quick',',style="popin 90%"'),('fade',3,'quick',''),('layers',3.8,'easeOutQuint',''),('workspaces',3,'easeOutQuint',',style="slide"')):
   source+='hl.animation({leaf="%s",enabled=true,speed=%.2f,bezier="%s"%s})\n'%(leaf,sp*mo,bez,extra)
 try:sf=float(p.get('scroll_speed',1.0) or 1.0)
 except (TypeError,ValueError):sf=1.0
 if sf!=sf:sf=1.0
 sf=max(0.1,min(10.0,sf))
 source+='hl.config({input={scroll_factor=%.2f}})\n'%sf   # Mausrad-Geschwindigkeit (1.0 = Standard)
 atomic_write(shared/'scroll-speed','%.2f\n'%sf)   # die Shell skaliert ihre Listen selbst (Qt ignoriert scroll_factor)
 if p.get('keymap') in KEYMAPS:
  source+='hl.config({input={kb_layout="%s"}})\n'%p['keymap']   # Tastaturbelegung (gilt sofort nach dem Neuladen)
  atomic_write(shared/'keymap',p['keymap']+'\n')
 mode=modifier_mode()
 # erst alles prüfen, dann schreiben: eine ungültige Kombination darf preferences.lua nicht halb ändern
 for key,combo in p['shortcuts'].items():
  if key in ACTIONS:p['shortcuts'][key]=normalize_combo(combo)
 for key,combo in p['shortcuts'].items():
  if key not in ACTIONS:continue
  if mode=='ctrl-alt':combo=combo.replace('SUPER + CTRL','CTRL + ALT + SHIFT').replace('SUPER','CTRL + ALT')   # Super aus: Strg+Alt ersetzt sie
  source+='if aurora_bindings and aurora_bindings.'+key+' then aurora_bindings.'+key+':remove() end\n'
  if combo.strip():source+='aurora_bindings.'+key+' = hl.bind('+json.dumps(combo)+',hl.dsp.exec_cmd('+json.dumps(str(BASE/ACTIONS[key]))+'))\n'
 atomic_write(BASE/'preferences.lua',source)
 try:op=max(.2,min(1,float(p.get('dock_opacity',.95))))
 except (TypeError,ValueError):op=.95
 atomic_write(BASE/'preferences.css','.desktop-label {font-size: %dpx;} .app-dock {background: transparent;} window#waybar {background: rgba(38,42,48,%.2f);}\n'%(n('desktop_font_size',8,20),op))
 if SHELL:return   # mit der Hypr Hypr-Shell gibt es keine waybar/Aurora-Dock-Neustarts
 config=home/'.config/waybar/config.jsonc'
 try:c=json.loads(config.read_text())
 except (OSError,ValueError):return   # keine (oder kaputte) waybar-Konfiguration: nichts anfassen
 if not isinstance(c,dict):return
 adaptive=p.get('dock_visibility','always') in ('auto','dodge')
 options={'output':p.get('dock_monitor',DEFAULTS['dock_monitor']),'exclusive':not adaptive,'layer':'overlay' if adaptive else 'top','mode':'default','passthrough':False,'on-sigusr1':'hide','on-sigusr2':'show'}
 changed=any(c.get(k)!=v for k,v in options.items());c.update(options);atomic_write(config,json.dumps(c,ensure_ascii=False,indent=2)+'\n')
 run_quiet(['hyprctl','reload','config-only']);send_ui('reload-settings')
 if changed:
  run_quiet(['pkill','-x','waybar'])
  try:subprocess.Popen([str(BASE/'start-dock')],start_new_session=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  except OSError:pass
SHELL_SETTINGS=Path.home()/'.local/state/draconyx/settings.json'
def shell_settings_read(path=None):
 """(Daten, ok): ok=False, wenn die Datei zwar existiert, aber nicht als JSON-Objekt lesbar ist (dann nie überschreiben)."""
 path=Path(path) if path else SHELL_SETTINGS
 try:text=path.read_text(encoding='utf-8')
 except FileNotFoundError:return {},True
 except (OSError,ValueError):return {},False
 if not text.strip():return {},True
 try:data=json.loads(text)
 except ValueError:return {},False
 return (data,True) if isinstance(data,dict) else ({},False)
def shell_settings_update(changes,path=None):
 """Nur die geänderten Schlüssel in settings.json der Shell setzen: frisch lesen, ändern, atomar ersetzen (kein Lost-Update mit
 veralteten Werten; die Shell schreibt die Datei selbst). Eine unlesbare Datei bleibt unberührt (Sicherung *.defekt), es wird
 ein Fehler gemeldet statt alle Einstellungen zu verlieren. Gibt True zurück, wenn geschrieben wurde."""
 path=Path(path) if path else SHELL_SETTINGS
 data,ok=shell_settings_read(path)
 if not ok:
  try:shutil.copy2(path,str(path)+'.defekt')
  except OSError:pass
  raise ValueError('settings.json der Shell ist nicht lesbar – nichts geändert (Kopie: settings.json.defekt)')
 data.update(changes)
 atomic_write(path,json.dumps(data,indent=4))
 return True
def _shell_we(assign):
 """Mit der Hypr Hypr-Shell: Wallpaper Engine der Shell steuern (settings.json + Neustart über die Shell)."""
 shell_settings_update({'weWallpapers':assign})
 try:subprocess.Popen(['qs','-c','draconyx','ipc','call','shell','weReapply'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 except OSError:pass
def stop_engine():
 if SHELL:_shell_we({});return
 return
def _monitor_names():
 try:
  r=subprocess.run(['hyprctl','-j','monitors'],capture_output=True,text=True,timeout=10)
  return [m['name'] for m in json.loads(r.stdout or '[]') if isinstance(m,dict) and 'name' in m]
 except (OSError,ValueError,subprocess.SubprocessError):return []
def apply_background(p,engine=False,preview=False):
 if engine and SHELL:
  folder=Path(str(p.get('engine_path') or '')).expanduser()
  if not str(p.get('engine_path') or '').strip() or not (folder/'project.json').is_file():raise ValueError('Bitte einen Wallpaper-Engine-Hintergrund auswählen.')
  if preview:raise ValueError('Vorschau gibt es mit der Shell nicht – direkt anwenden.')
  atomic_write(BASE/'preferences.json',json.dumps(p,ensure_ascii=False,indent=2))
  monitors=[p['engine_monitor']] if p.get('engine_monitor') else _monitor_names()
  if not monitors:raise ValueError('Keine Bildschirme gefunden – läuft Hyprland?')
  _shell_we({m:folder.name for m in monitors});p['engine_active']=True;return
 if engine:raise ValueError('Animierte Hintergründe laufen über die Hypr Hypr-Shell (Wallpaper Engine) – bitte die Shell starten.')
 else:
  raw=str(p.get('wallpaper') or '')
  path=Path(raw).expanduser()
  if not raw.strip() or not path.is_file():raise ValueError('Bitte ein vorhandenes Hintergrundbild auswählen.')
  if '\n' in str(path) or '\r' in str(path):raise ValueError('Dieser Dateiname wird nicht unterstützt.')
  monitor=str(p.get('wallpaper_monitor') or '')
  if not re.fullmatch(r'[A-Za-z0-9_.:\-]*',monitor):raise ValueError('Ungültiger Bildschirmname: '+monitor)
  fit=p.get('wallpaper_fit') or 'cover'
  if fit not in ('cover','contain','tile','fill'):raise ValueError('Ungültige Anpassung: '+str(fit))
  stop_engine();p['engine_active']=False
  wallpapers=p.setdefault('wallpapers',{});wallpapers[monitor]={'path':str(path),'fit':fit}
  text='ipc = on\nsplash = false\n'
  for mon,wall in wallpapers.items():
   if not isinstance(wall,dict) or '\n' in str(wall.get('path','')) or not re.fullmatch(r'[A-Za-z0-9_.:\-]*',str(mon)):continue
   text+='wallpaper {\n    monitor = '+mon+'\n    path = '+str(wall.get('path',''))+'\n    fit_mode = '+str(wall.get('fit','cover'))+'\n}\n'
  atomic_write(BASE/'hyprpaper.conf',text)
  run_quiet(['pkill','-x','hyprpaper'],5)
  logdir=Path.home()/'.cache/aurora'
  try:
   logdir.mkdir(parents=True,exist_ok=True)
   with open(logdir/'hyprpaper.log','a') as log:subprocess.Popen(['hyprpaper','-c',str(BASE/'hyprpaper.conf')],start_new_session=True,stdout=log,stderr=log)
  except OSError as e:raise ValueError('hyprpaper konnte nicht gestartet werden: '+str(e))
 atomic_write(BASE/'preferences.json',json.dumps(p,ensure_ascii=False,indent=2))

# ---------------------------------------------------------------- Zurücksetzen, Export, Import
RESET_GROUPS={   # Seite -> Schlüssel in preferences.json, die „Auf Standard“ zurücksetzt
 'Fenster':('titlebar_height','titlebar_font','rounding','border_size','blur','blur_size','blur_passes','tile_gap'),
 'Übersicht':('scroll_speed','focus_follows_mouse'),
 'Bewegung & Licht':('motion',)}
def reset_keys(p,keys):
 """Setzt die genannten Schlüssel auf den Standard (Schlüssel ohne Standard werden entfernt)."""
 for k in keys:
  if k in DEFAULTS:p[k]=DEFAULTS[k]
  elif k=='shortcuts':p[k]={}
  else:p.pop(k,None)
EXPORT_FORMAT='aurora-settings-1'
SHELL_EXPORT_SKIP=('weWallpapers',)
def export_settings(path):
 """Alle Einstellungen in eine JSON-Datei: preferences.json, settings.json der Shell, binds.conf, Haupttaste, Farben."""
 shell,_=shell_settings_read()
 colors=None
 try:colors=json.loads((Path.home()/'.config/draconyx/colors.json').read_text())
 except (OSError,ValueError):pass
 data={'format':EXPORT_FORMAT,'preferences':load_preferences(),'shell':{k:v for k,v in shell.items() if k not in SHELL_EXPORT_SKIP},
  'binds':read_binds_conf(),'modifier':modifier_mode(),'colors':colors if isinstance(colors,dict) else None}
 atomic_write(path,json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def import_settings(path):
 """Liest eine Exportdatei. Prüft alles vor dem ersten Schreiben; schreibt nur die enthaltenen Teile (Shell-Einstellungen werden
 schlüsselweise eingemischt, nicht ersetzt). Gibt eine Liste der übernommenen Teile zurück."""
 try:data=json.loads(Path(path).read_text(encoding='utf-8'))
 except (OSError,ValueError) as e:raise ValueError('Datei nicht lesbar: '+str(e))
 if not isinstance(data,dict) or data.get('format')!=EXPORT_FORMAT:raise ValueError('Keine Aurora-Einstellungsdatei (Format „%s“ erwartet).'%EXPORT_FORMAT)
 prefs=data.get('preferences');shell=data.get('shell');binds=data.get('binds');mod=data.get('modifier');colors=data.get('colors')
 if prefs is not None and not isinstance(prefs,dict):raise ValueError('„preferences“ ist kein Objekt.')
 if shell is not None and not isinstance(shell,dict):raise ValueError('„shell“ ist kein Objekt.')
 if binds is not None:
  if not isinstance(binds,dict):raise ValueError('„binds“ ist kein Objekt.')
  for k,v in binds.items():
   if not re.fullmatch(r'[A-Za-z0-9_.\-]+',str(k)):raise ValueError('Ungültige Aktion in binds: '+repr(k))
   binds[k]=normalize_combo(v)
 if mod is not None and mod not in MODIFIERS:raise ValueError('Ungültige Haupttaste: '+repr(mod))
 if colors is not None and not isinstance(colors,dict):raise ValueError('„colors“ ist kein Objekt.')
 if prefs is not None:
  prefs=sanitize_preferences(prefs);
  for key,combo in (prefs.get('shortcuts') or {}).items():prefs['shortcuts'][key]=normalize_combo(combo)
 done=[]
 if shell:
  shell_settings_update({k:v for k,v in shell.items() if k not in SHELL_EXPORT_SKIP});done.append('Shell')
 if binds is not None:write_binds_conf(binds);done.append('Tastenkombinationen')
 if mod is not None:set_modifier_mode(mod);done.append('Haupttaste')
 if colors:atomic_write(Path.home()/'.config/draconyx/colors.json',json.dumps(colors,indent=2)+'\n');done.append('Farben')
 if prefs is not None:save_preferences(prefs);done.append('Aurora')
 return done
