import QtQuick
import Ryoku.PluginKit.Singletons

// Details card. Opens when the pointer rests on the glyph. Actions run only on
// a click, and settings live under QS Bar Settings > Community.
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

    function fileName(p) {
        const i = p.lastIndexOf("/");
        return i >= 0 ? p.slice(i + 1) : p;
    }

    readonly property var rows: {
        const v = root.service;
        if (!v) return [];
        const list = [];
        if (v.src) list.push(["File", root.fileName(v.src)]);
        if (v.engine) list.push(["Engine", v.engine === "realesrgan" ? "Real-ESRGAN x4plus" : "waifu2x cunet"]);
        if (root.state === "working") {
            list.push(["Source", v.fromSize + (v.target ? " to about " + v.target + " px wide" : "")]);
            list.push(["Elapsed", v.fmt(v.elapsed)]);
            if (v.eta >= 0) list.push(["Remaining", "about " + v.fmt(v.eta)]);
        } else if (root.state === "done" || root.state === "ready") {
            list.push(["Size", v.fromSize + " to " + v.toSize]);
            list.push(["Took", v.cached ? "cached, instant" : v.fmt(v.seconds)]);
            if (v.out) list.push(["Saved as", root.fileName(v.out)]);
        }
        return list;
    }

    readonly property string headline: {
        const v = root.service;
        if (!v) return "Starting";
        if (!root.enabled) return "Off";
        switch (root.state) {
        case "working": return "Upscaling " + Math.round(v.progress * 100) + "%";
        case "done": return "Upscaled and applied";
        case "ready": return "Ready, not applied";
        case "reverted": return "Showing the original";
        case "skipped": return "Skipped";
        case "error": return "Failed";
        default: return "Waiting for the next wallpaper pick";
        }
    }

    readonly property string note: {
        const v = root.service;
        if (!v) return "";
        if (!root.enabled) return "Turn it on in QS Bar Settings > Community.";
        switch (root.state) {
        case "working": return "It applies when ready, unless you pick another wallpaper first.";
        case "ready": return "It finished after you picked another wallpaper. Pick that file again to use the upscaled copy.";
        case "skipped": case "error": return v.message;
        default: return "";
        }
    }

    implicitWidth: root.widthBudget
    implicitHeight: col.implicitHeight + 24 * root.s

    HoverHandler {
        onHoveredChanged: if (root.service) root.service.hoverChanged("panel", hovered)
    }

    Column {
        id: col
        x: 12 * root.s
        y: 12 * root.s
        width: root.width - 24 * root.s
        spacing: 10 * root.s

        Text {
            text: root.headline
            color: root.state === "error" ? Theme.vermBurn : Theme.bright
            font.family: Theme.display
            font.pixelSize: 16 * root.s
        }

        // Progress bar, only while working.
        Rectangle {
            visible: root.state === "working"
            width: parent.width
            height: Math.max(4, 5 * root.s)
            radius: height / 2
            color: Theme.border
            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0.02, Math.min(1, root.service ? root.service.progress : 0))
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }

        Repeater {
            model: root.rows
            delegate: Row {
                id: line
                required property var modelData
                width: col.width
                spacing: 8 * root.s
                Text {
                    width: 72 * root.s
                    text: line.modelData[0]
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                }
                Text {
                    width: line.width - 80 * root.s
                    text: line.modelData[1]
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    elide: Text.ElideMiddle
                }
            }
        }

        Text {
            visible: text.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.note
            color: root.state === "error" ? Theme.vermBurn : Theme.dim
            font.family: Theme.font
            font.pixelSize: 12 * root.s
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
