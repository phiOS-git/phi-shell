import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Theme (S-40; OOP-08 restyle). The user's
// directive: "All variables that are reasonable to change should have an
// editable setting in the theme section... The accent color should be the
// main one, then fonts, font sizes, spacings, radiuses, color palette."
//
// Every editor writes a per-user override through Config/ThemeOverrides.qml
// (a flat JSON file in $XDG_STATE_HOME/phi — never the repo: design/ stays
// the source of the DEFAULTS, I-05). Config/Appearance merges the override
// over the generated Config/Tokens.qml at read time, so a change here is
// live everywhere. `phi theme set` regenerating the tokens does not clear
// the file; the user accepted that an update can supersede an override.
// `phi theme check`'s contrast verification does NOT see an overridden
// colour — a development-time trade-off, flagged.
//
// Fields seed from Config.Appearance.tokenValue(key) on load and apply on
// editingFinished (Enter or focus-out), not per keystroke — a half-typed
// hex should not repaint the shell. Each row has a reset that clears just
// that key; "Reset all" clears every override.
//
// Variant (dark/light), Night shift, Spotlight and Wallpaper stay here —
// they are theme state too, and were here before. Night shift / True Tone
// are also reachable from the notification panel now (OOP-06); both points
// call the same Services/NightShift.

