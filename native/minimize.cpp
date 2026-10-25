#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <algorithm>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/XWaylandManager.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
extern "C" {
#include <lua.h>
#include <lauxlib.h>
}
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <unordered_map>
#include <format>
#include <cstring>
static CFunctionHook* uvHook=nullptr;
static CFunctionHook* hitHook=nullptr;
using CalculateUV = void(*)(void*,PHLWINDOW,SP<CWLSurfaceResource>,PHLMONITOR,bool,const Vector2D&,const Vector2D&,bool);
static void calculateUV(void* renderer, PHLWINDOW window, SP<CWLSurfaceResource> surface, PHLMONITOR monitor, bool main, const Vector2D& projected, const Vector2D& unscaled, bool fractional) {
    reinterpret_cast<CalculateUV>(uvHook->m_original)(renderer,window,surface,monitor,main,projected,unscaled,fractional);
    if(!main || !window || window->m_isX11 || !window->m_xdgSurface || !surface)return;
    const auto geometry=window->m_xdgSurface->m_current.geometry;
    const auto size=surface->m_current.size;
    if(size.x<=0 || size.y<=0 || geometry.w<=0 || geometry.h<=0)return;
    if(geometry.x==0 && geometry.y==0 && geometry.size()==size)return;
    // xdg_surface geometry excludes a client's shadows. Map that complete content
    // rectangle into the texture, including fractional-scale viewport sources.
    if(geometry.x<0 || geometry.y<0 || geometry.x+geometry.w>size.x+1 || geometry.y+geometry.h>size.y+1)return;
    Vector2D start{0,0},end{1,1};
    if(surface->m_current.viewport.hasSource) {
        const auto& source=surface->m_current.viewport.source;
        const auto buffer=surface->m_current.bufferSize;
        if(buffer.x<=0 || buffer.y<=0)return;
        start=source.pos()/buffer;end=(source.pos()+source.size())/buffer;
    }
    const auto span=end-start;
    const auto pixels=surface->m_current.bufferSize;
    // Shadows can have a half-physical-pixel inset at fractional output scales.
    // Sampling that fractional origin blurs the entire window, even when its
    // content is already rendered at the exact output resolution.
    const auto topLeft=((start+(geometry.pos()/size)*span)*pixels).round();
    const auto bottomRight=topLeft+((geometry.size()/size)*span*pixels).round();
    g_pHyprRenderer->m_renderData.primarySurfaceUVTopLeft=topLeft/pixels;
    g_pHyprRenderer->m_renderData.primarySurfaceUVBottomRight=bottomRight/pixels;
}
using HitTest = SP<CWLSurfaceResource>(*)(const void*,const Vector2D&,PHLWINDOW,Vector2D&);
static SP<CWLSurfaceResource> windowSurfaceAt(const void* tester,const Vector2D& pos,PHLWINDOW window,Vector2D& local) {
    auto surface=reinterpret_cast<HitTest>(hitHook->m_original)(tester,pos,window,local);
    if(surface && window && !window->m_isX11 && window->m_xdgSurface && surface==window->wlSurface()->resource())
        local+=window->m_xdgSurface->m_current.geometry.pos();
    return surface;
}
static std::unordered_map<Desktop::View::CWindow*,CHyprSignalListener> listeners;
static CHyprSignalListener opened, destroyed, floated, fullscreenChanged, mouseButton;
// Hyprland 0.56.2 marks XDG surfaces maximized on map to suppress CSD but
// never updates that protocol flag when floating or changing maximize mode.
static void syncState(PHLWINDOW win) {
    if(!win || !win->m_isMapped || !win->m_isFloating) return;
    const auto modes=Fullscreen::controller()->getFullscreenModes(win);
    const bool maximized=modes.internal==Fullscreen::FSMODE_MAXIMIZED;
    win->m_suppressNextMaximize=false;
    // suppress_event is a static, per-window bit. Removing its config rule
    // does not clear it on windows which were already open.
    win->m_suppressedEvents &= ~Desktop::View::SUPPRESS_MAXIMIZE;
    if(win->m_xdgSurface && win->m_xdgSurface->m_toplevel) {
        win->m_xdgSurface->m_toplevel->setMaximized(maximized);
    } else if(win->m_xwaylandSurface) {
        auto x=win->m_xwaylandSurface;
        if(x->m_maximized!=maximized) {
            x->m_maximized=maximized;
            x->setFullscreen(x->m_fullscreen); // resend _NET_WM_STATE through XWM
        }
    }
}
static int repairFocus(lua_State* L) {
    auto w=Desktop::focusState()->window();
    if(!w || !w->m_isMapped || w->isHidden() || !w->wlSurface()->resource()){lua_pushboolean(L,false);return 1;}
    g_pXWaylandManager->activateWindow(w,true);
    g_pSeatManager->setKeyboardFocus(nullptr);
    g_pSeatManager->setKeyboardFocus(w->wlSurface()->resource());
    lua_pushboolean(L,true);return 1;
}
static int resync(lua_State* L) {
    int n=0;
    for(auto& w:Desktop::windowState()->windows()) if(w->m_isMapped && w->m_isFloating) {syncState(w);++n;}
    lua_pushinteger(L,n);return 1;
}
static int inspectState(lua_State* L) {
    lua_newtable(L);int index=1;
    for(auto& w:Desktop::windowState()->windows()) {
        if(!w->m_isMapped)continue;
        lua_newtable(L);
        lua_pushstring(L,w->m_class.c_str());lua_setfield(L,-2,"class");
        const auto modes=Fullscreen::controller()->getFullscreenModes(w);
        lua_pushinteger(L,modes.internal);lua_setfield(L,-2,"internal");
        lua_pushboolean(L,w->m_suppressedEvents & Desktop::View::SUPPRESS_MAXIMIZE);lua_setfield(L,-2,"maximize_blocked");
        bool maximized=false;
        if(w->m_xdgSurface && w->m_xdgSurface->m_toplevel) {
            auto& states=w->m_xdgSurface->m_toplevel->m_pendingApply.states;
            maximized=std::ranges::find(states,XDG_TOPLEVEL_STATE_MAXIMIZED)!=states.end();
        } else if(w->m_xwaylandSurface)maximized=w->m_xwaylandSurface->m_maximized;
        lua_pushboolean(L,maximized);lua_setfield(L,-2,"reported_maximized");
        if(w->m_xdgSurface && w->wlSurface()->resource()) {
            const auto g=w->m_xdgSurface->m_current.geometry;
            const auto& st=w->wlSurface()->resource()->m_current;
            const auto v=st.viewport.source;const auto d=st.viewport.destination;
            auto info=std::format("geometry=({},{},{},{}) surface=({},{}) buffer=({},{}) scale={} source={}({},{},{},{}) destination={}({},{})",g.x,g.y,g.w,g.h,st.size.x,st.size.y,st.bufferSize.x,st.bufferSize.y,st.scale,st.viewport.hasSource,v.x,v.y,v.w,v.h,st.viewport.hasDestination,d.x,d.y);
            lua_pushstring(L,info.c_str());lua_setfield(L,-2,"surface_info");
        }
        lua_rawseti(L,-2,index++);
    }
    return 1;
}
static void watch(PHLWINDOW w) {
    if (!w || listeners.contains(w.get())) return;
    PHLWINDOWREF weak=w;
    auto callback=[weak]() {
        auto win=weak.lock(); if(!win || !win->m_isMapped) return;
        bool requested=win->m_xdgSurface && win->m_xdgSurface->m_toplevel ? win->m_xdgSurface->m_toplevel->m_state.requestsMinimize.value_or(false) : win->m_xwaylandSurface ? win->m_xwaylandSurface->m_state.requestsMinimize.value_or(false) : false;
        syncState(win);
        // XWM retains request optionals after dispatch; don't let an unrelated
        // later state request reapply an old maximize or minimize request.
        if(win->m_xwaylandSurface) {
            win->m_xwaylandSurface->m_state.requestsMaximize.reset();
            win->m_xwaylandSurface->m_state.requestsMinimize.reset();
            win->m_xwaylandSurface->m_state.requestsFullscreen.reset();
        }
        if(!requested) return;
        const char* runtime=getenv("XDG_RUNTIME_DIR"); if(!runtime) return;
        std::string path=std::string(runtime)+"/aurora-ui.sock";
        sockaddr_un addr{};addr.sun_family=AF_UNIX;if(path.size()>=sizeof(addr.sun_path))return;
        std::memcpy(addr.sun_path,path.c_str(),path.size()+1);
        int fd=socket(AF_UNIX,SOCK_DGRAM|SOCK_NONBLOCK|SOCK_CLOEXEC,0);if(fd<0)return;
        auto message=std::format("[\"minimize\",\"0x{:x}\"]",reinterpret_cast<uintptr_t>(win.get()));
        sendto(fd,message.data(),message.size(),MSG_DONTWAIT,reinterpret_cast<sockaddr*>(&addr),sizeof(addr));close(fd);
    };
    if(w->m_xdgSurface && w->m_xdgSurface->m_toplevel)listeners.emplace(w.get(),w->m_xdgSurface->m_toplevel->m_events.stateChanged.listen(callback));
    else if(w->m_xwaylandSurface)listeners.emplace(w.get(),w->m_xwaylandSurface->m_events.stateChanged.listen(callback));
}
APICALL EXPORT std::string PLUGIN_API_VERSION(){return HYPRLAND_API_VERSION;}
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle){
    if(std::string(__hyprland_api_get_hash())!=std::string(__hyprland_api_get_client_hash()))throw std::runtime_error("Aurora native bridge: compositor version mismatch");
    for(const auto& match:HyprlandAPI::findFunctionsByName(handle,"calculateUVForSurface")) {
        if(match.demangled.find("IElementRenderer::calculateUVForSurface")!=std::string::npos) {
            uvHook=HyprlandAPI::createFunctionHook(handle,match.address,reinterpret_cast<void*>(&calculateUV));
            if(uvHook && !uvHook->hook())throw std::runtime_error("Aurora: could not attach XDG geometry correction");
            break;
        }
    }
    if(!uvHook)throw std::runtime_error("Aurora: missing renderer symbol for XDG geometry correction");
    for(const auto& match:HyprlandAPI::findFunctionsByName(handle,"windowSurfaceAt")) {
        if(match.demangled.find("CViewHitTester::windowSurfaceAt")!=std::string::npos) {
            hitHook=HyprlandAPI::createFunctionHook(handle,match.address,reinterpret_cast<void*>(&windowSurfaceAt));
            if(hitHook && !hitHook->hook())throw std::runtime_error("Aurora: could not attach XDG input correction");
            break;
        }
    }
    if(!hitHook)throw std::runtime_error("Aurora: missing XDG input geometry symbol");
    mouseButton=Event::bus()->m_events.input.mouse.button.listen([](const IPointer::SButtonEvent& event,const Event::SCallbackInfo&) {
        if(event.state!=WL_POINTER_BUTTON_STATE_PRESSED)return;
        const char* runtime=getenv("XDG_RUNTIME_DIR");if(!runtime)return;
        auto marker=std::string(runtime)+"/aurora-controls-open";if(access(marker.c_str(),F_OK))return;
        const auto pos=g_pInputManager->getMouseCoordsInternal();
        auto message=std::format("[\"pointer-button\",{},{}]",pos.x,pos.y);
        auto path=std::string(runtime)+"/aurora-ui.sock";sockaddr_un addr{};addr.sun_family=AF_UNIX;if(path.size()>=sizeof(addr.sun_path))return;std::memcpy(addr.sun_path,path.c_str(),path.size()+1);
        int fd=socket(AF_UNIX,SOCK_DGRAM|SOCK_NONBLOCK|SOCK_CLOEXEC,0);if(fd<0)return;sendto(fd,message.data(),message.size(),MSG_DONTWAIT,reinterpret_cast<sockaddr*>(&addr),sizeof(addr));close(fd);
    });
    opened=Event::bus()->m_events.window.openLate.listen([](PHLWINDOW w){watch(w);syncState(w);});
    floated=Event::bus()->m_events.window.floating.listen([](PHLWINDOW w){syncState(w);});
    fullscreenChanged=Event::bus()->m_events.window.fullscreen.listen([](PHLWINDOW w){syncState(w);});
    HyprlandAPI::addLuaFunction(handle,"aurora_native","resync",resync);
    HyprlandAPI::addLuaFunction(handle,"aurora_native","repair_focus",repairFocus);
    HyprlandAPI::addLuaFunction(handle,"aurora_native","state",inspectState);
    destroyed=Event::bus()->m_events.window.destroy.listen([](PHLWINDOWREF w){if(auto p=w.lock())listeners.erase(p.get());});
    for(auto& w:Desktop::windowState()->windows())if(w->m_isMapped){watch(w);syncState(w);}
    return {"aurora-native","Synchronizes native maximize state and routes minimize requests to the dock","Aurora","1.7"};
}
APICALL EXPORT void PLUGIN_EXIT(){if(hitHook){hitHook->unhook();hitHook=nullptr;}if(uvHook){uvHook->unhook();uvHook=nullptr;}listeners.clear();opened.reset();destroyed.reset();floated.reset();fullscreenChanged.reset();mouseButton.reset();}
