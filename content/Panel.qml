import QtQuick
import Ryoku.PluginKit.Singletons

// Details card. Opens when the pointer rests on the orb. While an upscale runs
// it previews the source image. Afterwards it shows the original and upscaled
// copies side by side, and clicking the other one flips to it.
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
    readonly property bool working: root.state === "working"
    readonly property var pair: service && service.pair ? service.pair : ({ flip: false, kind: "other" })
    readonly property bool canFlip: !!root.pair.flip

    function fileName(p) {
        const i = p.lastIndexOf("/");
        return i >= 0 ? p.slice(i + 1) : p;
    }

    function fileUrl(p) {
        return p ? "file://" + p : "";
    }

    readonly property var rows: {
        const v = root.service;
        if (!v) return [];
        const list = [];
        if (root.working) {
            if (v.src) list.push(["File", root.fileName(v.src)]);
            list.push(["Engine", v.engine === "realesrgan" ? "Real-ESRGAN x4plus" : v.engine === "realcugan" ? "Real-CUGAN" : "waifu2x cunet"]);
            list.push(["Source", v.fromSize + (v.target ? " to about " + v.target + " px wide" : "")]);
            list.push(["Elapsed", v.fmt(v.elapsed)]);
            if (v.eta >= 0) list.push(["Remaining", "about " + v.fmt(v.eta)]);
        } else if (root.canFlip) {
            list.push(["File", root.pair.srcName]);
            list.push(["Engine", root.pair.engine === "realesrgan" ? "Real-ESRGAN x4plus" : root.pair.engine === "realcugan" ? "Real-CUGAN" : "waifu2x cunet"]);
            list.push(["Size", root.pair.from + " to " + root.pair.to]);
        }
        return list;
    }

    readonly property string headline: {
        if (!root.service) return "Starting";
        if (!root.enabled) return "Off";
        if (root.working) return "Upscaling " + Math.round(root.service.progress * 100) + "%";
        if (root.canFlip) return root.pair.kind === "upscaled" ? "Showing the upscaled copy" : "Showing the original";
        if (root.state === "error") return "Failed";
        if (root.state === "ready") return "Ready, not applied";
        return "Waiting for the next wallpaper pick";
    }

    readonly property string note: {
        if (!root.service) return "";
        if (!root.enabled) return "Turn it on in QS Bar Settings > Community.";
        if (root.working) return "It applies when ready, unless you pick another wallpaper first.";
        if (root.state === "error") return root.service.message;
        if (root.state === "ready") return root.fileName(root.service.src) + " finished after you picked another wallpaper.";
        if (root.canFlip) return "Click the other copy, or the button, to flip.";
        return "";
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
            color: root.state === "error" && !root.working ? Theme.vermBurn : Theme.bright
            font.family: Theme.display
            font.pixelSize: 16 * root.s
        }

        // Source preview with a progress bar across its bottom edge, while working.
        Rectangle {
            visible: root.working
            width: parent.width
            height: width * 9 / 16
            radius: Theme.radius
            color: Theme.tileBg
            clip: true
            Image {
                anchors.fill: parent
                source: root.fileUrl(root.service ? root.service.thumb : "")
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 360
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(4, 5 * root.s)
                color: Qt.rgba(0, 0, 0, 0.45)
                Rectangle {
                    height: parent.height
                    width: parent.width * Math.max(0.02, Math.min(1, root.service ? root.service.progress : 0))
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                }
            }
        }

        // Original and upscaled copies side by side. The showing one is outlined.
        Row {
            visible: !root.working && root.canFlip
            spacing: 8 * root.s

            Repeater {
                model: [
                    { label: "Original", size: root.pair.from, path: root.pair.srcThumb, active: root.pair.kind === "original" },
                    { label: "Upscaled", size: root.pair.to, path: root.pair.outThumb, active: root.pair.kind === "upscaled" }
                ]
                delegate: Item {
                    id: card
                    required property var modelData
                    width: (col.width - 8 * root.s) / 2
                    height: width * 9 / 16 + 20 * root.s

                    Rectangle {
                        width: parent.width
                        height: width * 9 / 16
                        radius: Theme.radius
                        color: Theme.tileBg
                        clip: true
                        border.width: card.modelData.active ? Math.max(2, 2 * root.s) : 1
                        border.color: card.modelData.active ? Theme.accent : Theme.border
                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            source: root.fileUrl(card.modelData.path)
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 360
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !card.modelData.active
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.service) root.service.flip()
                        }
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        text: card.modelData.label + "  " + card.modelData.size
                        color: card.modelData.active ? Theme.bright : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                    }
                }
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
            color: root.state === "error" && !root.working ? Theme.vermBurn : Theme.dim
            font.family: Theme.font
            font.pixelSize: 12 * root.s
        }

        Row {
            spacing: 8 * root.s

            Rectangle {
                visible: !root.working && root.canFlip
                width: flipLabel.implicitWidth + 24 * root.s
                height: flipLabel.implicitHeight + 12 * root.s
                radius: Theme.radius
                color: flipArea.pressed ? Theme.vermDeep : Theme.accent
                Text {
                    id: flipLabel
                    anchors.centerIn: parent
                    text: root.pair.kind === "upscaled" ? "SHOW ORIGINAL" : "SHOW UPSCALED"
                    color: Theme.cardBot
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                }
                MouseArea {
                    id: flipArea
                    anchors.fill: parent
                    onClicked: if (root.service) root.service.flip()
                }
            }

            Rectangle {
                visible: !root.working && !root.canFlip && root.state === "error"
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
