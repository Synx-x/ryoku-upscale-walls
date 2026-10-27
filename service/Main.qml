pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Polls the worker once every few seconds. The worker reads Ryoku's current
// wallpaper, upscales a small one into the cache, and applies the result.
Item {
    id: svc

    property var pluginApi
    readonly property var settings: pluginApi ? pluginApi.pluginSettings : null

    property bool busy: false
    property string state: "idle"
    property string message: ""
    property string engine: ""
    property string src: ""
    property string out: ""
    property string fromSize: ""
    property string toSize: ""
    property real seconds: 0
    property bool cached: false

    readonly property bool working: svc.busy && svc.state === "working"

    function settingsJson() {
        const s = svc.settings || {};
        return JSON.stringify({
            enabled: s.enabled ?? true,
            mode: s.mode ?? "auto",
            targetWidth: s.targetWidth ?? 3840,
            cacheMB: s.cacheMB ?? 2000,
            gpu: s.gpu ?? ""
        });
    }

    function run(action) {
        if (svc.busy || !svc.pluginApi) return;
        svc.busy = true;
        if (action !== "tick") svc.state = "working";
        worker.command = ["python3", svc.pluginApi.pluginDir + "/bin/upscale_walls.py", action, svc.settingsJson()];
        worker.running = true;
    }

    function tick() { svc.run("tick"); }
    function revert() { svc.run("revert"); }
    function redo() { svc.run("redo"); }

    function apply(result) {
        // A tick that has nothing to do returns a bare idle result. Keep the
        // last real result on screen instead of blanking it.
        if (result.state === "idle" && !result.src) {
            if (svc.state === "working") svc.state = "idle";
            return;
        }
        svc.state = result.state || "idle";
        svc.message = result.message || "";
        svc.engine = result.engine || "";
        svc.src = result.src || "";
        svc.out = result.out || "";
        svc.fromSize = result.from || "";
        svc.toSize = result.to || "";
        svc.seconds = result.seconds || 0;
        svc.cached = !!result.cached;
    }

    Process {
        id: worker
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: function(code) {
            svc.busy = false;
            try {
                svc.apply(JSON.parse(output.text));
            } catch (e) {
                svc.state = "error";
                svc.message = (errors.text || "worker failed").trim().slice(-120);
            }
        }
    }

    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: svc.tick()
    }
}
