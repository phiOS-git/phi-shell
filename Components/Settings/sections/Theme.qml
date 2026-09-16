import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import qs.Lock as LockFx
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

    // Keeps pendingVariant (the Dark/Light buttons' "active" highlight)
    // in sync when the variant changes from outside this row's own click
    // handler — the schedule below can switch it on its own timer.
    Connections {
        target: Config.Appearance
        function onVariantChanged() { root.pendingVariant = Config.Appearance.variant }
    }

    // OOP-54 / panels-ux-rework: the token key whose editor panel is open.
    // One at a time across every colour group, so at most one editor panel
    // is ever slid open under the grids.
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

    // panels-ux-rework: a colour context is a stable grid of compact
    // swatches plus ONE editor panel that slides open (category B) directly
    // beneath the group. Tapping a swatch — or a search reveal / `qs ipc
    // call settings reveal theme.colors.<key>` — rings it and opens the
    // editor; `root._openColor` keeps exactly one swatch open across every
    // colour group. This replaces OOP-54's in-place expand, where the
    // tapped chip grew to a full-width row and shoved its neighbours around
    // the Flow (the user's "editing one completely breaks the layout").
    //
    // `swatches` is a list of { key, label, contrast }: `key` a design
    // token name, `contrast` opting the editor into the live `phi theme
    // contrast` badge.
    component ColorGroup: SettingsGroup {
        id: cg
        property var swatches: []

        // The swatch entry in THIS group that is open, or null. ColorEditor
        // keeps the last non-null one through the close animation so the
        // panel does not blank while it collapses.
        readonly property var _openEntry: {
            for (var i = 0; i < cg.swatches.length; i++)
                if (cg.swatches[i].key === root._openColor) return cg.swatches[i]
            return null
        }

        Item { width: 1; height: Math.round(root.chWidth * Config.Appearance.space1) }

        // The swatch grid. Each tile is fixed size — the grid never reflows
        // on edit. Each registers its `theme.colors.<key>` optionId so a
        // search selection still lands on an individual colour.
        Flow {
            x: root.gap
            width: parent.width - root.gap * 2
            spacing: root.chWidth

            Repeater {
                model: cg.swatches

                Rectangle {
                    id: sw
                    required property var modelData
                    readonly property string tokenKey: sw.modelData ? (sw.modelData.key || "") : ""
                    readonly property string optionId: "theme.colors." + sw.tokenKey
                    readonly property string _hex: sw.tokenKey.length > 0 ? Config.Appearance.tokenValue(sw.tokenKey) : ""
                    readonly property bool _valid: /^#([0-9a-fA-F]{6})$/.test(sw._hex)
                    readonly property bool _overridden: sw.tokenKey.length > 0 && Config.ThemeOverrides.has(sw.tokenKey)
                    readonly property bool _open: sw.tokenKey.length > 0 && root._openColor === sw.tokenKey
                    readonly property bool _highlighted: Services.SettingsPanel.shown
                        && Services.SettingsPanel.query.length > 0
                        && sw.tokenKey.length > 0
                        && Options.matches(sw.optionId, Services.SettingsPanel.query)
                    // Style pass 2026-09-14 (docs/TODO.md: "in the theme
                    // settings colors have no hover effect"). This tile had
                    // an open/selected wash, a search-match wash and a
                    // pulse-on-reveal — every state except the one that
                    // tells you it is clickable at all before you click.
                    readonly property bool _hovered: swHover.hovered || sw.activeFocus

                    width: Math.round(root.chWidth * 24)
                    height: swRow.implicitHeight + Math.round(root.chWidth * Config.Appearance.space1)
                    radius: Config.Appearance.radiusSmall
                    color: sw._open ? Config.Appearance.surface1
                        : (sw._hovered ? Config.Appearance.panelHover : "transparent")
                    border.width: (sw._open || sw.activeFocus) ? Config.Appearance.borderWidth : 0
                    border.color: (sw._open || sw.activeFocus) ? Config.Appearance.focusRing : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                    }

                    HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }

                    Component.onCompleted: if (sw.tokenKey.length > 0) Services.SettingsPanel.registerRow(sw.optionId, sw)
                    Component.onDestruction: if (sw.tokenKey.length > 0) Services.SettingsPanel.unregisterRow(sw.optionId)
                    function pulse() { root._openColor = sw.tokenKey; pulseAnim.restart() }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Config.Appearance.accent
                        opacity: sw._highlighted && !sw._open ? 0.12 : 0
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
                        id: swRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: root.chWidth
                        anchors.rightMargin: root.chWidth
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.chWidth

                        Rectangle {
                            id: swChip
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(Config.Appearance.fontSize3 * 1.3)
                            height: width
                            radius: Config.Appearance.radiusSmall
                            color: sw._valid ? sw._hex : "transparent"
                            border.width: Config.Appearance.borderWidth
                            border.color: Config.Appearance.border
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: swRow.width - swRow.spacing - swChip.width
                            spacing: Math.round(root.chWidth * Config.Appearance.space1 * 0.4)
                            Widgets.StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: sw.modelData ? (sw.modelData.label || "") : ""
                            }
                            Widgets.StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                kind: "label"
                                sizeStep: 0
                                mono: true
                                text: sw._hex + (sw._overridden ? "  ·edited" : "")
                            }
                        }
                    }

                    TapHandler { onTapped: root._openColor = sw._open ? "" : sw.tokenKey }

                    // Style pass 2026-09-14: this tile had no
                    // `activeFocusOnTab` at all — unlike every shared
                    // Widgets/ control (now keyboard-activatable end to
                    // end, a separate fix this same pass), a raw
                    // Rectangle+TapHandler composition like this one was
                    // not just dead to Enter/Space, it could not even
                    // receive Tab focus in the first place, so keyboard
                    // navigation through Settings → Theme silently
                    // skipped the whole colour swatch grid.
                    activeFocusOnTab: true
                    Keys.onReturnPressed: root._openColor = sw._open ? "" : sw.tokenKey
                    Keys.onSpacePressed: root._openColor = sw._open ? "" : sw.tokenKey
                }
            }
        }

        Item { width: 1; height: Math.round(root.chWidth * Config.Appearance.space1) }

        Widgets.Reveal {
            shown: cg._openEntry !== null
            ColorEditor {
                x: root.gap
                width: parent.width - root.gap * 2
                entry: cg._openEntry
            }
        }

        Item {
            width: 1
            height: cg._openEntry !== null ? Math.round(root.chWidth * Config.Appearance.space1) : 0
            Behavior on height {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
        }
    }

    // The single editor panel a ColorGroup slides open under its grid.
    component ColorEditor: Rectangle {
        id: ce
        property var entry: null
        // Hold the last non-null entry so the panel keeps its content while
        // the Reveal collapses on close.
        property var _shownEntry: null
        onEntryChanged: if (ce.entry) ce._shownEntry = ce.entry
        readonly property string tokenKey: ce._shownEntry ? (ce._shownEntry.key || "") : ""
        readonly property bool _overridden: ce.tokenKey.length > 0 && Config.ThemeOverrides.has(ce.tokenKey)

        onTokenKeyChanged: edField.reseed()

        width: parent ? parent.width : 0
        height: ceCol.implicitHeight + root.gap * 2
        radius: Config.Appearance.radiusSmall
        color: Config.Appearance.surface1
        border.width: Config.Appearance.borderWidth
        border.color: Config.Appearance.border

        Column {
            id: ceCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.gap
            spacing: Math.round(root.chWidth * Config.Appearance.space2)

            Item {
                width: parent.width
                height: Math.max(edLabel.implicitHeight, edReset.implicitHeight)
                Widgets.StyledText {
                    id: edLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "label"
                    sizeStep: 0
                    text: "EDITING — " + (ce._shownEntry ? String(ce._shownEntry.label || "").toUpperCase() : "")
                }
                Widgets.SmallButton {
                    id: edReset
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ce._overridden
                    label: "reset to default"
                    onClicked: {
                        if (ce.tokenKey.length === 0) return
                        Config.ThemeOverrides.clear(ce.tokenKey)
                        edField.reseed()
                    }
                }
            }

            Widgets.ColorField {
                id: edField
                width: parent.width
                function reseed() {
                    edField.value = ce.tokenKey.length > 0
                        ? Config.Appearance.tokenValue(ce.tokenKey) : ""
                }
                Component.onCompleted: reseed()
                onCommitted: (hex) => { if (ce.tokenKey.length > 0) Config.ThemeOverrides.setValue(ce.tokenKey, hex) }
                Connections {
                    target: resetSignal
                    function onFired() { edField.reseed() }
                }
            }

            ContrastBadge {
                visible: !!ce._shownEntry && ce._shownEntry.contrast === true
                hex: edField.value
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
        property bool browsing: false
        wide: true
        optionId: "theme.fonts." + tokenKey.replace("font-", "")
        resettable: Config.ThemeOverrides.has(tokenKey)
        onReset: { Config.ThemeOverrides.clear(tokenKey); ff.text = Config.Appearance.tokenValue(tokenKey) }

        Column {
            width: parent.width
            spacing: 6
            Row {
                width: parent.width
                spacing: root.gap
                Widgets.TextField {
                    id: ff
                    // Style pass 2026-09-14 (docs/TODO.md: "options inputs
                    // in settings like 'ringtone' are text field rather
                    // then real selection elements" — the exact same
                    // pattern, just for an installed font name instead of
                    // a sound name). The field stays — a power user who
                    // already knows the exact family name can still just
                    // type it — but "Browse…" reveals every font Qt
                    // actually has installed (Qt.fontFamilies(), a plain
                    // Qt API — no subprocess needed at all, unlike
                    // Widgets/SoundPicker's directory scan), filterable,
                    // tap to select.
                    width: parent.width - browseBtn.implicitWidth - parent.spacing
                    mono: false
                    placeholder: "Font family name"
                    Component.onCompleted: text = Config.Appearance.tokenValue(fr.tokenKey)
                    onCommitted: (t) => Config.ThemeOverrides.setValue(fr.tokenKey, t.trim())
                    Connections {
                        target: resetSignal
                        function onFired() { ff.text = Config.Appearance.tokenValue(fr.tokenKey) }
                    }
                }
                Widgets.SmallButton {
                    id: browseBtn
                    anchors.verticalCenter: parent.verticalCenter
                    label: fr.browsing ? "Hide list" : "Browse…"
                    onClicked: fr.browsing = !fr.browsing
                }
            }
            Widgets.Reveal {
                shown: fr.browsing
                width: parent.width
                Column {
                    width: parent.width
                    spacing: 6
                    Widgets.TextField {
                        id: fontFilter
                        width: parent.width
                        mono: false
                        placeholder: "Filter installed fonts…"
                    }
                    Widgets.Panel {
                        id: fontListPanel
                        width: parent.width
                        // Enumerated once when the list is first opened, not
                        // re-queried on every keystroke — Qt.fontFamilies()
                        // is a real OS font-enumeration call, not a cheap
                        // constant, and only the FILTER needs to be live.
                        property var _allFamilies: []
                        Component.onCompleted: fontListPanel._allFamilies = Qt.fontFamilies()
                        readonly property var _matches: fontListPanel._allFamilies.filter(
                            (n) => n.toLowerCase().indexOf(fontFilter.text.toLowerCase()) !== -1)
                        height: Math.min(fontListCol.implicitHeight + padding * 2, root.chWidth * 22)
                        Flickable {
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: fontListCol.implicitHeight
                            clip: true
                            Column {
                                id: fontListCol
                                width: parent.width
                                Repeater {
                                    model: fontListPanel._matches
                                    Widgets.ListRow {
                                        required property string modelData
                                        width: parent.width
                                        label: modelData
                                        active: modelData === ff.text
                                        onActivated: {
                                            ff.text = modelData
                                            Config.ThemeOverrides.setValue(fr.tokenKey, modelData)
                                            fr.browsing = false
                                        }
                                    }
                                }
                                Widgets.StyledText {
                                    width: parent.width
                                    visible: fontListPanel._matches.length === 0
                                    kind: "label"; sizeStep: 0
                                    text: "No installed font matches."
                                }
                            }
                        }
                    }
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
            description: Services.ThemeSchedule.scheduleMode === "off"
                ? "Dark and light are permanent, independent variants."
                : "Controlled by the schedule below."
            Row {
                spacing: root.gap
                Widgets.StyledButton {
                    label: "Dark"
                    active: root.pendingVariant === "dark"
                    enabled: Services.ThemeSchedule.scheduleMode === "off"
                    onClicked: root.setVariant("dark")
                }
                Widgets.StyledButton {
                    label: "Light"
                    active: root.pendingVariant === "light"
                    enabled: Services.ThemeSchedule.scheduleMode === "off"
                    onClicked: root.setVariant("light")
                }
            }
        }
        SettingsRow {
            optionId: "theme.schedule"
            title: "Schedule"
            description: "Switch dark and light automatically instead of by hand."
            wide: true
            Row {
                spacing: root.gap
                Repeater {
                    model: [
                        { key: "off", label: "Off" },
                        { key: "auto", label: "Automatic" },
                        { key: "custom", label: "Custom hours" }
                    ]
                    Widgets.StyledButton {
                        required property var modelData
                        label: modelData.label
                        active: Services.ThemeSchedule.scheduleMode === modelData.key
                        onClicked: Services.ThemeSchedule.setScheduleMode(modelData.key)
                    }
                }
            }
        }
        Widgets.Reveal {
            shown: Services.ThemeSchedule.scheduleMode === "auto"
            SettingsRow {
                title: "Automatic window"
                description: "Fixed default — dark from " + Services.ThemeSchedule.autoStartHour + ":00 to "
                    + Services.ThemeSchedule.autoEndHour + ":00, light the rest of the day. Not location-based: this shell has no source for a real sunset/sunrise time, so it's a sensible fixed evening-to-morning window rather than one computed per day. Use Custom hours to pick your own."
                wide: true
            }
        }
        Widgets.Reveal {
            shown: Services.ThemeSchedule.scheduleMode === "custom"
            SettingsRow {
                title: "Dark starts at"
                Widgets.NumberField {
                    value: Services.ThemeSchedule.scheduleStartHour
                    step: 1; suffix: ":00"; from: 0; to: 23
                    onCommitted: (v) => Services.ThemeSchedule.setScheduleStartHour(Math.round(v))
                }
            }
            SettingsRow {
                title: "Light starts at"
                Widgets.NumberField {
                    value: Services.ThemeSchedule.scheduleEndHour
                    step: 1; suffix: ":00"; from: 0; to: 23
                    onCommitted: (v) => Services.ThemeSchedule.setScheduleEndHour(Math.round(v))
                }
            }
        }
    }

    // --- Colours (first inner section) -------------------------------
    // panels-ux-rework: grouped by context, each a ColorGroup — a stable
    // swatch grid plus one slide-open editor panel (see the component).
    ColorGroup {
        title: "Colours — structure"
        caption: "Two structural colours (background, primary text) carry the whole shell; the surfaces step up from the background for stacked panels."
        swatches: [
            { key: "bg-0", label: "Background", contrast: false },
            { key: "bg-1", label: "Surface +1", contrast: false },
            { key: "bg-2", label: "Surface +2", contrast: false },
            { key: "bg-3", label: "Surface +3", contrast: false }
        ]
    }

    ColorGroup {
        title: "Colours — text"
        swatches: [
            { key: "fg-0", label: "Text (primary)", contrast: true },
            { key: "fg-1", label: "Text, secondary", contrast: true },
            { key: "fg-2", label: "Text, muted", contrast: true },
            { key: "fg-3", label: "Text, faint", contrast: false }
        ]
    }

    ColorGroup {
        title: "Colours — borders"
        swatches: [
            { key: "border", label: "Border", contrast: false },
            { key: "border-strong", label: "Border, strong", contrast: false }
        ]
    }

    ColorGroup {
        title: "Colours — accent & status"
        caption: "The accent is fine detail only — titles, the keyboard focus ring, the agent's working state. The status colours appear only when a real threshold is crossed."
        swatches: [
            { key: "accent", label: "Accent", contrast: true },
            { key: "error", label: "Error", contrast: true },
            { key: "warn", label: "Warning", contrast: true },
            { key: "success", label: "Success", contrast: true },
            { key: "info", label: "Info", contrast: true }
        ]
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
        // rework-issues.md "New requests" item 16. Not a TokenNumberRow/
        // ThemeOverrides value like its siblings above — those only ever
        // affect phi-shell's own rendering, but this one has to reach
        // kitty (a separate process, its own config file), so it goes
        // through `phi state` (Services/Terminal.qml) and a real
        // `phi theme set` re-render instead, reusing this section's own
        // `setVariant` plumbing to apply immediately rather than only on
        // the next manual theme switch.
        SettingsRow {
            optionId: "theme.shape.terminal-padding"
            title: "Terminal window padding"
            description: "kitty's own window_padding_width. Applies to new windows; already-open ones pick it up on their next theme re-render."
            Widgets.NumberField {
                value: Services.Terminal.padding
                step: 4; suffix: "px"; from: 0; to: 120
                onCommitted: (v) => {
                    Services.Terminal.setPadding(v)
                    root.setVariant(Config.Appearance.variant)
                }
            }
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

    // --- Night shift ---------------------------------------------
    SettingsGroup {
        title: "Night shift"
        SettingsRow {
            optionId: "theme.nightshift"
            title: "Night shift"
            description: Services.NightShift.scheduleMode === "off"
                ? "Warms the display in the evening."
                : "Controlled by the schedule below."
            Widgets.Toggle {
                checked: Services.NightShift.enabled
                enabled: Services.NightShift.scheduleMode === "off"
                onToggled: (v) => Services.NightShift.setEnabled(v)
            }
        }
        SettingsRow {
            title: "Schedule"
            description: "Turn night shift on and off automatically instead of by hand."
            wide: true
            Row {
                spacing: root.gap
                Repeater {
                    model: [
                        { key: "off", label: "Off" },
                        { key: "auto", label: "Automatic" },
                        { key: "custom", label: "Custom hours" }
                    ]
                    Widgets.StyledButton {
                        required property var modelData
                        label: modelData.label
                        active: Services.NightShift.scheduleMode === modelData.key
                        onClicked: Services.NightShift.setScheduleMode(modelData.key)
                    }
                }
            }
        }
        Widgets.Reveal {
            shown: Services.NightShift.scheduleMode === "auto"
            SettingsRow {
                title: "Automatic window"
                description: "Fixed default — " + Services.NightShift.autoStartHour + ":00 to "
                    + Services.NightShift.autoEndHour + ":00. Not location-based: this shell has no source for a real sunset/sunrise time, so it's a sensible fixed evening-to-morning window rather than one computed per day. Use Custom hours to pick your own."
                wide: true
            }
        }
        Widgets.Reveal {
            shown: Services.NightShift.scheduleMode === "custom"
            SettingsRow {
                title: "Starts at"
                Widgets.NumberField {
                    value: Services.NightShift.scheduleStartHour
                    step: 1; suffix: ":00"; from: 0; to: 23
                    onCommitted: (v) => Services.NightShift.setScheduleStartHour(Math.round(v))
                }
            }
            SettingsRow {
                title: "Ends at"
                Widgets.NumberField {
                    value: Services.NightShift.scheduleEndHour
                    step: 1; suffix: ":00"; from: 0; to: 23
                    onCommitted: (v) => Services.NightShift.setScheduleEndHour(Math.round(v))
                }
            }
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

        // dim / flashlight options — slide in/out with the effect choice
        // (panels-ux-rework) rather than the sub-rows popping.
        Widgets.Reveal {
            shown: Services.Spotlight.effect === "dim" || Services.Spotlight.effect === "flashlight"
            SettingsRow {
                title: "Circle size"
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
                Widgets.NumberField {
                    value: Services.Spotlight.intensity
                    step: 5; suffix: "%"; from: 0; to: 100
                    onCommitted: (v) => Services.Spotlight.setIntensity(v)
                }
            }
        }

        // crosshair options
        Widgets.Reveal {
            shown: Services.Spotlight.effect === "crosshair"
            SettingsRow {
                title: "Line thickness"
                Widgets.NumberField {
                    value: Services.Spotlight.crosshairThickness
                    step: 1; suffix: "px"; from: 1; to: 8
                    onCommitted: (v) => Services.Spotlight.setCrosshairThickness(v)
                }
            }
            SettingsRow {
                title: "Line opacity"
                Widgets.NumberField {
                    value: Services.Spotlight.crosshairOpacity
                    step: 5; suffix: "%"; from: 5; to: 100
                    onCommitted: (v) => Services.Spotlight.setCrosshairOpacity(v)
                }
            }
        }

        // ring options
        Widgets.Reveal {
            shown: Services.Spotlight.effect === "ring"
            SettingsRow {
                title: "Ring radius"
                Widgets.NumberField {
                    value: Services.Spotlight.ringRadius
                    step: 5; suffix: "px"; from: 20; to: 240
                    onCommitted: (v) => Services.Spotlight.setRingRadius(v)
                }
            }
            SettingsRow {
                title: "Ring thickness"
                Widgets.NumberField {
                    value: Services.Spotlight.ringThickness
                    step: 1; suffix: "px"; from: 1; to: 12
                    onCommitted: (v) => Services.Spotlight.setRingThickness(v)
                }
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

    // --- Clock ---------------------------------------------------
    // docs/TODO.md: "add settings for the status bar time in the settings
    // panel. Allow to set the format with day/number/year/second etc."
    // Stored in Config/ClockPrefs.qml ($XDG_STATE_HOME/phi/clock.json),
    // read by Bar/modules/Clock.qml. Same shape and reasoning as the Lock
    // screen group just below.
    SettingsGroup {
        title: "Clock"
        optionId: "theme.clock"

        SettingsRow {
            title: "12-hour clock"
            description: "Show the bar clock as 1-12 with AM/PM instead of 0-23."
            Widgets.Toggle {
                checked: Config.ClockPrefs.hour12
                onToggled: (v) => Config.ClockPrefs.setHour12(v)
            }
        }
        SettingsRow {
            title: "Show seconds"
            Widgets.Toggle {
                checked: Config.ClockPrefs.showSeconds
                onToggled: (v) => Config.ClockPrefs.setShowSeconds(v)
            }
        }
        SettingsRow {
            title: "Date"
            description: "Adds the date before the time in the bar. Short is day/month (13/09); long adds the weekday name and year (Sat 13 Sep 2026)."
            Row {
                spacing: root.gap
                Repeater {
                    model: [
                        { key: "off", label: "Off" },
                        { key: "short", label: "Short" },
                        { key: "long", label: "Long" }
                    ]
                    Widgets.StyledButton {
                        required property var modelData
                        label: modelData.label
                        active: Config.ClockPrefs.dateStyle === modelData.key
                        onClicked: Config.ClockPrefs.setDateStyle(modelData.key)
                    }
                }
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
            wide: true
            Flow {
                width: parent.width
                spacing: root.gap
                Repeater {
                    model: [
                        { key: "none", label: "None" },
                        { key: "lava", label: "Lava lamp" },
                        { key: "matrix", label: "Matrix" },
                        { key: "starfield", label: "Starfield" },
                        { key: "plasma", label: "Plasma" },
                        { key: "life", label: "Life" },
                        { key: "boids", label: "Boids" }
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

        // docs/TODO.md: "ambient effects look great, they should have many
        // settings: some shared (eg. speed) some specific for the selected
        // one." Speed applies to whichever effect is picked above (one
        // multiplier every Lock/*.qml effect already scales its own motion
        // by — see Config/LockPrefs.qml's own header); Intensity is scoped
        // to the CURRENTLY selected effect specifically, each with its own
        // stored value and its own pre-existing default.
        SettingsRow {
            visible: Config.LockPrefs.effect !== "none"
            title: "Speed"
            description: "Applies to whichever ambient effect is selected above."
            Widgets.NumberField {
                value: Config.LockPrefs.speed
                from: 0.25; to: 3.0; step: 0.25; decimals: 2
                suffix: "×"
                onCommitted: (v) => Config.LockPrefs.setSpeed(v)
            }
        }
        SettingsRow {
            visible: Config.LockPrefs.effect !== "none"
            title: "Intensity"
            description: "Specific to the currently-selected effect — Matrix and Lava lamp are deliberately faint by default, Starfield and Plasma are not."
            Widgets.NumberField {
                // Plain binding, no extra re-seed mechanism needed: this
                // reads Config.LockPrefs.effect directly (as the function
                // argument) and Config.LockPrefs.prefs indirectly (inside
                // intensityFor() itself) — QML's dependency tracker follows
                // property reads through a called function just as it
                // would a direct property access, so this already
                // re-evaluates correctly on either changing. NumberField's
                // own onValueChanged (Widgets/NumberField.qml) re-syncs its
                // displayed text whenever `value` changes externally like
                // this, as long as the field isn't mid-edit.
                value: Config.LockPrefs.intensityFor(Config.LockPrefs.effect)
                from: 0.05; to: 1.0; step: 0.05; decimals: 2
                onCommitted: (v) => Config.LockPrefs.setIntensity(Config.LockPrefs.effect, v)
            }
        }

        // docs/TODO.md follow-up (user, 2026-09-15): "way more
        // customisability" — one settings block per effect, visible only
        // while that effect is the one actually selected above (the same
        // gating Speed/Intensity already use): showing all six effects'
        // own extra knobs at once would defeat "make the layout fit" by
        // reintroducing the exact clutter this round is fixing, when only
        // one of them can ever be active at a time anyway.
        SettingsRow {
            visible: Config.LockPrefs.effect === "lava"
            title: "Lava lamp"
            description: "More blobs read as a denser, busier field. Wobble scales how much each blob squashes/stretches and drifts sideways as it rises."
            // `wide: true` (2026-09-15): the default compact layout
            // right-aligns a content-sized control slot, sized to fit ONE
            // small control (a single NumberField, same as Matrix/
            // Starfield/Plasma/Boids below). This row's slot instead holds
            // a whole Column of label+field pairs (Blob count, Wobble),
            // which is wide enough to overflow past the dialog's own right
            // edge in that compact slot — confirmed with a real screenshot
            // ("the options are out of bound", reported directly). `wide`
            // is the existing, documented layout for exactly this case
            // (SettingsRow.qml's own header: "a colour picker, a keyboard
            // map, a chart" — any control too wide for the compact slot),
            // not a new mechanism.
            wide: true
            Column {
                width: parent.width
                spacing: root.gap
                Row {
                    spacing: root.gap
                    Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "Blob count" }
                    Widgets.NumberField {
                        value: Config.LockPrefs.paramFor("lava", "blobCount", 9)
                        from: 3; to: 18; step: 1
                        onCommitted: (v) => Config.LockPrefs.setParam("lava", "blobCount", Math.round(v))
                    }
                }
                Row {
                    spacing: root.gap
                    Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "Wobble" }
                    Widgets.NumberField {
                        value: Config.LockPrefs.paramFor("lava", "wobble", 1.0)
                        from: 0.25; to: 3.0; step: 0.25; decimals: 2; suffix: "×"
                        onCommitted: (v) => Config.LockPrefs.setParam("lava", "wobble", v)
                    }
                }
            }
        }
        SettingsRow {
            visible: Config.LockPrefs.effect === "matrix"
            title: "Matrix"
            description: "Column density — higher packs the columns closer together."
            Widgets.NumberField {
                value: Config.LockPrefs.paramFor("matrix", "density", 1.0)
                from: 0.4; to: 2.0; step: 0.2; decimals: 1; suffix: "×"
                onCommitted: (v) => Config.LockPrefs.setParam("matrix", "density", v)
            }
        }
        SettingsRow {
            visible: Config.LockPrefs.effect === "starfield"
            title: "Starfield"
            description: "How many points drift across the field at once."
            Widgets.NumberField {
                value: Config.LockPrefs.paramFor("starfield", "starCount", 140)
                from: 30; to: 400; step: 10
                onCommitted: (v) => Config.LockPrefs.setParam("starfield", "starCount", Math.round(v))
            }
        }
        SettingsRow {
            visible: Config.LockPrefs.effect === "plasma"
            title: "Plasma"
            description: "Grid resolution — higher is finer detail at a higher redraw cost."
            Widgets.NumberField {
                value: Config.LockPrefs.paramFor("plasma", "resolution", 1.0)
                from: 0.5; to: 2.0; step: 0.25; decimals: 2; suffix: "×"
                onCommitted: (v) => Config.LockPrefs.setParam("plasma", "resolution", v)
            }
        }
        SettingsRow {
            visible: Config.LockPrefs.effect === "life"
            title: "Life"
            description: "Grid resolution changes the cell size; seed density is how much of the board starts alive when a generation is (re)seeded."
            // Same overflow, same fix as the Lava lamp row above.
            wide: true
            Column {
                width: parent.width
                spacing: root.gap
                Row {
                    spacing: root.gap
                    Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "Grid resolution" }
                    Widgets.NumberField {
                        value: Config.LockPrefs.paramFor("life", "resolution", 1.0)
                        from: 0.5; to: 2.0; step: 0.25; decimals: 2; suffix: "×"
                        onCommitted: (v) => Config.LockPrefs.setParam("life", "resolution", v)
                    }
                }
                Row {
                    spacing: root.gap
                    Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "Seed density" }
                    Widgets.NumberField {
                        value: Config.LockPrefs.paramFor("life", "seedDensity", 0.28)
                        from: 0.1; to: 0.5; step: 0.02; decimals: 2
                        onCommitted: (v) => Config.LockPrefs.setParam("life", "seedDensity", v)
                    }
                }
            }
        }
        SettingsRow {
            visible: Config.LockPrefs.effect === "boids"
            title: "Boids"
            description: "How many boids flock together."
            Widgets.NumberField {
                value: Config.LockPrefs.paramFor("boids", "boidCount", 40)
                from: 10; to: 120; step: 5
                onCommitted: (v) => Config.LockPrefs.setParam("boids", "boidCount", Math.round(v))
            }
        }
    }

    // docs/TODO.md: "add a live preview of the effect in the settings
    // when one is selected" — same `preview: true` shape as "Colour
    // preview" above: a real, live instance of the currently-selected
    // effect, not a static screenshot. Fixed-size box (the effects assume
    // full-lockscreen dimensions normally; here they just get a smaller
    // Item to fill instead — every effect already scales its own grid/
    // point positions off `width`/`height`, so no effect-side change was
    // needed for this).
    //
    // docs/TODO.md (style pass): "the settings panel now can be laggy
    // especially with live previews. Make them toggable and hidden by
    // default (should be toggled on when their relative option like
    // ambient effect change)." This ran `active: true` unconditionally —
    // Life (a real Conway's-game-of-life simulation) and MatrixRain in
    // particular are genuinely expensive continuous Canvas repaints, and
    // this box sat there running for the ENTIRE time Theme was the open
    // settings section, whether or not the user was even looking at this
    // part of the page. `_previewLive` now starts false (hidden by
    // default, matching the entry's own wording) and the Loader is gated
    // on it; picking a different effect above sets it back to true (also
    // per the entry's own wording — a changed selection is exactly the
    // moment a live look is actually wanted), and a small toggle lets the
    // user turn it off again (or back on) whenever they like.
    SettingsGroup {
        id: ambientPreviewGroup
        title: "Ambient effect preview"
        preview: true
        visible: Config.LockPrefs.effect !== "none"

        property bool previewLive: false
        // Auto-shows the preview the moment the selection actually
        // changes. Explicit id reference, not a bare `parent` — Connections
        // is a plain QtObject, not an Item, so its own `parent` is not
        // reliably the enclosing SettingsGroup the way an Item's would be
        // (the same class of gotcha Widgets/Panel.qml's own header already
        // flags for a *different* parent-vs-contentItem indirection).
        Connections {
            target: Config.LockPrefs
            function onEffectChanged() { ambientPreviewGroup.previewLive = true }
        }

        SettingsRow {
            wide: true
            title: "Live preview"
            // docs/TODO.md follow-up (user, 2026-09-15): "the preview
            // header is covering most part of the preview area" — this
            // description used to stay populated (a full sentence) even
            // while the preview was actually showing, on top of the
            // group's own title/caption above and the Show/Hide button
            // below, all stacked ahead of a comparatively small 20ch-tall
            // canvas. Empty string while live (SettingsRow's own
            // description Text is `visible: description.length > 0`, so
            // this removes the line entirely rather than leaving it
            // blank) — the explanatory sentence only earns its keep while
            // there is nothing else to look at yet.
            description: ambientPreviewGroup.previewLive
                ? ""
                : "Hidden by default — some effects are expensive to render continuously. Pick a different effect above, or show it manually."
            Column {
                width: parent.width
                spacing: root.gap
                Widgets.SmallButton {
                    label: ambientPreviewGroup.previewLive ? "Hide preview" : "Show preview"
                    onClicked: ambientPreviewGroup.previewLive = !ambientPreviewGroup.previewLive
                }
                Item {
                    width: parent.width
                    // Was chWidth*20 — nearly as tall as the header chrome
                    // stacked above it (group title+caption, this row's
                    // own title, the Show/Hide button), which is what
                    // read as "the header covers most of the preview".
                    // Close to doubled so the actual live effect is the
                    // dominant visual element once shown, not a small box
                    // squeezed under a wall of text.
                    height: root.chWidth * 34
                    clip: true
                    visible: ambientPreviewGroup.previewLive

                    Loader {
                        anchors.fill: parent
                        // Settings/Settings.qml's own Loader already
                        // destroys this whole section (and everything in
                        // it) the moment another section becomes active,
                        // so there is no separate "on this page but
                        // scrolled off" state worth guarding against here
                        // beyond previewLive itself.
                        active: ambientPreviewGroup.previewLive
                        sourceComponent: {
                            switch (Config.LockPrefs.effect) {
                            case "lava": return lavaPreview
                            case "matrix": return matrixPreview
                            case "starfield": return starPreview
                            case "plasma": return plasmaPreview
                            case "life": return lifePreview
                            case "boids": return boidsPreview
                            default: return null
                            }
                        }
                    }
                    // Speed/intensity/per-effect-param bindings so the
                    // preview actually shows what the fields above are set
                    // to, live, matching what Lock/Lock.qml itself will
                    // use at the next real lock — same defaults as that
                    // file's own component list.
                    Component { id: lavaPreview; LockFx.LavaLamp {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("lava")
                        blobCount: Config.LockPrefs.paramFor("lava", "blobCount", 9)
                        wobble: Config.LockPrefs.paramFor("lava", "wobble", 1.0)
                    } }
                    Component { id: matrixPreview; LockFx.MatrixRain {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("matrix")
                        density: Config.LockPrefs.paramFor("matrix", "density", 1.0)
                    } }
                    Component { id: starPreview; LockFx.Starfield {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("starfield")
                        starCount: Config.LockPrefs.paramFor("starfield", "starCount", 140)
                    } }
                    Component { id: plasmaPreview; LockFx.Plasma {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("plasma")
                        resolution: Config.LockPrefs.paramFor("plasma", "resolution", 1.0)
                    } }
                    Component { id: lifePreview; LockFx.Life {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("life")
                        resolution: Config.LockPrefs.paramFor("life", "resolution", 1.0)
                        seedDensity: Config.LockPrefs.paramFor("life", "seedDensity", 0.28)
                    } }
                    Component { id: boidsPreview; LockFx.Boids {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("boids")
                        boidCount: Config.LockPrefs.paramFor("boids", "boidCount", 40)
                    } }
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
                        id: noneTile
                        width: root.chWidth * 12; height: root.chWidth * 8
                        radius: Config.Appearance.radiusSmall
                        color: Config.Appearance.surface1
                        border.width: Config.Appearance.borderWidth
                        // Style pass: thumbnails had no hover affordance at
                        // all — a hairline brightens on hover, distinct from
                        // the (unchanged) accent border that marks the
                        // CURRENT selection, so "hovering" and "selected"
                        // never read as the same thing.
                        border.color: Services.Background.image.length === 0
                            ? Config.Appearance.accent
                            : ((noneHover.hovered || noneTile.activeFocus) ? Config.Appearance.borderStrong : Config.Appearance.border)
                        Behavior on border.color {
                            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                        Widgets.StyledText { anchors.centerIn: parent; kind: "label"; sizeStep: 0; text: "none" }
                        HoverHandler { id: noneHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Services.Background.clearImage() }
                        // Style pass 2026-09-14: same "not even Tab-
                        // reachable" gap as the colour swatches above —
                        // see that fix's own comment.
                        activeFocusOnTab: true
                        Keys.onReturnPressed: Services.Background.clearImage()
                        Keys.onSpacePressed: Services.Background.clearImage()
                    }

                    Repeater {
                        model: Services.Background.available
                        Rectangle {
                            id: wpTile
                            required property string modelData
                            width: root.chWidth * 12; height: root.chWidth * 8
                            radius: Config.Appearance.radiusSmall
                            color: Config.Appearance.surface1
                            clip: true
                            border.width: Config.Appearance.borderWidth
                            border.color: Services.Background.image === modelData
                                ? Config.Appearance.accent
                                : ((wpHover.hovered || wpTile.activeFocus) ? Config.Appearance.borderStrong : Config.Appearance.border)
                            Behavior on border.color {
                                ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                            }
                            Image {
                                anchors.fill: parent
                                anchors.margins: Config.Appearance.borderWidth
                                source: "file://" + modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 256
                            }
                            HoverHandler { id: wpHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Services.Background.setImage(modelData) }
                            // Style pass 2026-09-14: same fix as the
                            // colour swatches / "none" tile above.
                            activeFocusOnTab: true
                            Keys.onReturnPressed: Services.Background.setImage(modelData)
                            Keys.onSpacePressed: Services.Background.setImage(modelData)
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

    // panels-ux-rework: the global "reset every override" is a footer
    // action at the very bottom of the section now, behind a rule — it used
    // to sit mid-list between Animations and Night shift, reading as a row
    // that belonged to neither.
    Column {
        width: parent.width
        spacing: Config.Appearance.space2 * root.chWidth
        Widgets.Separator { width: parent.width }
        Row {
            width: parent.width
            layoutDirection: Qt.RightToLeft
            Widgets.StyledButton {
                label: "Reset all theme overrides"
                // Style pass 2026-09-14: the same bulk-irreversible-action
                // gap this section's "Clear all keys" (Devices.qml) and the
                // notification panel's "Clear all"/per-app "clear" already
                // got fixed for — every colour, font, size, radius and
                // motion override the user has made, gone in one click,
                // with no confirmation at all.
                onClicked: Services.ConfirmDialog.open({
                    title: "Reset all theme overrides",
                    message: "Removes every colour, font, size and motion override you've made and returns to the design defaults. This cannot be undone.",
                    confirmLabel: "Reset all",
                    onConfirm: () => { Config.ThemeOverrides.clearAll(); resetSignal.fired() }
                })
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
