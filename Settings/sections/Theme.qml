import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Theme (S-40, master plan §9.12): "toggle
// chiaro/scuro live con anteprima doppia · night shift · True Tone se
// sbloccata · spotlight cursore · sfondo. L'accento è fisso: nessun
// controllo." Variant switching runs `phi theme set <variant>` directly
// (S-12's own verb, already idempotent and already the renderer of
// record) — this section is a thin trigger over it, not a second
// implementation of theme application.
//
// Night shift / True Tone (S-42) and Spotlight (S-43, revised after real-
// hardware verification) all follow the same shape: a Services/*.qml file
// owns the state and does the work, this section only reads it and calls
// its setters — not Config.Settings directly, so there is one place each
// value lives, not two racing copies. Wallpaper is still only wired to its
// phi state key (S-40's own perimeter) — S-44's own work, flagged inline.
//
// "Anteprima doppia" (§9.12) is read here as both options presented
// together with an immediate live switch, not a simultaneous side-by-side
// swatch render of the INACTIVE variant's palette: Config.Appearance only
// ever exposes the currently active variant (Config/Tokens.qml is
// generated for one variant at a time, S-20's own contract), so a true
// dual-swatch preview would need a second, parallel token load this step
// does not build. Flagged as a deliberate scope narrowing, not a silent
// one.

