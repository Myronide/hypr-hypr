import gi,subprocess,threading,re,os,json,time
from pathlib import Path
gi.require_version('Gtk','3.0');gi.require_version('GtkLayerShell','0.1')
from gi.repository import Gtk,Gdk,GLib,GtkLayerShell as Layer
BASE=Path.home()/'.config/hypr/aurora'
def run(args,timeout=4):
 try:return subprocess.run(args,capture_output=True,text=True,timeout=timeout,env=os.environ|{'LC_ALL':'C'}).stdout.strip()
 except (OSError,subprocess.TimeoutExpired):return ''
def text(value,name=None):
 w=Gtk.Label(label=value)
 if name:w.get_style_context().add_class(name)
 return w
def symbol(name,size=20):
 w=Gtk.Image.new_from_icon_name(name,Gtk.IconSize.BUTTON);w.set_pixel_size(size);return w
class ControlCenter:
 def controls(self,side='right'):
  if self.control_panel:self.close_controls();return
  self.close_popup();self.capture_return_focus()
  w=Gtk.Window(type=Gtk.WindowType.TOPLEVEL);self.prepare(w,'aurora-control-center',Layer.Layer.OVERLAY);self.control_panel=w
  try:hs=[m for m in json.loads(run(['hyprctl','-j','monitors']) or '[]') if isinstance(m,dict) and 'name' in m]
  except ValueError:hs=[]
  if not hs:   # kein Hyprland / keine Bildschirme: Fenster nicht halb aufbauen
   self.control_panel=None;w.destroy();print('Kontrollzentrum: keine Bildschirme gefunden',flush=True);return
  target=next((m for m in hs if m['name']==self.prefs.get('dock_monitor')),hs[0]);self.control_monitor=target;self.control_side=side
  try:(Path(os.environ['XDG_RUNTIME_DIR'])/'aurora-controls-open').touch()
  except (KeyError,OSError):pass
  Layer.set_monitor(w,self.monitor(target));Layer.set_exclusive_zone(w,-1)
  edge=Layer.Edge.LEFT if side=='left' else Layer.Edge.RIGHT
  Layer.set_anchor(w,Layer.Edge.BOTTOM,True);Layer.set_anchor(w,edge,True);Layer.set_margin(w,Layer.Edge.BOTTOM,90);Layer.set_margin(w,edge,24);Layer.set_keyboard_mode(w,Layer.KeyboardMode.ON_DEMAND)
  w.connect('key-press-event',lambda _,e:(self.close_controls(),True)[1] if e.keyval==Gdk.KEY_Escape else False)
  panel=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=12,margin=0);panel.get_style_context().add_class('quick-panel');w.add(panel);panel.set_size_request(390,-1)
  head=Gtk.Box(spacing=12);head.pack_start(text('Kontrollzentrum','popup-title'),True,True,0);close=Gtk.Button();close.add(symbol('window-close-symbolic',16));close.get_style_context().add_class('quick-icon-button');close.connect('clicked',lambda *_:self.close_controls());head.pack_end(close,False,False,0);panel.pack_start(head,False,False,0)
  grid=Gtk.Grid(column_spacing=8,row_spacing=8);self.control_tiles={}
  def tile(key,title,icon,callback,x,y):
   b=Gtk.Button();b.get_style_context().add_class('quick-tile');b.set_hexpand(True);v=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=6);v.pack_start(symbol(icon,22),False,False,0);v.pack_start(text(title),False,False,0);b.add(v);b.connect('clicked',lambda *_:callback());grid.attach(b,x,y,1,1);self.control_tiles[key]=b
  tile('wifi','WLAN','network-wireless-symbolic',self.toggle_wifi,0,0);tile('ethernet','Ethernet','network-wired-symbolic',self.toggle_ethernet,1,0);tile('bluetooth','Bluetooth','bluetooth-active-symbolic',self.toggle_bluetooth,2,0)
  tile('mic','Mikrofon','audio-input-microphone-symbolic',lambda:self.control_command(['wpctl','set-mute','@DEFAULT_AUDIO_SOURCE@','toggle']),0,1)
  tile('layout','Anordnung','view-grid-symbolic',lambda:self.toggle_layout_mode(),1,1);tile('desktop','Schreibtisch','user-desktop-symbolic',lambda:(self.close_controls(),self.show_desktop()),2,1);panel.pack_start(grid,False,False,0)
  net=Gtk.Button(label='WLAN-Netze auswählen  ›');net.get_style_context().add_class('quick-network');net.connect('clicked',lambda b:self.wifi_networks(b));panel.pack_start(net,False,False,0)
  self.control_updating=False;self.control_sliders={}
  for key,title,icon,maximum in [('volume','Lautstärke','audio-volume-high-symbolic',100),('mic','Mikrofon','audio-input-microphone-symbolic',100),('brightness','Helligkeit','display-brightness-symbolic',100)]:
   box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=3);top=Gtk.Box(spacing=8);top.pack_start(symbol(icon,16),False,False,0);title_label=text(title);title_label.set_xalign(0);top.pack_start(title_label,True,True,0);value=text('—','quick-value');top.pack_end(value,False,False,0);box.pack_start(top,False,False,0);scale=Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL,0,maximum,1);scale.set_draw_value(False);scale.connect('value-changed',self.control_slider,key);box.pack_start(scale,False,False,0);panel.pack_start(box,False,False,0);self.control_sliders[key]=(scale,value)
  self.control_sliders['brightness'][0].set_sensitive(False);self.ddc_buses=[];self.backlights=list(Path('/sys/class/backlight').iterdir()) if Path('/sys/class/backlight').is_dir() else [];threading.Thread(target=self.detect_brightness,daemon=True).start()
  media=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=9);media.get_style_context().add_class('media-card');self.media_title=text('Keine Medienwiedergabe');self.media_title.set_max_width_chars(38);self.media_title.set_ellipsize(3);self.media_title.set_xalign(0);media_head=Gtk.Box(spacing=10);media_head.pack_start(symbol('audio-x-generic-symbolic',24),False,False,0);media_head.pack_start(self.media_title,True,True,0);media.pack_start(media_head,False,False,0);buttons=Gtk.Box(spacing=14)
  for title,action in [('media-skip-backward-symbolic','previous'),('media-playback-start-symbolic','play-pause'),('media-skip-forward-symbolic','next')]:
   b=Gtk.Button();b.add(symbol(title,18));b.connect('clicked',lambda _,a=action:self.control_command(['playerctl',a]));buttons.pack_start(b,True,True,0)
  media.pack_start(buttons,False,False,0);panel.pack_start(media,False,False,0)
  footer=Gtk.Box(spacing=8);footer.get_style_context().add_class('quick-footer')
  for title,tip,action in [('󰅍','Zwischenablage',lambda:(self.close_controls(),self.clipboard())),('󰒓','Einstellungen',lambda:(self.close_controls(),subprocess.Popen([str(BASE/'settings-app')]))),('󰈀','Netzwerk-Einstellungen',lambda:(self.close_controls(),subprocess.Popen(['nm-connection-editor']))),('󰕾','Audio-Geräte',lambda:(self.close_controls(),subprocess.Popen(['kcmshell6','kcm_pulseaudio'])))]:
   b=Gtk.Button();b.add(symbol({'󰅍':'edit-paste-symbolic','󰒓':'preferences-system-symbolic','󰈀':'network-wired-symbolic','󰕾':'audio-volume-high-symbolic'}[title],18));b.set_tooltip_text(tip);b.connect('clicked',lambda _,fn=action:fn());footer.pack_start(b,True,True,0)
  power=Gtk.Button();power.add(symbol('system-shutdown-symbolic',18));power.set_tooltip_text('Sitzung und Energie');power.connect('clicked',lambda b:self.power_menu(b));footer.pack_start(power,True,True,0)
  panel.pack_start(footer,False,False,0);self.control_notice=text('','hint');self.control_notice.set_line_wrap(True);self.control_notice.set_max_width_chars(42);panel.pack_start(self.control_notice,False,False,0)
  w.show_all();self.refresh_controls();GLib.timeout_add(2000,self.refresh_controls)
 def close_controls(self):
  if self.control_panel:
   try:(Path(os.environ['XDG_RUNTIME_DIR'])/'aurora-controls-open').unlink(missing_ok=True)
   except (KeyError,OSError):pass
   w=self.control_panel;self.control_panel=None;w.destroy();self.restore_keyboard_focus()
 def control_command(self,args):
  def worker():run(args,25);GLib.idle_add(self.refresh_controls)
  threading.Thread(target=worker,daemon=True).start()
 def refresh_controls(self):
  if not self.control_panel:return False
  self.control_updating=True
  for key,device in [('volume','@DEFAULT_AUDIO_SINK@'),('mic','@DEFAULT_AUDIO_SOURCE@')]:
   state=run(['wpctl','get-volume',device]);m=re.search(r'Volume:\s*([0-9.]+)',state)
   if m:
    value=max(0,min(150,round(float(m.group(1))*100)));self.control_sliders[key][0].set_value(value);self.control_sliders[key][1].set_text(('Stumm' if 'MUTED' in state else str(value)+'%'))
  active={'wifi':run(['nmcli','radio','wifi'])=='enabled','bluetooth':'Powered: yes' in run(['bluetoothctl','show']),'ethernet':any(':ethernet:connected' in line for line in run(['nmcli','-t','-f','DEVICE,TYPE,STATE','device']).splitlines()),'mic':'MUTED' not in run(['wpctl','get-volume','@DEFAULT_AUDIO_SOURCE@']),'layout':self.layout_mode=='tiling'}
  for key,enabled in active.items():
   style=self.control_tiles[key].get_style_context();style.add_class('enabled') if enabled else style.remove_class('enabled')
  title=run(['playerctl','metadata','--format','{{artist}} — {{title}}']);self.media_title.set_text(title or 'Keine Medienwiedergabe');self.control_updating=False;return True
 def control_slider(self,scale,key):
  if self.control_updating:return
  value=round(scale.get_value());self.control_sliders[key][1].set_text(str(value)+'%')
  if key in ('volume','mic'):self.control_command(['wpctl','set-volume','@DEFAULT_AUDIO_SINK@' if key=='volume' else '@DEFAULT_AUDIO_SOURCE@',str(value)+'%'])
  else:
   if hasattr(self,'brightness_timeout'):
    try:GLib.source_remove(self.brightness_timeout)
    except Exception:pass
   def set_value():
    self.brightness_timeout=None
    def worker():
     if self.backlights:run(['brightnessctl','-c','backlight','set',str(max(1,value))+'%'])
     else:
      for bus in self.ddc_buses:run(['ddcutil','--bus',bus,'setvcp','10',str(max(1,value))],5)
    threading.Thread(target=worker,daemon=True).start();return False
   self.brightness_timeout=GLib.timeout_add(180,set_value)
 def detect_brightness(self):
  buses=[];value=50
  if self.backlights:
   current=run(['brightnessctl','-c','backlight','get']);maximum=run(['brightnessctl','-c','backlight','max'])
   if current.isdigit() and maximum.isdigit() and int(maximum):value=round(int(current)/int(maximum)*100)
  else:
   output=run(['ddcutil','detect','--brief'],8);buses=re.findall(r'I2C bus:\s*/dev/i2c-(\d+)',output)
   if buses:
    val=run(['ddcutil','--bus',buses[0],'getvcp','10','--brief'],5);m=re.search(r' C\s+(\d+)\s+(\d+)',val)
    if m and int(m.group(2)):value=round(int(m.group(1))/int(m.group(2))*100)
  def apply():
   self.ddc_buses=buses
   if self.control_panel:
    self.control_updating=True;scale,number=self.control_sliders['brightness'];scale.set_sensitive(bool(self.backlights or buses));scale.set_value(value);number.set_text(str(value)+'%' if self.backlights or buses else 'DDC/CI nicht verfügbar');self.control_updating=False
   return False
  GLib.idle_add(apply)
 def toggle_wifi(self):self.control_command(['nmcli','radio','wifi','off' if run(['nmcli','radio','wifi'])=='enabled' else 'on'])
 def toggle_bluetooth(self):self.control_command(['bluetoothctl','power','off' if 'Powered: yes' in run(['bluetoothctl','show']) else 'on'])
 def toggle_ethernet(self):
  for line in run(['nmcli','-t','-f','DEVICE,TYPE,STATE','device']).splitlines():
   parts=line.split(':')
   if len(parts)>=3 and parts[1]=='ethernet':self.control_command(['nmcli','device','disconnect' if parts[2]=='connected' else 'connect',parts[0]]);break
 def wifi_networks(self,anchor):
  panel=self.popover_box(anchor,Gtk.PositionType.TOP);panel.pack_start(text('WLAN-Netze','context-title'),False,False,0)
  lines=run(['nmcli','-t','--escape','no','-f','SSID,SIGNAL,SECURITY','device','wifi','list','--rescan','auto']);seen=set()
  for line in lines.splitlines():
   parts=line.rsplit(':',2)
   if len(parts)!=3 or not parts[0] or parts[0] in seen:continue
   ssid,signal,security=parts;seen.add(ssid);self.popover_row(panel,ssid+'  ·  '+signal+'%'+('  󰌾' if security else ''),lambda s=ssid,sec=security:self.connect_wifi(s,sec))
   if len(seen)>=14:break
  if not seen:panel.pack_start(text('Keine Netze gefunden'),False,False,8)
  self.show_popover()
 def connect_wifi(self,ssid,security):
  args=['nmcli','device','wifi','connect',ssid]
  if security:
   self.control_dialog=True;dialog=Gtk.Dialog(title=ssid,transient_for=self.control_panel,modal=True);dialog.add_button('Abbrechen',Gtk.ResponseType.CANCEL);dialog.add_button('Verbinden',Gtk.ResponseType.OK);entry=Gtk.Entry(visibility=False);entry.set_placeholder_text('WLAN-Passwort');entry.set_margin_top(15);entry.set_margin_bottom(15);entry.set_margin_start(15);entry.set_margin_end(15);dialog.get_content_area().add(entry);dialog.show_all();reply=dialog.run();password=entry.get_text();dialog.destroy();self.control_dialog=False
   if reply!=Gtk.ResponseType.OK:return
   args+=['password',password]
  self.control_command(args)

 def power_menu(self,anchor):
  panel=self.popover_box(anchor,Gtk.PositionType.TOP)
  self.popover_row(panel,'Standby',lambda:self.control_command(['systemctl','suspend']))
  self.popover_row(panel,'Neustarten',lambda:self.confirm_power('reboot','Neu starten?'))
  self.popover_row(panel,'Ausschalten',lambda:self.confirm_power('poweroff','Computer ausschalten?'))
  self.show_popover()
 def confirm_power(self,action,title):
  self.control_dialog=True;d=Gtk.MessageDialog(transient_for=self.control_panel,modal=True,message_type=Gtk.MessageType.QUESTION,buttons=Gtk.ButtonsType.OK_CANCEL,text=title);r=d.run();d.destroy();self.control_dialog=False
  if r==Gtk.ResponseType.OK:self.control_command(['systemctl',action])
