pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services

// Dynamic wallpapers: folders of images under
// $XDG_DATA_HOME/phi/wallpapers/dynamic/<name>/ that rotate by time of day,
// season and — once a weather source exists — weather. Read side only:
// Services/Background.qml composes what is actually painted, so the user's
// static pick is never overwritten.
//
// Naming convention
// -----------------
// One directory per dynamic wallpaper, each file named
// `<daytime>[-<optional>...].<ext>`:
//
//   daytime: dawn | day | dusk | night          (required, first token)
//   season:  spring | summer | autumn | winter  (optional)
//   weather: clear | cloudy | rain | snow | storm | fog  (optional)
//
// So day.png, night-winter.png, dusk-spring-rain.png, day-clear.png. Any
// further token ("-2", "-dark") is decorative and ignored, so a folder can
// hold alternatives for one condition; ties resolve alphabetically.
//
// An entry is eligible when its daytime equals the current slot and every
// optional it names matches. The most specific eligible entry wins
// (season+weather > season > weather > bare daytime). With nothing eligible,
// later slots are tried in day order (dawn → day → dusk → night), so a folder
// holding only day.png and night.png shows day through the dawn hour. An image
// naming a season or weather never matches a different value.
//
// An entry may instead be a bare .heic/.heif sitting directly in
// wallpapers/dynamic/ — it needs no folder, carrying its own whole-day
// schedule.
//
// Daytime slots
// -------------
// Two configurable boundaries split the day (wrap-aware hour math, as in
// Services/NightShift.qml; defaults fitted to Central Europe):
//
//   dawn:  [dawnHour, dawnHour + transitionLength)
//   day:   the hours in between
//   dusk:  [duskHour, duskHour + transitionLength)
//   night: [dusk + transitionLength, 24) + [0, dawnHour)
//
// transitionLength is a fixed 1 hour, not user-configurable. A single-shot
// timer is armed to the next boundary's exact minute, with a 1-minute safety
// timer catching suspend/resume and drift. Re-evaluation is deduplicated
// against the last (enabled, folder, daytime, season, weather, solar frame)
// tuple, so steady-state ticks are no-ops.
//
// HEIC/HEIF dynamic desktops
// --------------------------
// Apple Dynamic Desktop files carry an `apple_desktop:solar` (sun angle →
// frame) or `apple_desktop:h24` (clock start → frame) XMP map. Such a file in
// the active folder takes over the whole day, and conventional names beside it
// are ignored. Solar `z` values are day angles where 0..360 == 00:00..24:00:
// the nearest frame wins and the timer is armed to each map midpoint. h24 `t`
// values are frame start times: the frame whose start has just passed wins and
// the timer is armed to the next start. Season and weather do not apply —
// the file is its own schedule.
//
// Qt cannot decode HEIC, so the chosen frame is converted on demand with
// ImageMagick into a cached JPEG under Config.Paths.dynamicWallpaperCacheDir,
// keyed on source mtime plus frame index so a replaced source re-converts. A
// .heic with neither map is treated as an ordinary image.
//
// Season comes from the current month, Northern-hemisphere meteorological
// quarters; there is no location source for an astronomical season.
//
// While Services/PowerBridge.qml reports battery saver, the dynamic wallpaper
// is suppressed and the static image is painted. Read-side only — nothing is
// written back to the user's settings.
//
// The four settings (enabled, activeName, dawnHour, duskHour) live in one flat
// JSON file, rewritten whole on change, following the ClockPrefs/LockPrefs
// pattern. Not `phi state`: those keys would be rejected until the CLI
// declared them, and nothing outside quickshell uses this feature.
//
// TODO(weather): no weather source exists yet, so `_weather()` returns "" and
// weather-specified images are never eligible. When a Services/Weather.qml
// lands, making `_weather()` return one of `_weathers` is the only change
// needed — parsing, matching and crossfade already handle it.

