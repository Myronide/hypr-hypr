import QtQuick

// Fluent-Icon (Iconify) in Textfarbe oder Violett
Image {
    property string name
    property bool accent: false
    property int size: 20

    source: name !== "" ? Theme.icon(name, accent) : ""
    sourceSize: Qt.size(size * 2, size * 2)
    width: size
    height: size
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
}
