import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../Bar/glyphs.js" as Glyphs
import "../../Widgets/WidgetStates.js" as WidgetStates

// Row of icon+label power-action pills. Hover fills with semantic tone
// (shutdown red, logout/reboot amber, suspend blue, lock/hibernate accent)
// and flips glyph/label to that tone's text token. At rest: bare icon+label
// in textMuted; keyboard-focus pill keeps full accent fill. Shared by
// PowerMenu (includes "lock") and Lock screen (omits "lock"). Confirmation
// via Services.ConfirmDialog. Keyboard-focus is the real accent fill state
// (via `active: pill.keyboardFocus`), not a separate marker. `focusFirst()`
// preselects the first pill on open. Stays in tab chain everywhere — actual
// Tab-focus trap fix is in Lock.qml's password field, not here.

Row {
    id: root

    property var actions: []
    signal chosen(string action)

    // Select the first pill on surface visibility. Component.onCompleted fires
    // only on first session open, not on later reopens (window shown via opacity).
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

    // Semantic tone per action (design tokens only). Read as pill's hover
    // background — shutdown always hovers error-red regardless of surface.
    // Paired with _toneTextFor() for text on that fill.
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

    // Text token paired with tone above (*Text companion); glyph and label flip
    // to this while hovered, staying readable on the tone fill.
    function _toneTextFor(action) {
        switch (action) {
        case "lock": return Config.Appearance.accentText
        case "suspend": return Config.Appearance.infoText
        case "hibernate": return Config.Appearance.accentText
        case "logout": return Config.Appearance.warnText
        case "reboot": return Config.Appearance.warnText
        case "shutdown": return Config.Appearance.errorText
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

            // keyboardFocus: false forces focused pill to full accent fill via
            // `active`, not resolve()'s focus case (border-ring only).
            readonly property string resolvedState: WidgetStates.resolve({
                enabled: true, hovered: pill.hovered, pressed: pill.pressed,
                active: pill.keyboardFocus, keyboardFocus: false,
                loading: false, invalid: false
            })
            readonly property var stateColors: WidgetStates.surfaceColors(Config.Appearance, resolvedState, "powerPill")

            // Tone is hover background, not resting glyph color. On hover, pill
            // fills with tone and glyph/label flip to that tone's text token.
            // Rest stays neutral (textMuted); keyboard-focus keeps accent fill.
            readonly property color pillBg: pill.resolvedState === "hover"
                ? root._toneFor(pill.modelData)
                : pill.stateColors.bg
            readonly property color pillFg: pill.resolvedState === "hover"
                ? root._toneTextFor(pill.modelData)
                : pill.stateColors.fg

            implicitWidth: row.implicitWidth + root._padH * 2
            implicitHeight: row.implicitHeight + root._padV * 2
            activeFocusOnTab: true

            Rectangle {
                anchors.fill: parent
                radius: Config.Appearance.radiusSmall
                color: pill.pillBg
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
                    color: pill.pillFg
                }
                Widgets.StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Services.PowerActions.title(pill.modelData)
                    color: pill.pillFg
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
