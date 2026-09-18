pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services

// Shared wallpaper state — a per-screen Components/Background.qml surface
// can't own its own IPC or state without colliding across instances (same
// split as Services/Spotlight.qml).
//
// The wallpaper is composited from up to three layers: a solid `color`,
// an optional procedural `texture` overlay (generated once by `phi
// wallpaper texture` and cached), and an optional `image` with a fit
// `mode`. Every value is persisted through `phi state`.
//
// setX() updates the reactive property synchronously (the surface
// repaints at once) and fires `phi state set` underneath fire-and-forget,
// purely for persistence.

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

    // Every image in the wallpaper folder, grouped for the settings picker:
    // [{ name, images: [absolute paths] }] — one section per subfolder,
    // loose files under "General". A subfolder is how a set of static
    // wallpapers is organised; the picker renders the sections as
    // collapsible accordions so a closed group costs nothing while the
    // panel is open. Populated by an `ls` probe (the repo's own
    // dir-listing pattern, Services/Agent.qml), refreshed when the panel
    // opens or a new image is added.
    property var groups: []

    // The image actually painted on the shell surface: while a dynamic
    // wallpaper is driving the wallpaper (Services/DynamicWallpaper.activeNow)
    // it is that service's current entry, otherwise the user's manually
    // picked static image. One source of truth, so the surface, the
    // texture-applies check and the settings all agree on what is shown.
    // Falls back to the static pick whenever the dynamic entry is empty —
    // before its first probe resolves, and whenever the active folder has
    // no matching image — so the wallpaper never blanks for a feature.
    readonly property string displayImage: Services.DynamicWallpaper.activeNow
            && Services.DynamicWallpaper.currentImage.length > 0
        ? Services.DynamicWallpaper.currentImage
        : root.image

    // The texture only means anything when there is no image, or the image
    // does not fully cover the solid colour (contain / repeat leave gaps,
    // where the colour + texture show through). Judged on `displayImage` —
    // the image actually shown — not the static pick, so a covering
    // dynamic image suppresses the grain exactly like a static one.
    readonly property bool textureApplies: root.displayImage.length === 0
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
            'mkdir -p "$1" && for e in "$1"/*; do [ -e "$e" ] || continue; if [ -d "$e" ]; then g=$(basename -- "$e"); for f in "$e"/*; do case "$f" in *.png|*.PNG|*.jpg|*.JPG|*.jpeg|*.JPEG|*.webp|*.WEBP|*.bmp|*.BMP|*.gif|*.GIF) printf "%s\\t%s\\n" "$g" "$f" ;; esac; done; else case "$e" in *.png|*.PNG|*.jpg|*.JPG|*.jpeg|*.JPEG|*.webp|*.WEBP|*.bmp|*.BMP|*.gif|*.GIF) printf "%s\\t%s\\n" "General" "$e" ;; esac; fi; done | sort',
            "ls", Config.Paths.wallpaperDir]
        onExited: lsProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n").map((s) => s.trim()).filter((s) => s.length > 0)
                var grouped = {}
                var order = []
                for (var k = 0; k < lines.length; k++) {
                    var p = lines[k].split("\t")
                    if (p.length < 2 || p[1].length === 0) continue
                    var g = p[0]
                    if (!grouped[g]) { grouped[g] = []; order.push(g) }
                    grouped[g].push(p[1])
                }
                // Loose top-level files become "General" and sit first; the
                // subfolders follow in listing order.
                var out = []
                for (var o = 0; o < order.length; o++) {
                    if (order[o] === "General") continue
                    out.push({ name: order[o], images: grouped[order[o]] })
                }
                if (grouped["General"]) out.unshift({ name: "General", images: grouped["General"] })
                root.groups = out
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
