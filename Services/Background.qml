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
// layers: a solid `color`, an optional procedural `texture` overlay
// (generated once by `phi wallpaper texture` and cached), and an optional
// `image` with a fit `mode`. Every value is persisted through `phi state`
// (the keys were added to internal/state in the same batch). `wallpaper.
// path` is read as the initial `image` for back-compat with S-44.
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

    // Every image in the wallpaper folder, absolute paths — the settings
    // panel's picker grid. Populated by an `ls` probe (the repo's own
    // dir-listing pattern, Services/Agent.qml), refreshed when the panel
    // opens or a new image is added.
    property var available: []

    // The texture only means anything when there is no image, or the image
    // does not fully cover the solid colour (contain / repeat leave gaps,
    // where the colour + texture show through).
    readonly property bool textureApplies: root.image.length === 0
        || (root.mode !== "cover" && root.mode !== "stretch")

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
        if (root.texture.length === 0) {
            root.texturePath = ""
            return
        }
        root._generateTexture()
    }
    function setTextureIntensity(n) { root.setTexture(root.texture, n) }

    function _generateTexture() {
        var out = Config.Paths.texturesDir + "/" + root.texture + "-" + root.textureIntensity + ".png"
        textureProc.command = ["sh", "-c",
            'mkdir -p "$(dirname "$3")"; [ -f "$3" ] || phi wallpaper texture "$1" --intensity "$2" --out "$3"; printf "%s" "$3"',
            "gen", root.texture, String(root.textureIntensity), out]
        textureProc.running = true
    }

    Process {
        id: textureProc
        onExited: textureProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim()
                if (p.length > 0) root.texturePath = p
            }
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