// OOP-09: a Column, not a Flickable. Every other Settings section is a
// Column and the panel's own content pane (Settings/Settings.qml) is the
// Flickable that scrolls them — a Flickable rooted here has implicitHeight
// 0 inside that outer Loader, which is why this section rendered blank.
Column {
    id: root
    width: parent ? parent.width : 0
    spacing: root.gap

    TextMetrics {
        id: ch
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2
    readonly property real labelW: chWidth * 22
    readonly property real fieldW: chWidth * 20

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

    // Editable token groups. `kind`: "color" shows a swatch, "text" a plain
    // field (font family / number).
    readonly property var groupAccent: [
        { key: "accent", label: "Accent", kind: "color" }
    ]
    readonly property var groupPalette: [
        { key: "bg-0", label: "Background (main)", kind: "color" },
        { key: "bg-1", label: "Surface +1", kind: "color" },
        { key: "bg-2", label: "Surface +2", kind: "color" },
        { key: "bg-3", label: "Surface +3", kind: "color" },
        { key: "fg-0", label: "Text (opposite)", kind: "color" },
        { key: "fg-1", label: "Text, secondary", kind: "color" },
        { key: "fg-2", label: "Text, muted", kind: "color" },
        { key: "fg-3", label: "Text, faint", kind: "color" },
        { key: "border", label: "Border", kind: "color" },
        { key: "border-strong", label: "Border, strong", kind: "color" },
        { key: "error", label: "Error", kind: "color" },
        { key: "warn", label: "Warning", kind: "color" },
        { key: "success", label: "Success", kind: "color" },
        { key: "info", label: "Info", kind: "color" }
    ]
    readonly property var groupType: [
        { key: "font-mono", label: "Mono font", kind: "text" },
        { key: "font-reading", label: "Reading font", kind: "text" },
        { key: "font-ui", label: "UI font", kind: "text" },
        { key: "font-scale", label: "Font scale (×)", kind: "text" }
    ]
    readonly property var groupShape: [
        { key: "space-scale", label: "Spacing scale (×)", kind: "text" },
        { key: "radius-base", label: "Radius, base", kind: "text" },
        { key: "radius-small", label: "Radius, small", kind: "text" },
        { key: "radius-large", label: "Radius, large (runner)", kind: "text" }
    ]

        // --- Variant ----------------------------------------------------
        Widgets.StyledText { kind: "title"; sizeStep: 3; text: "Appearance" }
        Row {
            spacing: root.gap
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

        // --- Accent ---------------------------------------------------
        Widgets.StyledText { kind: "title"; sizeStep: 3; topPadding: root.gap; text: "Accent" }
        Widgets.StyledText {
            kind: "label"; sizeStep: 0; width: parent.width; wrapMode: Text.WordWrap
            text: "The one colour used for fine detail — titles, the focus ring, the agent's working state."
        }
        Repeater { model: root.groupAccent; delegate: tokenRow }

        // --- Palette ------------------------------------------------
        Widgets.StyledText { kind: "title"; sizeStep: 3; topPadding: root.gap; text: "Palette" }
        Repeater { model: root.groupPalette; delegate: tokenRow }

        // --- Typography -------------------------------------------
        Widgets.StyledText { kind: "title"; sizeStep: 3; topPadding: root.gap; text: "Typography" }
        Repeater { model: root.groupType; delegate: tokenRow }

        // --- Shape & spacing --------------------------------------
        Widgets.StyledText { kind: "title"; sizeStep: 3; topPadding: root.gap; text: "Shape & spacing" }
        Repeater { model: root.groupShape; delegate: tokenRow }

        Item { width: 1; height: root.gap }
        Widgets.StyledButton {
            label: "Reset all overrides"
            onClicked: {
                Config.ThemeOverrides.clearAll()
                resetSignal.fired()
            }
        }
        // Rows listen to this to re-seed their fields after "Reset all".
        QtObject {
            id: resetSignal
            signal fired()
        }

        // --- Night shift (also in the notification panel) ------------
        Widgets.StyledText { kind: "title"; sizeStep: 3; topPadding: root.gap; text: "Night shift" }
        Widgets.ToggleRow {
            width: parent.width
            label: "Night shift (warms the display in the evening)"
            checked: Services.NightShift.enabled
            onToggled: (v) => Services.NightShift.setEnabled(v)
        }
        Widgets.ToggleRow {
            width: parent.width
            label: "True Tone (drive from ambient light instead of a fixed temperature)"
            checked: Services.NightShift.trueTone
            onToggled: (v) => Services.NightShift.setTrueTone(v)
        }
        Widgets.StyledText {
            visible: !Config.Capabilities.ambientLight
            kind: "label"; sizeStep: 0
            text: "No ambient light sensor on this host — True Tone will have nothing to read."
        }
        Row {
            spacing: root.chWidth * Config.Appearance.space2
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

        // --- Spotlight ----------------------------------------------
        Widgets.StyledText { kind: "title"; sizeStep: 3; topPadding: root.gap; text: "Cursor spotlight" }
        Widgets.ToggleRow {
            width: parent.width
            label: "Cursor spotlight (hold Super+G elsewhere; click toggles here)"
            checked: Services.Spotlight.shown
            onToggled: (v) => (v ? Services.Spotlight.show() : Services.Spotlight.hide())
        }
        Row {
            spacing: root.chWidth * Config.Appearance.space2
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

        // --- Lock screen ------------------------------------------
        // OOP-35: the ambient backdrop behind the lock screen. Stored in
        // Config/LockPrefs.qml ($XDG_STATE_HOME/phi/lock.json), read by
        // Lock/Lock.qml. Not a design token — runtime UI state, same
        // category as the spotlight size above.
        Widgets.StyledText { kind: "title"; sizeStep: 3; topPadding: root.gap; text: "Lock screen effect" }
        Row {
            spacing: root.chWidth * Config.Appearance.space2
            Repeater {
                model: [
                    { key: "none", label: "None" },
                    { key: "lava", label: "Lava lamp" },
                    { key: "matrix", label: "Matrix" },
                    { key: "starfield", label: "Starfield" }
                ]
                Widgets.StyledButton {
                    required property var modelData
                    label: modelData.label
                    active: Config.LockPrefs.effect === modelData.key
                    onClicked: Config.LockPrefs.setEffect(modelData.key)
                }
            }
        }

        // --- Wallpaper --------------------------------------------
        Widgets.StyledText { kind: "title"; sizeStep: 3; topPadding: root.gap; text: "Wallpaper" }
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
            kind: "label"; sizeStep: 0; wrapMode: Text.WordWrap; width: parent.width
            text: "No native file browser — paste a path. Wireframe/technical grid or flat gradient only (style plan), never photographic."
        }

    function _setWallpaper(srcPath) {
        let p = (srcPath || "").trim()
        if (p.length === 0) return
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

    // --- one editable token row -------------------------------------
    Component {
        id: tokenRow

        Item {
            id: rowItem
            required property var modelData
            width: root.width
            height: Math.max(field.implicitHeight, rowLabel.implicitHeight)
                + root.chWidth * Config.Appearance.space1

            readonly property bool overridden: Config.ThemeOverrides.has(modelData.key)

            function seed() { field.text = Config.Appearance.tokenValue(rowItem.modelData.key) }
            Component.onCompleted: seed()

            Connections {
                target: resetSignal
                function onFired() { rowItem.seed() }
            }

            Widgets.StyledText {
                id: rowLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.labelW
                kind: "label"
                text: rowItem.modelData.label
                elide: Text.ElideRight
            }

            Rectangle {
                id: swatch
                visible: rowItem.modelData.kind === "color"
                anchors.left: rowLabel.right
                anchors.verticalCenter: parent.verticalCenter
                width: rowItem.height * 0.6
                height: width
                radius: Config.Appearance.radiusSmall
                border.width: Config.Appearance.borderWidth
                border.color: Config.Appearance.border
                color: {
                    const v = Config.Appearance.tokenValue(rowItem.modelData.key)
                    return (v && v.length >= 4) ? v : "transparent"
                }
            }

            Rectangle {
                id: fieldBox
                anchors.left: swatch.visible ? swatch.right : rowLabel.right
                anchors.leftMargin: root.chWidth
                anchors.verticalCenter: parent.verticalCenter
                width: root.fieldW
                height: field.implicitHeight + root.chWidth
                radius: Config.Appearance.radiusBase
                color: "transparent"
                border.width: Config.Appearance.borderWidth
                border.color: field.activeFocus ? Config.Appearance.accent : Config.Appearance.border

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: root.chWidth / 2
                    anchors.rightMargin: root.chWidth / 2
                    verticalAlignment: Text.AlignVCenter
                    clip: true
                    font.family: Config.Appearance.fontMono
                    font.pixelSize: Config.Appearance.fontSize1
                    color: Config.Appearance.textPrimary
                    onEditingFinished: Config.ThemeOverrides.setValue(rowItem.modelData.key, text.trim())
                }
            }

            Widgets.StyledText {
                anchors.left: fieldBox.right
                anchors.leftMargin: root.chWidth
                anchors.verticalCenter: parent.verticalCenter
                kind: "label"
                sizeStep: 0
                text: rowItem.overridden ? "reset" : ""
                visible: rowItem.overridden

                TapHandler {
                    onTapped: {
                        Config.ThemeOverrides.clear(rowItem.modelData.key)
                        rowItem.seed()
                    }
                }
            }
        }
    }
}
