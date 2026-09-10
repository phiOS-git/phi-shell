pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config

// phiOS — Services/Background (S-44; Out-of-plan: settings-overhaul batch
// D). Shared wallpaper state — a per-screen Background/Background.qml
// surface cannot own its own IPC or state without colliding across
// instances (same split as Services/Spotlight.qml).
//
// The wallpaper is composited by the background layer from up to three
// layers: a solid `color`, an optional `image` with a fit `mode`, and — on
// top of both — an optional procedural `texture` grain (generated once by
// `phi wallpaper texture` and cached). Every value is persisted through
// `phi state` (the keys were added to internal/state in the same batch).
// `wallpaper.path` is read as the initial `image` for back-compat with S-44.
//
// features-change (item 3): the texture used to sit BEHIND the image and
// was gated off whenever the image covered the screen — so with any
// ordinary cover wallpaper it did nothing and its settings control was
// disabled. It is a grain overlay: it now composites on top of everything
// and always applies. `_generateTexture()` was also made robust — an
// atomic temp-file write, a real "did it produce a file" check, and
// `textureError` surfaced in the settings caption (a stale `phi` with no
// `wallpaper` verb was invisible before).
//
// setX() updates the reactive property synchronously (the surface repaints
// at once) and fires the `phi state set` underneath fire-and-forget, purely
// for persistence — same rationale as the original setPath().

Singleton {
    id: root

    // Legacy single-string API kept so existing callers (the bar OSD
    // deep-link, older code) still compile; it maps onto `image`.
    property string path: ""

    property string color: "#000000"
    property string image: ""
    property string mode: "cover"        // cover | contain | stretch | repeat
    property real scale: 1.0
    property string texture: ""           // "" or a phi wallpaper texture mode
    property int textureIntensity: 40
    property string texturePath: ""       // cached PNG, "" until generated
    property string textureError: ""      // last generation failure, "" when fine

    // Every image in the wallpaper folder, absolute paths — the settings
    // panel's picker grid. Populated by an `ls` probe (the repo's own
    // dir-listing pattern, Services/Agent.qml), refreshed when the panel
    // opens or a new image is added.
    property var available: []

    function setPath(p) { root.setImage(p) }

    function setColor(hex) {
        root.color = hex
        Config.Settings.set("wallpaper.color", hex)
    }
    function setImage(p) {
        root.image = p || ""
        root.path = root.image
        Config.Settings.set("wallpaper.path", root.image)
    }
    function setMode(m) {
        root.mode = m
        Config.Settings.set("wallpaper.mode", m)
    }
    function setScale(s) {
        root.scale = s
        Config.Settings.set("wallpaper.scale", String(s))
    }
    function clearImage() { root.setImage("") }

    // mode "" clears the texture.
    function setTexture(mode, intensity) {
        root.texture = mode || ""
        if (intensity !== undefined) root.textureIntensity = intensity
        Config.Settings.set("wallpaper.texture", root.texture)
        Config.Settings.set("wallpaper.texture-intensity", String(root.textureIntensity))
        root._generateTexture()
    }
    function setTextureIntensity(n) { root.setTexture(root.texture, n) }

    function _generateTexture() {
        if (root.texture.length === 0) { root.texturePath = ""; root.textureError = ""; return }
        if (textureProc.running) { textureProc._pending = true; return }
        var out = Config.Paths.texturesDir + "/" + root.texture + "-" + root.textureIntensity + ".png"
        // Atomic: generate into a temp file and rename only on success, so a
        // half-written or empty PNG can never become the cached one. `-s`
        // (exists and non-empty) is the cache check — a zero-byte file left
        // by a failed run is treated as absent. stdout is the final path on
        // success and empty on failure; stderr carries `phi`'s own message.
        textureProc.command = ["sh", "-c",
            'out="$3"; mkdir -p "$(dirname "$out")" || exit 1; '
            + 'if [ ! -s "$out" ]; then tmp="$out.$$"; '
            + 'if phi wallpaper texture "$1" --intensity "$2" --out "$tmp"; then mv -f "$tmp" "$out"; else rm -f "$tmp"; fi; fi; '
            + '[ -s "$out" ] && printf "%s" "$out"',
            "gen", root.texture, String(root.textureIntensity), out]
        textureProc.running = true
    }

    Process {
        id: textureProc
        property bool _pending: false
        stderr: StdioCollector { id: textureErr }
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim()
                if (p.length > 0) {
                    root.texturePath = p
                    root.textureError = ""
                } else {
                    root.texturePath = ""
                    var e = textureErr.text.trim().split("\n").filter((s) => s.length > 0)
                    root.textureError = e.length > 0 ? e[e.length - 1]
                        : "could not generate the texture — is `phi` current? (`phi wallpaper texture` ships with the settings overhaul)"
                }
            }
        }
        onExited: {
            textureProc.running = false
            if (textureProc._pending) { textureProc._pending = false; root._generateTexture() }
        }
    }

    function refreshAvailable() { lsProc.running = true }

    Process {
        id: lsProc
        command: ["sh", "-c",
            'ls -1 "$1" 2>/dev/null | grep -iE "\\.(png|jpe?g|webp|bmp|gif)$" | while IFS= read -r f; do printf "%s/%s\\n" "$1" "$f"; done',
            "ls", Config.Paths.wallpaperDir]
        onExited: lsProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n").map((s) => s.trim()).filter((s) => s.length > 0)
                root.available = lines
            }
        }
    }

    Component.onCompleted: {
        Config.Settings.get("wallpaper.color", (v, c) => { if (v) root.color = v })
        Config.Settings.get("wallpaper.path", (v, c) => { if (v) { root.image = v; root.path = v } })
        Config.Settings.get("wallpaper.mode", (v, c) => { if (v) root.mode = v })
        Config.Settings.get("wallpaper.scale", (v, c) => { var n = parseFloat(v); if (!isNaN(n)) root.scale = n })
        Config.Settings.get("wallpaper.texture-intensity", (v, c) => { var n = parseInt(v); if (!isNaN(n)) root.textureIntensity = n })
        Config.Settings.get("wallpaper.texture", (v, c) => { if (v && v.length > 0) { root.texture = v; root._generateTexture() } })
    }
}
