pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Polls the worker every few seconds. The worker reads Ryoku's current
// wallpaper, upscales a small one into the cache, and applies the result.
// While it runs, a second light process reads its progress file each second.
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
    property real startedAt: 0
    property int target: 0
    property real nowMs: Date.now()

    // Hover and pin, so the details panel opens when the pointer rests on the glyph.
    property bool widgetHovered: false
    property bool panelHovered: false
    property bool panelHoverEstablished: false
    property bool pinned: false

    readonly property bool working: svc.state === "working"

    // The glyph shows only on demand: while working, then for a while after a
    // result so it is still there when you look up.
    property bool recent: false
    readonly property bool showGlyph: svc.working
        || (svc.recent && (svc.state === "done" || svc.state === "ready" || svc.state === "error" || svc.state === "reverted"))
    readonly property int lingerSeconds: Math.max(10, Math.min(3600, (svc.settings && svc.settings.lingerSeconds) ? svc.settings.lingerSeconds : 180))

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
        svc.target = result.target || svc.target;
        if (svc.state === "working") {
            svc.progress = result.progress || 0;
            svc.startedAt = result.started || svc.startedAt;
            svc.recent = false;
            linger.stop();
        } else if (svc.state === "done" || svc.state === "ready" || svc.state === "error" || svc.state === "reverted") {
            svc.progress = svc.state === "done" || svc.state === "ready" ? 1 : svc.progress;
            svc.recent = true;
            linger.restart();
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
        const isActive = svc.widgetHovered || svc.panelHovered || svc.pinned;
        if (isActive) {
            closeTimer.stop();
            if (svc.pluginApi && !svc.pluginApi.panelOpen)
                svc.pluginApi.openPanel();
        } else if (svc.panelHoverEstablished) {
            closeTimer.restart();
        } else {
            // The host panel is a full-screen layer. Opening it can drop glyph
            // hover before the pointer reaches the card, so hold it open
            // through that handoff.
            closeTimer.stop();
        }
    }

    function togglePinned() {
        svc.pinned = !svc.pinned;
        if (svc.pinned) {
            closeTimer.stop();
            if (svc.pluginApi && !svc.pluginApi.panelOpen)
                svc.pluginApi.openPanel();
        } else if (!svc.widgetHovered && !svc.panelHovered) {
            closeTimer.restart();
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
            if (!svc.busy) return;
            try {
                const r = JSON.parse(progressOut.text);
                if (r.state === "working") svc.apply(r);
            } catch (e) {}
        }
    }

    Timer {
        interval: 1000
        running: svc.busy && svc.pluginApi
        repeat: true
        onTriggered: {
            svc.nowMs = Date.now();
            if (!progressProc.running) progressProc.running = true;
        }
    }

    Timer {
        id: linger
        interval: svc.lingerSeconds * 1000
        onTriggered: svc.recent = false
    }

    Timer {
        id: closeTimer
        interval: 350
        onTriggered: {
            if (!svc.pinned && !svc.widgetHovered && !svc.panelHovered && svc.pluginApi && svc.pluginApi.panelOpen)
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
