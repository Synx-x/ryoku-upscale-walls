#!/usr/bin/env python3
"""Upscale Walls worker.

tick    Read the current wallpaper from Ryoku's stage state. If it is a small
        raster image, upscale it into the plugin cache and apply the result.
flip    Switch between the original and its cached upscaled copy.
status  Print the last result as JSON.

Every command prints one JSON object on stdout. Writes go only to the plugin
state dir and cache dir (rule R8). The wallpaper is applied through
`ryogami wallpaper set`. The source file is never modified.
"""
import fcntl
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import threading
import time

ID = "upscale-walls"
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp"}
HOME = os.path.expanduser("~")
STATE_HOME = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
CACHE_HOME = os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache")
WALL_STATE = os.path.join(STATE_HOME, "ryoku", "stage-walls.json")
STATE_DIR = os.path.join(STATE_HOME, "ryoku", "plugins", ID)
CACHE_DIR = os.path.join(CACHE_HOME, "ryoku", "plugins", ID)
STATUS_FILE = os.path.join(STATE_DIR, "status.json")
HANDLED_FILE = os.path.join(STATE_DIR, "handled.json")
LOCK_FILE = os.path.join(STATE_DIR, "lock")
INDEX_FILE = os.path.join(STATE_DIR, "index.json")
THUMB_DIR = os.path.join(CACHE_DIR, "thumbs")
ENGINE_TIMEOUT = 600


def out(obj):
    """Print one JSON result. Every result carries `pair`, the original and upscaled copy of the current wallpaper."""
    if "pair" not in obj:
        try:
            obj["pair"] = pair()
        except Exception:  # noqa: BLE001
            obj["pair"] = {"flip": False}
    print(json.dumps(obj))
    return 0


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def settings_from(argv):
    raw = argv[0] if argv else "{}"
    try:
        s = json.loads(raw)
    except ValueError:
        s = {}
    return {
        "enabled": bool(s.get("enabled", True)),
        "mode": s.get("mode", "auto") if s.get("mode") in ("auto", "waifu2x", "realesrgan") else "auto",
        "targetWidth": int(s.get("targetWidth", 3840) or 3840),
        "gpu": str(s.get("gpu", "") or "").strip(),
        "cacheMB": int(s.get("cacheMB", 2000) or 2000),
    }


def find_engine(name, extra_dirs):
    path = shutil.which(name)
    if path:
        return path
    for d in extra_dirs:
        cand = os.path.join(d, name)
        if os.access(cand, os.X_OK):
            return cand
    return None


def realesrgan_models():
    for d in (os.path.join(HOME, ".local", "share", "realesrgan-ncnn-vulkan", "models"),
              "/usr/share/realesrgan-ncnn-vulkan/models"):
        if os.path.isfile(os.path.join(d, "realesrgan-x4plus.param")):
            return d
    return None


def waifu2x_models():
    for d in ("/usr/share/waifu2x-ncnn-vulkan/models-cunet",):
        if os.path.isdir(d):
            return d
    return None


