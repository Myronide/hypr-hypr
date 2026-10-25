#define _GNU_SOURCE
#include <wayland-client.h>
#include <cairo/cairo.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include "export-client.h"
static struct hyprland_toplevel_export_manager_v1* manager;
static struct wl_shm* shm;
static struct wl_buffer* buffer;
static void* pixels;
static uint32_t width,height,stride,format,flags;
static int done=0,failed=0;
static void global(void*d,struct wl_registry*r,uint32_t id,const char*n,uint32_t v){
 if(!strcmp(n,hyprland_toplevel_export_manager_v1_interface.name))manager=wl_registry_bind(r,id,&hyprland_toplevel_export_manager_v1_interface,1);
 if(!strcmp(n,wl_shm_interface.name))shm=wl_registry_bind(r,id,&wl_shm_interface,1);
}
static void gone(void*d,struct wl_registry*r,uint32_t id){}
static const struct wl_registry_listener registry_listener={global,gone};
static void frame_buffer(void*d,struct hyprland_toplevel_export_frame_v1*f,uint32_t fmt,uint32_t w,uint32_t h,uint32_t s){format=fmt;width=w;height=h;stride=s;}
static void frame_damage(void*d,struct hyprland_toplevel_export_frame_v1*f,uint32_t x,uint32_t y,uint32_t w,uint32_t h){}
static void frame_flags(void*d,struct hyprland_toplevel_export_frame_v1*f,uint32_t value){flags=value;}
static void frame_ready(void*d,struct hyprland_toplevel_export_frame_v1*f,uint32_t hi,uint32_t lo,uint32_t ns){done=1;}
static void frame_failed(void*d,struct hyprland_toplevel_export_frame_v1*f){failed=1;done=1;}
static void frame_dma(void*d,struct hyprland_toplevel_export_frame_v1*f,uint32_t fmt,uint32_t w,uint32_t h){}
static void frame_buffers_done(void*d,struct hyprland_toplevel_export_frame_v1*f){
 if(!width||!height||stride<width*4||height>16384||width>16384){failed=done=1;return;}
 int fd=memfd_create("aurora-preview",MFD_CLOEXEC);if(fd<0||ftruncate(fd,(size_t)stride*height)){failed=done=1;return;}
 pixels=mmap(NULL,(size_t)stride*height,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);if(pixels==MAP_FAILED){close(fd);failed=done=1;return;}
 struct wl_shm_pool*pool=wl_shm_create_pool(shm,fd,stride*height);buffer=wl_shm_pool_create_buffer(pool,0,width,height,stride,format);wl_shm_pool_destroy(pool);close(fd);
 hyprland_toplevel_export_frame_v1_copy(f,buffer,1);
}
static const struct hyprland_toplevel_export_frame_v1_listener frames={.buffer=frame_buffer,.damage=frame_damage,.flags=frame_flags,.ready=frame_ready,.failed=frame_failed,.linux_dmabuf=frame_dma,.buffer_done=frame_buffers_done};
int main(int argc,char**argv){
 if(argc!=3)return 2;alarm(3);struct wl_display*d=wl_display_connect(NULL);if(!d)return 3;
 struct wl_registry*r=wl_display_get_registry(d);wl_registry_add_listener(r,&registry_listener,NULL);wl_display_roundtrip(d);if(!shm||!manager)return 4;
 struct hyprland_toplevel_export_frame_v1*f=hyprland_toplevel_export_manager_v1_capture_toplevel(manager,0,(uint32_t)strtoull(argv[1],NULL,0));hyprland_toplevel_export_frame_v1_add_listener(f,&frames,NULL);
 while(!done&&wl_display_dispatch(d)>=0){}if(failed||!pixels)return 5;
 int swap=format==WL_SHM_FORMAT_ABGR8888||format==WL_SHM_FORMAT_XBGR8888;
 int opaque=format==WL_SHM_FORMAT_XRGB8888||format==WL_SHM_FORMAT_XBGR8888;
 for(uint32_t y=0;y<height;y++)for(uint32_t x=0;x<width;x++) {uint32_t*p=(uint32_t*)((char*)pixels+y*stride)+x;uint32_t c=*p;if(swap)c=(c&0xff00ff00)|((c&0xff)<<16)|((c>>16)&0xff);if(opaque)c|=0xff000000;*p=c;}
 cairo_surface_t*source=cairo_image_surface_create_for_data(pixels,CAIRO_FORMAT_ARGB32,width,height,stride);
 int thumbw=320,thumbh=(int)((double)height*thumbw/width);if(thumbh<1)thumbh=1;
 cairo_surface_t*out=cairo_image_surface_create(CAIRO_FORMAT_RGB24,thumbw,thumbh);cairo_t*cr=cairo_create(out);cairo_set_source_rgb(cr,.08,.1,.16);cairo_paint(cr);
 cairo_scale(cr,(double)thumbw/width,(double)thumbh/height);
 if(flags&HYPRLAND_TOPLEVEL_EXPORT_FRAME_V1_FLAGS_Y_INVERT){cairo_translate(cr,0,height);cairo_scale(cr,1,-1);}
 cairo_set_source_surface(cr,source,0,0);cairo_pattern_set_filter(cairo_get_source(cr),CAIRO_FILTER_BILINEAR);cairo_paint(cr);
 int result=cairo_surface_write_to_png(out,argv[2]);cairo_destroy(cr);cairo_surface_destroy(out);cairo_surface_destroy(source);munmap(pixels,(size_t)stride*height);
 hyprland_toplevel_export_frame_v1_destroy(f);wl_display_disconnect(d);return result?6:0;
}
