import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs
import "." as Local

// Bar/modules/StatusMenu.qml's own card: profile row, power actions,
// real MPRIS media controls, compact system toggles, and the tiling-mode
// grid. No avatar-picture or per-session-length data source exists
// anywhere in this codebase — `_profileName` below and "session time"
// (Services.SystemInfo.uptime, the same figure General's own "System"
// card shows) are both real, just not what the original request assumed
// existed.

Widgets.StaggerReveal {
    id: root

    property real chWidth: 0
    property bool active: false

    shown: root.active
    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space2
    visible: root.active

    readonly property string _profileName: Quickshell.env("USER") || "user"

    // Session-local only — no native Hyprland concept exists for four of
    // these six (only Tile/dwindle-master and Floating are real; the
    // Grid's Column further down documents this for whoever reaches it
    // next). Selecting a non-real one only highlights the button.
    property string _tilingMode: "tile"
    function _applyTilingMode(id) {
        root._tilingMode = id
        if (id === "tile" || id === "floating") {
            var floating = (id === "floating") ? "true" : "false"
            Services.HyprlandBridge.dispatch(
                'function() for _, w in ipairs(hl.get_workspace_windows(hl.get_active_workspace())) do w.floating = '
                + floating + ' end end')
        }
    }

    Local.PowerActions { id: powerActions }

    // --- profile row --------------------------------------------------
    Widgets.OverlaySection {
        width: parent.width
        Row {
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space2

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: root.chWidth * 4
                height: width
                radius: width / 2
                color: Config.Appearance.colorOpposite
                Widgets.StyledText {
                    anchors.centerIn: parent
                    mono: true
                    sizeStep: 3
                    color: Config.Appearance.colorMain
                    text: root._profileName.length > 0 ? root._profileName.charAt(0).toUpperCase() : "?"
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.chWidth * Config.Appearance.space1 * 0.5
                Widgets.StyledText { kind: "title"; text: root._profileName }
                Widgets.StyledText {
                    kind: "label"; sizeStep: 0
                    text: "Uptime " + (Services.SystemInfo.uptime.length > 0 ? Services.SystemInfo.uptime : "—")
                }
            }
        }
    }

    // --- power actions, a full-width band of six equal tiled buttons ---
    Widgets.OverlaySection {
        width: parent.width
        Row {
            id: pwrRow
            width: parent.width
            spacing: 0
            Repeater {
                model: ["lock", "suspend", "hibernate", "logout", "reboot", "shutdown"]

                // One plain Item-rooted button per action, tiling the row's full
                // width edge-to-edge: with no spacing each button is
                // exactly one sixth of the row and as tall as it is wide
                // (1/1), the glyph centered with even padding on all four
                // sides. On hover the whole button fills
                // with its action's own semantic tone (powerActions.toneFor
                // — the same map PowerMenu's pills use, so a shutdown
                // action always reads error-red here too) and the glyph
                // flips to that tone's paired text token, carrying the
                // colour identity the way the pill row does. At rest the
                // tile is surface1-identical, ringed by a thin
                // borderWidth outline in borderStrong — the same visible
                // resting outline Radio and Checkbox draw; the plain
                // `border` hairline was effectively invisible on the
                // card — so the six read as bare power icons in outlined
                // slots; the glyphs stay uniformly textPrimary, differing
                // by shape (powerActions.glyph) alone until hovered.
                //
                // Plain Item, not Widgets.Panel, on purpose: Panel routes
                // declared children into its padded contentItem, and
                // pointer handlers only receive hover/click along the hit
                // item's own ancestry — a handler living inside contentItem
                // never reacts to a cursor over the background Rectangle
                // (its sibling), so only the glyph's own area ever hovered
                // while the wash still filled the whole tile. Rooting the
                // full-bleed wash Rectangle and both handlers on this Item
                // itself (the same shape as Widgets/IconButton — a click
                // target that is the entire control) puts every pixel of
                // the tile — wash, border, glyph — under the handlers.
                Item {
                    id: pwrBtn
                    required property string modelData
                    width: pwrRow.width / 6
                    height: width

                    Rectangle {
                        anchors.fill: parent
                        radius: Config.Appearance.radiusSmall
                        color: pwrHover.hovered
                            ? powerActions.toneFor(pwrBtn.modelData)
                            : "transparent"
                        border.width: Config.Appearance.borderWidth
                        border.color: Config.Appearance.borderStrong

                        Behavior on color {
                            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                    }

                    Widgets.StyledIcon {
                        anchors.centerIn: parent
                        glyph: powerActions.glyph(pwrBtn.modelData)
                        sizeStep: 3
                        color: pwrHover.hovered
                            ? powerActions.toneTextFor(pwrBtn.modelData)
                            : Config.Appearance.textPrimary
                    }

                    HoverHandler { id: pwrHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: powerActions.request(pwrBtn.modelData) }
                }
            }
        }
    }

    // --- media (only while a source is available) ----------------------
    Widgets.OverlaySection {
        width: parent.width
        visible: Services.Mpris.active !== null
        // The same controls body as the dedicated Media popout —
        // Local.MediaControls (this directory's shared section) is the
        // one place the track info, progress and transport live, so
        // the two cards can't drift apart. No own title: the section is
        // self-evident, the same way the Media popout shows none.
        Local.MediaControls {
            width: parent.width
            chWidth: root.chWidth
            active: root.active
        }
    }

    // --- system control --------------------------------------------------
    Widgets.OverlaySection {
        width: parent.width
        Column {
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space2

            Widgets.StyledText { kind: "title"; sizeStep: 0; text: "System control" }

            // A compact icon + read-only-looking bar, not a second full
            // draggable Widgets.Meter — the Volume/Brightness cards already
            // have one each; two sliders for the same value risks drifting
            // out of sync visually. The icon still toggles mute for volume.
            Item {
                width: parent.width
                implicitHeight: Math.max(statusVolMeter.implicitHeight, statusVolPct.implicitHeight)
                Widgets.StyledIcon {
                    id: statusVolIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: Services.AudioBridge.muted ? Glyphs.volumeMute : Glyphs.volume
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Services.AudioBridge.toggleMute() }
                }
                Widgets.StyledText {
                    id: statusVolPct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    mono: true; kind: "label"; sizeStep: 0
                    text: Math.round(Services.AudioBridge.volume * 100) + "%"
                }
                Widgets.Meter {
                    id: statusVolMeter
                    anchors.left: statusVolIcon.right
                    anchors.leftMargin: root.chWidth
                    anchors.right: statusVolPct.left
                    anchors.rightMargin: root.chWidth
                    anchors.verticalCenter: parent.verticalCenter
                    interactive: true
                    value: Services.AudioBridge.volume
                    fillColor: Services.AudioBridge.muted ? Config.Appearance.textFaint : Config.Appearance.textPrimary
                    onMoved: (v) => Services.AudioBridge.setVolume(v)
                }
            }
            Item {
                width: parent.width
                implicitHeight: Math.max(statusBriMeter.implicitHeight, statusBriPct.implicitHeight)
                Widgets.StyledIcon {
                    id: statusBriIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: Glyphs.brightness
                }
                Widgets.StyledText {
                    id: statusBriPct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    mono: true; kind: "label"; sizeStep: 0
                    text: Services.Brightness.percent + "%"
                }
                Widgets.Meter {
                    id: statusBriMeter
                    anchors.left: statusBriIcon.right
                    anchors.leftMargin: root.chWidth
                    anchors.right: statusBriPct.left
                    anchors.rightMargin: root.chWidth
                    anchors.verticalCenter: parent.verticalCenter
                    interactive: true
                    value: Services.Brightness.percent / 100
                    fillColor: Config.Appearance.textPrimary
                    onReleased: (v) => Services.Brightness.set(Math.round(v * 100))
                }
            }

            // Five real states across five sensor icons, distributed
            // evenly — hand-drawn Canvas icons (Widgets/TrueToneIcon,
            // StayAwakeIcon, MicrophoneIcon, CameraIcon), same convention
            // as every other icon in this shell with no reliable font
            // glyph, so each toggle gets a real per-state shape rather
            // than a short text abbreviation.
            Row {
                id: sensorRow
                width: parent.width
                readonly property int _count: 5
                readonly property real _btnSize: root.chWidth * 4
                spacing: _count > 1 ? (width - _count * _btnSize) / (_count - 1) : 0

                Item {
                    id: nightBtn
                    width: sensorRow._btnSize; height: width
                    Widgets.SunMoonIcon {
                        anchors.centerIn: parent
                        sizeStep: 3
                        dayness: Services.NightShift.enabled ? 0 : 1
                        fillLevel: 1
                        iconColor: nightHover.hovered ? Config.Appearance.accent : Config.Appearance.textPrimary
                        Behavior on dayness {
                            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                        Behavior on iconColor {
                            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                    }
                    HoverHandler { id: nightHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Services.NightShift.setEnabled(!Services.NightShift.enabled) }
                }

                Item {
                    id: trueToneBtn
                    width: sensorRow._btnSize; height: width
                    enabled: Config.Capabilities.ambientLight
                    // 0.45 mirrors Widgets/WidgetStates.js's own INACTIVE_OPACITY.
                    opacity: enabled ? 1 : 0.45
                    Widgets.TrueToneIcon {
                        anchors.centerIn: parent
                        sizeStep: 3
                        on: Services.NightShift.trueTone
                        iconColor: Services.NightShift.trueTone
                            ? Config.Appearance.accent
                            : (trueToneHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.textMuted)
                        Behavior on iconColor {
                            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                    }
                    HoverHandler { id: trueToneHover; cursorShape: trueToneBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: trueToneBtn.enabled; onTapped: Services.NightShift.setTrueTone(!Services.NightShift.trueTone) }
                }

                // Stay-awake (Services/Idle.qml's `manualOverride`) — see
                // Widgets/StayAwakeIcon.qml's own header for why this draws
                // an eye rather than a named third-party app's own logo.
                Item {
                    id: awakeBtn
                    width: sensorRow._btnSize; height: width
                    Widgets.StayAwakeIcon {
                        anchors.centerIn: parent
                        sizeStep: 3
                        awake: Services.Idle.manualOverride
                        iconColor: Services.Idle.manualOverride
                            ? Config.Appearance.accent
                            : (awakeHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.textMuted)
                        Behavior on iconColor {
                            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                    }
                    HoverHandler { id: awakeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Services.Idle.setManualOverride(!Services.Idle.manualOverride) }
                }

                // Microphone — three real states marked by shape (Widgets/
                // MicrophoneIcon.qml: muted strikes the capsule through,
                // in-use fills it solid) as well as colour.
                Item {
                    id: micBtn
                    width: sensorRow._btnSize; height: width
                    Widgets.MicrophoneIcon {
                        anchors.centerIn: parent
                        sizeStep: 3
                        state: Services.AudioBridge.inputMuted ? "muted"
                            : (Services.AudioBridge.micInUse ? "inUse" : "idle")
                        iconColor: Services.AudioBridge.inputMuted ? Config.Appearance.textMuted
                            : (Services.AudioBridge.micInUse ? Config.Appearance.error
                                : (micHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.accent))
                        Behavior on iconColor {
                            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                    }
                    HoverHandler { id: micHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Services.AudioBridge.toggleInputMute() }
                }

                // Camera — "in use" reads Services.SensorPermissions.
                // activeUsers, the same source Camera.qml's own list
                // filters; it stays empty until a real detection backend
                // exists, so "in use" here is honest, not faked.
                Item {
                    id: camBtn
                    width: sensorRow._btnSize; height: width
                    readonly property bool _inUse: Services.SensorPermissions.activeUsers
                        .filter(u => u.sensor === "camera").length > 0
                    Widgets.CameraIcon {
                        anchors.centerIn: parent
                        sizeStep: 3
                        state: !Services.SensorPermissions.cameraEnabled ? "disabled"
                            : (camBtn._inUse ? "inUse" : "enabled")
                        iconColor: !Services.SensorPermissions.cameraEnabled ? Config.Appearance.textMuted
                            : (camBtn._inUse ? Config.Appearance.error
                                : (camHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.accent))
                        Behavior on iconColor {
                            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                        }
                    }
                    HoverHandler { id: camHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Services.SensorPermissions.setCameraEnabled(!Services.SensorPermissions.cameraEnabled) }
                }
            }
            Widgets.StyledText {
                width: parent.width
                visible: Services.AudioBridge.micInUse
                kind: "label"; sizeStep: 0; tone: "error"
                text: "Microphone in use"
            }
        }
    }

    // --- tiling options grid --------------------------------------------
    Widgets.OverlaySection {
        width: parent.width
        Column {
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space1

            Widgets.StyledText { kind: "title"; sizeStep: 0; text: "Tiling" }
            Widgets.StyledText {
                width: parent.width
                kind: "label"; sizeStep: 0
                wrapMode: Text.WordWrap
                text: "Stock Hyprland has no native X/Y-scroll, Center or Fair "
                    + "layout — only Tile (dwindle/master) and Floating are real "
                    + "here, applied to every window on the current workspace; "
                    + "the rest only highlight."
            }
            Grid {
                width: parent.width
                columns: 3
                columnSpacing: root.chWidth * Config.Appearance.space2
                rowSpacing: root.chWidth * Config.Appearance.space2
                Repeater {
                    model: [
                        { id: "xscroll", label: "X scroll", glyph: Glyphs.tilingXScroll },
                        { id: "yscroll", label: "Y scroll", glyph: Glyphs.tilingYScroll },
                        { id: "tile", label: "Tile", glyph: Glyphs.tilingTile },
                        { id: "center", label: "Center", glyph: Glyphs.tilingCenter },
                        { id: "fair", label: "Fair", glyph: Glyphs.tilingFair },
                        { id: "floating", label: "Floating", glyph: Glyphs.tilingFloating },
                    ]
                    Widgets.Panel {
                        id: tilingBtn
                        required property var modelData
                        width: (parent.width - root.chWidth * Config.Appearance.space2 * 2) / 3
                        height: tilingCol.implicitHeight + padding * 2
                        radius: Config.Appearance.radiusSmall
                        hovered: tilingHover.hovered
                        active: root._tilingMode === tilingBtn.modelData.id

                        Column {
                            id: tilingCol
                            anchors.centerIn: parent
                            spacing: root.chWidth * Config.Appearance.space1 * 0.5
                            Widgets.StyledIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                glyph: tilingBtn.modelData.glyph
                                sizeStep: 2
                                color: tilingBtn.contentColor
                            }
                            Widgets.StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                kind: "label"
                                sizeStep: 0
                                color: tilingBtn.contentColor
                                text: tilingBtn.modelData.label
                            }
                        }

                        HoverHandler { id: tilingHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root._applyTilingMode(tilingBtn.modelData.id) }
                    }
                }
            }
        }
    }
}