def image_size(path):
    r = subprocess.run(["magick", "identify", "-ping", "-format", "%w %h", path + "[0]"],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        return None
    try:
        w, h = r.stdout.split()[:2]
        return int(w), int(h)
    except ValueError:
        return None


def under(path, root):
    return os.path.realpath(path).startswith(os.path.realpath(root) + os.sep)


def prune_cache(limit_mb):
    try:
        files = [os.path.join(CACHE_DIR, f) for f in os.listdir(CACHE_DIR) if f.endswith(".png")]
    except OSError:
        return
    files.sort(key=os.path.getmtime)
    total = sum(os.path.getsize(f) for f in files)
    while files and total > limit_mb * 1024 * 1024 and len(files) > 1:
        victim = files.pop(0)
        total -= os.path.getsize(victim)
        try:
            os.remove(victim)
        except OSError:
            pass


def choose_engine(mode):
    """Return (name, binary, model_dir). Falls back to waifu2x when Real-ESRGAN is absent."""
    re_bin = find_engine("realesrgan-ncnn-vulkan", [os.path.join(HOME, ".local", "bin")])
    re_models = realesrgan_models()
    w2_bin = find_engine("waifu2x-ncnn-vulkan", [])
    w2_models = waifu2x_models()
    have_re = bool(re_bin and re_models)
    have_w2 = bool(w2_bin and w2_models)
    if mode == "realesrgan" and have_re:
        return "realesrgan", re_bin, re_models
    if mode == "waifu2x" and have_w2:
        return "waifu2x", w2_bin, w2_models
    if mode == "auto" and have_re:
        return "realesrgan", re_bin, re_models
    if have_w2:
        return "waifu2x", w2_bin, w2_models
    if have_re:
        return "realesrgan", re_bin, re_models
    return None, None, None


def thumb(path):
    """A 360 px preview for the hover card, cached by path and mtime."""
    if not path or not os.path.isfile(path):
        return ""
    try:
        key = hashlib.sha1(("%s|%d" % (path, os.stat(path).st_mtime_ns)).encode()).hexdigest()[:16]
    except OSError:
        return ""
    dst = os.path.join(THUMB_DIR, key + ".jpg")
    if not os.path.isfile(dst):
        os.makedirs(THUMB_DIR, exist_ok=True)
        r = subprocess.run(["magick", path + "[0]", "-auto-orient", "-thumbnail", "360x", "-quality", "80", dst],
                           capture_output=True, timeout=60)
        if r.returncode != 0:
            return ""
    return dst


def load_index():
    idx = read_json(INDEX_FILE, {})
    idx.setdefault("by_src", {})
    idx.setdefault("by_out", {})
    return idx


def remember_pair(src, dst, engine, from_size, to_size):
    os.makedirs(STATE_DIR, exist_ok=True)
    idx = load_index()
    idx["by_src"][src] = {"out": dst, "engine": engine, "from": from_size, "to": to_size}
    idx["by_out"][dst] = src
    write_json(INDEX_FILE, idx)


def pair():
    """The original and upscaled copy of the current wallpaper, when both exist."""
    path = read_json(WALL_STATE, {}).get("current", "") or ""
    idx = load_index()
    kind, src, dst = "other", "", ""
    if path in idx["by_out"] and os.path.isfile(path):
        kind, src, dst = "upscaled", idx["by_out"][path], path
    elif path in idx["by_src"] and os.path.isfile(idx["by_src"][path]["out"]):
        kind, src, dst = "original", path, idx["by_src"][path]["out"]
    if kind == "other" or not os.path.isfile(src):
        return {"flip": False, "kind": "other"}
    entry = idx["by_src"].get(src, {})
    return {"flip": True, "kind": kind, "src": src, "out": dst, "srcName": os.path.basename(src),
            "from": entry.get("from", ""), "to": entry.get("to", ""), "engine": entry.get("engine", ""),
            "srcThumb": thumb(src), "outThumb": thumb(dst)}


def run_engine(name, binary, models, src, dst, scale, gpu, on_progress=None):
    """Run one engine. Both print a percentage line per tile on stderr, which feeds on_progress."""
    if name == "realesrgan":
        cmd = [binary, "-i", src, "-o", dst, "-n", "realesrgan-x4plus", "-s", "4", "-m", models]
    else:
        cmd = [binary, "-i", src, "-o", dst, "-n", "1", "-s", str(scale), "-m", models]
    if gpu:
        cmd += ["-g", gpu]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    tail = []

    def reader():
        for line in proc.stderr:
            line = line.strip()
            if line.endswith("%"):
                try:
                    if on_progress:
                        on_progress(min(1.0, max(0.0, float(line[:-1]) / 100)))
                except ValueError:
                    pass
            elif line:
                tail.append(line)

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    try:
        proc.wait(timeout=ENGINE_TIMEOUT)
    except subprocess.TimeoutExpired:
        proc.kill()
        raise
    t.join(2)
    return proc.returncode == 0 and os.path.isfile(dst) and os.path.getsize(dst) > 0, " ".join(tail)[-200:]


def record(status):
    status["at"] = int(time.time())
    write_json(STATUS_FILE, status)
    return out(status)


def write_status(status):
    status["at"] = int(time.time())
    write_json(STATUS_FILE, status)


def notify(summary, body=""):
    """One replaceable desktop notification, so the progress updates in place."""
    id_file = os.path.join(STATE_DIR, "notify.id")
    cmd = ["notify-send", "-a", "Upscale Walls", "-p", "-t", "6000"]
    try:
        with open(id_file) as f:
            prev = f.read().strip()
        if prev.isdigit():
            cmd += ["-r", prev]
    except OSError:
        pass
    try:
        r = subprocess.run(cmd + [summary, body], capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip().isdigit():
            with open(id_file, "w") as f:
                f.write(r.stdout.strip())
    except (OSError, subprocess.TimeoutExpired):
        pass


def apply_wallpaper(path):
    r = subprocess.run(["ryogami", "wallpaper", "set", path], capture_output=True, text=True, timeout=60)
    return r.returncode == 0, (r.stderr or r.stdout).strip()[-200:]


def wall_stamp():
    try:
        return os.stat(WALL_STATE).st_mtime_ns
    except OSError:
        return 0


def mark_handled(path):
    """Remember the pick we acted on. The stamp makes a later re-pick of the same file count as new."""
    write_json(HANDLED_FILE, {"path": path, "stamp": wall_stamp()})


def wait_for_current(path, seconds=3.0):
    end = time.time() + seconds
    while time.time() < end:
        if read_json(WALL_STATE, {}).get("current") == path:
            return True
        time.sleep(0.1)
    return False


def tick(settings):
    os.makedirs(STATE_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
    current = read_json(WALL_STATE, {}).get("current", "")
    if not current or not os.path.isfile(current):
        return out({"state": "idle", "message": "no wallpaper"})
    handled = read_json(HANDLED_FILE, {})
    if handled.get("path") == current and handled.get("stamp") == wall_stamp():
        return out({"state": "idle"})
    mark_handled(current)

    if under(current, CACHE_DIR):
        return out({"state": "idle", "message": "showing upscaled copy"})
    if not settings["enabled"]:
        return out({"state": "idle", "message": "disabled"})
    if os.path.splitext(current)[1].lower() not in IMAGE_EXT:
        return record({"state": "skipped", "src": current, "message": "not a still image"})

    size = image_size(current)
    if not size:
        return record({"state": "error", "src": current, "message": "could not read image size"})
    width = size[0]
    target = settings["targetWidth"]
    if width >= target:
        return record({"state": "skipped", "src": current, "width": width,
                       "message": "already %d px wide (target %d)" % (width, target)})

    name, binary, models = choose_engine(settings["mode"])
    if not name:
        return record({"state": "error", "src": current,
                       "message": "no upscaler found (install waifu2x-ncnn-vulkan)"})

    scale = 2 if target / width <= 2 else 4
    st = os.stat(current)
    key = hashlib.sha1(("%s|%d|%d|%s|%d|%d" % (current, st.st_mtime_ns, st.st_size, name, scale, target)).encode()).hexdigest()[:20]
    dst = os.path.join(CACHE_DIR, "%s-%s.png" % (os.path.splitext(os.path.basename(current))[0], key))
    cached = os.path.isfile(dst)
    began = time.time()

    if not cached:
        lock = open(LOCK_FILE, "w")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return out({"state": "busy"})
        started = time.time()
        base = {"state": "working", "src": current, "engine": name, "started": started,
                "from": "%dx%d" % size, "target": target, "progress": 0.0, "thumb": thumb(current)}
        write_status(dict(base))
        notify("Upscaling wallpaper", "%s (%d px wide)" % (os.path.basename(current), width))
        beat = {"cur": dict(base), "stop": False}

        def heartbeat():
            """Refresh the status once a second, so a slow last tile never reads as stale."""
            while not beat["stop"]:
                time.sleep(1.0)
                if not beat["stop"]:
                    write_status(dict(beat["cur"]))

        threading.Thread(target=heartbeat, daemon=True).start()

        def on_progress(p):
            if p - beat["cur"]["progress"] >= 0.01 or p >= 0.999:
                beat["cur"]["progress"] = round(p, 3)
                write_status(dict(beat["cur"]))

        ok, err = run_engine(name, binary, models, current, dst + ".part.png", scale, settings["gpu"], on_progress)
        if not ok:
            try:
                os.remove(dst + ".part.png")
            except OSError:
                pass
            beat["stop"] = True
            notify("Upscale failed", os.path.basename(current))
            return record({"state": "error", "src": current, "engine": name, "message": err or "engine failed"})
        beat["cur"].update(progress=1.0, phase="finishing")
        write_status(dict(beat["cur"]))
        os.replace(dst + ".part.png", dst)
        up = image_size(dst)
        if up and up[0] > target * 1.05:
            subprocess.run(["magick", dst, "-filter", "Lanczos", "-resize", "%dx" % target, dst],
                           capture_output=True, timeout=120)
        prune_cache(settings["cacheMB"])
        beat["stop"] = True

    final = image_size(dst) or (0, 0)
    remember_pair(current, dst, name, "%dx%d" % size, "%dx%d" % final)
    if read_json(WALL_STATE, {}).get("current") != current:
        notify("Upscale ready, not applied", "%s finished after you picked another wallpaper" % os.path.basename(current))
        return record({"state": "ready", "src": current, "out": dst, "engine": name, "cached": cached,
                       "from": "%dx%d" % size, "to": "%dx%d" % final,
                       "seconds": round(time.time() - began, 1),
                       "message": "finished after you picked another wallpaper"})
    ok, err = apply_wallpaper(dst)
    if not ok:
        return record({"state": "error", "src": current, "out": dst, "message": err or "ryogami set failed"})
    notify("Wallpaper upscaled", "%s  %dx%d to %dx%d" % (os.path.basename(current), size[0], size[1], final[0], final[1]))
    return record({"state": "done", "src": current, "out": dst, "engine": name, "cached": cached,
                   "from": "%dx%d" % size, "to": "%dx%d" % final,
                   "seconds": round(time.time() - began, 1)})


def flip():
    """Switch between the original and its cached upscaled copy. Instant, no engine run."""
    info = pair()
    if not info.get("flip"):
        return out({"state": "error", "message": "no upscaled copy of this wallpaper"})
    target = info["out"] if info["kind"] == "original" else info["src"]
    os.makedirs(STATE_DIR, exist_ok=True)
    ok, err = apply_wallpaper(target)
    if not ok:
        return record({"state": "error", "src": info["src"], "message": err or "ryogami set failed"})
    wait_for_current(target)
    mark_handled(target)
    showing = "upscaled" if info["kind"] == "original" else "original"
    return record({"state": "flipped", "src": info["src"], "out": info["out"], "engine": info["engine"],
                   "from": info["from"], "to": info["to"], "message": "showing the " + showing})


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    rest = sys.argv[2:]
    if cmd == "tick":
        return tick(settings_from(rest))
    if cmd == "flip":
        return flip()
    if cmd == "redo":
        try:
            os.remove(HANDLED_FILE)
        except OSError:
            pass
        return tick(settings_from(rest))
    if cmd == "status":
        return out(read_json(STATUS_FILE, {"state": "idle"}))
    return out({"state": "error", "message": "unknown command: %s" % cmd})


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.TimeoutExpired:
        sys.exit(out({"state": "error", "message": "timed out"}))
    except Exception as e:  # noqa: BLE001
        sys.exit(out({"state": "error", "message": "%s: %s" % (type(e).__name__, e)}))
