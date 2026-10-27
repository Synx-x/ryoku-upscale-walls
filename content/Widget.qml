pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.PluginKit.Singletons

// Glyph beside the clock. Hidden when idle. While an upscale runs it shows the
// percentage with a thin progress strip underneath. Hover opens the details
// panel, click pins it.
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
    readonly property bool shown: root.enabled && (root.service ? root.service.showGlyph : false)
    readonly property real progress: service ? service.progress : 0

    visible: root.shown
    implicitWidth: root.shown ? row.implicitWidth : 0
    implicitHeight: root.shown ? Math.max(row.implicitHeight, 18 * root.s) : 0

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
            color: root.state === "error" ? Theme.vermBurn
                 : (root.state === "working" || root.state === "done" || root.state === "ready" || root.open) ? Theme.accent
                 : Theme.dim
            SequentialAnimation on opacity {
                running: root.service ? root.service.working : false
                loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: 700 }
                NumberAnimation { to: 1.0; duration: 700 }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.state === "working" ? Math.round(root.progress * 100) + "%"
                : root.state === "done" ? (root.service ? root.service.toSize : "")
                : root.state === "ready" ? "ready, not applied"
                : root.state === "error" ? "failed"
                : root.state === "reverted" ? "original" : ""
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            elide: Text.ElideRight
            width: root.widthBudget > 0 ? Math.min(implicitWidth, root.widthBudget) : implicitWidth
        }
    }

    // Progress strip along the bottom edge while working.
    Rectangle {
        visible: root.state === "working"
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: Math.max(2, 2 * root.s)
        radius: height / 2
        width: parent.width
        color: Theme.border
        Rectangle {
            height: parent.height
            radius: parent.radius
            width: parent.width * Math.max(0.02, Math.min(1, root.progress))
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }

    HoverHandler {
        onHoveredChanged: if (root.service) root.service.hoverChanged("widget", hovered)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.service) root.service.togglePinned()
    }
}
