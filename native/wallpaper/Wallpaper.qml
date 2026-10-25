import QtQuick
import QtWebEngine
import com.github.catsout.wallpaperEngineKde 1.2
Item {
    width: 960; height: 540
    Rectangle { anchors.fill: parent; color: "#101521" }
    Loader {
        anchors.fill: parent
        sourceComponent: engineType === "scene" ? scene : engineType === "video" ? video : engineType === "web" ? web : picture
    }
    Component {
        id: scene
        SceneViewer {
            source: engineSource; assets: engineAssets; fps: engineFps
            muted: engineVolume === 0; volume: engineVolume / 100.0
            cachePasses: true; shareGpu: false; mirrorScene: false; speed: 1.0
            userProperties: engineProperties; fillMode: SceneViewer.ASPECTCROP
            Component.onCompleted: { setAcceptMouse(false); setAcceptHover(false); play(); }
        }
    }
    Component {
        id: video
        Mpv {
            source: engineSource; volume: engineVolume; mute: engineVolume === 0; maxFps: engineFps
            Component.onCompleted: { setProperty("keepaspect",true); setProperty("panscan",1.0); play(); }
        }
    }
    Component {
        id: web
        WebEngineView {
            url: engineSource; audioMuted: engineVolume === 0; activeFocusOnPress: false
            onLoadingChanged: function(request) {
                if (request.status === WebEngineView.LoadSucceededStatus)
                    runJavaScript("if(window.wallpaperPropertyListener){if(window.wallpaperPropertyListener.applyGeneralProperties)window.wallpaperPropertyListener.applyGeneralProperties({fps:"+engineFps+"});if(window.wallpaperPropertyListener.applyUserProperties)window.wallpaperPropertyListener.applyUserProperties("+engineProperties+");}")
            }
        }
    }
    Component { id: picture; Image { source: engineSource; fillMode: Image.PreserveAspectCrop } }
}
