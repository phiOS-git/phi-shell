import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../Bar/glyphs.js" as Glyphs
import "../../Widgets/WidgetStates.js" as WidgetStates

// A horizontal row of icon+label power-action pills: each pill's GLYPH
// carries its action's semantic tone (shutdown error, logout/reboot warn,
// suspend info, lock/hibernate accent) on whatever surface it sits on —
// the colour identity the status card's compact row used to apply on
// hover, now steady on each pill instead of appearing only under the
// cursor. Hover adds only the flat wash behind the pill
// (WidgetStates.js's own `ambient: "powerPill"` carries the colour
// recipe); the keyboard-focus pill keeps its full accent fill with
// accentText glyph so the selection stays readable over the tone. This
// file is presentation and action-dispatch only.
//
// Shared by both surfaces that offer power actions, so they can't
// visually disagree about what one action looks like:
//   - Components/Dialogs/PowerMenu.qml (SUPER+L, before locking) —
//     includes "lock".
//   - Components/Lock/Lock.qml (already locked, no authentication
//     required to use this row) — omits "lock", since locking an
//     already-locked screen is meaningless.
//
// Confirmation for reboot/shutdown goes through the same
// Services.ConfirmDialog step both callers already used before this
// component existed (Services.PowerActions.needsConfirm()) — `onChosen`
// below only decides whether to interpose that step, never bypasses it.
//
// The accent fill IS the real keyboard-focus state, not a separate
// static "default/primary" marker independent of Tab focus (`active:
// pill.keyboardFocus` below, short-circuiting WidgetStates.resolve() past
// its own separate `focus` case entirely) — a Tab-selected pill gets the
// full accent fill rather than just a border ring. `focusFirst()` lets
// the caller select the first pill the moment the surface appears, so
// something is always visibly selected without waiting for a first Tab
// press.
//
// This row stays plain `activeFocusOnTab: true` for every caller: Lock.qml
// briefly removed these pills from the tab chain to fix a Tab-focus trap,
// but that made the row keyboard-unreachable — the actual fix lives in
// Lock.qml's own password field instead (it opts into the tab chain too,
// closing the loop field → pills → back to field).

Row {
    id: root

    property var actions: []
    signal chosen(string action)

    // Selects the first pill — call this once, when the surface that
    // hosts this row actually becomes visible. Component.onCompleted
    // alone would not do this: the host window is created once and only
    // ever shown/hidden via opacity, so this component's own
    // Component.onCompleted fires exactly once, on the very first open of
    // the whole session, never again on a later reopen.
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

    // One semantic tone per action, from this shell's existing tone palette
    // (rule 6: design tokens are the only source of colour) — read by each
    // pill's own `iconColor`, so a shutdown action is always error-coloured
    // no matter which surface hosts this row (PowerMenu, Lock screen).
    function _toneFor(action) {
        switch (action) {
        case "lock": return Config.Appearance.accent
        case "suspend": return Config.Appearance.info
        case "hibernate": return Config.Appearance.accent
        case "logout": return Config.Appearance.warn
        case "reboot": return Config.Appearance.warn
        case "shutdown": return Config.Appearance.error
        }
        return Config.Appearance.textMuted
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

            // `keyboardFocus: false` here is deliberate: resolve()'s own
            // precedence would otherwise route a focused pill to its
            // "focus" case (a border-ring look, one rung below "active")
            // — passing it as `active` directly is what gives a
            // Tab-selected pill the full accent fill rather than just a
            // ring (see this file's own header).
            readonly property string resolvedState: WidgetStates.resolve({
                enabled: true, hovered: pill.hovered, pressed: pill.pressed,
                active: pill.keyboardFocus, keyboardFocus: false,
                loading: false, invalid: false
            })
            readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "powerPill")

            // Per-action semantic colour on the GLYPH, steady in every state
            // (hover only adds the wash behind it): a shutdown pill always
            // reads error, a logout warn, a suspend info, lock/hibernate
            // accent — the same per-action colouring the status card's
            // compact row used to apply on hover, now each action's
            // identity instead. The two exceptions fall back to
            // `stateColors.fg`: the keyboard-focus pill fills solid with
            // accent, so its glyph must be accentText to stay readable on
            // that fill, and an invalid pill keeps the error state's fg.
            readonly property color iconColor: (pill.resolvedState === "active" || pill.resolvedState === "invalid")
                ? pill.stateColors.fg
                : root._toneFor(pill.modelData)

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
                    color: pill.iconColor
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
