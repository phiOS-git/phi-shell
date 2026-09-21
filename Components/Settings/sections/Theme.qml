import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../modules" as Modules
import "../modules/options.js" as Options
import "../../Lock/screensavers" as LockFx


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

    // Keeps pendingVariant in sync when the variant changes from outside this
    // row's own click handler — the schedule can switch it on its own timer.
    Connections {
        target: Config.Appearance
        function onVariantChanged() { root.pendingVariant = Config.Appearance.variant }
    }

    // The token key whose editor panel is open. One at a time across every
    // colour group, so at most one editor panel is ever slid open under the
    // grids.
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

    // A grid of swatches with one editor panel that slides open beneath the
    // group. `swatches`: list of {key, label, contrast} where key is a token
    // name, contrast opts into the live `phi theme contrast` check.
    component ColorGroup: Modules.SettingsGroup {
        id: cg
        property var swatches: []

        // The swatch entry in THIS group that is open, or null. ColorEditor
        // keeps the last non-null one through the close animation — panel does
        // not blank while it collapses.
        readonly property var _openEntry: {
            for (var i = 0; i < cg.swatches.length; i++)
                if (cg.swatches[i].key === root._openColor) return cg.swatches[i]
            return null
        }

        Item { width: 1; height: Math.round(root.chWidth * Config.Appearance.space1) }

        // The swatch grid. Each tile is fixed size — the grid never reflows on
        // edit. Each registers its `theme.colors.<key>` optionId — search
        // selection still lands on an individual colour.
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
                    // This tile had an open/selected wash, a search-match wash
                    // and a pulse-on-reveal — every state except the one that
                    // tells you it is clickable before you click.
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

                    // A raw Rectangle+TapHandler composition is not
                    // Tab-reachable by default, unlike the shared Widgets/
                    // controls — without this, keyboard navigation through
                    // Settings → Theme silently skipped the whole colour
                    // swatch grid.
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
        // Hold the last non-null entry — panel keeps its content while the
        // Reveal collapses on close.
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
    component MotionRow: Modules.SettingsRow {
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

    component TokenNumberRow: Modules.SettingsRow {
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

    component TokenFontRow: Modules.SettingsRow {
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
                    // The field stays — a power user who already knows the
                    // exact family name can still just type it — but "Browse…"
                    // reveals every font Qt actually has installed
                    // (Qt.fontFamilies(), a plain Qt API — no subprocess
                    // needed, unlike Widgets/SoundPicker's directory scan),
                    // filterable, tap to select.
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
                        // re-queried on every keystroke — Qt.fontFamilies() is
                        // a real OS font-enumeration call, not a cheap
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
                                        interactive: true
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

    // A tile-shaped loading placeholder for the wallpaper grids: the same
    // quiet "breathe" (motion category A) Widgets/Skeleton.qml uses, filling
    // whichever tile it sits on, so a thumbnail still decoding or a .heic
    // preview still converting reads as "loading", not a blank box. `visible`
    // gates it, and the animation stops when it hides.
    component WallpaperTileSkeleton: Rectangle {
        id: wts
        anchors.fill: parent
        // Same inset as the tile's Image layers, so the tile's own border (hover /
        // selection) stays visible on top of the placeholder.
        anchors.margins: Config.Appearance.borderWidth
        radius: Config.Appearance.radiusSmall
        color: Config.Appearance.surface2
        SequentialAnimation on opacity {
            running: wts.visible
            loops: Animation.Infinite
            NumberAnimation {
                from: 1.0; to: 0.4
                duration: Config.Appearance.motionAPeriod / 2
                easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
            }
            NumberAnimation {
                from: 0.4; to: 1.0
                duration: Config.Appearance.motionAPeriod / 2
                easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
            }
        }
    }

    // One static wallpaper tile in the picker grid: thumbnail, hover / active
    // border, keyboard reachability and the breathing placeholder while
    // decoding — shared by the flat row of root-folder files and every
    // subfolder section, so both look identical. `loading` gates the source: a
    // collapsed section passes false, and nothing decodes until the section
    // opens.
    component StaticWallpaperTile: Rectangle {
        id: sTile
        required property string modelData
        property bool loading: true
        width: root.chWidth * 12; height: root.chWidth * 8
        radius: Config.Appearance.radiusSmall
        color: Config.Appearance.surface1
        clip: true
        border.width: Config.Appearance.borderWidth
        border.color: Services.Background.image === sTile.modelData
            ? Config.Appearance.accent
            : ((sHover.hovered || sTile.activeFocus) ? Config.Appearance.borderStrong : Config.Appearance.border)
        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Image {
            id: sImg
            anchors.fill: parent
            anchors.margins: Config.Appearance.borderWidth
            source: sTile.loading ? "file://" + sTile.modelData : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 256
        }
        // Breathing placeholder while the thumbnail decodes, so the tile reads as
        // loading instead of a blank box.
        WallpaperTileSkeleton {
            visible: sTile.loading && sImg.status === Image.Loading
        }
        HoverHandler { id: sHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Services.Background.setImage(sTile.modelData) }
        // Same Tab-reachability fix as the colour swatches / "none" tile.
        activeFocusOnTab: true
        Keys.onReturnPressed: Services.Background.setImage(sTile.modelData)
        Keys.onSpacePressed: Services.Background.setImage(sTile.modelData)
    }

    // --- Appearance ----------------------------------------------------
    Modules.SettingsGroup {
        title: "Appearance"
        Modules.SettingsRow {
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
        Modules.SettingsRow {
            optionId: "theme.schedule"
            title: "Schedule"
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
            Modules.SettingsRow {
                title: "Automatic window"
                description: "Fixed default — dark from " + Services.ThemeSchedule.autoStartHour + ":00 to "
                    + Services.ThemeSchedule.autoEndHour + ":00, light the rest of the day. Not location-based: this shell has no source for a real sunset/sunrise time, so it's a sensible fixed evening-to-morning window rather than one computed per day. Use Custom hours to pick your own."
                wide: true
            }
        }
        Widgets.Reveal {
            shown: Services.ThemeSchedule.scheduleMode === "custom"
            Modules.SettingsRow {
                title: "Dark starts at"
                Widgets.NumberField {
                    value: Services.ThemeSchedule.scheduleStartHour
                    step: 1; suffix: ":00"; from: 0; to: 23
                    onCommitted: (v) => Services.ThemeSchedule.setScheduleStartHour(Math.round(v))
                }
            }
            Modules.SettingsRow {
                title: "Light starts at"
                Widgets.NumberField {
                    value: Services.ThemeSchedule.scheduleEndHour
                    step: 1; suffix: ":00"; from: 0; to: 23
                    onCommitted: (v) => Services.ThemeSchedule.setScheduleEndHour(Math.round(v))
                }
            }
        }
    }

    // --- Colours ------------------------------------------------------
    // Grouped by context, each a ColorGroup — a stable swatch grid plus one
    // slide-open editor panel (see the component).
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

    Modules.SettingsGroup {
        title: "Colour preview"
        preview: true

        Modules.SettingsRow {
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
    Modules.SettingsGroup {
        title: "Typography"
        TokenFontRow { tokenKey: "font-mono"; title: "Mono font"; previewFamily: Config.Appearance.fontMono
            description: "Terminal, code, and the whole UI's spacing rhythm (1ch)." }
        TokenFontRow { tokenKey: "font-reading"; title: "Reading font"; previewFamily: Config.Appearance.fontReading
            description: "Long-form prose surfaces." }
        TokenFontRow { tokenKey: "font-ui"; title: "UI font"; previewFamily: Config.Appearance.fontUi
            description: "Labels, buttons, most interface text." }
    }

    // --- Shape & spacing -----------------------------------------
    Modules.SettingsGroup {
        title: "Shape & spacing"
        caption: "Scales multiply the whole generated set. Sliders are deliberately not used here — a theme value should be set, not swept."
        TokenNumberRow { tokenKey: "font-scale"; title: "Font scale"; step: 0.05; decimals: 2; from: 0.5; to: 2.0 }
        TokenNumberRow { tokenKey: "space-scale"; title: "Spacing scale"; step: 0.05; decimals: 2; from: 0.5; to: 2.0 }
        TokenNumberRow { tokenKey: "radius-base"; title: "Radius, base"; step: 1; suffix: "px"; from: 0; to: 24 }
        TokenNumberRow { tokenKey: "radius-small"; title: "Radius, small (bar isles)"; step: 1; suffix: "px"; from: 0; to: 24 }
        TokenNumberRow { tokenKey: "radius-large"; title: "Radius, large (runner)"; step: 1; suffix: "px"; from: 0; to: 24 }
        TokenNumberRow {
            tokenKey: "panel-gap"; title: "Panel gap"; step: 1; suffix: "px"; from: 0; to: 24
            description: "Gap between floating panels and the bar or screen edges."
        }
        TokenNumberRow {
            tokenKey: "panel-radius"; title: "Panel corner radius"; step: 1; suffix: "px"; from: 0; to: 24
            description: "Corner rounding of floating panels."
        }
        // Not a TokenNumberRow/ThemeOverrides value like its siblings — those
        // only ever affect phi-shell's own rendering, but this one has to
        // reach kitty, so it goes through `phi state` (Services/Terminal.qml)
        // and a real `phi theme set` re-render instead, reusing this section's
        // own `setVariant` plumbing to apply immediately rather than only on
        // the next manual theme switch.
        Modules.SettingsRow {
            optionId: "theme.shape.terminal-padding"
            title: "Terminal window padding"
            description: "Applies to new kitty windows."
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
    Modules.SettingsGroup {
        title: "Animations"
        optionId: "theme.animations"
        caption: "The four style-plan motion categories. Category B is every state transition — panels, drawers, workspaces, notifications — so its duration and curve reach the whole shell. A is the agent's tracking indicator, C the rare boot/unlock effects, D ambient (off by default)."

        MotionRow { mkey: "motion-b-duration"; title: "B — transition duration"; seedMs: Config.Appearance.motionBDuration }

        Modules.SettingsRow {
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
    Modules.SettingsGroup {
        title: "Night shift"
        Modules.SettingsRow {
            optionId: "theme.nightshift"
            title: "Night shift"
            description: Services.NightShift.scheduleMode === "off"
                ? "Warms the display in the evening."
                : "Follows the schedule below — toggling here holds until its next change."
            Widgets.Toggle {
                checked: Services.NightShift.enabled
                onToggled: (v) => Services.NightShift.setEnabled(v)
            }
        }
        Modules.SettingsRow {
            title: "Schedule"
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
            Modules.SettingsRow {
                title: "Automatic window"
                description: "Fixed default — " + Services.NightShift.autoStartHour + ":00 to "
                    + Services.NightShift.autoEndHour + ":00. Not location-based: this shell has no source for a real sunset/sunrise time, so it's a sensible fixed evening-to-morning window rather than one computed per day. Use Custom hours to pick your own."
                wide: true
            }
        }
        Widgets.Reveal {
            shown: Services.NightShift.scheduleMode === "custom"
            Modules.SettingsRow {
                title: "Starts at"
                Widgets.NumberField {
                    value: Services.NightShift.scheduleStartHour
                    step: 1; suffix: ":00"; from: 0; to: 23
                    onCommitted: (v) => Services.NightShift.setScheduleStartHour(Math.round(v))
                }
            }
            Modules.SettingsRow {
                title: "Ends at"
                Widgets.NumberField {
                    value: Services.NightShift.scheduleEndHour
                    step: 1; suffix: ":00"; from: 0; to: 23
                    onCommitted: (v) => Services.NightShift.setScheduleEndHour(Math.round(v))
                }
            }
        }
        Modules.SettingsRow {
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
        Modules.SettingsRow {
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
    Modules.SettingsGroup {
        title: "Cursor spotlight"
        caption: "Double-press Super and hold to show it; the toggle here is sticky. Dim and flashlight dim the screen around a clear circle; crosshair and ring just mark the pointer and never dim."

        Modules.SettingsRow {
            optionId: "theme.spotlight"
            title: "Cursor spotlight"
            Widgets.Toggle {
                checked: Services.Spotlight.shown
                onToggled: (v) => (v ? Services.Spotlight.show() : Services.Spotlight.hide())
            }
        }
        Modules.SettingsRow {
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

        // dim / flashlight options slide in/out with the effect choice rather
        // than the sub-rows popping.
        Widgets.Reveal {
            shown: Services.Spotlight.effect === "dim" || Services.Spotlight.effect === "flashlight"
            Modules.SettingsRow {
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
            Modules.SettingsRow {
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
            Modules.SettingsRow {
                title: "Line thickness"
                Widgets.NumberField {
                    value: Services.Spotlight.crosshairThickness
                    step: 1; suffix: "px"; from: 1; to: 8
                    onCommitted: (v) => Services.Spotlight.setCrosshairThickness(v)
                }
            }
            Modules.SettingsRow {
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
            Modules.SettingsRow {
                title: "Ring radius"
                Widgets.NumberField {
                    value: Services.Spotlight.ringRadius
                    step: 5; suffix: "px"; from: 20; to: 240
                    onCommitted: (v) => Services.Spotlight.setRingRadius(v)
                }
            }
            Modules.SettingsRow {
                title: "Ring thickness"
                Widgets.NumberField {
                    value: Services.Spotlight.ringThickness
                    step: 1; suffix: "px"; from: 1; to: 12
                    onCommitted: (v) => Services.Spotlight.setRingThickness(v)
                }
            }
        }
    }

    // --- Screen magnifier ------------------------------------ The loupe (Magnifier/Magnifier.qml).
    // Runtime UI state stored through `phi state` by Services/Magnifier, same
    // category as the spotlight size — not a design token.
    Modules.SettingsGroup {
        title: "Screen magnifier"
        Modules.SettingsRow {
            optionId: "theme.magnifier"
            title: "Magnifier loupe"
            description: "Super+Z toggles it. Super + = / - zoom; with Shift, the lens size."
            Widgets.Toggle {
                checked: Services.Magnifier.shown
                onToggled: (v) => (v ? Services.Magnifier.show() : Services.Magnifier.hide())
            }
        }
        Modules.SettingsRow {
            title: "Zoom"
            Widgets.NumberField {
                value: Services.Magnifier.zoom
                step: 0.5; suffix: "×"; from: 1.5; to: 6; decimals: 1
                onCommitted: (v) => Services.Magnifier.setZoom(v)
            }
        }
        Modules.SettingsRow {
            title: "Lens size"
            Widgets.NumberField {
                value: Services.Magnifier.size
                step: 20; suffix: "px"; from: 180; to: 720
                onCommitted: (v) => Services.Magnifier.setSize(Math.round(v))
            }
        }
    }

    // --- Clock ---------------------------------------------------
    // Stored in Config/ClockPrefs.qml, read by Bar/modules/Clock.qml.
    // Same shape and reasoning as the Lock screen group just.
    Modules.SettingsGroup {
        title: "Clock"
        optionId: "theme.clock"

        Modules.SettingsRow {
            title: "12-hour clock"
            Widgets.Toggle {
                checked: Config.ClockPrefs.hour12
                onToggled: (v) => Config.ClockPrefs.setHour12(v)
            }
        }
        Modules.SettingsRow {
            title: "Show seconds"
            Widgets.Toggle {
                checked: Config.ClockPrefs.showSeconds
                onToggled: (v) => Config.ClockPrefs.setShowSeconds(v)
            }
        }
        Modules.SettingsRow {
            title: "Date"
            description: "Short: 13/09. Long: Sat 13 Sep 2026."
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
    // The screensaver backdrop behind the lock screen.
    // Stored in Config/LockPrefs.qml ($XDG_STATE_HOME/phi/lock.json), read by Lock/Lock.qml.
    // Runtime UI state, not a design token — same category as the spotlight size.
    Modules.SettingsGroup {
        title: "Lock screen"
        optionId: "theme.lockscreen"
        Modules.SettingsRow {
            title: "Screensaver"
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

        // Speed applies to whichever effect is picked; Intensity is scoped to
        // the CURRENTLY selected effect specifically, each with its own stored
        // value and its own default.
        Modules.SettingsRow {
            visible: Config.LockPrefs.effect !== "none"
            title: "Speed"
            Widgets.NumberField {
                value: Config.LockPrefs.speed
                from: 0.25; to: 3.0; step: 0.25; decimals: 2
                suffix: "×"
                onCommitted: (v) => Config.LockPrefs.setSpeed(v)
            }
        }
        Modules.SettingsRow {
            visible: Config.LockPrefs.effect !== "none"
            title: "Intensity"
            Widgets.NumberField {
                // Plain binding: QML tracks property reads through function
                // calls, so this re-evaluates correctly on either property
                // change. NumberField's onValueChanged re-syncs on external
                // changes (unless mid-edit).
                value: Config.LockPrefs.intensityFor(Config.LockPrefs.effect)
                from: 0.05; to: 1.0; step: 0.05; decimals: 2
                onCommitted: (v) => Config.LockPrefs.setIntensity(Config.LockPrefs.effect, v)
            }
        }

        // One settings block per effect, visible only while that effect is the
        // one actually selected — showing all six effects' own extra knobs at
        // once would just be clutter, when only one of them can ever be active
        // at a time anyway.
        Modules.SettingsRow {
            visible: Config.LockPrefs.effect === "lava"
            title: "Lava lamp"
            description: "Wobble spreads the blob sizes."
            // The default compact layout right-aligns a content-sized slot
            // sized for ONE small control. This row's slot holds a whole
            // Column of label+field pairs (Blob count, Wobble), so it needs
            // the full-width `wide` layout or it overflows the dialog's edge.
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
        Modules.SettingsRow {
            visible: Config.LockPrefs.effect === "matrix"
            title: "Matrix"
            Widgets.NumberField {
                value: Config.LockPrefs.paramFor("matrix", "density", 1.0)
                from: 0.4; to: 2.0; step: 0.2; decimals: 1; suffix: "×"
                onCommitted: (v) => Config.LockPrefs.setParam("matrix", "density", v)
            }
        }
        Modules.SettingsRow {
            visible: Config.LockPrefs.effect === "starfield"
            title: "Starfield"
            Widgets.NumberField {
                value: Config.LockPrefs.paramFor("starfield", "starCount", 140)
                from: 30; to: 400; step: 10
                onCommitted: (v) => Config.LockPrefs.setParam("starfield", "starCount", Math.round(v))
            }
        }
        Modules.SettingsRow {
            visible: Config.LockPrefs.effect === "plasma"
            title: "Plasma"
            description: "Higher is finer and costs more to draw."
            Widgets.NumberField {
                value: Config.LockPrefs.paramFor("plasma", "resolution", 1.0)
                from: 0.5; to: 2.0; step: 0.25; decimals: 2; suffix: "×"
                onCommitted: (v) => Config.LockPrefs.setParam("plasma", "resolution", v)
            }
        }
        Modules.SettingsRow {
            visible: Config.LockPrefs.effect === "life"
            title: "Life"
            description: "Seed density is how much of the board starts alive."
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
        Modules.SettingsRow {
            visible: Config.LockPrefs.effect === "boids"
            title: "Boids"
            Widgets.NumberField {
                value: Config.LockPrefs.paramFor("boids", "boidCount", 40)
                from: 10; to: 120; step: 5
                onCommitted: (v) => Config.LockPrefs.setParam("boids", "boidCount", Math.round(v))
            }
        }
    }

    // A live instance of the selected lock effect, not a screenshot. Effects
    // scale off width/height. Life and MatrixRain are expensive continuous
    // renders, so the preview is gated on `previewLive` and toggled by the user;
    // selecting a different effect turns it back on.
    Modules.SettingsGroup {
        id: screensaverPreviewGroup
        title: "Screensaver preview"
        preview: true
        visible: Config.LockPrefs.effect !== "none"

        property bool previewLive: false
        // Auto-shows the preview the moment the selection actually changes.
        // Explicit id reference, not a bare `parent` — Connections is a plain
        // QtObject, not an Item, so its own `parent` is not reliably the
        // enclosing Modules.SettingsGroup the way an Item's would be.
        Connections {
            target: Config.LockPrefs
            // A changed selection is exactly the moment a live look is wanted,
            // and a fresh effect starts from a fresh simulated auth state —
            // the same way a real lock never surfaces with a mid-verification
            // or mid-cooldown state still running.
            function onEffectChanged() {
                screensaverPreviewGroup.previewLive = true
                screensaverPreviewGroup.fxValidating = false
                screensaverPreviewGroup.fxLockedOut = false
                screensaverPreviewGroup.fxLockoutRemaining = 0
            }
        }

        // --- simulated lock/auth state -----------------------------------
        // The feature buttons fake the auth states the lock really produces.
        // Durations are the real ones: the ~2s verification wait and the 30s
        // lockout cooldown.
        property bool fxValidating: false
        property bool fxLockedOut: false
        readonly property int fxLockoutSeconds: 30
        property int fxLockoutRemaining: 0
        readonly property real fxLockoutProgress: screensaverPreviewGroup.fxLockoutSeconds > 0
            ? fxLockoutRemaining / screensaverPreviewGroup.fxLockoutSeconds : 0
        // The same category-A pulse Lock.qml's field border runs through a
        // real verification; the effects' `validationProgress` reads this, so the
        // preview breathes in step with the real screen.
        property real fxValidationPulse: 0.0
        SequentialAnimation on fxValidationPulse {
            running: screensaverPreviewGroup.fxValidating
            loops: Animation.Infinite
            NumberAnimation {
                to: 1.0
                duration: Config.Appearance.motionAPeriod / 2
                easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
            }
            NumberAnimation {
                to: 0.0
                duration: Config.Appearance.motionAPeriod / 2
                easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
            }
        }

        // Simulated PAM round-trip length — a real-world duration, not a
        // motion token.
        Timer {
            id: verifySim
            interval: 2000
            onTriggered: screensaverPreviewGroup.fxValidating = false
        }

        // The 30s lockout cooldown, counting down exactly like Lock.qml's own
        // lockoutCountdown timer.
        Timer {
            id: lockoutSim
            interval: 1000
            repeat: true
            running: screensaverPreviewGroup.fxLockedOut
            onTriggered: {
                screensaverPreviewGroup.fxLockoutRemaining -= 1
                if (screensaverPreviewGroup.fxLockoutRemaining <= 0) {
                    screensaverPreviewGroup.fxLockedOut = false
                    screensaverPreviewGroup.fxLockoutRemaining = 0
                }
            }
        }

        // Same typeof-guarded broadcast Lock.qml's _pulseScreensaver uses: an
        // effect without triggerValidation() (all but Plasma) is simply never
        // called.
        function _pulsePreview(success) {
            var fx = previewLoader.item
            if (fx && typeof fx.triggerValidation === "function") fx.triggerValidation(success)
        }

        // Feature catalogue helpers for the test buttons: the label, the
        // active highlight, the enable guard and the trigger for each feature
        // id a screensaver declares in its `features` list.
        function _featureLabel(id) {
            switch (id) {
            case "verification":
                return screensaverPreviewGroup.fxValidating ? "Verifying…" : "Verify"
            case "lockout":
                return screensaverPreviewGroup.fxLockedOut
                    ? "Locked — " + screensaverPreviewGroup.fxLockoutRemaining + "s"
                    : "Locked account"
            case "wave-wrong": return "Wrong password"
            case "wave-correct": return "Correct password"
            default: return id
            }
        }
        function _featureActive(id) {
            if (id === "verification") return screensaverPreviewGroup.fxValidating
            if (id === "lockout") return screensaverPreviewGroup.fxLockedOut
            return false
        }
        function _featureEnabled(id) {
            // Mutually exclusive, mirroring the real screen's respond() guard:
            // no verification while locked out, no lockout while a
            // verification is running.
            if (id === "verification") return !screensaverPreviewGroup.fxLockedOut
            if (id === "lockout") return !screensaverPreviewGroup.fxValidating
            return true
        }
        function _triggerFeature(id) {
            switch (id) {
            case "verification":
                if (screensaverPreviewGroup.fxValidating) {
                    screensaverPreviewGroup.fxValidating = false
                    verifySim.stop()
                } else {
                    screensaverPreviewGroup.fxValidating = true
                    verifySim.restart()
                }
                break
            case "lockout":
                if (screensaverPreviewGroup.fxLockedOut) {
                    screensaverPreviewGroup.fxLockedOut = false
                    screensaverPreviewGroup.fxLockoutRemaining = 0
                } else {
                    screensaverPreviewGroup.fxLockedOut = true
                    screensaverPreviewGroup.fxLockoutRemaining = screensaverPreviewGroup.fxLockoutSeconds
                }
                break
            case "wave-wrong": screensaverPreviewGroup._pulsePreview(false); break
            case "wave-correct": screensaverPreviewGroup._pulsePreview(true); break
            default: break
            }
        }

        Modules.SettingsRow {
            wide: true
            title: "Live preview"
            // Empty while live: otherwise it stays stacked alongside the
            // canvas, the group's title/caption and the Show/Hide button,
            // crowding a small preview area. The explanatory sentence only
            // earns its keep while there is nothing else to look at.
            description: screensaverPreviewGroup.previewLive
                ? ""
                : "Hidden by default — some effects are expensive to render continuously. Pick a different effect above, or show it manually."
            Column {
                width: parent.width
                spacing: root.gap
                Widgets.SmallButton {
                    label: screensaverPreviewGroup.previewLive ? "Hide preview" : "Show preview"
                    onClicked: screensaverPreviewGroup.previewLive = !screensaverPreviewGroup.previewLive
                }
                // One test button per reaction the SELECTED effect declares in
                // its `features` list, so the row is a truthful catalogue,
                // never a fixed set. Every effect answers "verification" (the
                // ~2s wait) and "lockout" (the 30s cooldown) through the state
                // bindings; only Plasma adds the outcome-wave entries.
                // Clicking drives the simulated states on the preview instance
                // exactly the way Lock.qml wires the real lock —
                // _triggerFeature. The two state toggles are mutually
                // exclusive like the real screen (respond() is guarded by
                // !lockedOut), enforced in _featureEnabled.
                Flow {
                    width: parent.width
                    spacing: root.gap
                    visible: screensaverPreviewGroup.previewLive
                    Repeater {
                        model: previewLoader.item ? previewLoader.item.features : []
                        delegate: Widgets.SmallButton {
                            required property string modelData
                            label: screensaverPreviewGroup._featureLabel(modelData)
                            active: screensaverPreviewGroup._featureActive(modelData)
                            enabled: screensaverPreviewGroup._featureEnabled(modelData)
                            onClicked: screensaverPreviewGroup._triggerFeature(modelData)
                        }
                    }
                }
                Item {
                    width: parent.width
                    // Tall enough that the live effect reads as the dominant
                    // visual element once shown, rather than a small box
                    // squeezed under the header chrome it.
                    height: root.chWidth * 34
                    clip: true
                    visible: screensaverPreviewGroup.previewLive

                    Loader {
                        id: previewLoader
                        anchors.fill: parent
                        // Settings/Settings.qml's own Loader already destroys
                        // this whole section (and everything in it) the moment
                        // another section becomes active, so there is no
                        // separate "on this page but scrolled off" state worth
                        // guarding against beyond previewLive itself.
                        active: screensaverPreviewGroup.previewLive
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
                    // Speed/intensity/per-effect-param bindings — preview
                    // actually shows what the fields are set to, live,
                    // matching what Lock/Lock.qml itself will use at the next
                    // real lock — same defaults as that file's own component
                    // list. The lock/auth state bindings mirror Lock.qml's own
                    // fx wiring, fed by the simulated states and the buttons.
                    Component { id: lavaPreview; LockFx.LavaLamp {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("lava")
                        blobCount: Config.LockPrefs.paramFor("lava", "blobCount", 9)
                        wobble: Config.LockPrefs.paramFor("lava", "wobble", 1.0)
                        validating: screensaverPreviewGroup.fxValidating
                        validationProgress: screensaverPreviewGroup.fxValidationPulse
                        lockedOut: screensaverPreviewGroup.fxLockedOut
                        lockoutProgress: screensaverPreviewGroup.fxLockoutProgress
                    } }
                    Component { id: matrixPreview; LockFx.MatrixRain {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("matrix")
                        density: Config.LockPrefs.paramFor("matrix", "density", 1.0)
                        validating: screensaverPreviewGroup.fxValidating
                        validationProgress: screensaverPreviewGroup.fxValidationPulse
                        lockedOut: screensaverPreviewGroup.fxLockedOut
                        lockoutProgress: screensaverPreviewGroup.fxLockoutProgress
                    } }
                    Component { id: starPreview; LockFx.Starfield {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("starfield")
                        starCount: Config.LockPrefs.paramFor("starfield", "starCount", 140)
                        validating: screensaverPreviewGroup.fxValidating
                        validationProgress: screensaverPreviewGroup.fxValidationPulse
                        lockedOut: screensaverPreviewGroup.fxLockedOut
                        lockoutProgress: screensaverPreviewGroup.fxLockoutProgress
                    } }
                    Component { id: plasmaPreview; LockFx.Plasma {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("plasma")
                        resolution: Config.LockPrefs.paramFor("plasma", "resolution", 1.0)
                        validating: screensaverPreviewGroup.fxValidating
                        validationProgress: screensaverPreviewGroup.fxValidationPulse
                        lockedOut: screensaverPreviewGroup.fxLockedOut
                        lockoutProgress: screensaverPreviewGroup.fxLockoutProgress
                    } }
                    Component { id: lifePreview; LockFx.Life {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("life")
                        resolution: Config.LockPrefs.paramFor("life", "resolution", 1.0)
                        seedDensity: Config.LockPrefs.paramFor("life", "seedDensity", 0.28)
                        validating: screensaverPreviewGroup.fxValidating
                        validationProgress: screensaverPreviewGroup.fxValidationPulse
                        lockedOut: screensaverPreviewGroup.fxLockedOut
                        lockoutProgress: screensaverPreviewGroup.fxLockoutProgress
                    } }
                    Component { id: boidsPreview; LockFx.Boids {
                        running: true; speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("boids")
                        boidCount: Config.LockPrefs.paramFor("boids", "boidCount", 40)
                        validating: screensaverPreviewGroup.fxValidating
                        validationProgress: screensaverPreviewGroup.fxValidationPulse
                        lockedOut: screensaverPreviewGroup.fxLockedOut
                        lockoutProgress: screensaverPreviewGroup.fxLockoutProgress
                    } }
                }
            }
        }
    }

    // --- Wallpaper ------------------------------------------------
    // Three groups by context — the base layers, the image and how it fills
    // the screen, and the dynamic rotation — so options that belong together
    // sit together instead of being scattered down one long wall of rows.
    Modules.SettingsGroup {
        title: "Wallpaper — base"
        caption: "The solid colour underneath the picture, with an optional grain."
        Component.onCompleted: {
            Services.Background.refreshAvailable()
            Services.DynamicWallpaper.refresh()
        }

        Modules.SettingsRow {
            optionId: "theme.wallpaper.color"
            title: "Solid colour"
            Widgets.ColorField {
                value: Services.Background.color
                onCommitted: (hex) => Services.Background.setColor(hex)
            }
        }

        Modules.SettingsRow {
            optionId: "theme.wallpaper.texture"
            title: "Texture"
            description: Services.Background.textureApplies
                ? "A generated grain over the solid colour."
                : "Only with no image or contain/repeat."
            enabled: Services.Background.textureApplies
            Column {
                spacing: root.gap
                Row {
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
                    spacing: root.gap
                    visible: Services.Background.texture.length > 0
                    Widgets.StyledText { anchors.verticalCenter: parent.verticalCenter; kind: "label"; text: "Intensity" }
                    Widgets.Meter {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.chWidth * 14
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

    Modules.SettingsGroup {
        title: "Wallpaper — image"
        caption: "Pick a picture, then how it fills the screen."

        Modules.SettingsRow {
            optionId: "theme.wallpaper.image"
            title: "Image"
            wide: true
            Column {
                width: parent.width
                spacing: root.gap

                // "No image" tile, always available, outside the sections.
                Flow {
                    width: parent.width
                    spacing: 6

                    Rectangle {
                        id: noneTile
                        width: root.chWidth * 12; height: root.chWidth * 8
                        radius: Config.Appearance.radiusSmall
                        color: Config.Appearance.surface1
                        border.width: Config.Appearance.borderWidth
                        // A hairline brightens on hover, distinct from the
                        // accent border that marks the CURRENT selection, so
                        // "hovering" and "selected" never read as the same
                        // thing.
                        border.color: Services.Background.image.length === 0
                            ? Config.Appearance.accent
                            : ((noneHover.hovered || noneTile.activeFocus) ? Config.Appearance.borderStrong : Config.Appearance.border)
                        Behavior on border.color {
                            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                        Widgets.StyledText { anchors.centerIn: parent; kind: "label"; sizeStep: 0; text: "none" }
                        HoverHandler { id: noneHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Services.Background.clearImage() }
                        // Same Tab-reachability fix as the colour swatches
                        // above.
                        activeFocusOnTab: true
                        Keys.onReturnPressed: Services.Background.clearImage()
                        Keys.onSpacePressed: Services.Background.clearImage()
                    }

                    // The wallpaper folder's loose top-level files sit flat,
                    // next to "none"; only subfolders collapse.
                    Repeater {
                        model: Services.Background.rootImages
                        delegate: StaticWallpaperTile {
                            loading: true
                        }
                    }
                }

                // One collapsible section per subfolder of the wallpaper
                // folder. A closed section loads nothing: a tile only gets a
                // source once its section is open (is what stops a large
                // folder from decoding every thumbnail at once). The loose
                // top-level files are not a section — they sit flat beside
                // "none".
                Repeater {
                    model: Services.Background.groups.filter(g => g.name !== "General")
                    delegate: Widgets.Accordion {
                        id: section
                        required property var modelData
                        title: modelData.name
                        content:
                            Flow {
                                width: parent.width
                                spacing: 6
                                Repeater {
                                    model: section.modelData.images
                                    delegate: StaticWallpaperTile {
                                        loading: section.expanded
                                    }
                                }
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

        Modules.SettingsRow {
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

        Modules.SettingsRow {
            optionId: "theme.wallpaper.scale"
            title: "Scale"
            description: "Zoom for contain and repeat."
            enabled: Services.Background.image.length > 0
                && (Services.Background.mode === "contain" || Services.Background.mode === "repeat")
            Widgets.NumberField {
                value: Services.Background.scale
                step: 0.1; decimals: 1; from: 0.1; to: 4.0
                onCommitted: (v) => Services.Background.setScale(v)
            }
        }
    }

    // --- Dynamic wallpaper ----------------------------------------
    // Entries under wallpapers/dynamic/ that rotate the wallpaper by daytime,
    // season and (future) weather.
    // All state lives in Services/DynamicWallpaper.qml — this group only reads it and calls its setters.
    // While it is on, the image shown becomes the entry's most specific image for the current slot;
    // while off, or paused by battery saver, the static pick apply unchanged.
    Modules.SettingsGroup {
        title: "Wallpaper — dynamic"
        caption: "Rotate the wallpaper by time of day and season."

        Modules.SettingsRow {
            optionId: "theme.wallpaper.dynamic"
            title: "Dynamic wallpaper"
            Widgets.Toggle {
                checked: Services.DynamicWallpaper.enabled
                onToggled: (v) => Services.DynamicWallpaper.setEnabled(v)
            }
        }

        Modules.SettingsRow {
            optionId: "theme.wallpaper.dynamic.folder"
            title: "Entry"
            description: "A folder of state images, or a single dynamic .heic (solar or 24-hour timeline) right in wallpapers/dynamic/."
            enabled: Services.DynamicWallpaper.enabled
            wide: true
            Column {
                width: parent.width
                spacing: root.gap
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: Services.DynamicWallpaper.available
                        delegate: Rectangle {
                            id: dynTile
                            required property var modelData
                            width: root.chWidth * 12; height: root.chWidth * 8
                            radius: Config.Appearance.radiusSmall
                            color: Config.Appearance.surface1
                            clip: true
                            border.width: Config.Appearance.borderWidth
                            border.color: Services.DynamicWallpaper.activeName === modelData.name
                                ? Config.Appearance.accent
                                : ((dynHover.hovered || dynTile.activeFocus) ? Config.Appearance.borderStrong : Config.Appearance.border)
                            Behavior on border.color {
                                ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                            }

                            // What this entry previews: a folder cycles
                            // through the raster images it holds, one every
                            // 1.5s while hovered; a bare.heic shows its
                            // converted first frame.
                            readonly property var frames: modelData.kind === "folder"
                                ? modelData.images
                                : (Services.DynamicWallpaper.previews[modelData.name]
                                    ? [Services.DynamicWallpaper.previews[modelData.name]] : [])
                            property int cycleIdx: 0
                            property bool frontIsA: true
                            // True once any frame has actually painted on
                            // either layer; the skeleton then never shows
                            // again, even while hover-cycling swaps frames.
                            property bool _everReady: false
                            // A preview that never converts (an undecodable
                            // heic) stops breathing after this long instead of
                            // looking like it is loading forever. Long enough
                            // to cover a queued backlog of several big heic
                            // conversions.
                            property bool _giveUp: false

                            Timer {
                                id: previewWait
                                interval: 15000
                                running: dynTile.frames.length === 0 && !dynTile._everReady && !dynTile._giveUp
                                onTriggered: dynTile._giveUp = true
                            }

                            Component.onCompleted:
                                if (modelData.kind === "file") Services.DynamicWallpaper.ensureFilePreview(modelData.name)

                            // Two stacked layers; each cycle loads the next
                            // frame into the hidden one and crossfades, then
                            // the layers swap roles.
                            Image {
                                id: dynA
                                anchors.fill: parent
                                anchors.margins: Config.Appearance.borderWidth
                                source: dynTile.frames.length > 0
                                    ? "file://" + dynTile.frames[dynTile.cycleIdx % dynTile.frames.length] : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 256
                                onStatusChanged: if (status === Image.Ready) dynTile._everReady = true
                                Behavior on opacity {
                                    NumberAnimation { duration: Config.Appearance.motionBDuration * 2; easing.type: Easing.InOutQuad }
                                }
                            }
                            Image {
                                id: dynB
                                anchors.fill: parent
                                anchors.margins: Config.Appearance.borderWidth
                                opacity: 0
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 256
                                onStatusChanged: if (status === Image.Ready) dynTile._everReady = true
                                Behavior on opacity {
                                    NumberAnimation { duration: Config.Appearance.motionBDuration * 2; easing.type: Easing.InOutQuad }
                                }
                            }

                            // Breathing placeholder until this tile has
                            // something to paint: the.heic preview is still
                            // converting, or the first frame is still
                            // decoding. Once any frame has painted, hover-
                            // cycling swaps cached frames and the placeholder
                            // stays gone.
                            WallpaperTileSkeleton {
                                visible: (dynTile.frames.length === 0 && !dynTile._giveUp)
                                    || (dynTile.frames.length > 0 && !dynTile._everReady
                                        && (dynTile.frontIsA ? dynA.status === Image.Loading : dynB.status === Image.Loading))
                            }

                            Timer {
                                id: cycleTimer
                                interval: 1500
                                repeat: true
                                onTriggered: {
                                    var n = dynTile.frames.length
                                    if (n < 2) return
                                    var next = (dynTile.cycleIdx + 1) % n
                                    if (dynTile.frontIsA) {
                                        dynB.source = "file://" + dynTile.frames[next]
                                        dynA.opacity = 0
                                        dynB.opacity = 1
                                    } else {
                                        dynA.source = "file://" + dynTile.frames[next]
                                        dynB.opacity = 0
                                        dynA.opacity = 1
                                    }
                                    dynTile.frontIsA = !dynTile.frontIsA
                                    dynTile.cycleIdx = next
                                }
                            }

                            HoverHandler {
                                id: dynHover
                                cursorShape: Qt.PointingHandCursor
                                onHoveredChanged: {
                                    if (dynHover.hovered) { if (dynTile.frames.length > 1) cycleTimer.start() }
                                    else cycleTimer.stop()
                                }
                            }
                            TapHandler { onTapped: Services.DynamicWallpaper.setActive(modelData.name) }
                            activeFocusOnTab: true
                            Keys.onReturnPressed: Services.DynamicWallpaper.setActive(modelData.name)
                            Keys.onSpacePressed: Services.DynamicWallpaper.setActive(modelData.name)

                            // Name caption on a bottom band, so an entry with
                            // no previews (an empty folder) still reads as
                            // selectable.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: root.chWidth * 2
                                color: Config.Appearance.surface2
                                opacity: 0.85
                                Widgets.StyledText {
                                    anchors.left: parent.left
                                    anchors.leftMargin: root.chWidth
                                    anchors.right: parent.right
                                    anchors.rightMargin: root.chWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    kind: "label"; sizeStep: 0
                                    text: modelData.name
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                    Widgets.StyledText {
                        visible: Services.DynamicWallpaper.available.length === 0
                        kind: "label"; sizeStep: 0
                        text: "Nothing here yet — add a folder or a .heic under wallpapers/dynamic/."
                    }
                }
                Widgets.SmallButton {
                    label: "Open dynamic folder"
                    onClicked: Quickshell.execDetached(["xdg-open", Config.Paths.dynamicWallpaperDir])
                }
            }
        }

        Modules.SettingsRow {
            optionId: "theme.wallpaper.dynamic.dawn"
            title: "Sunrise starts at"
            description: "Dawn runs one hour from this hour."
            enabled: Services.DynamicWallpaper.enabled
            Widgets.NumberField {
                value: Services.DynamicWallpaper.dawnHour
                step: 1; suffix: ":00"; from: 0; to: 23
                onCommitted: (v) => Services.DynamicWallpaper.setDawnHour(v)
            }
        }

        Modules.SettingsRow {
            optionId: "theme.wallpaper.dynamic.dusk"
            title: "Sunset starts at"
            description: "Dusk runs one hour from this hour."
            enabled: Services.DynamicWallpaper.enabled
            Widgets.NumberField {
                value: Services.DynamicWallpaper.duskHour
                step: 1; suffix: ":00"; from: 0; to: 23
                onCommitted: (v) => Services.DynamicWallpaper.setDuskHour(v)
            }
        }

        // Read-only status — a cheap way to see what the matcher resolved
        // without waiting for a boundary: the slot, the season/weather
        // considered, and the filename actually painted. Only meaningful while
        // the feature is on, so it hides (not dims) when off.
        Modules.SettingsRow {
            visible: Services.DynamicWallpaper.enabled
            title: "Now showing"
            description: root._dynamicStatus()
            wide: true
        }

    }

    // The global "reset every override" sits as a footer action at the very
    // bottom of the section, behind a rule — not mid-list where it would read
    // as belonging to whichever group happened to be nearby.
    Column {
        width: parent.width
        spacing: Config.Appearance.space2 * root.chWidth
        Widgets.Separator { width: parent.width }
        Row {
            width: parent.width
            layoutDirection: Qt.RightToLeft
            Widgets.StyledButton {
                label: "Reset all theme overrides"
                // Confirmed like every other bulk-irreversible action — every
                // colour, font, size, radius and motion override gone in one
                // click deserves a confirmation.
                onClicked: Services.ConfirmDialog.open({
                    title: "Reset all theme overrides",
                    message: "Removes every colour, font, size and motion override you've made and returns to the design defaults. This cannot be undone.",
                    confirmLabel: "Reset all",
                    onConfirm: () => { Config.ThemeOverrides.clearAll(); resetSignal.fired() }
                })
            }
        }
    }

    function _dynamicStatus() {
        const s = Services.DynamicWallpaper
        if (s.activeName.length === 0) return "No entry picked."
        if (s.pausedByLowPower) return "Paused by battery saver — static image showing."
        if (s.solarFile.length > 0) {
            const fr = s.solarFrame < 0 ? "…" : String(s.solarFrame)
            const what = s.solarKind === "h24" ? "Timeline" : "Solar"
            return what + " " + s.solarFile + " — frame " + fr + " (" + s.solarTimeText + ")."
        }
        if (s.currentImage.length === 0) return "No image matches " + s.activeName + "."
        const parts = [s.currentDaytime]
        if (s.currentSeason.length > 0) parts.push(s.currentSeason)
        if (s.currentWeather.length > 0) parts.push(s.currentWeather)
        return s.currentImage.split("/").pop() + " (" + parts.join(" · ") + ")."
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
