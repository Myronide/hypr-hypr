import json,subprocess,os,re,shutil,time
from pathlib import Path
BASE=Path.home()/'.config/hypr/aurora'
DEFAULTS={'dock_visibility':'always','dock_monitor':'DP-2','dock_icon_size':32,'dock_opacity':0.95,'desktop_icon_size':44,'desktop_font_size':11,'grid_snap':True,'grid_visible':False,'grid_width':122,'grid_height':112,'titlebar_height':28,'titlebar_font':10,'tile_gap':12,'rounding':12,'border_size':0,'blur':True,'blur_size':6,'blur_passes':3,'wallpaper':'','wallpaper_monitor':'','wallpaper_fit':'cover','workshop':'/mnt/Games/Steam/steamapps/workshop/content/431960','engine_assets':'/mnt/Games/Steam/steamapps/common/wallpaper_engine/assets','engine_fps':30,'engine_volume':0,'engine_path':'','engine_monitor':'DP-2','engine_mouse':True,'engine_parallax':True,'engine_fullscreen_pause':True,'engine_active':False}
def load_preferences():
 try:return DEFAULTS|json.loads((BASE/'preferences.json').read_text())
 except (OSError,ValueError):return DEFAULTS.copy()
def send_ui(*args):
 import socket
 try:
  with socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM) as s:s.sendto(json.dumps(args).encode(),str(Path(os.environ['XDG_RUNTIME_DIR'])/'aurora-ui.sock'))
 except OSError:pass
def save_preferences(p):
 (BASE/'preferences.json').write_text(json.dumps(p,ensure_ascii=False,indent=2))
 n=lambda key,lo,hi:max(lo,min(hi,int(p[key])))
 source='hl.config({general={border_size=%d,resize_on_border=true,extend_border_grab_area=8},decoration={rounding=%d,blur={enabled=%s,size=%d,passes=%d}}})\n'%(n('border_size',0,6),n('rounding',0,40),'true' if p['blur'] else 'false',n('blur_size',1,15),n('blur_passes',1,5))
 source+='if hl.plugin.hyprbars then hl.config({plugin={hyprbars={bar_height=%d,bar_text_size=%d}}}) end\n'%(n('titlebar_height',22,48),n('titlebar_font',8,16))
 source+='hl.config({input={follow_mouse=%d}})\n'%(1 if p.get('focus_follows_mouse',False) else 0)
 actions={'launcher':'launcher','clipboard':'desktop-ui clipboard','settings':'settings-app','desktop':'desktop-ui show-desktop','mode':'mode --toggle','minimize':'desktop-ui minimize'}
 for key,combo in p.get('shortcuts',{}).items():
  if key not in actions:continue
  if not re.fullmatch(r'[A-Za-z0-9 +_:\-]*',combo):raise ValueError('Ungültige Tastenkombination: '+combo)
  source+='if aurora_bindings and aurora_bindings.'+key+' then aurora_bindings.'+key+':remove() end\n'
  if combo.strip():source+='aurora_bindings.'+key+' = hl.bind('+json.dumps(combo)+',hl.dsp.exec_cmd('+json.dumps(str(BASE)+'/'+actions[key])+'))\n'
 (BASE/'preferences.lua').write_text(source)
 custom='.desktop-label {font-size: %dpx;} .app-dock {background: transparent;} window#waybar {background: rgba(38,42,48,%.2f);}\n'%(n('desktop_font_size',8,20),max(.2,min(1,float(p['dock_opacity']))))
 (BASE/'preferences.css').write_text(custom)
 config=Path.home()/'.config/waybar/config.jsonc';c=json.loads(config.read_text())
 adaptive=p.get('dock_visibility','always') in ('auto','dodge')
 options={'output':p['dock_monitor'],'exclusive':not adaptive,'layer':'overlay' if adaptive else 'top','mode':'default','passthrough':False,'on-sigusr1':'hide','on-sigusr2':'show'}
 changed=any(c.get(k)!=v for k,v in options.items());c.update(options);config.write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n')
 subprocess.run(['hyprctl','reload','config-only'],stdout=subprocess.DEVNULL);send_ui('reload-settings')
 if changed:
  subprocess.run(['pkill','-x','waybar']);subprocess.Popen([str(BASE/'start-dock')],start_new_session=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
def stop_engine():
 pidfile=Path(os.environ.get('XDG_RUNTIME_DIR','/tmp'))/'aurora-wallpaper-pids.json'
 if pidfile.exists():
  for pid in json.loads(pidfile.read_text()):
   try:
    command=Path('/proc')/str(pid)/'cmdline'
    if b'/aurora/native/wallpaper/aurora-wallpaper' in command.read_bytes():os.kill(pid,15)
   except OSError:pass
  pidfile.unlink(missing_ok=True)
def apply_background(p,engine=False,preview=False):
 if engine:
  folder=Path(p['engine_path']).expanduser()
  if not (folder/'project.json').is_file():raise ValueError('Bitte einen Wallpaper-Engine-Hintergrund auswählen.')
  exe=BASE/'native/wallpaper/aurora-wallpaper'
  if not exe.is_file():raise ValueError('Der Hintergrund-Renderer ist noch nicht verfügbar.')
  (BASE/'preferences.json').write_text(json.dumps(p,ensure_ascii=False,indent=2))
  if preview:
   subprocess.Popen([str(exe),str(folder),p['engine_monitor'] or 'DP-2','--preview'],start_new_session=True,stdout=subprocess.DEVNULL,stderr=open(Path.home()/'.cache/aurora/wallpaper-preview.log','a'));return
  stop_engine();monitors=[p['engine_monitor']] if p['engine_monitor'] else [m['name'] for m in json.loads(subprocess.check_output(['hyprctl','-j','monitors']))]
  processes=[]
  for monitor in monitors:
   log=open(Path.home()/'.cache/aurora/wallpaper.log','a')
   proc=subprocess.Popen([str(exe),str(folder),monitor],start_new_session=True,stdout=log,stderr=log);processes.append(proc.pid)
  (Path(os.environ['XDG_RUNTIME_DIR'])/'aurora-wallpaper-pids.json').write_text(json.dumps(processes));p['engine_active']=True
 else:
  path=Path(p['wallpaper']).expanduser()
  if not path.is_file():raise ValueError('Bitte ein vorhandenes Hintergrundbild auswählen.')
  if '\n' in str(path) or '\r' in str(path):raise ValueError('Dieser Dateiname wird nicht unterstützt.')
  stop_engine();p['engine_active']=False
  wallpapers=p.setdefault('wallpapers',{});wallpapers[p['wallpaper_monitor']]={'path':str(path),'fit':p['wallpaper_fit']}
  text='ipc = on\nsplash = false\n'
  for monitor,wall in wallpapers.items():text+='wallpaper {\n    monitor = '+monitor+'\n    path = '+wall['path']+'\n    fit_mode = '+wall['fit']+'\n}\n'
  (BASE/'hyprpaper.conf').write_text(text)
  subprocess.run(['pkill','-x','hyprpaper'],capture_output=True)
  log=open(Path.home()/'.cache/aurora/hyprpaper.log','a');subprocess.Popen(['hyprpaper','-c',str(BASE/'hyprpaper.conf')],start_new_session=True,stdout=log,stderr=log)
 (BASE/'preferences.json').write_text(json.dumps(p,ensure_ascii=False,indent=2))
