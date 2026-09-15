import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../Bar/glyphs.js" as Glyphs
import "../Widgets/WidgetStates.js" as WidgetStates

// phiOS — Dialogs/PowerActionsRow (2026-09-15). A horizontal row of
// icon+label power-action pills, styled after references/
// lock-options-reference.webp (user-provided): one pill filled solid with
// accent to mark it, the rest bare icon+text directly on the wallpaper/
// scrim behind them. WidgetStates.js's own `ambient: "powerPill"` carries
// the colour recipe and the reasoning for the accent-fill exception; this
// file is presentation and action-dispatch only.
//
// Shared by both surfaces that offer power actions, so they cannot
// visually disagree about what one action looks like:
//   - Dialogs/PowerMenu.qml (SUPER+L, before locking) — restyled from a
//     plain vertical icon+label list to this pill row, per the same
//     reference. Includes "lock".
//   - Lock/Lock.qml (already locked, no authentication required to use
//     this row) — omits "lock", since locking an already-locked screen is
//     meaningless; docs/TODO.md's own direct request: "add the power
//     options in the lockscreen as well to use them without unlocking."
//
// Confirmation for reboot/shutdown goes through the same
// Services.ConfirmDialog step both callers already used before this
// component existed (Services.PowerActions.needsConfirm()) — nothing
// about that path changes; `onChosen` below only decides whether to
// interpose that step, never bypasses it.
//
// `highlightedAction` names the one pill to mark with the accent fill —
// each caller decides which (PowerMenu.qml: a static "lock", matching the
// reference image's own default; Lock.qml: none, "" — no single action
// there is more "the" action than another). Independent of real keyboard
// focus (Tab still moves between pills and shows the ordinary `focus`
// ring state below), the same way a static reference screenshot cannot
// itself be showing live input — this is a "default/primary" marker, not
// a focus indicator.

Row {
    id: root

    property var actions: []
    property string highlightedAction: ""
    signal chosen(string action)

    spacing: chMetrics.width * Config.Appearance.space4

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _padH: chMetrics.width * Config.Appearance.space3
    readonly property real _padV: chMetrics.width * Config.Appearance.space2

    function _glyphFor(action) {
        switch (action) {
        case "lock": return Glyphs.lock
        case "suspend": return Glyphs.powerSleep
        case "hibernate": return Glyphs.hibernate
        case "logout": return Glyphs.logout
        case "reboot": return Glyphs.restart
        case "shutdown": return Glyphs.power
        }
        return ""
    }

    Repeater {
        model: root.actions

        Item {
            id: pill
            required property string modelData

            readonly property bool isActive: modelData === root.highlightedAction
            readonly property bool hovered: hoverHandler.hovered
            readonly property bool pressed: tapHandler.pressed
            readonly property bool keyboardFocus: activeFocus

            readonly property string resolvedState: WidgetStates.resolve({
                enabled: true, hovered: pill.hovered, pressed: pill.pressed,
                active: pill.isActive, keyboardFocus: pill.keyboardFocus,
                loading: false, invalid: false
            })
            readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "powerPill")

            implicitWidth: row.implicitWidth + root._padH * 2
            implicitHeight: row.implicitHeight + root._padV * 2
            activeFocusOnTab: true

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: pill.stateColors.bg
                border.width: Config.Appearance.borderWidth
                border.color: pill.stateColors.border

                Behavior on color {
                    ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
                Behavior on border.color {
                    ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
            }

            Row {
                id: row
                anchors.centerIn: parent
                spacing: root._padH * 0.6

                Widgets.StyledIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: root._glyphFor(pill.modelData)
                    sizeStep: 2
                    color: pill.stateColors.fg
                }
                Widgets.StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Services.PowerActions.title(pill.modelData)
                    color: pill.stateColors.fg
                }
            }

            HoverHandler {
                id: hoverHandler
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: tapHandler
                onTapped: root.chosen(pill.modelData)
            }
            Keys.onReturnPressed: root.chosen(pill.modelData)
            Keys.onSpacePressed: root.chosen(pill.modelData)
        }
    }
}