Singleton {
    id: root

    // --- persisted settings --------------------------------------------
    property bool enabled: false
    // Name of the active folder under wallpapers/dynamic/; "" = no folder.
    property string activeName: ""
    // "folder" | "file" — the entry kind of activeName, resolved from the
    // entry list (or, before it is loaded, from the name's extension).
    property string _activeKind: "folder"
    // The two configurable daytime boundaries, whole hours 0-23.
    property int dawnHour: 7
    property int duskHour: 19

    // Fixed width of the dawn/dusk transition windows, in hours. Not
    // user-configurable; a comment-constant so the schedule stays simple.
    readonly property int transitionLength: 1

    // --- runtime state (for the settings panel and the surface) ---------
    // What the matching used at the last evaluation.
    property string currentDaytime: "day"     // night | dawn | day | dusk
    property string currentSeason: _seasonOf(new Date().getMonth())
    property string currentWeather: ""        // "" while weather is not implemented
    // Absolute path of the image the dynamic wallpaper wants to show, or ""
    // when nothing matches / the feature is off. Services/Background.qml
    // composes this with the static image.
    property string currentImage: ""

    // Entries under wallpapers/dynamic/, refreshed on demand: a subfolder of
    // state images (kind "folder", carrying absolute paths for the settings
    // preview) or a single .heic/.heif file (kind "file", scheduling the day
    // itself).
    property var available: []
    // Converted first-frame JPEG per bare .heic entry, for its settings
    // preview tile (Qt cannot decode HEIC, so previews point at these).
    property var previews: ({})

    // While a timeline HEIF drives the folder these describe what is painted;
    // they stay empty when the folder uses conventional names. Exposed for the
    // settings "Now showing" row.
    property string solarFile: ""        // base name of the driving HEIF
    property int solarFrame: -1          // frame index currently painted
    property string solarTimeText: ""    // its mapped time, "HH:MM"
    property string solarKind: "solar"   // "solar" (sun-angle) or "h24" (clock)

    readonly property bool lowPowerActive: Services.PowerBridge.batterySaverActive
    // Dynamic is actually driving the wallpaper right now: on, a folder is
    // picked, and battery saver is not suppressing it.
    readonly property bool activeNow: root.enabled
        && root.activeName.length > 0
        && !Services.PowerBridge.batterySaverActive
    // True when the feature is armed but battery saver is hiding it — lets the
    // settings panel distinguish "off" from "paused, will resume".
    readonly property bool pausedByLowPower: root.enabled
        && root.activeName.length > 0
        && Services.PowerBridge.batterySaverActive

    // --- vocabularies ----------------------------------------------------
    readonly property var _daytimes: ["dawn", "day", "dusk", "night"]
    readonly property var _seasons: ["spring", "summer", "autumn", "winter"]
    // The closed set of weather tokens the filename parser recognises. Keeping
    // TODO(weather): align this list with whatever the future weather source
    // reports, or map its values onto these.
    readonly property var _weathers: ["clear", "cloudy", "rain", "snow", "storm", "fog"]

    // --- settings API ----------------------------------------------------
    function setEnabled(v) { root.enabled = !!v; root._commit(); root._evaluate() }
    function setActive(name) {
        root.activeName = String(name || "")
        root._activeKind = root._resolveActiveKind(root.activeName)
        root._commit()
        root._evaluate()
    }
    function setDawnHour(h) {
        var n = parseInt(h)
        if (isNaN(n)) return
        root.dawnHour = ((n % 24) + 24) % 24
        root._commit()
        root._evaluate()
    }
    function setDuskHour(h) {
        var n = parseInt(h)
        if (isNaN(n)) return
        root.duskHour = ((n % 24) + 24) % 24
        root._commit()
        root._evaluate()
    }

    function _commit() {
        prefsFile.setText(JSON.stringify({
            enabled: root.enabled,
            activeName: root.activeName,
            dawnHour: root.dawnHour,
            duskHour: root.duskHour
        }, null, 2))
    }

    FileView {
        id: prefsFile
        path: Config.Paths.dynamicWallpaperPrefsFile
        onLoaded: {
            try {
                var parsed = JSON.parse(prefsFile.text())
                if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
                    if (typeof parsed.enabled === "boolean") root.enabled = parsed.enabled
                    if (typeof parsed.activeName === "string") root.activeName = parsed.activeName
                    var d = parseInt(parsed.dawnHour)
                    if (!isNaN(d)) root.dawnHour = ((d % 24) + 24) % 24
                    var u = parseInt(parsed.duskHour)
                    if (!isNaN(u)) root.duskHour = ((u % 24) + 24) % 24
                }
            } catch (e) {
                console.warn("phi-shell: dynamic-wallpaper.json failed to parse, ignoring: " + e)
            }
            root._evaluate()
            root.refresh()
        }
        onLoadFailed: function (error) {
            // Normal before the feature has ever been used: every property
            // keeps its default. The FileView fires once, so the startup dance
            // runs here too.
            root._evaluate()
            root.refresh()
        }
    }

    // Re-list entries and force a re-probe, so an image dropped into the
    // active entry shows without waiting for the next boundary. The probe
    // lives in listProc's completion so the entry kind is authoritative first.
    function refresh() {
        root._lastKey = ""
        listProc.running = true
    }

    Process {
        id: listProc
        onExited: listProc.running = false
        command: ["sh", "-c",
            'mkdir -p "$1" && for e in "$1"/*; do [ -e "$e" ] || continue; b=$(basename -- "$e"); if [ -d "$e" ]; then imgs=""; for im in "$e"/*; do case "$im" in *.png|*.PNG|*.jpg|*.JPG|*.jpeg|*.JPEG|*.webp|*.WEBP|*.bmp|*.BMP|*.gif|*.GIF) imgs="$imgs,$im" ;; esac; done; printf "D\\t%s\\t%s\\n" "$b" "${imgs#,}"; else case "$e" in *.heic|*.HEIC|*.heif|*.HEIF) printf "F\\t%s\\t%s\\n" "$b" "$(stat -c %Y "$e" 2>/dev/null)" ;; esac; fi; done | sort',
            "list", Config.Paths.dynamicWallpaperDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n").map((s) => s.trim()).filter((s) => s.length > 0)
                var entries = []
                for (var k = 0; k < lines.length; k++) {
                    var p = lines[k].split("\t")
                    if (p[0] === "D") {
                        entries.push({ name: p[1], kind: "folder",
                            images: (p[2] || "").split(",").filter((s) => s.length > 0) })
                    } else if (p[0] === "F") {
                        entries.push({ name: p[1], kind: "file", mtime: p[2] || "0" })
                    }
                }
                root.available = entries
                // Bare .heic entries get their first frame converted eagerly
                // so their preview tile always has something to show. Cheap:
                // the converter skips magick when the cache file exists.
                for (var f = 0; f < entries.length; f++)
                    root.ensureFilePreview(entries[f].name)
                // Re-probe the active entry now that its kind is authoritative
                // (a probe that ran before the list resolved may have guessed
                // wrong).
                if (root.enabled && root.activeName.length > 0) {
                    root._activeKind = root._resolveActiveKind(root.activeName)
                    root._probeActiveFolder()
                }
            }
        }
    }

    // List the active folder's images, then resolve. One probe per evaluation,
    // and the folder is hand-edited, so reading it fresh means edits show up
    // with no file watcher. Each line is "mtime\tname\tsolar": mtime keys the
    // render cache, `solar` flags an Apple dynamic-desktop HEIF.
    function _probeActiveFolder() {
        var dir = Config.Paths.dynamicWallpaperDir + "/" + root.activeName
        folderProc.command = ["sh", "-c",
            'case "$2" in file) f=$(basename -- "$1"); m=$(stat -c %Y "$1" 2>/dev/null); s=0; grep -aqE "apple_desktop:(solar|h24)" "$1" 2>/dev/null && s=1; printf "%s\\t%s\\t%s\\n" "${m:-0}" "$f" "$s" ;; *) ls -1 "$1" 2>/dev/null | grep -iE "\\.(png|jpe?g|webp|bmp|gif|heic|heif)$" | while IFS= read -r f; do m=$(stat -c %Y "$1/$f" 2>/dev/null); s=0; case "$f" in *.heic|*.HEIC|*.heif|*.HEIF) grep -aqE "apple_desktop:(solar|h24)" "$1/$f" 2>/dev/null && s=1 ;; esac; printf "%s\\t%s\\t%s\\n" "${m:-0}" "$f" "$s"; done ;; esac',
            "probe", dir, root._activeKind]
        folderProc.running = true
    }

    Process {
        id: folderProc
        onExited: folderProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                var files = this.text.split("\n").map((s) => s.trim()).filter((s) => s.length > 0)
                    .map((l) => {
                        var p = l.split("\t")
                        return { mtime: p[0] || "0", file: p[1] || "", solar: p[2] === "1" }
                    })
                // A solar-carrying HEIF owns the folder, so conventional names
                // are ignored while it is present. `_solarRejected` marks a
                // flagged file whose map failed to parse (by name + mtime) so
                // it degrades to the convention path instead of re-resolving
                // forever.
                for (var f = 0; f < files.length; f++) {
                    if (files[f].solar
                        && !(root._solarRejected !== null
                            && root._solarRejected.name === files[f].file
                            && root._solarRejected.mtime === files[f].mtime)) {
                        root._resolveSolar(files[f]); return
                    }
                }
                root._solarClear()
                var entries = files.map((x) => root._parseEntry(x.file)).filter((e) => e !== null)
                var pick = root._pick(entries, root.currentDaytime, root.currentSeason, root.currentWeather)
                if (!pick) { if (root.currentImage !== "") root.currentImage = ""; return }
                // Qt cannot decode HEIC — a named .heic renders its first
                // frame into the cache like every other image.
                if (/\.(heic|heif)$/i.test(pick.file)) {
                    root._renderHeic(pick.file, "0", root._mtimeOf(files, pick.file))
                    return
                }
                var next = root._entryPath(pick.file)
                // Only assign on a real change so the surface's crossfade
                // fires once per transition, not on every safety tick.
                if (next !== root.currentImage) root.currentImage = next
            }
        }
    }

    function _mtimeOf(files, name) {
        for (var k = 0; k < files.length; k++) if (files[k].file === name) return files[k].mtime
        return "0"
    }

    // Full source path of a file inside the active entry: a folder entry joins
    // the file under the folder; a bare .heic entry IS the file.
    function _entryPath(file) {
        if (root._activeKind === "file") return Config.Paths.dynamicWallpaperDir + "/" + root.activeName
        return Config.Paths.dynamicWallpaperDir + "/" + root.activeName + "/" + file
    }

    function _resolveActiveKind(name) {
        for (var a = 0; a < root.available.length; a++)
            if (root.available[a].name === name) return root.available[a].kind
        return /\.(heic|heif)$/i.test(name) ? "file" : "folder"
    }

    // The map is an apple_desktop XMP plist inside the file, which plain sh
    // cannot parse. python3 is an official Arch package present on every
    // machine the shell runs on — the smallest sanctioned way to turn the map
    // into "S z i" / "H minutes i" lines without touching pixels. The tag on
    // the first line tells the collector which kind it is.
    readonly property string _solarScript:
        "import base64,plistlib,re,sys\n"
        + "d=open(sys.argv[1],'rb').read()\n"
        + "def dec(ab,kb):\n"
        + "  m=re.search(rb'apple_desktop:'+ab+rb'[=>]\"?([A-Za-z0-9+/=]+)',d)\n"
        + "  if not m: return None\n"
        + "  s=m.group(1)+(b'='*((4-len(m.group(1))%4)%4))\n"
        + "  try: return plistlib.loads(base64.b64decode(s)).get(kb,[])\n"
        + "  except Exception: return None\n"
        + "si=dec(b'solar','si')\n"
        + "if si:\n"
        + "  for e in si:\n"
        + "    if 'z' in e and 'i' in e: print('S',e['z'],e['i'])\n"
        + "  sys.exit(0)\n"
        + "ti=dec(b'h24','ti')\n"
        + "if ti:\n"
        + "  for e in ti:\n"
        + "    if 't' in e and 'i' in e: print('H',round(float(e['t'])*1440)%1440,e['i'])"

    function _resolveSolar(file) {
        root._solarTarget = file
        solarProc.command = ["python3", "-c", root._solarScript, root._entryPath(file.file)]
        solarProc.running = true
    }

    Process {
        id: solarProc
        onExited: solarProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                // Completion always serves the newest _solarTarget, so a stale
                // run for a folder that was switched away is superseded rather
                // than applied twice.
                var target = root._solarTarget
                if (!target) return
                root._solarTarget = null
                var lines = this.text.split("\n").map((s) => s.trim()).filter((s) => s.length > 0)
                var map = []
                var kind = "solar"
                for (var k = 0; k < lines.length; k++) {
                    var parts = lines[k].split(/\s+/)
                    if (k === 0 && parts[0] === "H") kind = "h24"
                    var v = parseFloat(parts[1]), i = parseInt(parts[2])
                    if (!isNaN(v) && !isNaN(i)) {
                        if (kind === "h24") map.push({ minutes: v, i: i })
                        else map.push({ z: v, i: i })
                    }
                }
                if (map.length < 2) {
                    // The marked file carries no usable map: fold back to the
                    // convention path. Rejected by name + mtime, so a replaced
                    // file is retried.
                    root._solarRejected = { name: target.file, mtime: target.mtime }
                    root._solarClear()
                    root._lastKey = ""
                    root._evaluate()
                    return
                }
                root._solarMap = map
                root.solarKind = kind
                root._solarMtime = target.mtime
                root.solarFile = target.file
                root._showSolarFrame(kind === "h24"
                    ? root._frameAtTime(map, root._nowMinutes())
                    : root._frameAt(map, root._nowAngle()))
            }
        }
    }

    // Frame selection: the map entry whose z is nearest the current 0..360 day
    // angle, wrap aware. Switches therefore land at the midpoints between
    // neighbouring z values, which is what the boundary timer is armed to.
    function _nowAngle() {
        var d = new Date()
        return ((d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()) / 86400) * 360
    }

    function _frameAt(map, angle) {
        var best = null, bestD = 361
        for (var k = 0; k < map.length; k++) {
            var dz = Math.abs(map[k].z - angle)
            if (dz > 180) dz = 360 - dz
            if (dz < bestD) { bestD = dz; best = map[k] }
        }
        if (!best) return { i: 0, z: 0, minutes: 0 }
        return { i: best.i, z: best.z, minutes: Math.round(best.z / 360 * 1440) % 1440 }
    }

    // Milliseconds to the next frame switch: the nearest midpoint ahead, or -1
    // for an empty map. Re-armed after every show so a frame lands on its
    // exact minute.
    function _msToNextSolarBoundary(map, angle) {
        var zs = []
        for (var k = 0; k < map.length; k++) zs.push(map[k].z)
        zs.sort((a, b) => a - b)
        var mid = []
        for (var s = 0; s < zs.length; s++) {
            var lo = zs[s]
            var hi = zs[(s + 1) % zs.length]
            if (s === zs.length - 1) hi += 360
            mid.push((lo + hi) / 2)
        }
        var best = -1
        for (var m = 0; m < mid.length; m++) {
            var dz = mid[m] - angle
            if (dz <= 0) dz += 360
            if (best < 0 || dz < best) best = dz
        }
        return best < 0 ? -1 : best / 360 * 86400 * 1000
    }

    // h24 variant: each entry is the minute of day (0..1439) a frame starts,
    // running until the next entry (the last window wraps past midnight).
    // Plain interval lookup, and each future start is itself a boundary, not a
    // midpoint.
    function _nowMinutes() {
        var d = new Date()
        return d.getHours() * 60 + d.getMinutes()
    }

    function _frameAtTime(map, minutes) {
        var best = null, latest = null
        for (var k = 0; k < map.length; k++) {
            if (latest === null || map[k].minutes > latest.minutes) latest = map[k]
            if (map[k].minutes <= minutes && (best === null || map[k].minutes > best.minutes)) best = map[k]
        }
        if (!best) best = latest // before the cycle's first start, the last window still runs
        return { i: best.i, minutes: best.minutes }
    }

    function _msToNextTimeBoundary(map, minutes) {
        var best = -1
        for (var k = 0; k < map.length; k++) {
            var dm = map[k].minutes - minutes
            if (dm <= 0) dm += 1440
            if (best < 0 || dm < best) best = dm
        }
        return best < 0 ? -1 : best * 60000
    }

    function _showSolarFrame(pair) {
        root.solarFrame = pair.i
        var h = Math.floor(pair.minutes / 60)
        var m = pair.minutes % 60
        root.solarTimeText = (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
        root._renderHeic(root.solarFile, String(pair.i), root._solarMtime)
        var next = root.solarKind === "h24"
            ? root._msToNextTimeBoundary(root._solarMap, root._nowMinutes())
            : root._msToNextSolarBoundary(root._solarMap, root._nowAngle())
        if (next >= 0) {
            root._solarNextBoundary = next
            if (root.enabled && root.activeName.length > 0 && !Services.PowerBridge.batterySaverActive) {
                boundaryTimer.interval = Math.max(1000, next)
                boundaryTimer.restart()
            }
        }
    }

    function _solarClear() {
        root._solarMap = []
        root.solarKind = "solar"
        root._solarMtime = ""
        root._solarTarget = null
        root._solarNextBoundary = -1
        root.solarFile = ""
        root.solarFrame = -1
        root.solarTimeText = ""
    }

    property var _solarMap: []
    property string _solarMtime: ""
    property var _solarTarget: null
    property var _solarRejected: null
    property real _solarNextBoundary: -1

    // Qt has no HEIC decoder, so a picked heic/heif is rendered with
    // ImageMagick to a cached JPEG and the surface points at the cache file.
    // The name keys on source mtime + frame index, so a replaced source or a
    // different frame re-converts into a fresh file.
    //
    // Latest-wins for the shown frame: one conversion at a time, `_heicWanted`
    // holding the newest request, so a rapid frame change replaces the pending
    // one rather than queueing both. Previews (frame 0 for settings tiles) are
    // less urgent and go through `_heicQueue` in order.
    //
    // The sh wrapper echoes the cache path it wrote as its only stdout so the
    // collector can confirm which job finished. That finish arrives before
    // `exited` (Quickshell nulls the process first), which is why this Process
    // has no `onExited: running = false` — it would kill the next conversion.
    property var _heicWanted: null
    property var _heicQueue: []
    property var _heicCurrent: null

    function _renderHeic(file, index, mtime) {
        var folder = root.activeName
        var cache = Config.Paths.dynamicWallpaperCacheDir + "/" + folder + "/"
            + file + "." + (mtime || "0") + "." + index + ".jpg"
        if (cache === root.currentImage) return
        root._heicWanted = { kind: "render", folder: folder, file: file, frame: index, cache: cache }
        root._heicStart()
    }

    // Preview for a bare .heic entry's settings tile: frame 0 into the cache,
    // exposed via `previews[name]`. No-op once cached, and queued requests are
    // deduplicated so simultaneous tiles never double-convert.
    function ensureFilePreview(name) {
        if (root.previews[name]) return
        for (var k = 0; k < root.available.length; k++) {
            var e = root.available[k]
            if (e.name !== name || e.kind !== "file") continue
            var cache = Config.Paths.dynamicWallpaperCacheDir + "/" + e.name + "/"
                + e.name + "." + (e.mtime || "0") + ".0.jpg"
            if (root._heicCurrent !== null && root._heicCurrent.cache === cache) return
            for (var q = 0; q < root._heicQueue.length; q++)
                if (root._heicQueue[q].cache === cache) return
            root._heicQueue.push({ kind: "preview", file: e.name, frame: "0", cache: cache })
            root._heicStart()
            return
        }
    }

    function _heicStart() {
        if (heicProc.running) return
        var job = null
        if (root._heicWanted !== null) {
            job = root._heicWanted
            root._heicWanted = null
        } else if (root._heicQueue.length > 0) {
            job = root._heicQueue.shift()
        }
        if (job === null) return
        root._heicCurrent = job
        var src = job.kind === "preview"
            ? Config.Paths.dynamicWallpaperDir + "/" + job.file
            : root._entryPath(job.file)
        heicProc.command = ["sh", "-c",
            'f="$3"; n="$4"; mkdir -p "$2" || exit 1; if [ ! -f "$f" ]; then magick "$1[$n]" -strip -quality 92 "$f" || exit 1; fi; if [ -f "$f" ]; then printf "%s" "$f"; fi',
            "heic", src,
            Config.Paths.dynamicWallpaperCacheDir + "/" + (job.kind === "preview" ? job.file : job.folder),
            job.cache, job.frame || "0"]
        heicProc.running = true
    }

    Process {
        id: heicProc
        stdout: StdioCollector {
            onStreamFinished: {
                // Apply only the conversion that finished: a render reaches
                // currentImage only while it still belongs to the active
                // entry; a preview lands in `previews`.
                var cache = this.text.trim()
                var job = root._heicCurrent
                if (cache.length > 0 && job !== null) {
                    if (job.kind === "preview") {
                        var p = root.previews
                        p[job.file] = cache
                        root.previews = p
                    } else if (job.folder === root.activeName
                        && job.cache === cache && cache !== root.currentImage) {
                        root.currentImage = cache
                    }
                }
                root._heicCurrent = null
                // A newer request may have landed while this one ran.
                root._heicStart()
            }
        }
    }

    // --- filename parsing ------------------------------------------------
    function _parseEntry(p) {
        var base = p.split("/").pop()
        var noext = base.replace(/\.(png|jpe?g|webp|bmp|gif|heic|heif)$/i, "")
        var parts = noext.split("-")
        if (parts.length === 0 || root._daytimes.indexOf(parts[0]) < 0) return null
        var season = ""
        var weather = ""
        for (var i = 1; i < parts.length; i++) {
            if (season.length === 0 && root._seasons.indexOf(parts[i]) >= 0) season = parts[i]
            else if (weather.length === 0 && root._weathers.indexOf(parts[i]) >= 0) weather = parts[i]
            // any other token is a decorative suffix — ignored
        }
        return { file: base, daytime: parts[0], season: season, weather: weather }
    }

    // --- matching ----------------------------------------------------------
    // Most specific eligible entry for the current slot; if none, the same
    // search for the next slots in day order. Returns {file, spec} or null.
    function _pick(entries, daytime, season, weather) {
        var idx = root._daytimes.indexOf(daytime)
        if (idx < 0) idx = 0
        for (var step = 0; step < root._daytimes.length; step++) {
            var slot = root._daytimes[(idx + step) % root._daytimes.length]
            var best = null
            var bestSpec = -1
            for (var i = 0; i < entries.length; i++) {
                var e = entries[i]
                if (e.daytime !== slot) continue
                if (e.season.length > 0 && e.season !== season) continue
                if (e.weather.length > 0 && e.weather !== weather) continue
                var spec = (e.season.length > 0 ? 1 : 0) + (e.weather.length > 0 ? 1 : 0)
                // Strictly-better wins; equal specificity goes to the
                // alphabetically last filename (deterministic, lets a user
                // pick between ties by renaming).
                if (best === null || spec > bestSpec || (spec === bestSpec && e.file > best.file)) {
                    best = e
                    bestSpec = spec
                }
            }
            if (best !== null) return best
        }
        return null
    }

    // Wrap-aware window membership, as in NightShift: start < end → inside
    // [start, end); start > end → outside [end, start); equal → always true.
    function _inWindow(m, start, end) {
        return start === end ? true
            : start < end ? (m >= start && m < end)
            : (m >= start || m < end)
    }

    function _daytime() {
        var d = new Date()
        var now = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()
        var tl = root.transitionLength * 3600
        var dawn = ((root.dawnHour % 24) + 24) % 24 * 3600
        var dusk = ((root.duskHour % 24) + 24) % 24 * 3600
        if (root._inWindow(now, dawn, dawn + tl)) return "dawn"
        if (root._inWindow(now, dusk, dusk + tl)) return "dusk"
        // Night is the wrap-aware complement of the two transition windows and
        // the day hours: from when dusk ends up to when dawn begins.
        if (root._inWindow(now, dusk + tl, dawn)) return "night"
        return "day"
    }

    // Seconds to the next daytime boundary. Whole hours plus fixed windows
    // give four: dawn start/end and dusk start/end. Distinct from NightShift's
    // minute-granularity polling because this changes an image.
    function _msToNextBoundary() {
        var d = new Date()
        var now = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()
        var tl = root.transitionLength * 3600
        var dawn = ((root.dawnHour % 24) + 24) % 24 * 3600
        var dusk = ((root.duskHour % 24) + 24) % 24 * 3600
        var boundaries = [dawn, dawn + tl, dusk, dusk + tl]
        var best = 86400
        for (var i = 0; i < boundaries.length; i++) {
            var bm = ((boundaries[i] % 86400) + 86400) % 86400
            var delta = bm - now
            if (delta <= 0) delta += 86400
            if (delta < best) best = delta
        }
        return best * 1000
    }

    // --- evaluation ----------------------------------------------------------
    function _evaluate() {
        // Always re-arm first: on/off, hour changes and solar map picks shift
        // the next event even when the current image doesn't change.
        if (!root.enabled || root.activeName.length === 0 || Services.PowerBridge.batterySaverActive) {
            boundaryTimer.stop()
        } else if (root._solarNextBoundary >= 0 && root.solarFile.length > 0) {
            // A solar HEIF schedules its own boundaries (map midpoints).
            boundaryTimer.interval = Math.max(1000, root._solarNextBoundary)
            boundaryTimer.restart()
        } else {
            boundaryTimer.interval = Math.max(1000, root._msToNextBoundary())
            boundaryTimer.restart()
        }

        root.currentDaytime = root._daytime()
        root.currentSeason = root._seasonOf(new Date().getMonth())
        root.currentWeather = root._weather()

        // Deduplicate: nothing to redo unless the deciding inputs changed. For
        // solar folders that input is the frame the map picks for right now,
        // computed from the cached map, so a midpoint step provokes a probe on
        // its own.
        var solarKey = ""
        if (root.solarFile.length > 0 && root._solarMap.length >= 2) {
            var sp = root.solarKind === "h24"
                ? root._frameAtTime(root._solarMap, root._nowMinutes())
                : root._frameAt(root._solarMap, root._nowAngle())
            solarKey = root.solarFile + "|" + sp.i
        }
        var key = (root.enabled ? "1" : "0") + "|" + root.activeName + "|"
            + root.currentDaytime + "|" + root.currentSeason + "|" + root.currentWeather
            + "|" + solarKey
        if (key === root._lastKey) return
        root._lastKey = key

        if (!root.enabled || root.activeName.length === 0) {
            if (root.currentImage !== "") root.currentImage = ""
            return
        }
        root._probeActiveFolder()
    }
    property string _lastKey: ""

    // The single-shot boundary timer — the "precise check" of the spec.
    Timer {
        id: boundaryTimer
        interval: 3600000
        onTriggered: root._evaluate()
    }

    // Battery saver pausing/resuming must land immediately, not on the next
    // safety tick — the wallpaper pauses exactly when the mode flips.
    Connections {
        target: Services.PowerBridge
        function onBatterySaverActiveChanged() { root._evaluate() }
    }

    // Coarse safety net: suspend/resume, timer drift, folder edits made while
    // the shell ran. No-op unless the deciding inputs actually changed (see
    // _evaluate's dedupe above).
    Timer {
        id: safetyTimer
        interval: 60000
        running: true
        repeat: true
        onTriggered: root._evaluate()
    }

    // TODO(weather): returns "" — no weather source exists. phi has no weather
    // command and QML has no sanctioned fetch, so this belongs in the phi CLI
    // or a small daemon, not here. When one lands, return its condition
    // normalized to one of `_weathers`.
    function _weather() { return "" }

    // Northern-hemisphere meteorological quarters; month is getMonth() (0-11).
    // All three machines are northern and there is no location source, so the
    // assumption is documented rather than hidden.
    function _seasonOf(month) {
        if (month === 11 || month <= 1) return "winter"
        if (month <= 4) return "spring"
        if (month <= 7) return "summer"
        return "autumn"
    }
}