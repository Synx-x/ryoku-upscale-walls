pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.PluginKit.Singletons

// An orb beside the clock. Filled means the upscaled copy is showing, hollow
// means the original. While an upscale runs it pulses, an orbiting spark turns
// and a ring fills with the progress. Hover opens the card, click flips.
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
    readonly property bool working: root.state === "working"
    readonly property bool showingOriginal: root.service && root.service.pair ? root.service.pair.kind === "original" : false
    readonly property bool failed: root.state === "error" && !root.working
    readonly property real progress: service ? service.progress : 0
    readonly property color tint: root.failed ? Theme.vermBurn : Theme.accent
    readonly property real orb: 18 * root.s

    visible: root.shown
    implicitWidth: root.shown ? row.implicitWidth : 0
    implicitHeight: root.shown ? Math.max(row.implicitHeight, root.orb + 2) : 0

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6 * root.s

        Item {
            id: orbBox
            width: root.orb
            height: root.orb
            anchors.verticalCenter: parent.verticalCenter

            // Soft halo that breathes while working and rests when idle.
            Rectangle {
                id: halo
                anchors.centerIn: parent
                width: parent.width
                height: width
                radius: width / 2
                color: root.tint
                opacity: root.working ? 0.28 : 0.12
                SequentialAnimation on scale {
                    running: root.working
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.25; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.85; duration: 900; easing.type: Easing.InOutSine }
                }
            }

            // Progress ring, drawn only while working.
            Canvas {
                id: ring
                anchors.fill: parent
                visible: root.working
                antialiasing: true
                property real value: root.progress
                onValueChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const c = width / 2;
                    const r = c - 1.2 * root.s;
                    ctx.lineWidth = Math.max(1.5, 1.6 * root.s);
                    ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.28);
                    ctx.beginPath();
                    ctx.arc(c, c, r, 0, Math.PI * 2);
                    ctx.stroke();
                    ctx.strokeStyle = root.tint;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.03, ring.value));
                    ctx.stroke();
                }
            }

            // The core: filled for the upscaled copy, a hollow ring for the original.
            Rectangle {
                id: core
                anchors.centerIn: parent
                width: parent.width * 0.5
                height: width
                radius: width / 2
                color: root.showingOriginal && !root.working ? "transparent" : root.tint
                border.width: root.showingOriginal && !root.working ? Math.max(1.5, 1.6 * root.s) : 0
                border.color: root.tint
                Behavior on color { ColorAnimation { duration: 220 } }
                SequentialAnimation on opacity {
                    running: root.working
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.55; duration: 700 }
                    NumberAnimation { to: 1.0; duration: 700 }
                }
            }

            // A small spark orbiting the core while working.
            Item {
                anchors.fill: parent
                visible: root.working
                RotationAnimator on rotation {
                    running: root.working
                    from: 0
                    to: 360
                    duration: 1400
                    loops: Animation.Infinite
                }
                Rectangle {
                    width: Math.max(2.5, 3 * root.s)
                    height: width
                    radius: width / 2
                    color: Theme.bright
                    x: parent.width / 2 - width / 2
                    y: 0
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text.length > 0
            text: root.working ? Math.round(root.progress * 100) + "%"
                : root.failed ? "failed" : ""
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            elide: Text.ElideRight
            width: root.widthBudget > 0 ? Math.min(implicitWidth, root.widthBudget) : implicitWidth
        }
    }

    HoverHandler {
        onHoveredChanged: if (root.service) root.service.hoverChanged("widget", hovered)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: root.service && root.service.canFlip ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.service && root.service.canFlip) root.service.flip()
    }
}
