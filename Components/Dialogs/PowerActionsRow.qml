import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../Bar/glyphs.js" as Glyphs
import "../../Widgets/WidgetStates.js" as WidgetStates

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
// Style pass 2026-09-15, take 2 (reported directly: "the lock button is
// in accent color but that should be the selected state, instead the
// selected state is just a border. fix it, the selected state should be
// the accent colour background. Also until i press tab the first option
// is not automatically selected and it should be."). The accent fill
// used to be `highlightedAction`, a static "default/primary" marker
// independent of real keyboard focus (Tab showed only a border-ring
// `focus` state, a separate look) — that is exactly the "selected state
// is just a border" complaint. `highlightedAction` is gone: the accent
// fill now IS the real keyboard-focus state (`active: pill.keyboardFocus`
// below, short-circuiting WidgetStates.resolve() past its own separate
// `focus` case entirely), and `focusFirst()` gives the caller a way to
// select the first pill the moment the surface appears, so something is
// always visibly selected without waiting for a first Tab press.
//
// Lock/Lock.qml briefly (2026-09-15) removed these pills from the tab
// chain entirely (`activeFocusOnTab: false`) to fix a real Tab-focus trap
// — but that made the row keyboard-UNREACHABLE, reported directly right
// back: "the lock screen now does not allow tab at all, so i can never
// reach the power options." The actual fix lives in Lock/Lock.qml's own
// password field instead (it now opts into the tab chain too, closing
// the loop field -> pills -> back to field) — this row stays plain
// `activeFocusOnTab: true` for every caller, no per-instance override.
//
// Sized compact (2026-09-15, reported directly: "borders are at least 3
// times larger" than references/lock-options-reference.webp) — the
// reference's own pills are slim, not the generous space3/space2 padding
// a settings-panel button gets away with sitting in a roomy dialog. Also
// reported directly: "the border radius of the option elements should be
// way less" — was a fully rounded pill (`height / 2`); now a plain
// `radiusSmall`, the same corner every other small control in this shell
// uses.

Row {
    id: root

    property var actions: []
    signal chosen(string action)

    // Selects the first pill — call this once, when the surface that
    // hosts this row actually becomes visible (Dialogs/PowerMenu.qml's
    // own onShownChanged). Component.onCompleted alone would not do this:
    // PowerMenu.qml's window is created once and only ever shown/hidden
    // via opacity, so this component's own Component.onCompleted fires
    // exactly once, on the very first SUPER+L of the whole session, never
    // again on a later reopen.
    function focusFirst() {
        if (pillRepeater.count > 0) pillRepeater.itemAt(0).forceActiveFocus()
    }

    spacing: chMetrics.width * Config.Appearance.space2

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _padH: chMetrics.width * Config.Appearance.space2
    readonly property real _padV: chMetrics.width * Config.Appearance.space1

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
        id: pillRepeater
        model: root.actions

        Item {
            id: pill
            required property string modelData

            readonly property bool hovered: hoverHandler.hovered
            readonly property bool pressed: tapHandler.pressed
            readonly property bool keyboardFocus: activeFocus

            // `active: pill.keyboardFocus` — the accent fill IS the real
            // keyboard-selection state, not a separate static marker
            // (see this file's own header). `keyboardFocus: false` here
            // is deliberate: resolve()'s own precedence would otherwise
            // route a focused pill to its "focus" case instead (a border-
            // ring look, one rung below "active") — passing it as `active`
            // directly is what gives a Tab-selected pill the full accent
            // fill rather than just a ring.
            readonly property string resolvedState: WidgetStates.resolve({
                enabled: true, hovered: pill.hovered, pressed: pill.pressed,
                active: pill.keyboardFocus, keyboardFocus: false,
                loading: false, invalid: false
            })
            readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "powerPill")

            implicitWidth: row.implicitWidth + root._padH * 2
            implicitHeight: row.implicitHeight + root._padV * 2
            activeFocusOnTab: true

            Rectangle {
                anchors.fill: parent
                radius: Config.Appearance.radiusSmall
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
                    sizeStep: 1
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