Column {
    id: root
    width: parent.width
    spacing: Config.Appearance.space3 * chWidth

    TextMetrics {
        id: chMetricsLocal
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetricsLocal.width

    property string pendingVariant: Config.Appearance.variant
    property string wallpaperPath: "…"

    Component.onCompleted: {
        Config.Settings.get("wallpaper.path", (v, code) => root.wallpaperPath = v || "(unset)")
    }

    function setVariant(v) {
        root.pendingVariant = v
        setProc.command = ["phi", "theme", "set", v]
        setProc.running = true
    }

    Process {
        id: setProc
        onExited: (exitCode) => {
            setProc.running = false
            if (exitCode !== 0) console.warn("phi-shell: phi theme set failed, exit " + exitCode)
        }
    }

    // --- Variant, dual preview ------------------------------------------
    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Appearance" }
    Row {
        spacing: Config.Appearance.space3 * chWidth

        Widgets.StyledButton {
            label: "Dark"
            active: root.pendingVariant === "dark"
            onClicked: root.setVariant("dark")
        }
        Widgets.StyledButton {
            label: "Light"
            active: root.pendingVariant === "light"
            onClicked: root.setVariant("light")
        }
    }
    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        text: "The accent colour is fixed by the design system — no control here (§9.12)."
    }

    // --- Night shift / True Tone (S-42) -----------------------------------
    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Night shift" }
    Widgets.ToggleRow {
        width: parent.width
        label: "Night shift (warms the display in the evening)"
        checked: Services.NightShift.enabled
        onToggled: (v) => Services.NightShift.setEnabled(v)
    }
    // Only meaningful once an ALS was confirmed (S-06: razer's
    // iio:device0, name "als"). Rendered regardless of host so the
    // control is not silently absent on a machine where a sensor might
    // later exist — but flagged, since zotac/mini are known to have none
    // right now (Config.Capabilities.ambientLight false).
    Widgets.ToggleRow {
        width: parent.width
        label: "True Tone (drive from ambient light instead of a fixed temperature)"
        checked: Services.NightShift.trueTone
        onToggled: (v) => Services.NightShift.setTrueTone(v)
    }
    Widgets.StyledText {
        visible: !Config.Capabilities.ambientLight
        kind: "label"; sizeStep: 0
        text: "No ambient light sensor detected on this host — True Tone will have nothing to read."
    }
    Row {
        spacing: Config.Appearance.space2 * chWidth
        // No text-entry widget exists yet in this library (S-21's own
        // inventory has none) — stepping by a fixed amount is the only
        // input this step can offer without inventing one. AWAITING a real
        // numeric field.
        Widgets.StyledText {
            anchors.verticalCenter: parent.verticalCenter
            kind: "label"
            text: "Target temperature (K), used when True Tone is off"
        }
        Widgets.StyledButton { label: "−500"; onClicked: Services.NightShift.setTemp(Math.max(2500, Services.NightShift.targetTemp - 500)) }
        Widgets.StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Services.NightShift.targetTemp + "K"
        }
        Widgets.StyledButton { label: "+500"; onClicked: Services.NightShift.setTemp(Math.min(6500, Services.NightShift.targetTemp + 500)) }
    }

    // --- Spotlight (S-43, revised after real-hardware round: both the
    // toggle and the size buttons here now call Services/Spotlight.qml
    // directly instead of writing an inert phi state key nothing read
    // live — same fix shape as Night shift/True Tone got at S-42, applied
    // here because the first round found it was never actually done for
    // spotlight). Daily use is Super+G HELD (hyprland.lua) — a bare-Super
    // tap-count gesture was tried at rounds 4/5 and reverted at round 6
    // (confirmed Hyprland compositor bug, release never fires for a bare
    // modifier bind) — not a click; this button stays a plain
    // click-to-show/hide for mouse-driven testing, since StyledButton has
    // no press/release distinction to give it the same hold gesture the
    // keybind has. ------------------------------------------------------
    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Cursor spotlight" }
    Widgets.ToggleRow {
        width: parent.width
        label: "Cursor spotlight (hold Super+G elsewhere; click toggles here)"
        checked: Services.Spotlight.shown
        onToggled: (v) => (v ? Services.Spotlight.show() : Services.Spotlight.hide())
    }
    Row {
        spacing: Config.Appearance.space2 * chWidth
        Widgets.StyledText {
            anchors.verticalCenter: parent.verticalCenter
            kind: "label"
            text: "Size"
        }
        Repeater {
            model: ["small", "medium", "large"]
            Widgets.StyledButton {
                required property string modelData
                label: modelData
                active: Services.Spotlight.size === modelData
                onClicked: Services.Spotlight.setSize(modelData)
            }
        }
    }

    // --- Wallpaper (S-44) ---------------------------------------------
    // No native file-browser dialog is confirmed available in this
    // Quickshell/layer-shell stack from here — a "selezione" (§9.12) that
    // asks for a typed/pasted path, not a visual browser. "Set" copies the
    // file into $XDG_DATA_HOME/phi/wallpapers/ (never referencing the
    // original) and only then writes wallpaper.path — the copy-before-set
    // ordering is what stops Background/Background.qml from ever briefly
    // pointing at a path outside that directory.
    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Wallpaper" }
    Widgets.ListRow {
        width: parent.width
        label: "Current wallpaper"
        value: root.wallpaperPath
    }
    Column {
        width: parent.width
        spacing: 0
        Item {
            width: parent.width
            height: wallpaperInput.implicitHeight
            Widgets.StyledText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: wallpaperInput.text.length === 0
                kind: "label"
                text: "Path to an image…"
            }
            TextInput {
                id: wallpaperInput
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: Config.Appearance.textPrimary
                font.family: Config.Appearance.fontUi
                font.pixelSize: Config.Appearance.fontSize1
            }
        }
        Widgets.Separator { width: parent.width }
    }
    Widgets.StyledButton {
        label: "Set"
        onClicked: root._setWallpaper(wallpaperInput.text)
    }
    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        text: "No native file browser — paste a path. Wireframe/technical grid or flat gradient only (style plan), never photographic (not enforced here, a human judgement call)."
        wrapMode: Text.WordWrap
        width: parent.width
    }

    function _setWallpaper(srcPath) {
        let p = (srcPath || "").trim()
        if (p.length === 0) return
        // "~/Downloads/x.jpg" didn't work, "Downloads/x.jpg" did (real-
        // hardware feedback) — because `$2` is a positional PARAMETER
        // value, not source text the shell tokenizes, and tilde expansion
        // only happens for an unquoted token written directly in shell
        // syntax. Expanded here instead, in QML, before the path ever
        // reaches the shell — a relative path (the "did work" case) is
        // untouched, cp already resolves that against the process's own
        // cwd correctly.
        if (p === "~" || p.startsWith("~/")) {
            const home = Quickshell.env("HOME") || ""
            p = home + p.slice(1)
        }
        wallpaperCopyProc.command = ["sh", "-c",
            'mkdir -p "$1" && cp -- "$2" "$1/$(basename -- "$2")" && printf "%s" "$1/$(basename -- "$2")"',
            "copy", Config.Paths.wallpaperDir, p]
        wallpaperCopyProc.running = true
    }

    Process {
        id: wallpaperCopyProc
        onExited: wallpaperCopyProc.running = false
        stdout: StdioCollector {
            onStreamFinished: {
                const dest = this.text.trim()
                if (dest.length === 0) return
                root.wallpaperPath = dest
                Services.Background.setPath(dest)
            }
        }
    }
}
