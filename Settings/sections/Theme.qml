import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "options.js" as Options

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

    // OOP-54: the token key whose ColorChip editor is currently open. One
    // at a time across every colour sub-group, so the palette stays a grid
    // of swatches and only the one being edited grows to a full row.
    property string _openColor: ""

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

    // OOP-54: one entry in a colour sub-group's Flow. Collapsed it is a
    // compact swatch + name + hex; tapped (or revealed by search) it grows
    // to a full-width row carrying the ColorField editor, the contrast
    // badge and a reset. `root._openColor` keeps exactly one chip open
    // across every sub-group. Registers its `theme.colors.<key>` optionId
    // with Services/SettingsPanel like a SettingsRow, so search reveal
    // still lands on an individual colour.
    component ColorFlow: Flow {
        width: parent ? parent.width : 0
        spacing: root.chWidth
    }

    component ColorChip: Column {
        id: chip
        property string tokenKey: ""
        property string label: ""
        property bool showContrast: false

        readonly property string optionId: "theme.colors." + chip.tokenKey
        readonly property bool expanded: root._openColor === chip.tokenKey
        readonly property string _hex: Config.Appearance.tokenValue(chip.tokenKey)
        readonly property bool _valid: /^#([0-9a-fA-F]{6})$/.test(chip._hex)
        readonly property bool _overridden: Config.ThemeOverrides.has(chip.tokenKey)
        readonly property bool _highlighted: Services.SettingsPanel.shown
            && Services.SettingsPanel.query.length > 0
            && Options.matches(chip.optionId, Services.SettingsPanel.query)

        width: chip.expanded && parent ? parent.width : Math.round(root.chWidth * 24)
        spacing: 4

        Component.onCompleted: Services.SettingsPanel.registerRow(chip.optionId, chip)
        Component.onDestruction: Services.SettingsPanel.unregisterRow(chip.optionId)
        function pulse() { root._openColor = chip.tokenKey; pulseAnim.restart() }

        Rectangle {
            id: chipHeader
            width: parent.width
            height: hdr.implicitHeight + root.chWidth
            radius: Config.Appearance.radiusSmall
            color: chip.expanded ? Config.Appearance.surface1 : "transparent"
            Behavior on color {
                ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Config.Appearance.accent
                opacity: chip._highlighted && !chip.expanded ? 0.12 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
            }
            Rectangle {
                id: pulseRect
                anchors.fill: parent
                radius: parent.radius
                color: Config.Appearance.accent
                opacity: 0
                SequentialAnimation {
                    id: pulseAnim
                    NumberAnimation { target: pulseRect; property: "opacity"; to: 0.28; duration: Config.Appearance.motionBDuration; easing.type: Easing.OutQuad }
                    NumberAnimation { target: pulseRect; property: "opacity"; to: 0; duration: Config.Appearance.motionBDuration * 3; easing.type: Easing.InQuad }
                }
            }

            Row {
                id: hdr
                anchors.left: parent.left
                anchors.leftMargin: root.chWidth
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.chWidth

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(Config.Appearance.fontSize2 * 1.4)
                    height: width
                    radius: Config.Appearance.radiusSmall
                    color: chip._valid ? chip._hex : "transparent"
                    border.width: Config.Appearance.borderWidth
                    border.color: Config.Appearance.border
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Widgets.StyledText { text: chip.label }
                    Widgets.StyledText {
                        kind: "label"
                        sizeStep: 0
                        mono: true
                        text: chip._hex + (chip._overridden ? "  ·edited" : "")
                    }
                }
            }

            TapHandler {
                onTapped: root._openColor = chip.expanded ? "" : chip.tokenKey
            }
        }

        Column {
            visible: chip.expanded
            width: parent.width - root.chWidth
            x: root.chWidth
            spacing: 6

            Widgets.ColorField {
                id: field
                width: parent.width
                value: Config.Appearance.tokenValue(chip.tokenKey)
                onCommitted: (hex) => Config.ThemeOverrides.setValue(chip.tokenKey, hex)
                Connections {
                    target: resetSignal
                    function onFired() { field.value = Config.Appearance.tokenValue(chip.tokenKey) }
                }
            }
            ContrastBadge {
                visible: chip.showContrast
                hex: field.value
            }
            Widgets.StyledText {
                visible: chip._overridden
                kind: "label"
                sizeStep: 0
                text: "reset to default"
                TapHandler {
                    onTapped: {
                        Config.ThemeOverrides.clear(chip.tokenKey)
                        field.value = Config.Appearance.tokenValue(chip.tokenKey)
                    }
                }
            }
        }
    }

    // one motion-duration override row (category period / step / duration)
    component MotionRow: SettingsRow {
        id: mr
        property string mkey: ""
        property int seedMs: 0
        resettable: Config.ThemeOverrides.has(mkey)
        onReset: { Config.ThemeOverrides.clear(mkey); mnum.value = mr.seedMs }
        Widgets.NumberField {
            id: mnum
            value: mr.seedMs
            step: 20; suffix: "ms"; from: 0; to: 4000
            onCommitted: (v) => Config.ThemeOverrides.setValue(mr.mkey, Math.round(v) + "ms")
            Connections { target: resetSignal; function onFired() { mnum.value = mr.seedMs } }
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
    // OOP-54: grouped by context and laid out as a Flow of swatches, more
    // than one per row. Editing one grows it to a full-width row in place
    // (see ColorChip / root._openColor).
    SettingsGroup {
        title: "Colours — structure"
        caption: "Two structural colours (background, primary text) carry the whole shell; the surfaces step up from the background for stacked panels."
        ColorFlow {
            ColorChip { tokenKey: "bg-0"; label: "Background" }
            ColorChip { tokenKey: "bg-1"; label: "Surface +1" }
            ColorChip { tokenKey: "bg-2"; label: "Surface +2" }
            ColorChip { tokenKey: "bg-3"; label: "Surface +3" }
        }
    }

    SettingsGroup {
        title: "Colours — text"
        ColorFlow {
            ColorChip { tokenKey: "fg-0"; label: "Text (primary)"; showContrast: true }
            ColorChip { tokenKey: "fg-1"; label: "Text, secondary"; showContrast: true }
            ColorChip { tokenKey: "fg-2"; label: "Text, muted"; showContrast: true }
            ColorChip { tokenKey: "fg-3"; label: "Text, faint" }
        }
    }

    SettingsGroup {
        title: "Colours — borders"
        ColorFlow {
            ColorChip { tokenKey: "border"; label: "Border" }
            ColorChip { tokenKey: "border-strong"; label: "Border, strong" }
        }
    }

    SettingsGroup {
        title: "Colours — accent & status"
        caption: "The accent is fine detail only — titles, the keyboard focus ring, the agent's working state. The status colours appear only when a real threshold is crossed."
        ColorFlow {
            ColorChip { tokenKey: "accent"; label: "Accent"; showContrast: true }
            ColorChip { tokenKey: "error"; label: "Error"; showContrast: true }
            ColorChip { tokenKey: "warn"; label: "Warning"; showContrast: true }
            ColorChip { tokenKey: "success"; label: "Success"; showContrast: true }
            ColorChip { tokenKey: "info"; label: "Info"; showContrast: true }
        }
    }

    SettingsGroup {
        title: "Colour preview"
        preview: true

        SettingsRow {
            wide: true
            title: "Live preview"
            description: "Rendered from the current overrides — not editable here."
            Column {
                width: parent.width
                spacing: root.gap
                Row {
                    spacing: root.gap
                    Widgets.StyledButton { label: "Button" }
                    Widgets.StyledButton { label: "Active"; active: true }
                    Widgets.Toggle { checked: true }
                    Widgets.Toggle { checked: false }
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
        TokenNumberRow {
            tokenKey: "panel-gap"; title: "Panel gap"; step: 1; suffix: "px"; from: 0; to: 24
            description: "Inset the notification and chat docks, the calendar and the bar popouts keep from the bar and the screen edges."
        }
        TokenNumberRow {
            tokenKey: "panel-radius"; title: "Panel corner radius"; step: 1; suffix: "px"; from: 0; to: 24
            description: "Corner rounding of those same below-the-bar surfaces."
        }
    }

    // --- Animations --------------------------------------------
    SettingsGroup {
        title: "Animations"
        optionId: "theme.animations"
        caption: "The four style-plan motion categories. Category B is every state transition — panels, drawers, workspaces, notifications — so its duration and curve reach the whole shell. A is the agent's tracking indicator, C the rare boot/unlock effects, D ambient (off by default)."

        MotionRow { mkey: "motion-b-duration"; title: "B — transition duration"; seedMs: Config.Appearance.motionBDuration }

        SettingsRow {
            title: "B — transition curve"
            description: "Drag the handles; the marker loops on the edited curve."
            wide: true
            resettable: Config.ThemeOverrides.has("motion-b-bezier")
            onReset: { Config.ThemeOverrides.clear("motion-b-bezier"); bez.setCurve(
                Config.Appearance.motionBCurve[0], Config.Appearance.motionBCurve[1],
                Config.Appearance.motionBCurve[2], Config.Appearance.motionBCurve[3]) }
            Widgets.BezierEditor {
                id: bez
                Component.onCompleted: setCurve(
                    Config.Appearance.motionBCurve[0], Config.Appearance.motionBCurve[1],
                    Config.Appearance.motionBCurve[2], Config.Appearance.motionBCurve[3])
                onCommitted: (a, b, c, d) => Config.ThemeOverrides.setValue("motion-b-bezier",
                    a.toFixed(3) + "," + b.toFixed(3) + "," + c.toFixed(3) + "," + d.toFixed(3))
                Connections {
                    target: resetSignal
                    function onFired() { bez.setCurve(
                        Config.Appearance.motionBCurve[0], Config.Appearance.motionBCurve[1],
                        Config.Appearance.motionBCurve[2], Config.Appearance.motionBCurve[3]) }
                }
            }
        }

        MotionRow { mkey: "motion-a-period"; title: "A — tracking period"; seedMs: Config.Appearance.motionAPeriod }
        MotionRow { mkey: "motion-c-type-step"; title: "C — typing step"; seedMs: Config.Appearance.motionCTypeStep }
        MotionRow { mkey: "motion-c-scramble"; title: "C — scramble duration"; seedMs: Config.Appearance.motionCScramble }
        MotionRow { mkey: "motion-d-duration"; title: "D — ambient duration"; seedMs: Config.Appearance.motionDDuration }
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
            Widgets.Toggle { checked: Services.NightShift.enabled; onToggled: (v) => Services.NightShift.setEnabled(v) }
        }
        SettingsRow {
            title: "True Tone"
            description: Config.Capabilities.ambientLight
                ? "Drive colour temperature from ambient light instead of a fixed value."
                : "No ambient light sensor on this host — True Tone has nothing to read."
            Widgets.Toggle {
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
        caption: "Hold Super+G to show it; the toggle here is sticky. Dim and flashlight dim the screen around a clear circle; crosshair and ring just mark the pointer and never dim."

        SettingsRow {
            optionId: "theme.spotlight"
            title: "Cursor spotlight"
            description: "Locate the pointer on a large or busy screen."
            Widgets.Toggle {
                checked: Services.Spotlight.shown
                onToggled: (v) => (v ? Services.Spotlight.show() : Services.Spotlight.hide())
            }
        }
        SettingsRow {
            title: "Effect"
            wide: true
            Flow {
                width: parent.width
                spacing: root.gap
                Repeater {
                    model: Services.Spotlight.effects
                    Widgets.StyledButton {
                        required property string modelData
                        label: modelData
                        active: Services.Spotlight.effect === modelData
                        onClicked: Services.Spotlight.setEffect(modelData)
                    }
                }
            }
        }

        // dim / flashlight options
        SettingsRow {
            title: "Circle size"
            visible: Services.Spotlight.effect === "dim" || Services.Spotlight.effect === "flashlight"
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
        SettingsRow {
            title: "Dim strength"
            visible: Services.Spotlight.effect === "dim" || Services.Spotlight.effect === "flashlight"
            Widgets.NumberField {
                value: Services.Spotlight.intensity
                step: 5; suffix: "%"; from: 0; to: 100
                onCommitted: (v) => Services.Spotlight.setIntensity(v)
            }
        }

        // crosshair options
        SettingsRow {
            title: "Line thickness"
            visible: Services.Spotlight.effect === "crosshair"
            Widgets.NumberField {
                value: Services.Spotlight.crosshairThickness
                step: 1; suffix: "px"; from: 1; to: 8
                onCommitted: (v) => Services.Spotlight.setCrosshairThickness(v)
            }
        }
        SettingsRow {
            title: "Line opacity"
            visible: Services.Spotlight.effect === "crosshair"
            Widgets.NumberField {
                value: Services.Spotlight.crosshairOpacity
                step: 5; suffix: "%"; from: 5; to: 100
                onCommitted: (v) => Services.Spotlight.setCrosshairOpacity(v)
            }
        }

        // ring options
        SettingsRow {
            title: "Ring radius"
            visible: Services.Spotlight.effect === "ring"
            Widgets.NumberField {
                value: Services.Spotlight.ringRadius
                step: 5; suffix: "px"; from: 20; to: 240
                onCommitted: (v) => Services.Spotlight.setRingRadius(v)
            }
        }
        SettingsRow {
            title: "Ring thickness"
            visible: Services.Spotlight.effect === "ring"
            Widgets.NumberField {
                value: Services.Spotlight.ringThickness
                step: 1; suffix: "px"; from: 1; to: 12
                onCommitted: (v) => Services.Spotlight.setRingThickness(v)
            }
        }
    }

    // --- Screen magnifier ------------------------------------
    // OOP-50: the loupe (Magnifier/Magnifier.qml). Runtime UI state stored
    // through `phi state` by Services/Magnifier, same category as the
    // spotlight size above — not a design token.
    SettingsGroup {
        title: "Screen magnifier"
        SettingsRow {
            optionId: "theme.magnifier"
            title: "Magnifier loupe"
            description: "A circular lens on the pointer. Super+Z toggles it; Super + = / Super + - change zoom, Super+Shift + those the lens size (Super+scroll too, where supported)."
            Widgets.Toggle {
                checked: Services.Magnifier.shown
                onToggled: (v) => (v ? Services.Magnifier.show() : Services.Magnifier.hide())
            }
        }
        SettingsRow {
            title: "Zoom"
            Widgets.NumberField {
                value: Services.Magnifier.zoom
                step: 0.5; suffix: "×"; from: 1.5; to: 6; decimals: 1
                onCommitted: (v) => Services.Magnifier.setZoom(v)
            }
        }
        SettingsRow {
            title: "Lens size"
            Widgets.NumberField {
                value: Services.Magnifier.size
                step: 20; suffix: "px"; from: 180; to: 720
                onCommitted: (v) => Services.Magnifier.setSize(Math.round(v))
            }
        }
    }

    // --- Lock screen -----------------------------------------
    // OOP-35 (auth surfaces): the ambient backdrop behind the lock screen.
    // Stored in Config/LockPrefs.qml ($XDG_STATE_HOME/phi/lock.json), read
    // by Lock/Lock.qml. Runtime UI state, not a design token — same
    // category as the spotlight size above. Ported into the batch-C/D/E
    // Theme rewrite on merge.
    SettingsGroup {
        title: "Lock screen"
        optionId: "theme.lockscreen"
        SettingsRow {
            title: "Ambient effect"
            description: "The backdrop behind the lock screen."
            Row {
                spacing: root.gap
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
            description: "A generated grain composited over the whole wallpaper — the solid colour and any image alike. Generated once, then cached."
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
                Widgets.StyledText {
                    width: parent.width
                    visible: Services.Background.textureError.length > 0
                    wrapMode: Text.WordWrap
                    tone: "error"
                    sizeStep: 0
                    text: "Texture: " + Services.Background.textureError
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
