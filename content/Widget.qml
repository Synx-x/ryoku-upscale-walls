pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.PluginKit.Singletons

// Glyph on the bar. Dim when idle, accent while a wallpaper is being upscaled
// or after a successful upscale, red tint on error. Click opens the panel.
Item {
    id: root

    property var pluginApi
    property var screen
    property bool active: false
    property string density: "glyph"
    property real s: 1
    property real widthBudget: 0
    property bool open: false
    property real reveal: 0
    property bool tabActive: false
    signal requestClose()

    readonly property var service: pluginApi ? pluginApi.mainInstance : null
    readonly property string state: service ? service.state : "idle"
    readonly property bool enabled: pluginApi ? (pluginApi.pluginSettings.enabled ?? true) : true

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(row.implicitHeight, 18 * root.s)

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6 * root.s

        Text {
            id: mark
            anchors.verticalCenter: parent.verticalCenter
            text: "⬆"
            font.family: Theme.mono
            font.pixelSize: 13 * root.s
            color: !root.enabled ? Theme.border2
                 : root.state === "error" ? Theme.vermBurn
                 : (root.state === "working" || root.state === "done" || root.open) ? Theme.accent
                 : Theme.dim
            SequentialAnimation on opacity {
                running: root.service ? root.service.working : false
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 600 }
                NumberAnimation { to: 1.0; duration: 600 }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.state === "working" || root.state === "done"
            text: root.state === "working" ? "upscaling" : (root.service ? root.service.toSize : "")
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            elide: Text.ElideRight
            width: root.widthBudget > 0 ? Math.min(implicitWidth, root.widthBudget) : implicitWidth
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (!root.pluginApi)
                return;
            if (root.open)
                root.requestClose();
            else if (root.pluginApi.togglePanel)
                root.pluginApi.togglePanel();
        }
    }
}
