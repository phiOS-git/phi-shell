import QtQuick
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import ".." as SettingsRoot

// phiOS — Settings/sections/Theme (S-40, master plan §9.12): "toggle
// chiaro/scuro live con anteprima doppia · night shift · True Tone se
// sbloccata · spotlight cursore · sfondo. L'accento è fisso: nessun
// controllo." Variant switching runs `phi theme set <variant>` directly
// (S-12's own verb, already idempotent and already the renderer of
// record) — this section is a thin trigger over it, not a second
// implementation of theme application.
//
// Night shift / True Tone / spotlight size / wallpaper: this step only
// wires the CONTROLS to their phi state keys (S-40's own perimeter). The
// processes that actually act on those keys — hyprsunset, the spotlight
// overlay, the wallpaper copy-and-set flow — are S-42/S-43/S-44's own
// work, flagged inline via StateToggleRow's backendPending and the plain-
// text notes below.

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
    property string nightTemp: "…"
    property string spotlightSize: "…"
    property string wallpaperPath: "…"

    Component.onCompleted: {
        Config.Settings.get("nightmode.temp", (v, code) => root.nightTemp = v || "4500")
        Config.Settings.get("spotlight.size", (v, code) => root.spotlightSize = v || "medium")
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

    // --- Night shift / True Tone -----------------------------------------
    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Night shift" }
    SettingsRoot.StateToggleRow {
        label: "Night shift"
        stateKey: "toggle.night-mode"
        backendPending: true
        helpText: "Warms the display in the evening (hyprsunset)."
    }
    SettingsRoot.StateToggleRow {
        // Only meaningful once an ALS was confirmed (S-06: razer's
        // iio:device0, name "als"). Rendered regardless of host so the
        // control is not silently absent on a machine where a sensor
        // might later exist — but flagged, since zotac/mini are known to
        // have none right now.
        label: "True Tone (drive from ambient light instead of a fixed schedule)"
        stateKey: "toggle.true-tone"
        backendPending: true
    }
    Row {
        spacing: Config.Appearance.space2 * chWidth
        // No text-entry widget exists yet in this library (S-21's own
        // inventory has none) — stepping by a fixed amount is the only
        // input this step can offer without inventing one. AWAITING a real
        // numeric field.
        function step(delta) {
            const next = String(Math.max(2500, Math.min(6500, parseInt(root.nightTemp || "4500") + delta)))
            root.nightTemp = next
            Config.Settings.set("nightmode.temp", next)
        }
        Widgets.StyledText {
            anchors.verticalCenter: parent.verticalCenter
            kind: "label"
            text: "Target temperature (K), used when True Tone is off"
        }
        Widgets.StyledButton { label: "−500"; onClicked: parent.step(-500) }
        Widgets.StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.nightTemp + "K"
        }
        Widgets.StyledButton { label: "+500"; onClicked: parent.step(500) }
    }

    // --- Spotlight ---------------------------------------------------
    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Cursor spotlight" }
    SettingsRoot.StateToggleRow {
        label: "Cursor spotlight"
        stateKey: "toggle.spotlight"
        backendPending: true
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
                active: root.spotlightSize === modelData
                onClicked: {
                    root.spotlightSize = modelData
                    Config.Settings.set("spotlight.size", modelData)
                }
            }
        }
    }

    // --- Wallpaper (S-44) ---------------------------------------------
    Widgets.StyledText { kind: "label"; sizeStep: 3; text: "Wallpaper" }
    Widgets.ListRow {
        width: parent.width
        label: "Current wallpaper"
        value: root.wallpaperPath
    }
    Widgets.StyledText {
        kind: "label"; sizeStep: 0
        text: "A picker is not built yet (S-44) — set with: phi state set wallpaper.path <path>"
    }
}
