pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services

// Dynamic wallpapers: folders of images under
// $XDG_DATA_HOME/phi/wallpapers/dynamic/<name>/ that rotate automatically
// by time of day, season and — once a weather source exists — weather.
// Read side only: Services/Background.qml composes the image actually
// painted (this service's `currentImage` when active, else the manually
// picked static one), so nothing here ever overwrites the user's static
// choice.
//
// Folder layout and naming convention
// ------------------------------------
//   wallpapers/dynamic/<name>/day.png            — daytime only (any season, any weather)
//   wallpapers/dynamic/<name>/night-winter.png   — daytime + season
//   wallpapers/dynamic/<name>/dusk-spring-rain.png — daytime + season + weather
//   wallpapers/dynamic/<name>/day-clear.png      — daytime + weather only
//
// An entry is either a directory like these, or — for a solar Apple
// dynamic-desktop file — the bare .heic/.heif itself sitting directly in
// wallpapers/dynamic/ (wallpapers/dynamic/sunset.heic): the file needs no
// folder, it carries its own whole-day schedule.
//
// One directory per dynamic wallpaper. Every image file is named
// `<daytime>[-<optional>...].<ext>` where the FIRST token is the required
// daytime slot and the following tokens (up to one season and one weather
// each, in any order) narrow the match:
//   daytime: dawn | day | dusk | night          (required)
//   season:  spring | summer | autumn | winter  (optional)
//   weather: clear | cloudy | rain | snow | storm | fog  (optional,
//            placeholder vocabulary — see the weather TODO below)
// Any other trailing token (e.g. "-2", "-dark") is decorative and ignored,
// so a folder can hold several alternatives for one condition and swap
// which one by editing ties (ties resolve alphabetically).
//
// Matching: an entry is eligible when its daytime equals the current slot
// AND every specified optional matches the current season/weather. Among
// eligible entries the most specific wins (season+weather > season >
// weather > bare daytime). When the current slot has no eligible entry,
// the following slots of the day are tried in day order (dawn → day →
// dusk → night) — so e.g. a folder with only day.png and night.png shows
// the day image through the dawn hour. An image that specifies a season
// or weather never matches a different season/weather value.
//
// Daytime slots
// -------------
// Two configurable boundaries split the day (same wrap-aware hour math as
// Services/NightShift.qml, defaults fitted to Central Europe):
//   dawn:  [dawnHour,           dawnHour + transitionLength)
//   day:   the hours in between
//   dusk:  [duskHour,           duskHour + transitionLength)
//   night: [dusk+transitionLength, 24) + [0, dawnHour)
// transitionLength is a fixed 1-hour window for each transition, not
// user-configurable. The check runs at the precise minute each boundary
// falls on (a single-shot timer armed to the next boundary, see
// _armTimer()), with a coarse 1-minute safety timer catching suspend/resume
// or drift. Re-evaluation is deduplicated against the last (enabled, folder,
// daytime, season, weather, solar frame) tuple, so the steady-state safety
// ticks are no-ops.
//
// HEIC/HEIF dynamic desktops
// --------------------------
// Apple "Dynamic Desktop"-style files — one multi-image HEIF carrying an
// `apple_desktop:solar` (sun-angle → frame) or `apple_desktop:h24`
// (clock-start → frame) XMP map — are supported as a whole-day wallpaper:
// a single .heic that schedules every hour of the day itself. Such a file
// in the active folder takes over the whole day (conventional named images
// in the same folder are ignored while it is present). The solar map's `z`
// values are day angles, 0..360 == 00:00..24:00 — the frame whose z is
// nearest right now wins, and the boundary timer is armed to each map
// midpoint so the next frame lands at its exact minute. The h24 map's `t`
// values are frame start times (fraction of a day): the frame whose start
// has just passed wins and the timer is armed to the next start. Season/
// weather do not apply to either — the file is its own schedule.
// Qt cannot decode HEIC at all (no QImageReader plugin), so the chosen
// frame is converted on demand with ImageMagick (libheif-backed) into a
// cached JPEG under Config.Paths.dynamicWallpaperCacheDir, keyed on source
// mtime + frame index so a replaced source re-converts. A .heic with
// neither map is an ordinary named image and shows its first frame when
// picked like any raster.
//
// Season is computed from the current month (meteorological quarters,
// Northern hemisphere — winter Dec-Feb, spring Mar-May, summer Jun-Aug,
// autumn Sep-Nov); there is no location source for an astronomical season.
//
// TODO(weather): the weather system is not implemented yet — nowhere in
// this shell (or its phi CLI backend) reports a current condition. Until
// it lands, `_weather()` always returns "" (no weather constraint), so
// weather-specified images are never eligible and only daytime/season
// images rotate. When a weather source exists (expected: a new
// Services/Weather.qml exposing e.g. `current` — one of the `_weathers`
// tokens below), this service only needs to make `_weather()` return it;
// the parsing, matching and crossfade already handle it.
//
// Low power mode
// --------------
// While Services/PowerBridge.qml's battery saver is active the dynamic
// wallpaper is suppressed (`activeNow` false), so the shell paints the
// static image the user picked. The suppression is read-side only, exactly
// like Lock/Lock.qml's battery-saver gate — nothing is written back to
// the user's settings. The static pick survives any session-start state.
//
// Persistence
// -----------
// The four settings (enabled, activeName, dawnHour, duskHour) live in one
// flat JSON file at Config.Paths.dynamicWallpaperPrefsFile, rewritten whole
// on change — the ClockPrefs/LockPrefs pattern. NOT `phi state`: those
// keys would be rejected by `phi` until the CLI grew new declared keys,
// and nothing outside quickshell is touched by this feature.

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

    // Entries under wallpapers/dynamic/, refreshed on demand (settings
    // open, after a restart): a subfolder of state images (kind "folder",
    // carrying its raster files' absolute paths for the settings preview)
    // or a single .heic/.heif file directly in the folder (kind "file" —
    // no folder needed, it schedules the day itself).
    property var available: []
    // Converted first-frame JPEG per bare .heic entry, for its settings
    // preview tile (Qt cannot decode HEIC, so previews point at these).
    property var previews: ({})

    // --- timeline HEIF state (see the HEIC section in the header comment) ---
    // While a timeline-carrying HEIF drives the folder, these describe what
    // is painted; they stay empty/default when the folder uses conventional
    // names. Exposed for the settings "Now showing" status row.
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
    // True when the feature is armed but battery saver is hiding it — lets
    // the settings panel distinguish "off" from "paused, will resume".
    readonly property bool pausedByLowPower: root.enabled
        && root.activeName.length > 0
        && Services.PowerBridge.batterySaverActive

    // --- vocabularies ----------------------------------------------------
    readonly property var _daytimes: ["dawn", "day", "dusk", "night"]
    readonly property var _seasons: ["spring", "summer", "autumn", "winter"]
    // The closed set of weather tokens the filename parser recognises.
    // Keeping TODO(weather): align this list with whatever the future
    // weather source reports, or map its values onto these.
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
            // Normal before the user has ever used dynamic wallpapers —
            // every property stays at its default above. The FileView only
            // fires once, so run the same startup dance here, with the
            // defaults standing in for the missing prefs.
            root._evaluate()
            root.refresh()
        }
    }

    // Re-list the dynamic entries (settings open, new folders dropped in).
    // Also force an entry re-probe so an image dropped into / replaced in
    // the active entry shows without waiting for the next boundary — the
    // dedupe key is cleared so the next _evaluate() re-reads it. The probe
    // after listing lives in listProc's completion so the entry kind is
    // authoritative first.
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
                // Re-probe the active entry now that its kind is
                // authoritative (a probe that ran before the list resolved
                // may have guessed wrong).
                if (root.enabled && root.activeName.length > 0) {
                    root._activeKind = root._resolveActiveKind(root.activeName)
                    root._probeActiveFolder()
                }
            }
        }
    }

    // List the image files of the active folder, then resolve. One probe
    // per evaluation — evaluations happen at most at each boundary plus on
    // user interaction, and the folder is hand-edited, so always reading it
    // fresh means edits show up without any file watcher plumbed through.
    // Each output line is "mtime\tname\tsolar": the mtime keys the HEIC
    // render cache, and `solar` flags Apple dynamic-desktop HEIF files
    // (they carry an apple_desktop:solar or apple_desktop:h24 time → frame
    // map and drive the whole day on their own — see the header comment).
    function _probeActiveFolder() {
        var dir = Config.Paths.dynamicWallpaperDir + "/" + root.activeName
        folderProc.command = ["sh", "-c",
            'case "$2" in file) f=$(basename -- "$1"); m=$(stat -c %Y "$1" 2>/dev/null); s=0; grep -aq "apple_desktop:solar\|apple_desktop:h24" "$1" 2>/dev/null && s=1; printf "%s\\t%s\\t%s\\n" "${m:-0}" "$f" "$s" ;; *) ls -1 "$1" 2>/dev/null | grep -iE "\\.(png|jpe?g|webp|bmp|gif|heic|heif)$" | while IFS= read -r f; do m=$(stat -c %Y "$1/$f" 2>/dev/null); s=0; case "$f" in *.heic|*.HEIC|*.heif|*.HEIF) grep -aq "apple_desktop:solar\|apple_desktop:h24" "$1/$f" 2>/dev/null && s=1 ;; esac; printf "%s\\t%s\\t%s\\n" "${m:-0}" "$f" "$s"; done ;; esac',
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
                // A solar-carrying HEIF owns the folder: it schedules the
                // whole day from its own map, so conventional names are
                // ignored while it is here. `_solarRejected` marks a flagged
                // file whose map failed to parse (same name + mtime), so a
                // degenerate file degrades to the convention path instead of
                // re-resolving forever.
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

    // Full source path of a file inside the active entry: a folder entry
    // joins the file under the folder; a bare .heic entry IS the file.
    function _entryPath(file) {
        if (root._activeKind === "file") return Config.Paths.dynamicWallpaperDir + "/" + root.activeName
        return Config.Paths.dynamicWallpaperDir + "/" + root.activeName + "/" + file
    }

    function _resolveActiveKind(name) {
        for (var a = 0; a < root.available.length; a++)
            if (root.available[a].name === name) return root.available[a].kind
        return /\.(heic|heif)$/i.test(name) ? "file" : "folder"
    }

    // --- timeline HEIF resolution ------------------------------------------
    // The map lives inside the file as an apple_desktop:solar or
    // apple_desktop:h24 XMP plist; extracting it needs a plist parse, which
    // plain sh cannot do. python3 is an official Arch package, installed on
    // every machine the shell runs on — the smallest sanctioned way to turn
    // the map into "S z i" / "H minutes i" lines WITHOUT converting any
    // pixels (that is left to magick, only for the frame that is actually
    // shown). The tag on the first line tells the collector which kind.
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
                // Completion always serves the newest _solarTarget, so a
                // stale run for a folder that was switched away is
                // superseded rather than applied twice.
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
                    // The marked file carries no usable map after all — fold
                    // back to the convention path for the folder. Reject by
                    // name + mtime so the next probe skips it (a replaced
                    // file with a new mtime gets retried).
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

    // --- the solar schedule ----------------------------------------------
    // Frame selection: the map entry whose z is nearest the current 0..360
    // day angle (wrap aware) — the photo whose time is closest to right
    // now. Frame switches therefore land at the MIDPOINTS between
    // neighbouring z's, and that is what the boundary timer gets armed to.
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

    // Milliseconds until the next frame switch: the nearest map midpoint
    // ahead in day-angle, or -1 for an empty map. The boundary timer is
    // re-armed with this after every show, so the next frame lands at its
    // exact minute rather than on a safety tick.
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

    // h24 variant ("Apple 24-hour timeline"): each entry is the minute of
    // day (0..1439) at which that frame starts showing; the frame runs
    // until the next entry's start (the day's last window runs past
    // midnight). Selection is a plain interval lookup, and a boundary is
    // each future start itself — not a midpoint.
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

    // --- HEIC rendering --------------------------------------------------
    // Qt has no HEIC decoder, so every heic/heif that gets picked is first
    // rendered with ImageMagick (libheif-backed) to a cached JPEG, and the
    // surface points at the cache file. The cache name keys on source mtime
    // + frame index, so a replaced source or a different frame lands in a
    // fresh file and re-converts. Latest-wins: at most one conversion runs
    // at a time and `_heicWanted` holds the newest request, so a rapid
    // frame change replaces the pending one instead of queueing both. The
    // sh wrapper echoes the cache path it wrote as its only stdout, so the
    // collector can confirm which job finished before touching
    // currentImage — the finish happens before `exited` (Quickshell nulls
    // the process first), which is also why this Process deliberately has
    // no `onExited: running = false`: that would terminate the next
    // conversion, which is already launched by then. The same pipeline
    // also serves previews for bare .heic entries (kind "preview": frame 0
    // into the cache, surfaced through `previews` instead of currentImage).
    property var _heicWanted: null
    property var _heicCurrent: null

    function _renderHeic(file, index, mtime) {
        var folder = root.activeName
        var cache = Config.Paths.dynamicWallpaperCacheDir + "/" + folder + "/"
            + file + "." + (mtime || "0") + "." + index + ".jpg"
        if (cache === root.currentImage) return
        root._heicWanted = { kind: "render", folder: folder, file: file, frame: index, cache: cache }
        root._heicStart()
    }

    // Preview for a bare .heic entry's settings tile: frame 0 converted to
    // a cached JPEG, exposed via `previews[name]`. No-op once cached.
    function ensureFilePreview(name) {
        if (root.previews[name]) return
        for (var k = 0; k < root.available.length; k++) {
            var e = root.available[k]
            if (e.name !== name || e.kind !== "file") continue
            var cache = Config.Paths.dynamicWallpaperCacheDir + "/" + e.name + "/"
                + e.name + "." + (e.mtime || "0") + ".0.jpg"
            if (root._heicWanted !== null && root._heicWanted.kind === "preview"
                && root._heicWanted.cache === cache) return
            root._heicWanted = { kind: "preview", file: e.name, frame: "0", cache: cache }
            root._heicStart()
            return
        }
    }

    function _heicStart() {
        if (heicProc.running || root._heicWanted === null) return
        var job = root._heicWanted
        root._heicWanted = null
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
                // Apply only the conversion that actually finished: a render
                // lands on currentImage when it still belongs to the active
                // entry (a switch away leaves stale completions unapplied);
                // a preview lands in `previews` for its tile.
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

    // --- schedule -----------------------------------------------------------
    // Wrap-aware window membership, same shape as NightShift._evaluateSchedule():
    // start < end → inside [start, end); start > end → outside [end, start);
    // equal → always true (a zero-width window has no other sensible reading).
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
        // Night is the wrap-aware complement of the two transition windows
        // and the day hours: from when dusk ends up to when dawn begins.
        if (root._inWindow(now, dusk + tl, dawn)) return "night"
        return "day"
    }

    // Seconds until the next daytime boundary, whatever it is. Whole
    // hours + fixed windows → four boundaries: dawn start/end, dusk
    // start/end. Purposely distinct from NightShift's minute-granularity
    // polling: this feature changes an image, so it checks at the actual
    // boundary second.
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
        // Always re-arm first: on/off, hour changes and solar map picks
        // shift the next event even when the current image doesn't change.
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

        // Deduplicate: nothing to redo unless the deciding inputs changed.
        // For solar folders the deciding input is the frame the map picks
        // for right now (computed from the cached map, not the one shown),
        // so a map midpoint step provokes a probe on its own.
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

    // Coarse safety net: suspend/resume, timer drift, folder edits made
    // while the shell ran. No-op unless the deciding inputs actually
    // changed (see _evaluate's dedupe above).
    Timer {
        id: safetyTimer
        interval: 60000
        running: true
        repeat: true
        onTriggered: root._evaluate()
    }

    // TODO(weather): the weather system is not implemented yet. When it
    // lands (planned as a Services/Weather.qml reporting a current
    // condition), return that condition here, normalized to one of
    // `_weathers` (or mapped onto it). Until then "" means "no weather
    // constraint", so weather-specified images are simply never eligible.
    // Today's temperature/condition has no source in this shell: phi has
    // no weather command, and this repo cannot reach a weather network API
    // by itself (QML has no sanctioned fetch; that belongs in the phi CLI
    // or a small daemon — outside this quickshell folder).
    function _weather() { return "" }

    // Northern-hemisphere meteorological quarters. month is getMonth()
    // (0-11). The user machines are all in the Northern hemisphere, and
    // there is no location source for an astronomical season — document
    // this assumption explicitly rather than pretend otherwise.
    function _seasonOf(month) {
        if (month === 11 || month <= 1) return "winter"
        if (month <= 4) return "spring"
        if (month <= 7) return "summer"
        return "autumn"
    }
}