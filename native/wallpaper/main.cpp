#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <QScreen>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDir>
#include <QSGRendererInterface>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include <LayerShellQt/Window>
int main(int argc,char**argv){
 QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);QtWebEngineQuick::initialize();QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
 QGuiApplication app(argc,argv);app.setApplicationName("aurora-wallpaper");
 if(argc<3)return 2;QString folder=QString::fromLocal8Bit(argv[1]),monitor=QString::fromLocal8Bit(argv[2]);bool preview=app.arguments().contains("--preview");
 QFile project(folder+"/project.json");if(!project.open(QIODevice::ReadOnly))return 3;auto meta=QJsonDocument::fromJson(project.readAll()).object();
 QFile pref(QDir::homePath()+"/.config/hypr/aurora/preferences.json");pref.open(QIODevice::ReadOnly);auto settings=QJsonDocument::fromJson(pref.readAll()).object();
 QQuickView view;view.setTitle("Wallpaper Engine Vorschau");view.setResizeMode(QQuickView::SizeRootObjectToView);
 auto context=view.rootContext();context->setContextProperty("engineSource",QUrl::fromLocalFile(folder+"/"+meta["file"].toString()));context->setContextProperty("engineType",meta["type"].toString());
 context->setContextProperty("engineAssets",QUrl::fromLocalFile(settings["engine_assets"].toString()));context->setContextProperty("engineFps",settings["engine_fps"].toInt(30));context->setContextProperty("engineVolume",settings["engine_volume"].toInt(0));
 context->setContextProperty("engineProperties",QString::fromUtf8(QJsonDocument(settings["engine_properties"].toObject()).toJson(QJsonDocument::Compact)));
 if(!preview){
  view.setFlags(Qt::FramelessWindowHint|Qt::WindowDoesNotAcceptFocus|Qt::WindowTransparentForInput);
  auto layer=LayerShellQt::Window::get(&view);layer->setScope("aurora-wallpaper");layer->setLayer(LayerShellQt::Window::LayerBackground);layer->setAnchors(LayerShellQt::Window::Anchors::fromInt(15));layer->setExclusiveZone(-1);layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
  for(auto screen:app.screens())if(screen->name()==monitor){view.setScreen(screen);layer->setScreen(screen);break;}
 }else view.resize(960,540);
 view.setSource(QUrl::fromLocalFile(QCoreApplication::applicationDirPath()+"/Wallpaper.qml"));if(view.status()==QQuickView::Error)return 4;view.show();return app.exec();
}
