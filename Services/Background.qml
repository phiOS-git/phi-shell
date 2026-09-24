pragma Singleton
import QtQml
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services

// Shared wallpaper state: solid color, optional procedural texture overlay,
// optional image. Composited from three layers; every value persisted through
// phi state. setX() updates synchronously and persists via fire-and-forget.

Singleton {
    id: root

    // Legacy single-string API (maps to image); kept for backward compat.
    property string path: ""

    property string color: "#000000"
    property string image: ""
    property string mode: "cover"        // cover | contain | stretch | repeat
    property real scale: 1.0
    property string texture: ""           // "" or a phi wallpaper texture mode
    property int textureIntensity: 40
    property string texturePath: ""       // cached PNG, "" until generated

    // Every wallpaper image grouped for the picker: [{ name, images: [...] }].
    // One section per subfolder; loose files grouped under "General".
    // Populated by ls probe; refreshed when panel opens or image added.
    property var groups: []

    // Wallpaper folder's loose top-level files (not shown as "General"
    // section, only subfolders).
    readonly property var rootImages: {
        for (var i = 0; i < root.groups.length; i++)
            if (root.groups[i].name === "General") return root.groups[i].images
        return []
    }

    // Image shown: dynamic wallpaper's current entry, else static pick. One
    // source of truth; falls back to static when dynamic empty or missing,
    // but not while battery saver has only frozen it.
    readonly property string displayImage: Services.DynamicWallpaper.painting
            && Services.DynamicWallpaper.currentImage.length > 0
        ? Services.DynamicWallpaper.currentImage
        : root.image

    // Texture applies when no image or image doesn't cover (contain/repeat).
    // Judged on displayImage so covering dynamic image suppresses grain.
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

    // Generate texture PNG or cache if already exists.
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
                // Loose files as "General" first; subfolders follow.
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
