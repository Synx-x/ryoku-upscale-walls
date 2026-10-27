import QtQuick
import Ryoku.PluginKit.Singletons

// Panel: what the last pick did, plus two explicit actions. Nothing here runs
// until a click; settings live under QS Bar Settings > Community.
Item {
    id: root

    property var pluginApi
    property string density: "full"
    property real s: 1
    property real widthBudget: 340
    property bool active: false

    readonly property var service: pluginApi ? pluginApi.mainInstance : null
    readonly property string state: service ? service.state : "idle"
    readonly property bool enabled: pluginApi ? (pluginApi.pluginSettings.enabled ?? true) : true
    readonly property bool hasResult: state === "done" || state === "reverted"

    implicitWidth: root.widthBudget
    implicitHeight: col.implicitHeight + 24 * root.s

    function fileName(p) {
        const i = p.lastIndexOf("/");
        return i >= 0 ? p.slice(i + 1) : p;
    }

    Column {
        id: col
        x: 12 * root.s
        y: 12 * root.s
        width: root.width - 24 * root.s
        spacing: 10 * root.s

        Text {
            text: "Upscale Walls"
            color: Theme.bright
            font.family: Theme.display
            font.pixelSize: 16 * root.s
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.state === "error" ? Theme.vermBurn : Theme.dim
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            text: {
                if (!root.service) return "Starting";
                if (!root.enabled) return "Off. Turn it on in QS Bar Settings > Community.";
                switch (root.state) {
                case "working": return "Upscaling the new wallpaper";
                case "done":
                    return root.fileName(root.service.src) + "\n" + root.service.fromSize + " to " + root.service.toSize
                         + " with " + root.service.engine + (root.service.cached ? " (cached)" : ", " + root.service.seconds + " s");
                case "reverted": return "Showing the original " + root.fileName(root.service.src);
                case "skipped": return root.service.message;
                case "error": return root.service.message;
                default: return "Waiting for the next wallpaper pick";
                }
            }
        }

        Row {
            spacing: 8 * root.s

            Rectangle {
                visible: root.state === "done"
                width: showLabel.implicitWidth + 24 * root.s
                height: showLabel.implicitHeight + 12 * root.s
                radius: Theme.radius
                color: showArea.pressed ? Theme.vermDeep : Theme.accent
                Text {
                    id: showLabel
                    anchors.centerIn: parent
                    text: "SHOW ORIGINAL"
                    color: Theme.cardBot
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                }
                MouseArea {
                    id: showArea
                    anchors.fill: parent
                    onClicked: if (root.service) root.service.revert()
                }
            }

            Rectangle {
                visible: root.state === "reverted" || root.state === "error"
                width: redoLabel.implicitWidth + 24 * root.s
                height: redoLabel.implicitHeight + 12 * root.s
                radius: Theme.radius
                color: redoArea.pressed ? Theme.vermDeep : Theme.accent
                Text {
                    id: redoLabel
                    anchors.centerIn: parent
                    text: "UPSCALE AGAIN"
                    color: Theme.cardBot
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                }
                MouseArea {
                    id: redoArea
                    anchors.fill: parent
                    onClicked: if (root.service) root.service.redo()
                }
            }
        }
    }
}
