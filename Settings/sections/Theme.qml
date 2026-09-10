import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Settings/sections/Theme (S-40; OOP-08; Out-of-plan: settings-
// overhaul batches C/D/E). Every variable that is reasonable to change has
// an editable control here, grouped by context (the reference's inner-
// section pattern): Appearance, Colours (first — the user's directive),
// Typography, Shape & spacing, Animations (batch D), Night shift, Cursor
// spotlight, Wallpaper (batch E).
//
// Every editor writes a per-user override through Config/ThemeOverrides.qml
// (a flat JSON file in $XDG_STATE_HOME/phi — never the repo: design/ stays
// the source of the DEFAULTS, I-05). Config/Appearance merges the override
// over the generated Config/Tokens.qml at read time, so a change here is
// live everywhere. Fields commit on Enter / focus-out, not per keystroke.
//
// Colours carry a live "phi theme check": ContrastBadge shells out to the
// new `phi theme contrast <hex> on <bg-0>` verb (batch C) — the one WCAG
// implementation, not a copy in QML — debounced, and only for the pairs
// `phi theme check` itself measures (fg-0/1/2, accent, error/warn/success/
// info vs bg-0).

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: Config.Appearance.space3 * chWidth

    TextMetrics {
        id: ch
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: ch.width
    readonly property real gap: chWidth * Config.Appearance.space2

    property string pendingVariant: Config.Appearance.variant
    readonly property string testString: "0008 iIlL1 g9qCGQ ~ -+=>"

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

    // Rows listen to this to re-seed their fields after "Reset all".
    QtObject {
        id: resetSignal
        signal fired()
    }

    // --- reusable rows ---------------------------------------------------
    component TokenColorRow: SettingsRow {
        id: cr
        property string tokenKey: ""
        property bool showContrast: false
        wide: true
        optionId: "theme.colors." + tokenKey
        resettable: Config.ThemeOverrides.has(tokenKey)
        onReset: { Config.ThemeOverrides.clear(tokenKey); field.value = Config.Appearance.tokenValue(tokenKey) }

        Column {
            width: parent.width
            spacing: 4
            Widgets.ColorField {
                id: field
                value: Config.Appearance.tokenValue(cr.tokenKey)
                onCommitted: (hex) => Config.ThemeOverrides.setValue(cr.tokenKey, hex)
                Connections {
                    target: resetSignal
                    function onFired() { field.value = Config.Appearance.tokenValue(cr.tokenKey) }
                }
            }
            ContrastBadge {
                visible: cr.showContrast
                hex: field.value
            }
        }
    }

    component TokenNumberRow: SettingsRow {
        id: nr
        property string tokenKey: ""
        property real step: 1
        property int decimals: 0
        property string suffix: ""
        property real from: 0
        property real to: 1e6
        optionId: "theme.shape." + tokenKey
        resettable: Config.ThemeOverrides.has(tokenKey)
        onReset: { Config.ThemeOverrides.clear(tokenKey); num.value = nr._seed() }

        function _seed() {
            var s = Config.Appearance.tokenValue(nr.tokenKey)
            var n = parseFloat(s)
            return isNaN(n) ? 0 : n
        }

        Widgets.NumberField {
            id: num
            value: nr._seed()
            step: nr.step
            decimals: nr.decimals
            suffix: nr.suffix
            from: nr.from
            to: nr.to
            onCommitted: (v) => Config.ThemeOverrides.setValue(nr.tokenKey,
                nr.suffix.length > 0 ? (Number(v).toFixed(nr.decimals) + nr.suffix) : String(Number(v).toFixed(nr.decimals)))
            Connections {
                target: resetSignal
                function onFired() { num.value = nr._seed() }
            }
        }
    }

    component TokenFontRow: SettingsRow {
        id: fr
        property string tokenKey: ""
        property string previewFamily: ""
        wide: true
        optionId: "theme.fonts." + tokenKey.replace("font-", "")
        resettable: Config.ThemeOverrides.has(tokenKey)
        onReset: { Config.ThemeOverrides.clear(tokenKey); ff.text = Config.Appearance.tokenValue(tokenKey) }

        Column {
            width: parent.width
            spacing: 6
            Widgets.TextField {
                id: ff
                width: parent.width
                mono: false
                placeholder: "Font family name"
                Component.onCompleted: text = Config.Appearance.tokenValue(fr.tokenKey)
                onCommitted: (t) => Config.ThemeOverrides.setValue(fr.tokenKey, t.trim())
                Connections {
                    target: resetSignal
                    function onFired() { ff.text = Config.Appearance.tokenValue(fr.tokenKey) }
                }
            }
            Widgets.StyledText {
                width: parent.width
                wrapMode: Text.WrapAnywhere
                font.family: fr.previewFamily
                font.pixelSize: Config.Appearance.fontSize2
                text: root.testString
            }
        }
    }

    component ContrastBadge: Row {
        id: badge
        property string hex: ""
        spacing: 6
        property string _ratio: ""
        property string _status: ""

        onHexChanged: debounce.restart()
        Timer {
            id: debounce
            interval: 250
            onTriggered: {
                if (!/^#([0-9a-fA-F]{6})$/.test(badge.hex)) { badge._ratio = ""; badge._status = ""; return }
                contrastProc.command = ["phi", "theme", "contrast", badge.hex, "on",
                    Config.Appearance.tokenValue("bg-0")]
                contrastProc.running = true
            }
        }
        Process {
            id: contrastProc
            onExited: contrastProc.running = false
            stdout: StdioCollector {
                onStreamFinished: {
                    var parts = this.text.trim().split(/\s+/)
                    badge._ratio = parts[0] || ""
                    badge._status = parts[1] || ""
                }
            }
        }
        Widgets.StyledText {
            kind: "label"; sizeStep: 0
            text: badge._ratio.length > 0 ? ("contrast " + badge._ratio + ":1 vs background") : "checking…"
        }
        Widgets.StyledText {
            visible: badge._status.length > 0
            sizeStep: 0
            tone: badge._status === "pass" ? "success" : "error"
            text: badge._status === "pass" ? "AA pass" : "below AA (4.5:1)"
        }
    }

    // --- Appearance ----------------------------------------------------
    SettingsGroup {
        title: "Appearance"
        SettingsRow {
            optionId: "theme.variant"
            title: "Variant"
            description: "Dark and light are permanent, independent variants."
            Row {
                spacing: root.gap
                Widgets.StyledButton { label: "Dark"; active: root.pendingVariant === "dark"; onClicked: root.setVariant("dark") }
                Widgets.StyledButton { label: "Light"; active: root.pendingVariant === "light"; onClicked: root.setVariant("light") }
            }
        }
    }

    // --- Colours (first inner section) -------------------------------
    SettingsGroup {
        title: "Colours"
        caption: "The accent is fine detail only — titles, the keyboard focus ring, the agent's working state. Two structural colours (background, primary text) carry the rest of the shell."

        TokenColorRow { tokenKey: "accent"; title: "Accent"; showContrast: true }
        TokenColorRow { tokenKey: "bg-0"; title: "Background (main)" }
        TokenColorRow { tokenKey: "bg-1"; title: "Surface +1" }
        TokenColorRow { tokenKey: "bg-2"; title: "Surface +2" }
        TokenColorRow { tokenKey: "bg-3"; title: "Surface +3" }
        TokenColorRow { tokenKey: "fg-0"; title: "Text (primary)"; showContrast: true }
        TokenColorRow { tokenKey: "fg-1"; title: "Text, secondary"; showContrast: true }
        TokenColorRow { tokenKey: "fg-2"; title: "Text, muted"; showContrast: true }
        TokenColorRow { tokenKey: "fg-3"; title: "Text, faint" }
        TokenColorRow { tokenKey: "border"; title: "Border" }
        TokenColorRow { tokenKey: "border-strong"; title: "Border, strong" }
        TokenColorRow { tokenKey: "error"; title: "Error"; showContrast: true }
        TokenColorRow { tokenKey: "warn"; title: "Warning"; showContrast: true }
        TokenColorRow { tokenKey: "success"; title: "Success"; showContrast: true }
        TokenColorRow { tokenKey: "info"; title: "Info"; showContrast: true }
    }

    SettingsGroup {
        title: "Colour preview"

        SettingsRow {
            wide: true
            title: "Live preview"
            description: "Rendered from the current overrides."
            Column {
                width: parent.width
                spacing: root.gap
                Row {
                    spacing: root.gap
                    Widgets.StyledButton { label: "Button" }
                    Widgets.StyledButton { label: "Active"; active: true }
                    Widgets.Pill { checked: true }
                    Widgets.Pill { checked: false }
                }
                Widgets.ListRow { width: parent.width; label: "Selected row"; value: "value"; active: true }
                Widgets.ListRow { width: parent.width; label: "Resting row"; value: "value" }
                Row {
                    spacing: root.gap
                    Widgets.StyledText { tone: "error"; text: "error" }
                    Widgets.StyledText { tone: "warn"; text: "warning" }
                    Widgets.StyledText { tone: "success"; text: "success" }
                    Widgets.StyledText { tone: "info"; text: "info" }
                }
            }
        }
    }

    // --- Typography --------------------------------------------------
    SettingsGroup {
        title: "Typography"
        TokenFontRow { tokenKey: "font-mono"; title: "Mono font"; previewFamily: Config.Appearance.fontMono
            description: "Terminal, code, and the whole UI's spacing rhythm (1ch)." }
        TokenFontRow { tokenKey: "font-reading"; title: "Reading font"; previewFamily: Config.Appearance.fontReading
            description: "Long-form prose surfaces." }
        TokenFontRow { tokenKey: "font-ui"; title: "UI font"; previewFamily: Config.Appearance.fontUi
            description: "Labels, buttons, most interface text." }
    }

    // --- Shape & spacing -----------------------------------------
    SettingsGroup {
        title: "Shape & spacing"
        caption: "Scales multiply the whole generated set. Sliders are deliberately not used here — a theme value should be set, not swept."
        TokenNumberRow { tokenKey: "font-scale"; title: "Font scale"; step: 0.05; decimals: 2; from: 0.5; to: 2.0 }
        TokenNumberRow { tokenKey: "space-scale"; title: "Spacing scale"; step: 0.05; decimals: 2; from: 0.5; to: 2.0 }
        TokenNumberRow { tokenKey: "radius-base"; title: "Radius, base"; step: 1; suffix: "px"; from: 0; to: 24 }
        TokenNumberRow { tokenKey: "radius-small"; title: "Radius, small (bar isles)"; step: 1; suffix: "px"; from: 0; to: 24 }
        TokenNumberRow { tokenKey: "radius-large"; title: "Radius, large (runner)"; step: 1; suffix: "px"; from: 0; to: 24 }
    }

    Widgets.StyledButton {
        label: "Reset all theme overrides"
        onClicked: { Config.ThemeOverrides.clearAll(); resetSignal.fired() }
    }

    // --- Night shift ---------------------------------------------
    SettingsGroup {
        title: "Night shift"
        SettingsRow {
            optionId: "theme.nightshift"
            title: "Night shift"
            description: "Warms the display in the evening."
            Widgets.Pill { checked: Services.NightShift.enabled; onToggled: (v) => Services.NightShift.setEnabled(v) }
        }
        SettingsRow {
            title: "True Tone"
            description: Config.Capabilities.ambientLight
                ? "Drive colour temperature from ambient light instead of a fixed value."
                : "No ambient light sensor on this host — True Tone has nothing to read."
            Widgets.Pill {
                checked: Services.NightShift.trueTone
                enabled: Config.Capabilities.ambientLight
                onToggled: (v) => Services.NightShift.setTrueTone(v)
            }
        }
        SettingsRow {
            title: "Target temperature"
            description: "Used when True Tone is off."
            Widgets.NumberField {
                value: Services.NightShift.targetTemp
                step: 250; suffix: "K"; from: 2500; to: 6500
                onCommitted: (v) => Services.NightShift.setTemp(Math.round(v))
            }
        }
    }

    // --- Cursor spotlight --------------------------------------
    SettingsGroup {
        title: "Cursor spotlight"
        SettingsRow {
            optionId: "theme.spotlight"
            title: "Cursor spotlight"
            description: "A vignette that follows the pointer. Hold Super+G elsewhere; this toggle is sticky."
            Widgets.Pill {
                checked: Services.Spotlight.shown
                onToggled: (v) => (v ? Services.Spotlight.show() : Services.Spotlight.hide())
            }
        }
        SettingsRow {
            title: "Size"
            Row {
                spacing: root.gap
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
        }
    }

    // --- Wallpaper (settings-overhaul batch D) ------------------
    SettingsGroup {
        title: "Wallpaper"
        Component.onCompleted: Services.Background.refreshAvailable()

        SettingsRow {
            optionId: "theme.wallpaper.color"
            title: "Solid colour"
            description: "The base layer — always visible where an image does not cover the screen."
            wide: true
            Widgets.ColorField {
                value: Services.Background.color
                onCommitted: (hex) => Services.Background.setColor(hex)
            }
        }

        SettingsRow {
            optionId: "theme.wallpaper.image"
            title: "Image"
            description: "Pick from the wallpaper folder, or add one from a path (it is copied into the folder and selected). Any image is allowed."
            wide: true
            Column {
                width: parent.width
                spacing: root.gap

                Flow {
                    width: parent.width
                    spacing: 6

                    Rectangle {
                        width: root.chWidth * 12; height: root.chWidth * 8
                        radius: Config.Appearance.radiusSmall
                        color: Config.Appearance.surface1
                        border.width: Config.Appearance.borderWidth
                        border.color: Services.Background.image.length === 0
                            ? Config.Appearance.accent : Config.Appearance.border
                        Widgets.StyledText { anchors.centerIn: parent; kind: "label"; sizeStep: 0; text: "none" }
                        TapHandler { onTapped: Services.Background.clearImage() }
                    }

                    Repeater {
                        model: Services.Background.available
                        Rectangle {
                            required property string modelData
                            width: root.chWidth * 12; height: root.chWidth * 8
                            radius: Config.Appearance.radiusSmall
                            color: Config.Appearance.surface1
                            clip: true
                            border.width: Config.Appearance.borderWidth
                            border.color: Services.Background.image === modelData
                                ? Config.Appearance.accent : Config.Appearance.border
                            Image {
                                anchors.fill: parent
                                anchors.margins: Config.Appearance.borderWidth
                                source: "file://" + modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 256
                            }
                            TapHandler { onTapped: Services.Background.setImage(modelData) }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: root.gap
                    Widgets.TextField {
                        id: wpPath
                        width: parent.width - addBtn.implicitWidth - openBtn.implicitWidth - root.gap * 2
                        mono: false
                        placeholder: "Path to an image…"
                        onCommitted: root._addWallpaper(text)
                    }
                    Widgets.StyledButton { id: addBtn; label: "Add"; onClicked: root._addWallpaper(wpPath.text) }
                    Widgets.StyledButton {
                        id: openBtn
                        label: "Open folder"
                        onClicked: Quickshell.execDetached(["xdg-open", Config.Paths.wallpaperDir])
                    }
                }
            }
        }

        SettingsRow {
            optionId: "theme.wallpaper.mode"
            title: "Fit mode"
            enabled: Services.Background.image.length > 0
            Row {
                spacing: 6
                Repeater {
                    model: ["cover", "contain", "stretch", "repeat"]
                    Widgets.StyledButton {
                        required property string modelData
                        label: modelData
                        active: Services.Background.mode === modelData
                        onClicked: Services.Background.setMode(modelData)
                    }
                }
            }
        }

        SettingsRow {
            optionId: "theme.wallpaper.scale"
            title: "Scale"
            description: "Zoom for contain and repeat; ignored for cover and stretch."
            enabled: Services.Background.image.length > 0
                && (Services.Background.mode === "contain" || Services.Background.mode === "repeat")
            Widgets.NumberField {
                value: Services.Background.scale
                step: 0.1; decimals: 1; from: 0.1; to: 4.0
                onCommitted: (v) => Services.Background.setScale(v)
            }
        }

        SettingsRow {
            optionId: "theme.wallpaper.texture"
            title: "Texture"
            description: Services.Background.textureApplies
                ? "A generated grain added over the solid colour. Generated once, not at runtime."
                : "Available only when there is no image, or the image is contain / repeat."
            enabled: Services.Background.textureApplies
            wide: true
            Column {
                width: parent.width
                spacing: root.gap
                Flow {
                    width: parent.width
                    spacing: 6
                    Widgets.StyledButton {
                        label: "none"
                        active: Services.Background.texture.length === 0
                        onClicked: Services.Background.setTexture("", Services.Background.textureIntensity)
                    }
                    Repeater {
                        model: Config.Appearance.textureModes
                        Widgets.StyledButton {
                            required property string modelData
                            label: modelData
                            active: Services.Background.texture === modelData
                            onClicked: Services.Background.setTexture(modelData, Services.Background.textureIntensity)
                        }
                    }
                }
                Row {
                    width: parent.width
                    spacing: root.gap
                    visible: Services.Background.texture.length > 0
                    Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "Intensity" }
                    Widgets.Meter {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 14 * root.chWidth
                        interactive: true
                        value: Services.Background.textureIntensity / 100
                        onReleased: (v) => Services.Background.setTextureIntensity(Math.round(v * 100))
                    }
                    Widgets.StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        mono: true; text: Services.Background.textureIntensity + "%"
                    }
                }
            }
        }
    }

    function _addWallpaper(srcPath) {
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
                Services.Background.setImage(dest)
                Services.Background.refreshAvailable()
            }
        }
    }
}
