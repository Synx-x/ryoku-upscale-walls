pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Polls the worker every few seconds. While one upscale runs, a second light
// process reads its progress file each second.
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
    property real progress: 0
    property string phase: ""
    property real startedAt: 0
    property int target: 0
    property string thumb: ""
    property var pair: ({ flip: false, kind: "other" })
    property real nowMs: Date.now()
    property bool errorRecent: false
    property real loadedAt: Date.now() / 1000
    property real lastAt: 0
    property int pairMisses: 0

    // Hover opens the details card. Click flips original and upscaled.
    property bool widgetHovered: false
    property bool panelHovered: false
    property bool panelHoverEstablished: false

    readonly property bool working: svc.state === "working"
    readonly property bool canFlip: !!(svc.pair && svc.pair.flip)

    // The orb shows while an upscale runs, and while the current wallpaper has
    // an original and an upscaled copy to flip between.
    readonly property bool showGlyph: svc.working || svc.canFlip || (svc.state === "error" && svc.errorRecent)

    readonly property real elapsed: svc.working && svc.startedAt > 0 ? Math.max(0, svc.nowMs / 1000 - svc.startedAt) : svc.seconds
    readonly property real eta: svc.working && svc.progress > 0.05 ? svc.elapsed * (1 - svc.progress) / svc.progress : -1

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
    function flip() { svc.run("flip"); }
    function redo() { svc.run("redo"); }

    // Ryogami rewrites its state file on a wallpaper change, so one poll can
    // read it half written. Hide the orb only after three polls agree.
    function setPair(p) {
        const next = p || ({ flip: false, kind: "other" });
        if (!next.flip && svc.canFlip) {
            svc.pairMisses += 1;
            if (svc.pairMisses < 3) return;
        }
        svc.pairMisses = 0;
        svc.pair = next;
    }

    // Take the shared status. A working status counts only while it is fresh,
    // and a finished one only if it happened after this copy loaded.
    function syncShared(r) {
        const now = Date.now() / 1000;
        svc.setPair(r.pair);
        if (r.state === "working") {
            if (r.at && now - r.at < 15) svc.apply(r);
            else if (svc.state === "working") svc.state = "idle";
        } else if (r.at && r.at >= svc.loadedAt && r.at !== svc.lastAt) {
            svc.lastAt = r.at;
            svc.apply(r);
        } else if (svc.state === "working") {
            svc.state = "idle";
        }
    }

    function apply(result) {
        if (result.state === "busy") return;
        svc.setPair(result.pair);
        // A tick with nothing to do returns a bare idle result. Ignore it: the
        // other copy of this service may be running the job, and syncShared
        // owns every move into or out of the working state.
        if (result.state === "idle" && !result.src) return;
        svc.state = result.state || "idle";
        svc.message = result.message || "";
        svc.engine = result.engine || "";
        svc.src = result.src || "";
        svc.out = result.out || "";
        svc.fromSize = result.from || "";
        svc.toSize = result.to || "";
        svc.seconds = result.seconds || 0;
        svc.cached = !!result.cached;
        svc.target = result.target || svc.target;
        svc.thumb = result.thumb || (svc.state === "working" ? svc.thumb : "");
        if (svc.state === "working") {
            svc.progress = result.progress || 0;
            svc.phase = result.phase || "";
            svc.startedAt = result.started || svc.startedAt;
            svc.errorRecent = false;
            errorTimer.stop();
        } else if (svc.state === "error") {
            svc.errorRecent = true;
            errorTimer.restart();
        } else if (svc.state === "done" || svc.state === "ready") {
            svc.progress = 1;
        }
    }

    function hoverChanged(source, hovered) {
        if (source === "widget") {
            svc.widgetHovered = hovered;
            if (hovered && svc.pluginApi && !svc.pluginApi.panelOpen)
                svc.panelHoverEstablished = false;
        } else {
            svc.panelHovered = hovered;
            if (hovered)
                svc.panelHoverEstablished = true;
        }
        if (svc.widgetHovered || svc.panelHovered) {
            closeTimer.stop();
            if (svc.pluginApi && !svc.pluginApi.panelOpen)
                svc.pluginApi.openPanel();
        } else if (svc.panelHoverEstablished) {
            closeTimer.restart();
        } else {
            // Opening the host panel can drop glyph hover before the pointer
            // reaches the card, so hold it open through that handoff.
            closeTimer.stop();
        }
    }

    function fmt(seconds) {
        if (seconds < 0) return "";
        const s = Math.round(seconds);
        return s < 60 ? s + " s" : Math.floor(s / 60) + " min " + (s % 60) + " s";
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

    Process {
        id: progressProc
        command: ["python3", svc.pluginApi ? svc.pluginApi.pluginDir + "/bin/upscale_walls.py" : "", "status"]
        stdout: StdioCollector { id: progressOut }
        onExited: function(code) {
            try {
                svc.syncShared(JSON.parse(progressOut.text));
            } catch (e) {}
        }
    }

    // Every monitor's bar loads its own copy of this service, and only one copy
    // starts a given upscale. Each copy therefore reads the shared status file.
    Timer {
        interval: 1200
        running: !!svc.pluginApi
        repeat: true
        onTriggered: {
            svc.nowMs = Date.now();
            if (!progressProc.running) progressProc.running = true;
        }
    }

    Timer {
        id: errorTimer
        interval: 30000
        onTriggered: svc.errorRecent = false
    }

    Timer {
        id: closeTimer
        interval: 350
        onTriggered: {
            if (!svc.widgetHovered && !svc.panelHovered && svc.pluginApi && svc.pluginApi.panelOpen)
                svc.pluginApi.closePanel();
        }
    }

    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: svc.tick()
    }
}
